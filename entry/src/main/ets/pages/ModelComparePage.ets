import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { OnnxRunner } from '../utils/onnx/OnnxRunner';
import { CaptchaDetector, INPUT_SIZE } from '../utils/onnx/CaptchaDetector';
import { MsCaptchaDetector } from '../utils/onnx/MsCaptchaDetector';

// 模型对比调试页：同一张 test.jpg → 同一份 native 预处理输入 →
// 分别跑华为原生 MindSpore Lite（.ms）与 ONNX Runtime（.onnx），
// 对比加载耗时、推理耗时与检测偏移一致性。结果解码逻辑两端共用（CaptchaDetector.decode）。
const ONNX_MODEL_RAWFILE = 'models/captcha_fp16_v2.onnx';
const IMAGE_RAWFILE = 'models/test.jpg';
const RUNS = 5;
const X_BASELINE = 258; // test.jpg 基准偏移（见 DebugPage ONNX 测试）

class RunStats {
  loadMs: number = 0; // ONNX=建会话（含首次模型拷贝），MS=loadModelFromBuffer
  warmupMs: number = 0;
  avgMs: number = 0;
  minMs: number = 0;
  maxMs: number = 0;
  xOffset: number = -1;
  error: string = '';
}

class RunResult {
  elapsed: number;
  xOffset: number;

  constructor(elapsed: number, xOffset: number) {
    this.elapsed = elapsed;
    this.xOffset = xOffset;
  }
}

@Builder
export function init() {
  ModelComparePage()
}

@Component
export default struct ModelComparePage {
  private context = getContext(this) as common.UIAbilityContext;
  @State running: boolean = false;
  @State progress: string = '';
  @State onnxStats: RunStats | undefined = undefined;
  @State msStats: RunStats | undefined = undefined;
  @State verdict: string = '';

  async aboutToAppear() {
    this.runCompare();
  }

  async runCompare() {
    if (this.running) {
      return;
    }
    this.running = true;
    this.onnxStats = undefined;
    this.msStats = undefined;
    this.verdict = '';
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await this.loadTestImage();
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const rgba = new Uint8Array(new ArrayBuffer(width * height * 4));
      await pixelMap.readPixelsToBuffer(rgba.buffer as ArrayBuffer);
      // 两端共用的预处理输入，保证逐位一致
      const input = OnnxRunner.preprocessImage(rgba, width, height);
      const canvasLength = Math.max(width, height);

      this.progress = 'ONNX 运行中...';
      this.onnxStats = await this.benchOnnx(input, canvasLength);
      this.progress = 'MindSpore Lite 运行中...';
      this.msStats = await this.benchMs(input, canvasLength);
      this.verdict = this.buildVerdict();
      this.progress = '';
    } catch (e) {
      this.progress = '';
      this.verdict = `测试失败: ${(e as BusinessError).message}`;
    } finally {
      if (pixelMap !== undefined) {
        pixelMap.release();
      }
      this.running = false;
    }
  }

  private async benchOnnx(input: Float32Array, canvasLength: number): Promise<RunStats> {
    const stats = new RunStats();
    try {
      const t0 = Date.now();
      const runner = await OnnxRunner.getShared(this.context, ONNX_MODEL_RAWFILE);
      stats.loadMs = Date.now() - t0;
      stats.warmupMs = this.timeOnnxRun(runner, input, canvasLength).elapsed;
      let sum = 0;
      let min = Number.MAX_SAFE_INTEGER;
      let max = 0;
      let x = -1;
      for (let i = 0; i < RUNS; i++) {
        const r = this.timeOnnxRun(runner, input, canvasLength);
        sum += r.elapsed;
        min = Math.min(min, r.elapsed);
        max = Math.max(max, r.elapsed);
        x = r.xOffset;
      }
      stats.avgMs = sum / RUNS;
      stats.minMs = min;
      stats.maxMs = max;
      stats.xOffset = x;
    } catch (e) {
      stats.error = (e as BusinessError).message;
    }
    return stats;
  }

  private timeOnnxRun(runner: OnnxRunner, input: Float32Array,
    canvasLength: number): RunResult {
    const start = Date.now();
    const outputs = runner.run([{ dims: [1, 3, INPUT_SIZE, INPUT_SIZE], data: input }]);
    const x = CaptchaDetector.decode(outputs, canvasLength);
    return new RunResult(Date.now() - start, x);
  }

  private async benchMs(input: Float32Array, canvasLength: number): Promise<RunStats> {
    const stats = new RunStats();
    try {
      stats.loadMs = await MsCaptchaDetector.load(this.context);
      stats.warmupMs = (await this.timeMsRun(input, canvasLength)).elapsed;
      let sum = 0;
      let min = Number.MAX_SAFE_INTEGER;
      let max = 0;
      let x = -1;
      for (let i = 0; i < RUNS; i++) {
        const r = await this.timeMsRun(input, canvasLength);
        sum += r.elapsed;
        min = Math.min(min, r.elapsed);
        max = Math.max(max, r.elapsed);
        x = r.xOffset;
      }
      stats.avgMs = sum / RUNS;
      stats.minMs = min;
      stats.maxMs = max;
      stats.xOffset = x;
    } catch (e) {
      stats.error = (e as BusinessError).message;
    }
    return stats;
  }

  private async timeMsRun(input: Float32Array, canvasLength: number): Promise<RunResult> {
    const start = Date.now();
    const x = await MsCaptchaDetector.runFromInput(input, canvasLength);
    return new RunResult(Date.now() - start, x);
  }

  private buildVerdict(): string {
    const onnx = this.onnxStats;
    const ms = this.msStats;
    if (onnx === undefined || ms === undefined) {
      return '';
    }
    if (onnx.error !== '' || ms.error !== '') {
      return '存在失败的后端，详见上方各卡片错误信息';
    }
    const same = onnx.xOffset === ms.xOffset;
    const lines: string[] = [];
    lines.push(`检测偏移: ONNX ${onnx.xOffset} vs MS ${ms.xOffset} → ` +
      (same ? `一致（基准 ${X_BASELINE}）` : `相差 ${Math.abs(onnx.xOffset - ms.xOffset)}px`));
    if (onnx.avgMs > 0 && ms.avgMs > 0) {
      const ratio = ms.avgMs / onnx.avgMs;
      lines.push(`推理均值(${RUNS}次): ONNX ${onnx.avgMs.toFixed(1)}ms · ` +
        `MS ${ms.avgMs.toFixed(1)}ms · MS/ONNX ${ratio.toFixed(2)}x`);
    }
    return lines.join('\n');
  }

  private async loadTestImage(): Promise<image.PixelMap> {
    const buf = this.context.resourceManager.getRawFileContentSync(IMAGE_RAWFILE);
    const source = image.createImageSource(buf.buffer as ArrayBuffer);
    try {
      return await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    } finally {
      source.release();
    }
  }

  @Builder
  statRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.secondary_text'))
      Blank()
      Text(value).fontSize(13).fontColor($r('app.color.primary_text'))
    }
    .width('100%').padding({ top: 3, bottom: 3 })
  }

  @Builder
  statCard(title: string, subtitle: string, stats: RunStats | undefined) {
    ListItem() {
      Column() {
        Row() {
          Text(title).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          Blank()
          Text(subtitle).fontSize(11).fontColor($r('app.color.secondary_text'))
        }
        .width('100%').margin({ bottom: 6 })

        if (stats === undefined) {
          Text('待运行')
            .fontSize(13).fontColor($r('app.color.text_placeholder'))
        } else if (stats.error !== '') {
          Text(`失败: ${stats.error}`)
            .fontSize(13).fontColor($r('app.color.unsignable'))
        } else {
          this.statRow('加载/建会话', stats.loadMs > 0 ? `${stats.loadMs}ms` : '缓存复用 0ms')
          this.statRow('预热单次', `${stats.warmupMs}ms`)
          this.statRow(`推理均值/${RUNS}次`, `${stats.avgMs.toFixed(1)}ms`)
          this.statRow('最短 / 最长', `${stats.minMs}ms / ${stats.maxMs}ms`)
          this.statRow('检测偏移 x_offset',
            stats.xOffset >= 0 ? `${stats.xOffset}（基准 ${X_BASELINE}）` : '未检测到滑块')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%').padding(12)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Text('模型对比：MindSpore Lite vs ONNX')
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%').textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 12 })

        List({ space: 12 }) {
          ListItem() {
            Column() {
              Row() {
                Image($rawfile(IMAGE_RAWFILE))
                  .height(64)
                  .objectFit(ImageFit.Contain)
                Blank()
                Button(this.running ? '运行中...' : '运行对比测试')
                  .fontSize(14)
                  .height(36)
                  .backgroundColor($r('app.color.class_button'))
                  .enabled(!this.running)
                  .onClick(() => { this.runCompare() })
              }
              .width('100%')

              Text(`输入: ${IMAGE_RAWFILE} · 预处理两端共用 · 各预热1次后计时${RUNS}次取均值\n` +
                `onnxruntime ${OnnxRunner.getRuntimeVersion()} · MindSpore Lite 系统内置`)
                .fontSize(12)
                .fontColor($r('app.color.secondary_text'))
                .width('100%')
                .margin({ top: 8 })
            }
            .width('100%').padding(12)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
          }

          this.statCard('ONNX Runtime', ONNX_MODEL_RAWFILE, this.onnxStats)
          this.statCard('MindSpore Lite（华为原生）', 'models/captcha_fp16_v2.ms', this.msStats)

          ListItem() {
            Column() {
              Row() {
                Text('对比结论').fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary_text'))
                Blank()
                Text(this.progress).fontSize(12).fontColor($r('app.color.secondary_text'))
              }
              .width('100%').margin({ bottom: 6 })

              Text(this.verdict === '' ? (this.running ? '测试中...' : '待运行') : this.verdict)
                .fontSize(13)
                .fontColor(this.verdict === '' ? $r('app.color.text_placeholder') : $r('app.color.primary_text'))
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%').padding(12)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
          }
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .height('100%')
    .width('100%')
  }
}
