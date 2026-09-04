import { DetTensor } from './ImagePreprocess';

// captcha 滑块检测模型（model/captcha，解码逻辑与 captcha.py 一致）
export const INPUT_SIZE = 640;
const SCORE_THRESHOLD = 0.25;
const X_OFFSET_MARGIN = 4;

/**
 * 滑块验证码解码：输出 [1,5,8400] → 最高分框的 x_offset（原图坐标）。
 * 推理由 MindSpore Lite 后端完成（MsCaptchaDetector），本类只承载与
 * captcha.py 一致的解码语义，后端无关。
 */
export class CaptchaDetector {
  /**
   * 解码检测结果。
   * @param outputs 模型输出（包装为 DetTensor，fp16 已在包装时转 fp32）
   * @param canvasLength 预处理画布边长（原图宽高中较大者）
   * @returns 滑块左边界的 x 偏移（已含 4px 余量，原图坐标）；未检测到返回 -1
   */
  static decode(outputs: DetTensor[], canvasLength: number): number {
    if (outputs.length === 0) {
      return -1;
    }
    const pred = new Float32Array(outputs[0].data);
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
