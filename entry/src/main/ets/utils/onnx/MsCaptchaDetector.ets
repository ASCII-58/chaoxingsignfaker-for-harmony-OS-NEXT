import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { OnnxRunner, OnnxOutput } from './OnnxRunner';
import { CaptchaDetector } from './CaptchaDetector';

// 华为原生 MindSpore Lite 推理封装：与 CaptchaDetector（ONNX）跑同一份模型
// （captcha_fp16_v2.onnx 经 mindspore 转换出的 .ms），预处理与解码完全共用，
// 仅推理后端不同，用于对比验证两个后端的结果一致性与耗时。
const MODEL_RAWFILE = 'models/captcha_fp16_v2.ms';

/**
 * MindSpore Lite 滑块检测封装：输入一张图片，输出一个数值（滑块 x 偏移，原图坐标）。
 * 与 CaptchaDetector.detect 同语义；未检测到滑块返回 -1。
 * 模型进程级缓存，加载一次后重复调用零加载开销。
 */
export class MsCaptchaDetector {
  private static model: mindSporeLite.Model | undefined = undefined;

  /**
   * 加载（并缓存）MindSpore Lite 模型。
   * @returns 加载耗时 ms；缓存命中返回 0
   */
  static async load(context: common.Context): Promise<number> {
    if (MsCaptchaDetector.model !== undefined) {
      return 0;
    }
    const buf = context.resourceManager.getRawFileContentSync(MODEL_RAWFILE);
    // 注意：第二个参数是 mindSporeLite.Context（设备配置），不是 UIAbilityContext
    const msContext: mindSporeLite.Context = { target: ['cpu'] };
    const start = Date.now();
    MsCaptchaDetector.model =
      await mindSporeLite.loadModelFromBuffer(buf.buffer as ArrayBuffer, msContext);
    return Date.now() - start;
  }

  static isLoaded(): boolean {
    return MsCaptchaDetector.model !== undefined;
  }

  /**
   * 检测滑块 x 偏移。
   * @param pixelMap 输入图片，必须为 RGBA_8888 格式（与 CaptchaDetector.detect 一致）
   * @returns 滑块左边界的 x 偏移（已含 4px 余量，原图坐标）；未检测到返回 -1
   */
  static async detect(pixelMap: image.PixelMap): Promise<number> {
    const info = await pixelMap.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const rgba = new Uint8Array(new ArrayBuffer(width * height * 4));
    await pixelMap.readPixelsToBuffer(rgba.buffer as ArrayBuffer);
    // 与 ONNX 完全同一份 native 预处理：方形补黑 → 640x640 → RGB /255 → CHW
    const input = OnnxRunner.preprocessImage(rgba, width, height);
    return MsCaptchaDetector.runFromInput(input, Math.max(width, height));
  }

  /**
   * 用已预处理好的 [1,3,640,640] float32 输入推理并解码。
   * 对比调试用：可与 ONNX 后端共享同一份预处理输入，保证逐位相同的输入。
   * @returns 滑块左边界的 x 偏移（原图坐标）；未检测到返回 -1
   */
  static async runFromInput(input: Float32Array, canvasLength: number): Promise<number> {
    const model = MsCaptchaDetector.model;
    if (model === undefined) {
      throw new Error('MindSpore Lite 模型未加载，请先调用 load()');
    }
    const inputs = model.getInputs();
    if (inputs.length === 0) {
      throw new Error('模型无输入张量');
    }
    const inputTensor = inputs[0];
    if (inputTensor.elementNum !== input.length) {
      throw new Error(`输入张量元素数不匹配: 模型 ${inputTensor.elementNum}, 实际 ${input.length}` +
        `（shape ${JSON.stringify(inputTensor.shape)}, dtype ${inputTensor.dtype}）`);
    }
    inputTensor.setData(input.buffer as ArrayBuffer);
    const outputs = await model.predict(inputs);
    return CaptchaDetector.decode(MsCaptchaDetector.wrapOutputs(outputs), canvasLength);
  }

  /** MSTensor[] → OnnxOutput[]（fp16 输出转为 fp32，保证共用 ONNX 解码路径） */
  private static wrapOutputs(tensors: mindSporeLite.MSTensor[]): OnnxOutput[] {
    const results: OnnxOutput[] = [];
    for (const t of tensors) {
      const raw = t.getData();
      if (t.dtype === mindSporeLite.DataType.NUMBER_TYPE_FLOAT32) {
        results.push({ name: t.name, dims: t.shape, type: 'float32', data: raw });
      } else if (t.dtype === mindSporeLite.DataType.NUMBER_TYPE_FLOAT16) {
        const src = new Uint16Array(raw);
        const dst = new Float32Array(src.length);
        for (let i = 0; i < src.length; i++) {
          dst[i] = MsCaptchaDetector.fp16ToFp32(src[i]);
        }
        results.push({ name: t.name, dims: t.shape, type: 'float32', data: dst.buffer as ArrayBuffer });
      } else {
        throw new Error(`不支持的输出 dtype: ${t.dtype}（tensor ${t.name}）`);
      }
    }
    return results;
  }

  /** IEEE 754 half → single 位级转换 */
  private static fp16ToFp32(h: number): number {
    const sign = (h & 0x8000) << 16;
    const exp = (h & 0x7C00) >> 10;
    const frac = h & 0x03FF;
    if (exp === 0) {
      if (frac === 0) {
        return sign; // ±0
      }
      // 次正规数：左移对齐到隐藏位（bit10），记录移位次数 s，指数场 = 113 - s
      let f = frac;
      let s = 0;
      while ((f & 0x0400) === 0) {
        f <<= 1;
        s++;
      }
      return sign | ((113 - s) << 23) | ((f & 0x03FF) << 13);
    }
    if (exp === 0x1F) {
      return sign | 0x7F800000 | (frac << 13); // inf / nan
    }
    return sign | ((exp - 15 + 127) << 23) | (frac << 13);
  }
}
