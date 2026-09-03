import native from 'libonnxruntime_napi.so';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

/** 支持的输入张量数据类型 */
export type OnnxInputData = Float32Array | Int32Array | Uint8Array | BigInt64Array;

/** 输出张量按 type 包装后的数据类型 */
export type OnnxOutputData = Float32Array | Int32Array | Uint8Array | BigInt64Array;

export interface OnnxInput {
  /** 输入名，缺省时按会话输入顺序绑定 */
  name?: string;
  /** 张量形状，如 [1, 3, 640, 640] */
  dims: number[];
  /** 张量数据，元素个数必须等于 dims 各维的乘积 */
  data: OnnxInputData;
}

export interface OnnxOutput {
  name: string;
  dims: number[];
  /** ONNX 元素类型：float32 / int32 / int64 / uint8 / bool / float16 ... */
  type: string;
  data: ArrayBuffer;
}

const MODEL_DIR = 'onnx_models';

/**
 * ONNX 推理会话封装。run() 是同步调用，小模型可在 UI 线程直接用，
 * 大模型请配合 OnnxTask.ets 的 taskpool 用法放到子线程。
 * 用法示例见 entry/src/main/cpp/README.md。
 */
export class OnnxRunner {
  private handle: number;

  private constructor(handle: number) {
    this.handle = handle;
  }

  /** onnxruntime 版本号，如 "1.29.0" */
  static getRuntimeVersion(): string {
    return native.getVersion();
  }

  /**
   * 从 rawfile 加载模型。rawfile 只能读流而 ORT 需要真实文件路径，
   * 第一次会先把模型拷贝到 <filesDir>/onnx_models/。
   * @param rawfilePath 相对 rawfile 的路径，如 'models/captcha_fp16.onnx'
   */
  static async fromRawfile(context: common.Context, rawfilePath: string): Promise<OnnxRunner> {
    const modelPath = await OnnxRunner.copyModelToSandbox(context, rawfilePath);
    return OnnxRunner.fromPath(modelPath);
  }

  /** 从沙箱内真实路径加载模型 */
  static fromPath(modelPath: string): OnnxRunner {
    return new OnnxRunner(native.createSession(modelPath));
  }

  /** 同步推理。inputs 数量必须等于会话输入个数 */
  run(inputs: OnnxInput[]): OnnxOutput[] {
    return native.runSession(this.handle, inputs);
  }

  getInputNames(): string[] {
    return native.getInputNames(this.handle);
  }

  getOutputNames(): string[] {
    return native.getOutputNames(this.handle);
  }

  /** 会话句柄，供 OnnxTask.ets 的 taskpool 用法使用 */
  getHandle(): number {
    return this.handle;
  }

  /** 把输出原始字节按 type 包装成 TypedArray（缺省按 float32） */
  static wrapOutput(output: OnnxOutput): OnnxOutputData {
    switch (output.type) {
      case 'int64':
        return new BigInt64Array(output.data);
      case 'int32':
        return new Int32Array(output.data);
      case 'uint8':
        return new Uint8Array(output.data);
      default:
        return new Float32Array(output.data);
    }
  }

  /** 释放会话；释放后本对象不可再用 */
  close(): void {
    if (this.handle !== 0) {
      native.releaseSession(this.handle);
      this.handle = 0;
    }
  }

  private static async copyModelToSandbox(context: common.Context,
    rawfilePath: string): Promise<string> {
    const dir = `${context.filesDir}/${MODEL_DIR}`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    const modelPath = `${dir}/${OnnxRunner.baseName(rawfilePath)}`;
    if (fs.accessSync(modelPath)) {
      return modelPath; // 沙箱已有一份，直接复用；更新模型请换文件名或清应用数据
    }
    const content = context.resourceManager.getRawFileContentSync(rawfilePath);
    const file = fs.openSync(modelPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content.buffer as ArrayBuffer);
    } finally {
      fs.closeSync(file.fd);
    }
    return modelPath;
  }

  private static baseName(path: string): string {
    const index = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }
}
