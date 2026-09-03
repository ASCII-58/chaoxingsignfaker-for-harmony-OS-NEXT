import native from 'libonnxruntime_napi.so';
import { OnnxInput, OnnxOutput } from './OnnxRunner';

/**
 * 在 taskpool 子线程执行同步推理（大模型请勿在 UI 线程直接调 OnnxRunner.run）。
 * 用法：
 *   import { taskpool } from '@kit.ArkTS';
 *   const outputs = await taskpool.execute(onnxRunTask, runner.getHandle(), inputs) as OnnxOutput[];
 */
@Concurrent
export function onnxRunTask(handle: number, inputs: OnnxInput[]): OnnxOutput[] {
  return native.runSession(handle, inputs);
}
