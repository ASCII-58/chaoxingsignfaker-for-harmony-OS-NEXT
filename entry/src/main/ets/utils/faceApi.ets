import { ChaoXingApi } from './PublicAPI';
import { Http, writeBufferToFile } from './httpClient';
import { JSON, util } from '@kit.ArkTS';
import CryptoJS from '@ohos/crypto-js';
import { systemDateTime } from '@kit.BasicServicesKit';

/** clientId 解密结果，用于计算人脸 signToken */
export interface ClientIdInfo {
  cid: string;
  sc: string;
}

export interface FaceResultParam {
  currentFaceId: string;
  LiveDetectionStatus: number;
  collectStatus: number;
  cxtime: string;
  cxcid?: string;
  signToken?: string;
}

/**
 * 人脸识别签到相关接口与 clientId 解密（对齐上游 ChaoxingFaceHelper/ChaoxingDeviceInfoHelper）
 */
export class FaceApi {
  // 上游设备信息 RSA 公钥（X509）解析出的模数与指数，用于 clientId 解密
  static readonly CLIENT_ID_RSA_MODULUS_HEX =
    'BBF5DF0EB748426F1C522120BAC7C482C1306CA454B394B28725462AA0536ED534916B0E2111890E9EF11A2F5572A3157A1D7703AF3C18BDA15969968F40F1677C21D9CB9750C3172689F8121EA4BEA0A5F0E3462CE1C548AA753977DD12EC459245D060957E3CF6396A55A35C412903C764D8982F836C0ABD155FC1534F4849';
  static readonly CLIENT_ID_RSA_EXPONENT = 65537;
  static readonly CLIENT_ID_BLOCK_SIZE = 128;

  /**
   * 获取账号默认人脸照片的 objectId
   */
  static async GetProfileFaceObjectId(cookies: string): Promise<string> {
    const jsonResult = await Http.getJson(ChaoXingApi.URL_GET_PROFILE_FACE_IMAGE.toString(), cookies);
    const oldObjectId = (jsonResult?.['data'] as object)?.['oldObjectId'] as string;
    if (!oldObjectId) {
      throw new Error('获取人脸照片ID失败');
    }
    return oldObjectId;
  }

  /**
   * 校验人脸结果并获取 faceEnc（对齐上游 checkFaceResultAndGetEnc）
   * @param clientId 用户信息接口返回的 clientId（可空，用于计算 signToken）
   */
  static async CheckFaceResultAndGetEnc(cookies: string, activeId: string, objectId: string,
    clientId?: string): Promise<string> {
    const url = ChaoXingApi.URL_CHECK_FACE_RESULT.buildUrl({
      'activeId': activeId,
      'faceResult': FaceApi.buildFaceResult(objectId, clientId)
    }).toString();
    const jsonResult = await Http.getJson(url, cookies);
    const enc = jsonResult?.['enc'] as string;
    if (!enc) {
      throw new Error('获取faceEnc失败');
    }
    return enc;
  }

  /**
   * 按 objectId 下载云盘人脸照片到指定文件
   */
  static async DownloadFaceImage(objectId: string, filePath: string): Promise<void> {
    const url = `${ChaoXingApi.URL_FACE_SHARED_IMAGE}${objectId}/origin.jpg`;
    writeBufferToFile(filePath, await Http.getBuffer(url));
  }

  /**
   * 构造人脸结果 JSON（对齐上游 buildFaceResult，含 signToken）
   */
  static buildFaceResult(objectId: string, clientId?: string): string {
    const cxtime = systemDateTime.getTime().toString();
    const faceResult: FaceResultParam = {
      currentFaceId: objectId,
      LiveDetectionStatus: 1,
      collectStatus: 1,
      cxtime: cxtime
    };
    if (clientId) {
      const deviceInfo = FaceApi.decryptClientId(clientId);
      if (deviceInfo) {
        faceResult.cxcid = deviceInfo.cid;
        // 对齐上游 TreeMap 排序后 key+value 拼接再附加 sc，整体 MD5
        const keys: string[] = ['LiveDetectionStatus', 'collectStatus', 'currentFaceId', 'cxcid', 'cxtime'];
        const values: string[] = ['1', '1', objectId, deviceInfo.cid, cxtime];
        let raw = '';
        for (let i = 0; i < keys.length; i++) {
          raw += keys[i] + values[i];
        }
        raw += deviceInfo.sc;
        faceResult.signToken = CryptoJS.MD5(raw).toString();
      }
    }
    return JSON.stringify(faceResult);
  }

  /**
   * 解密 clientId（固定 RSA 公钥 modPow 还原 PKCS1 type-1 块得到 JSON {cid, sc}）
   */
  static decryptClientId(clientId: string): ClientIdInfo | null {
    try {
      const encrypted = new util.Base64Helper().decodeSync(clientId);
      const modulus = BigInt('0x' + FaceApi.CLIENT_ID_RSA_MODULUS_HEX);
      const exponent = BigInt(FaceApi.CLIENT_ID_RSA_EXPONENT);
      let output = '';
      for (let offset = 0; offset < encrypted.length; offset += FaceApi.CLIENT_ID_BLOCK_SIZE) {
        let cipher = 0n;
        const end = Math.min(offset + FaceApi.CLIENT_ID_BLOCK_SIZE, encrypted.length);
        for (let i = offset; i < end; i++) {
          cipher = (cipher << 8n) | BigInt(encrypted[i]);
        }
        let result = 1n;
        let base = cipher % modulus;
        let exp = exponent;
        while (exp > 0n) {
          if ((exp & 1n) === 1n) {
            result = (result * base) % modulus;
          }
          base = (base * base) % modulus;
          exp = exp >> 1n;
        }
        const block = new Uint8Array(FaceApi.CLIENT_ID_BLOCK_SIZE);
        let value = result;
        for (let i = FaceApi.CLIENT_ID_BLOCK_SIZE - 1; i >= 0; i--) {
          block[i] = Number(value & 0xffn);
          value = value >> 8n;
        }
        if (!(block.length > 2 && block[0] === 0 && block[1] === 1)) {
          return null;
        }
        let separator = -1;
        for (let i = 2; i < block.length; i++) {
          if (block[i] === 0) {
            separator = i;
            break;
          }
        }
        if (separator <= 2) {
          return null;
        }
        output += new util.TextDecoder('utf-8').decodeToString(block.subarray(separator + 1, block.length));
      }
      const info = JSON.parse(output) as ClientIdInfo;
      if (!info.cid || !info.sc) {
        return null;
      }
      return info;
    } catch {
      return null;
    }
  }
}
