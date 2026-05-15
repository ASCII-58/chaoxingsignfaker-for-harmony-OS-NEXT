import { ChaoxingUtils } from './utils';
import http from '@ohos.net.http';
import { ChaoXingApi } from './PublicAPI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JSON } from '@kit.ArkTS';
import CryptoJS from '@ohos/crypto-js';
import { systemDateTime } from '@kit.BasicServicesKit';
import { CourseAndActivity } from './classFun';

const buildURL = ChaoxingUtils.buildUrl;

// 定义日志标签（便于筛选）
const TAG = 'SignService';
const DOMAIN = 0x0002; // 日志域（自定义即可）

// 常量定义
const SIGN_TIME_MARKER = '<p class="signtime">';
const CAPTCHA_CALLBACK = 'cx_captcha_function';
const CAPTCHA_TYPE = 'slide';
const CAPTCHA_VERSION = '1.1.20';
const TOKEN_EXPIRY_MS = 300000; // 5分钟

export interface UploadPhotoParam {
  '_token': string
}

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
  'token': string;
  'imageVerificationVo': Img
}

export interface Img {
  'shadeImage': string;
  'cutoutImage': string;
}

export interface UserQueryObject {
  uid: string;
  fid: string;
  name: string;
}

export interface SignQueryParams {
  activeId: string;
  uid: number;
  name: string;
  fid: number;
  latitude: string;
  longitude: string;
}

export interface PreSignParamInterface {
  activePrimaryId: string,
  classId: string,
  courseId: string,
  uid?: number
}

export interface CheckCaptchaParam{
  captchaId:string
  token:string
  textClickArr:string
}

export class Sign {
  private static async httpGetString(url: string, cookies: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      return result.result.toString()
    } finally {
      httpRequest.destroy()
    }
  }

  static async DoPreSignIn(PreSignParam: PreSignParamInterface, cookies: string) {
    const URL = ChaoXingApi.URL_PRE_SIGN.buildUrl(PreSignParam).toString()
    const result = await Sign.httpGetString(URL, cookies)
    return result.includes(SIGN_TIME_MARKER)
  }

  static async DoSignIn(cookies: string, queryParams: object, NeedDeviceCode: boolean = false) {
    const url = ChaoXingApi.URL_SIGN.buildUrl(queryParams).buildUrl({
      deviceCode: NeedDeviceCode ? ChaoxingUtils.generateUUIDv4() : ''
    }).toString()
    hilog.debug(DOMAIN, TAG, 'Executing sign-in request');
    return Sign.httpGetString(url, cookies)
  }

  static async DoSignInV2(cookies: string, CommonQueryParams: object, userQueryParams: UserQueryObject,
    NeedDeviceCode: boolean = false) {
    const url = ChaoXingApi.URL_SIGN.buildUrl(CommonQueryParams)
      .buildUrl(userQueryParams)
      .buildUrl({
        deviceCode: NeedDeviceCode ? ChaoxingUtils.generateUUIDv4() : ''
      })
      .toString()
    hilog.debug(DOMAIN, TAG, 'Executing sign-in V2 request');
    return Sign.httpGetString(url, cookies)
  }

  static async GetLocationSignInfo(cookies: string, activeId: string): Promise<object> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_GET_LOCATION_SIGN_INFO.buildUrl({ 'activeId': activeId }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const body = JSON.parse(result.result as string) as object
      return body?.['data'] as object
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Get location sign info failed: ${e.message}`);
      return JSON.parse('{}') as object
    } finally {
      httpRequest.destroy()
    }
  }

  static async ifPhoto(cookies: string, activeId: string): Promise<boolean> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_IF_PHOTO.buildUrl({ 'activeId': activeId }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          "Cookie": cookies
        }
      })
      const JsonResult = JSON.parse(result.result.toString()) as object
      return JsonResult?.['data']?.['ifphoto'] as boolean
    } finally {
      httpRequest.destroy()
    }
  }

  static async GetToken(cookies: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_GET_TOKEN, {
        method: http.RequestMethod.GET,
        header: {
          "Cookie": cookies
        }
      })
      const tokenOBJ: string = result.result.toString()
      hilog.debug(DOMAIN, TAG, 'Token response received');
      const token: string = (JSON.parse(tokenOBJ) as object)?.['_token'] as string
      hilog.info(DOMAIN, TAG, `token obtained: ${token ? 'success' : 'failed'}`);
      return token
    } catch (e) {
      const errorMsg = `GetToken failed: ${e instanceof Error ? e.message : String(e)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      return errorMsg
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 预签到
   * @param activePrimaryId
   * @param classId
   * @param courseId
   * @param uid
   * @param cookies
   * @returns -1 = 无权限 | 0 = 已签到 | 1 = 可签到
   */
  static async PreSignIn(activePrimaryId: string, classId: string, courseId: string, uid: number,
    cookies: string): Promise<number> {
    const activityArr = (await CourseAndActivity.getClassList(cookies)).classList
    if (activityArr.find(item => item.classId === classId) === undefined) {
      return -1
    }
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_PRE_SIGN.buildUrl({
        activePrimaryId: activePrimaryId,
        classId: classId,
        courseId: courseId,
        uid: uid
      }).toString(), {
        method: http.RequestMethod.GET,
        header: {
          "Cookie": cookies
        }
      })
      hilog.debug(DOMAIN, TAG, 'PreSignIn request sent');
      if (result.responseCode === 302 || (result.result as string).includes("校验失败，未查询到活动数据")) {
        return -1
      }
      if ((result.result as string).includes(SIGN_TIME_MARKER)) {
        return 0
      }
      return 1
    } finally {
      httpRequest.destroy()
    }
  }

  static async getCaptchaConf(): Promise<number> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_GET_CAPTCHA_CONF.buildUrl({
        'captchaId': ChaoXingApi.CAPTCHA_ID
      }).toString(), {
        method: http.RequestMethod.GET,
        header: undefined
      })
      const config =
        JSON.parse(result.result.toString().replace(`${CAPTCHA_CALLBACK}(`, "").replace(")", "")) as CaptchaConf
      return config.t as number
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 获取验证码图片
   * @param Param
   * @param cookies
   * @returns
   */
  static async getCaptchaPhotos(Param: CaptchaPhotosParam, cookies: string): Promise<CaptchaPhotosResult> {
    const t = await Sign.getCaptchaConf()
    const type = CAPTCHA_TYPE
    const captchaKey = CryptoJS.MD5(t.toString() + ChaoxingUtils.generateUUIDv4()).toString()
    const iv =
      CryptoJS.MD5(ChaoXingApi.CAPTCHA_ID + type + systemDateTime.getTime() + ChaoxingUtils.generateUUIDv4()).toString()
    const token = CryptoJS.MD5(t.toString() + ChaoXingApi.CAPTCHA_ID + type + captchaKey) + `:${t + TOKEN_EXPIRY_MS}`

    const referer = ChaoXingApi.URL_PRE_SIGN.buildUrl(Param).toString()
    let url = ChaoXingApi.URL_GET_CAPTCHA_PHOTOS.buildUrl({
      "callback": CAPTCHA_CALLBACK,
      "captchaId": ChaoXingApi.CAPTCHA_ID,
      "type": type,
      "version": CAPTCHA_VERSION,
      "captchaKey": captchaKey,
      "token": token,
      "iv": iv,
      "_": systemDateTime.getTime().toString(),
      "referer": referer
    }).toString()
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          "referer": referer,
          cookie: cookies
        }
      })
      const jsonRes =
        JSON.parse(result.result.toString().replace(`${CAPTCHA_CALLBACK}(`, "").replace(")", "")) as CaptchaPhotosResult
      return jsonRes
    } finally {
      httpRequest.destroy()
    }
  }

  static async checkCaptchaResult(ParamForCaptcha: object, ParamForRefer: PreSignParamInterface) {
    const httpRequest = http.createHttp()
    try {
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Check captcha result failed: ${e.message}`);
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 获取签到详细信息（包含签退信息）
   * @param cookies 用户 Cookie
   * @param activeId 活动 ID
   * @returns 签到信息对象
   */
  static async GetSignInfo(cookies: string, activeId: string): Promise<SignInfoResult> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_GET_SIGN_INFO.buildUrl({ 'activeId': activeId }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const jsonResult = JSON.parse(result.result as string) as object
      return {
        signInId: (jsonResult?.['signInId'] as number) ?? 0,
        signOutId: (jsonResult?.['signOutId'] as number) ?? 0,
        signOutPublishTimeStamp: (jsonResult?.['signOutPublishTimeStamp'] as number) ?? -1,
        numberCount: (jsonResult?.['numberCount'] as number) ?? 0
      } as SignInfoResult
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Get sign info failed: ${e.message}`);
      throw new Error(`Get sign info failed: ${e.message}`)
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 检查手势/签到码是否正确
   * @param cookies 用户 Cookie
   * @param activeId 活动 ID
   * @param signCode 签到码或手势码
   * @returns 是否正确
   */
  static async CheckSignCode(cookies: string, activeId: string, signCode: string): Promise<boolean> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_CHECK_SIGN_CODE.buildUrl({
      'activeId': activeId,
      'signCode': signCode
    }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const jsonResult = JSON.parse(result.result as string) as object
      return (jsonResult?.['result'] as number) === 1
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Check sign code failed: ${e.message}`);
      return false
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 手势签到或签到码签到
   * @param cookies 用户 Cookie
   * @param queryParams 查询参数（包含 activeId, uid, name, fid, latitude, longitude）
   * @param signCode 签到码或手势顺序码
   * @returns 签到结果
   */
  static async DoSignWithCode(cookies: string, queryParams: object, signCode: string): Promise<string> {
    const url = ChaoXingApi.URL_SIGN.buildUrl(queryParams).buildUrl({
      deviceCode: ChaoxingUtils.generateUUIDv4(),
      signCode: signCode
    }).toString()
    hilog.debug(DOMAIN, TAG, 'Executing sign with code request');
    return Sign.httpGetString(url, cookies)
  }

  /**
   * 签退操作
   * @param cookies 用户 Cookie
   * @param signInId 签到 ID
   * @param signOutId 签退 ID
   * @returns 签退结果
   */
  static async DoSignOut(cookies: string, signInId: number, signOutId: number): Promise<string> {
    const url = ChaoXingApi.URL_SIGN_OUT.buildUrl({
      'signInId': signInId,
      'signOutId': signOutId
    }).toString()
    hilog.debug(DOMAIN, TAG, 'Executing sign out request');
    try {
      return await Sign.httpGetString(url, cookies)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Sign out failed: ${e.message}`);
      throw new Error(`Sign out failed: ${e.message}`)
    }
  }

  /**
   * 构建签到查询参数对象
   * @param activeId 活动ID
   * @param uid 用户ID
   * @param name 用户名
   * @param fid 学校ID
   * @returns 查询参数对象
   */
  static buildSignQueryParams(activeId: string, uid: number, name: string, fid: number): SignQueryParams {
    return {
      activeId: activeId,
      uid: uid,
      name: name,
      fid: fid,
      latitude: '',
      longitude: ''
    };
  }
}

export interface SignInfoResult {
  signInId: number;
  signOutId: number;
  signOutPublishTimeStamp: number;
  numberCount: number;
}
