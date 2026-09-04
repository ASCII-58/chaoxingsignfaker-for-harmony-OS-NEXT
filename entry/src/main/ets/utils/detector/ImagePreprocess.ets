/**
 * 滑块检测模型预处理：RGBA → 方形画布补黑 → 最近邻缩放到 640×640 → RGB/255 → CHW float32。
 * 语义与 captcha.py 一致（除法先按 double 再入 Float32Array，保证逐位结果相同）。
 * 模型输入 [1,3,640,640]；画布尺寸取 srcWidth/srcHeight 较大者，补黑区保持 0。
 */
export const INPUT_SIZE = 640;

export class ImagePreprocess {
  static preprocessImage(rgba: Uint8Array, srcWidth: number, srcHeight: number): Float32Array {
    const canvasLength = srcWidth > srcHeight ? srcWidth : srcHeight;
    const ratio = canvasLength / INPUT_SIZE;
    const planeSize = INPUT_SIZE * INPUT_SIZE;
    const out = new Float32Array(planeSize * 3);
    for (let y = 0; y < INPUT_SIZE; y++) {
      let sy = Math.trunc(y * ratio);
      if (sy > canvasLength - 1) {
        sy = canvasLength - 1;
      }
      for (let x = 0; x < INPUT_SIZE; x++) {
        let sx = Math.trunc(x * ratio);
        if (sx > canvasLength - 1) {
          sx = canvasLength - 1;
        }
        const base = y * INPUT_SIZE + x;
        if (sx < srcWidth && sy < srcHeight) {
          const idx = (sy * srcWidth + sx) * 4;
          out[base] = rgba[idx] / 255.0;
          out[planeSize + base] = rgba[idx + 1] / 255.0;
          out[2 * planeSize + base] = rgba[idx + 2] / 255.0;
        }
      }
    }
    return out;
  }
}

/** 检测模型输出张量的统一描述（后端无关） */
export interface DetTensor {
  name: string;
  dims: number[];
  /** 元素类型标识，当前恒为 'float32'（fp16 输出在包装时已转换） */
  type: string;
  data: ArrayBuffer;
}
