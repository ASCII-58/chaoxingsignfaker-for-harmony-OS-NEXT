import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { OnnxRunner, OnnxOutput } from './OnnxRunner';

// captcha 滑块检测模型（model/captcha，预处理与解码逻辑与 captcha.py 一致）
// v2 = ir_version 9 + fp16 Softmax 展开为 fp32 三明治（ORT 1.16.3 兼容）
const MODEL_RAWFILE = 'models/captcha_fp16_v2.onnx';
const INPUT_SIZE = 640;
const SCORE_THRESHOLD = 0.25;
const X_OFFSET_MARGIN = 4;

/**
 * 滑块验证码检测封装：输入一张图片，输出一个数值（滑块 x 偏移，原图坐标）。
 * 内部自动完成 读图 → 预处理 → 推理 → 解码；会话进程级共享，重复调用零建会话开销。
 * 未检测到滑块时返回 -1。
 */
export class CaptchaDetector {
  /**
   * 检测滑块 x 偏移。
   * @param pixelMap 输入图片，必须为 RGBA_8888 格式（截图/选图时指定 desiredPixelFormat）
   * @returns 滑块左边界的 x 偏移（已含 4px 余量，原图坐标）；未检测到返回 -1
   */
  static async detect(context: common.Context, pixelMap: image.PixelMap): Promise<number> {
    const info = await pixelMap.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const rgba = new Uint8Array(new ArrayBuffer(width * height * 4));
    await pixelMap.readPixelsToBuffer(rgba.buffer as ArrayBuffer);

    // 与 captcha.py 一致：方形画布右/下补黑 → 整体缩到 640x640 → RGB /255 → CHW
    // （native 实现，结果与 ArkTS 逐像素循环逐位一致）
    const runner = await OnnxRunner.getShared(context, MODEL_RAWFILE);
    const input = OnnxRunner.preprocessImage(rgba, width, height);
    const outputs = runner.run([{ dims: [1, 3, INPUT_SIZE, INPUT_SIZE], data: input }]);
    return CaptchaDetector.decode(outputs, Math.max(width, height));
  }

  /** 输出 [1,5,8400] → 最高分框的 x_offset；无框或置信度不足返回 -1 */
  private static decode(outputs: OnnxOutput[], canvasLength: number): number {
    if (outputs.length === 0) {
      return -1;
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
    if (best < 0 || bestScore < SCORE_THRESHOLD) {
      return -1;
    }
    const cx = pred[0 * anchors + best];
    const bw = pred[2 * anchors + best];
    // 与 captcha.py 一致：640 坐标 → 原图坐标（左上角画布）→ 左边界 - 4
    const scale = canvasLength / INPUT_SIZE;
    return Math.trunc((cx - 0.5 * bw) * scale - X_OFFSET_MARGIN + 0.5);
  }
}
