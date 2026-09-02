import { ChaoXingApi } from './PublicAPI';
import { Http } from './httpClient';
import { Sign } from './sign';
import { ChaoxingUtils } from './utils';
import { JSON } from '@kit.ArkTS';
import CryptoJS from '@ohos/crypto-js';
import { systemDateTime } from '@kit.BasicServicesKit';

const CAPTCHA_CALLBACK = 'cx_captcha_function';
const CAPTCHA_TYPE = 'slide';
const CAPTCHA_VERSION = '1.1.20';
const TOKEN_EXPIRY_MS = 300000; // 5分钟

export interface CaptchaConf {
  t?: number;
  error?: number;
}

export interface CaptchaPhotosParam {
  courseId: string;
  classId: string;
  activePrimaryId: string;
  uid: string;
}

export interface CaptchaPhotosResult {
  'token': string
  'imageVerificationVo': CaptchaImg
  'captchaId': string
  'type': string
  'version': string
  'captchaKey': string
  'iv': string
}

export interface CaptchaImg {
  shadeImage: string;
  cutoutImage: string;
}

/**
 * 超星风控滑块验证码（获取配置/拉取滑块图/校验结果）
 */
export class CaptchaApi {
  static async getCaptchaConf(): Promise<number> {
    const captchaConfig = await Http.getJsonp(
      ChaoXingApi.URL_GET_CAPTCHA_CONF.buildUrl({
        'captchaId': ChaoXingApi.CAPTCHA_ID,
        '_': systemDateTime.getTime().toString()
      }).toString(), CAPTCHA_CALLBACK) as CaptchaConf;
    return captchaConfig.t as number;
  }

  /**
   * 获取滑块验证码图片（附带本地生成的 captchaKey/iv/token 等回填字段）
   */
  static async getCaptchaPhotos(captchaParams: CaptchaPhotosParam, cookies: string): Promise<CaptchaPhotosResult> {
    const serverTime = await CaptchaApi.getCaptchaConf();
    const captchaKey = CryptoJS.MD5(serverTime.toString() + ChaoxingUtils.generateUUIDv4()).toString();
    const iv =
      CryptoJS.MD5(ChaoXingApi.CAPTCHA_ID + CAPTCHA_TYPE + systemDateTime.getTime() + ChaoxingUtils.generateUUIDv4())
        .toString();
    const token = CryptoJS.MD5(serverTime.toString() + ChaoXingApi.CAPTCHA_ID + CAPTCHA_TYPE + captchaKey) +
      `:${serverTime + TOKEN_EXPIRY_MS}`;

    const referer = ChaoXingApi.URL_PRE_SIGN.buildUrl(captchaParams).toString();
    const url = ChaoXingApi.URL_GET_CAPTCHA_PHOTOS.buildUrl({
      'callback': CAPTCHA_CALLBACK,
      'captchaId': ChaoXingApi.CAPTCHA_ID,
      'type': CAPTCHA_TYPE,
      'version': CAPTCHA_VERSION,
      'captchaKey': captchaKey,
      'token': token,
      'iv': iv,
      '_': systemDateTime.getTime().toString(),
      'referer': referer
    }).toString();
    const captchaResult = await Http.getJsonp(url, CAPTCHA_CALLBACK, cookies, { 'referer': referer }) as
      CaptchaPhotosResult;
    captchaResult.captchaId = ChaoXingApi.CAPTCHA_ID;
    captchaResult.type = CAPTCHA_TYPE;
    captchaResult.version = CAPTCHA_VERSION;
    captchaResult.captchaKey = captchaKey;
    captchaResult.iv = iv;
    return captchaResult;
  }

  /**
   * 校验滑块位置，成功返回 extraData.validate，失败返回 null
   */
  static async checkCaptchaResult(captcha: CaptchaPhotosResult, xPosition: number, refererParams: CaptchaPhotosParam,
    cookies: string): Promise<string | null> {
    try {
      const referer = ChaoXingApi.URL_PRE_SIGN.buildUrl(refererParams).toString();
      const url = ChaoXingApi.URL_CHECK_CAPTCHA_RESULT.buildUrl({
        'captchaId': captcha.captchaId,
        'type': captcha.type,
        'token': captcha.token,
        'textClickArr': `[{"x":${Math.round(xPosition)}}]`,
        'coordinate': '[]',
        'runEnv': '10',
        'version': captcha.version,
        't': 'a',
        'iv': captcha.iv,
        '_': systemDateTime.getTime().toString()
      }).toString();
      const jsonResult = await Http.getJsonp(url, CAPTCHA_CALLBACK, cookies, { 'referer': referer });
      if ((jsonResult?.['error'] as number) === 1) {
        return null;
      }
      if ((jsonResult?.['result'] as boolean)) {
        const extraData = JSON.parse((jsonResult?.['extraData'] as string).replace(/\\"/g, '"')) as object;
        return extraData?.['validate'] as string;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
