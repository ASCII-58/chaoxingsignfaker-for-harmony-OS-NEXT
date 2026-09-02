import request from '@ohos.request';
import fs from '@ohos.file.fs';
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChaoXingApi } from './PublicAPI';
import { Sign } from './sign';
import { ChaoxingUtils } from './utils';

const TAG = 'CloudUpload';
const DOMAIN = 0x0011;
const UPLOAD_TIMEOUT_MS = 30000;

/**
 * 上传图片到超星云盘，返回 objectId
 * （拍照签到与人脸照片共用；内部完成 _token 获取与 multipart 上传）
 *
 * @param context UIAbilityContext
 * @param cookies 用户 Cookie
 * @param puid 用户 puid
 * @param srcUri 本地图片路径或媒体库 URI
 */
export async function uploadImageForObject(context: Context, cookies: string, puid: string,
  srcUri: string): Promise<string> {
  const token = await Sign.GetToken(cookies);
  const fileName = ChaoxingUtils.generatePhotoName() + '.jpg';
  const copyFilePath = context.cacheDir + '/' + fileName;
  fs.copyFileSync(srcUri, copyFilePath);
  const uploadConfig: request.UploadConfig = {
    url: `${ChaoXingApi.URL_UPLOAD_PHOTO.toString()}&_token=${token}`,
    method: 'POST',
    header: { 'Content-Type': 'multipart/form-data' },
    files: [{
      filename: fileName,
      type: 'jpg',
      name: 'file',
      uri: `internal://cache/${fileName}`
    }],
    data: [{ name: 'puid', value: puid }]
  };
  const task = await request.uploadFile(context, uploadConfig);
  return await new Promise<string>((resolve, reject) => {
    let settled = false;
    task.on('headerReceive', (value) => {
      if (settled || !(value && value['body'])) {
        return;
      }
      try {
        const bodyObj = JSON.parse(value['body']) as object;
        const objectId = bodyObj['objectId'] as string;
        if (objectId) {
          settled = true;
          resolve(objectId);
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Failed to parse upload response', e);
      }
    });
    task.on('fail', () => {
      if (!settled) {
        settled = true;
        reject(new Error('图片上传失败'));
      }
    });
    setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error('图片上传超时'));
      }
    }, UPLOAD_TIMEOUT_MS);
  });
}
