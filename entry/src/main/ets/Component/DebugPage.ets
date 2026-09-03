import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager } from '../utils/DataBase';
import { OnnxRunner, OnnxInput, OnnxOutput } from '../utils/onnx/OnnxRunner';

const ONNX_TEST_TAG = 'OnnxTest';

const SIGN_TIME = 'sign_time';
const VERSION = 'version';
const SIGN_EXPIRY_MS = 12 * 30 * 24 * 60 * 60 * 1000;
const BACKUP_REMINDER_MS = 11 * 30 * 24 * 60 * 60 * 1000;

// captcha 滑块检测模型测试（model/captcha，预处理与解码逻辑与 captcha.py 一致）
// v2 = ir_version 9 + fp16 Softmax 展开为 fp32 三明治（ORT 1.16.3 兼容）；
// 换文件名以绕过沙箱内旧模型的缓存
const MODEL_RAWFILE = 'models/captcha_fp16_v2.onnx';
const IMAGE_RAWFILE = 'models/test.jpg';
const INPUT_SIZE = 640;
const SCORE_THRESHOLD = 0.25;
const X_OFFSET_MARGIN = 4;

interface OnnxTestInput {
  inputs: OnnxInput[];
  canvasLength: number;
}

interface OnnxModelResult {
  label: string;
  score: number;
  xOffset: number;
  boxStr: string;
  outputName: string;
  dimsStr: string;
  sessionMs: number;
  inferMs: number;
  detected: boolean;
}

@Component
export struct DebugPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State dbInfo: string = '';
  @State onnxStatus: string = '';
  @State onnxResult: string = '';
  @State onnxRunning: boolean = false;
  private runner: OnnxRunner | undefined;
  @Consume('pathInfos') pathInfos: NavPathStack;

  async aboutToAppear() {
    await this.loadInfo();
  }

  aboutToDisappear() {
    // 共享会话进程级常驻（OnnxRunner.getShared），不在此处关闭
  }

  async loadInfo() {
    try {
      const dbManager = DatabaseManager.getInstance();
      const hostCount = await dbManager.getTableCount('HostUser');
      const otherCount = await dbManager.getTableCount('OtherUser');
      const signInfo = await this.getSignInfo();
      this.dbInfo = `HostUser: ${hostCount} 条, OtherUser: ${otherCount} 条\n\n${signInfo}`;
    } catch (e) {
      this.dbInfo = '加载失败';
    }
  }

  async getSignInfo(): Promise<string> {
    let pref = await preferences.getPreferences(this.context, 'settings');
    const signTime = await pref.get(SIGN_TIME, 0) as number;
    const ver = await pref.get(VERSION, '') as string;
    if (signTime === 0) {
      return '签名时间: 未记录\n版本: 未记录';
    }
    const date = new Date(signTime);
    const elapsed = Date.now() - signTime;
    const days = Math.floor(elapsed / (24 * 60 * 60 * 1000));
    let statusLine: string;
    if (elapsed >= SIGN_EXPIRY_MS) {
      statusLine = '状态: 已过期';
    } else if (elapsed >= BACKUP_REMINDER_MS) {
      const remain = Math.ceil((SIGN_EXPIRY_MS - elapsed) / (24 * 60 * 60 * 1000));
      statusLine = `状态: 即将过期 (剩余约${remain}天)`;
    } else {
      statusLine = '状态: 有效';
    }
    return `签名时间: ${date.toISOString().substring(0, 10)}\n版本: ${ver}\n${statusLine}\n已过 ${days} 天`;
  }

  async resetSignState() {
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.delete(SIGN_TIME);
      await pref.delete(VERSION);
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: '签名状态已重置' });
    } catch (e) {
      promptAction.showToast({ message: '重置失败' });
    }
  }

  async setSignTimeToTriggerReminder() {
    try {
      const target = Date.now() - BACKUP_REMINDER_MS - 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(SIGN_TIME, target);
      await pref.put(VERSION, '1.0.0-debug');
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: '签名时间已设为11个月前，下次启动将触发备份提醒' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  async setSignTimeExpired() {
    try {
      const target = Date.now() - SIGN_EXPIRY_MS - 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(SIGN_TIME, target);
      await pref.put(VERSION, '1.0.0-debug');
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: '签名时间已设为过期' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  async setSignDaysAgo(days: number) {
    try {
      const target = Date.now() - days * 24 * 60 * 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(SIGN_TIME, target);
      await pref.put(VERSION, '1.0.0-debug');
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: `签名时间已设为 ${days} 天前` });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  async runOnnxTest() {
    hilog.info(0x0000, ONNX_TEST_TAG, 'runOnnxTest invoked, running=%{public}s', String(this.onnxRunning));
    if (this.onnxRunning) {
      return;
    }
    this.onnxRunning = true;
    this.onnxResult = '';
    try {
      const start = Date.now();
      if (this.runner === undefined) {
        this.onnxStatus = '正在加载模型...';
        // 共享会话：首次创建（约 66ms），之后复用（0ms）
        this.runner = await OnnxRunner.getShared(this.context, MODEL_RAWFILE);
        hilog.info(0x0000, ONNX_TEST_TAG, 'session ready (shared), %{public}d ms', Date.now() - start);
      }
      const prepared = await this.prepareModelInput();
      hilog.info(0x0000, ONNX_TEST_TAG, 'input prepared, %{public}d ms', Date.now() - start);
      this.onnxStatus =
        `ORT ${OnnxRunner.getRuntimeVersion()}，输入: ${this.runner.getInputNames().join(',')}`;
      const outputs = this.runner.run(prepared.inputs);
      hilog.info(0x0000, ONNX_TEST_TAG, 'run done, %{public}d ms', Date.now() - start);
      this.onnxResult = this.decodeOutput(outputs, prepared.canvasLength, Date.now() - start);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, ONNX_TEST_TAG, 'test failed: %{public}s', err.message);
      this.onnxResult = `测试失败: ${err.message}`;
    } finally {
      this.onnxRunning = false;
    }
  }

  private async prepareModelInput(): Promise<OnnxTestInput> {
    const buf = this.context.resourceManager.getRawFileContentSync(IMAGE_RAWFILE);
    const source = image.createImageSource(buf.buffer as ArrayBuffer);
    const info = await source.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const pixelMap = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const rgba = new Uint8Array(new ArrayBuffer(width * height * 4));
    await pixelMap.readPixelsToBuffer(rgba.buffer as ArrayBuffer);

    // 与 captcha.py 一致：方形画布右/下补黑 → 整体缩到 640x640 → RGB /255 → CHW
    // （native 实现，结果与原 ArkTS 逐像素循环逐位一致）
    const canvasLength = Math.max(width, height);
    const input = OnnxRunner.preprocessImage(rgba, width, height);
    pixelMap.release();
    source.release();
    return {
      inputs: [{ dims: [1, 3, INPUT_SIZE, INPUT_SIZE], data: input }],
      canvasLength: canvasLength
    };
  }

  private decodeOutput(outputs: OnnxOutput[], canvasLength: number, elapsedMs: number): string {
    if (outputs.length === 0) {
      return '模型无输出';
    }
    const pred = OnnxRunner.wrapOutput(outputs[0]) as Float32Array;
    const channels = outputs[0].dims.length >= 3 ? outputs[0].dims[1] : 5;
    const anchors = outputs[0].dims.length >= 3 ? outputs[0].dims[2] : Math.floor(pred.length / channels);
    // NMS 后取最高分的幸存框 == 全局最高分框（最高分必然先被保留），与 captcha.py 结果一致
    let best = -1;
    let bestScore = 0;
    for (let i = 0; i < anchors; i++) {
      const score = pred[4 * anchors + i];
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    const header = `输出 ${outputs[0].name} [${outputs[0].dims.join(',')}]，耗时 ${elapsedMs}ms`;
    if (best < 0 || bestScore < SCORE_THRESHOLD) {
      return `${header}\n未检测到滑块（最高置信度 ${bestScore.toFixed(4)}）`;
    }
    const cx = pred[0 * anchors + best];
    const cy = pred[1 * anchors + best];
    const bw = pred[2 * anchors + best];
    const bh = pred[3 * anchors + best];
    // 与 captcha.py 一致：640 坐标 → 原图坐标（左上角画布）→ 左边界 - 4
    const scale = canvasLength / INPUT_SIZE;
    const xOffset = Math.trunc((cx - 0.5 * bw) * scale - X_OFFSET_MARGIN + 0.5);
    return `${header}\n最高置信度: ${bestScore.toFixed(4)}\n` +
      `x_offset: ${xOffset}（test.jpg 基准 258）\n` +
      `box(cx,cy,w,h): ${cx.toFixed(1)}, ${cy.toFixed(1)}, ${bw.toFixed(1)}, ${bh.toFixed(1)}`;
  }

  build() {
    Column() {
      Text('Debug 调试面板')
        .fontSize(24).fontWeight(FontWeight.Bold)
        .width('100%').textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 20 })

      List({ space: 12 }) {
        ListItem() {
          Column() {
            Text('签名状态')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              Row() {
                Text(this.dbInfo !== '' ? this.dbInfo : '加载中...')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              }
              .width('100%').padding(12)
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }

        ListItem() {
          Column() {
            Text('调试操作')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              Row() {
                Text('重置签名状态')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.resetSignState() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设11个月前签名（触发备份提醒）')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignTimeToTriggerReminder() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设过期签名（12个月前）')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignTimeExpired() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设1天前签名')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignDaysAgo(1) })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设365天前签名')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignDaysAgo(365) })
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }
        ListItem(){
          Column(){
            Text('打开Debug详情页')
          }.onClick(()=>{ this.pathInfos.pushPath({ name: 'Debug' }) })
        }

        ListItem() {
          Column() {
            Text('ONNX 模型测试')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              Row() {
                Image($rawfile(IMAGE_RAWFILE))
                  .height(64)
                  .objectFit(ImageFit.Contain)
                Blank()
                Button(this.onnxRunning ? '运行中...' : '运行滑块检测')
                  .fontSize(14)
                  .height(36)
                  .enabled(!this.onnxRunning)
                  .onClick(() => { this.runOnnxTest() })
              }
              .width('100%').padding(12)

              if (this.onnxStatus !== '') {
                Text(this.onnxStatus)
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                  .width('100%').padding({ left: 12, right: 12, bottom: 4 })
              }
              if (this.onnxResult !== '') {
                Text(this.onnxResult)
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .width('100%').padding({ left: 12, right: 12, bottom: 12 })
              }
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }
      }
      .width('100%').layoutWeight(1)
      .padding({ left: 16, right: 16 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }
}
