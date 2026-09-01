import { ChaoxingUtils } from './utils';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { ChaoXingApi } from './PublicAPI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JSON, util } from '@kit.ArkTS';
import CryptoJS from '@ohos/crypto-js';
import { systemDateTime } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const buildURL = ChaoxingUtils.buildUrl;

// 定义日志标签（便于筛选）
const TAG = 'SignService';
const DOMAIN = 0x0002; // 日志域（自定义即可）

// 常量定义
const SIGN_TIME_MARKER = '<p class="signtime">';
const SIGN_EXPIRED_MARKER = '下次早点哦';
const SIGN_NO_PERMISSION_MARKER = '校验失败，未查询到活动数据';
const CAPTCHA_CALLBACK = 'cx_captcha_function';
const CAPTCHA_TYPE = 'slide';
const CAPTCHA_VERSION = '1.1.20';
const TOKEN_EXPIRY_MS = 300000; // 5分钟
const NO_SIGN_OFF_EVENT = 4999; // 上游约定：signOutPublishTimeStamp==4999 表示无签退

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
  'imageVerificationVo': Img
  'captchaId': string
  'type': string
  'version': string
  'captchaKey': string
  'iv': string
}

export interface Img {
  shadeImage: string;
  cutoutImage: string;
}

export interface UserQueryObject {
  uid: string;
  fid: string;
  name: string;
}

export interface CommonSignParams {
  activeId: string;
  latitude: string;
  longitude: string;
  address: string;
  enc: string;
  objectId?: string;
  signCode?: string;
  validate?:string
  location?: string;
  courseId?: string;
  currentFaceId?: string;
  faceEnc?: string;
}

/** 完整活动详情（getPPTActiveInfo 的 data 字段） */
export interface SignDetailResult extends SignInfoResult {
  ifNeedVCode: number;
  openCheckFaceFlag: number;
  ifphoto: boolean;
  locationLatitude: string;
  locationLongitude: string;
  locationRange: number;
  ifopenAddress: number;
  ifrefreshewm: number;
  otherId: string;
}

/** 签到结果统一解析（对齐上游 checkSignResult 的全部状态） */
export interface SignOutcome {
  kind: string; // success | already | captcha | ended | qrcodeExpired | wrongPosition | face | error
  message: string;
  needCaptcha: boolean;
}

/** 待签到的用户信息（含 puid，与上游签到参数一致） */
export interface SignUserParam {
  cookies: string;
  uname: string;
  uid: string;
  fid: string;
}

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

export class Sign {
  // 上游设备信息 RSA 公钥（X509）解析出的模数与指数，用于 clientId 解密
  static readonly CLIENT_ID_RSA_MODULUS_HEX =
    'BBF5DF0EB748426F1C522120BAC7C482C1306CA454B394B28725462AA0536ED534916B0E2111890E9EF11A2F5572A3157A1D7703AF3C18BDA15969968F40F1677C21D9CB9750C3172689F8121EA4BEA0A5F0E3462CE1C548AA753977DD12EC459245D060957E3CF6396A55A35C412903C764D8982F836C0ABD155FC1534F4849'
  static readonly CLIENT_ID_RSA_EXPONENT = 65537
  static readonly CLIENT_ID_BLOCK_SIZE = 128

  /**
   * 预签到（对齐上游：POST ext 表单 + 分析回传）
   * @param activePrimaryId 签到id
   * @param classId
   * @param courseId
   * @param uid
   * @param cookies
   * @param ext 活动列表返回的 data.ext 原样字符串
   * @returns -1 = 无权限 | 0 = 已签到 | 1 = 可签到 | 2 = 已截止
   */
  static async PreSignIn(activePrimaryId: string, classId: string, courseId: string, uid: number,
    cookies: string, ext: string = ''): Promise<number> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_PRE_SIGN.buildUrl({
        activePrimaryId: activePrimaryId,
        classId: classId,
        courseId: courseId,
        uid: uid
      }).toString(), {
        method: http.RequestMethod.POST,
        extraData: `ext=${encodeURIComponent(ext)}`,
        header: {
          'Cookie': cookies,
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      })
      hilog.debug(DOMAIN, TAG, 'PreSignIn request sent');
      const body = result.result as string
      if (result.responseCode === 302 || body.includes(SIGN_NO_PERMISSION_MARKER)) {
        return -1
      }
      await Sign.postAnalysis(cookies, activePrimaryId)
      if (body.includes(SIGN_EXPIRED_MARKER)) {
        return 2
      }
      if (body.includes(SIGN_TIME_MARKER)) {
        return 0
      }
      return 1
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 签到行为分析回传（对齐上游 postAnalysis/postAfterAnalysis）
   * 失败不阻断签到流程
   */
  static async postAnalysis(cookies: string, activeId: string): Promise<void> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_ANALYSIS.buildUrl({ 'aid': activeId }).toString(), {
        method: http.RequestMethod.GET,
        header: { 'Cookie': cookies }
      })
      const match = /code='\+'([a-f0-9]+)'/.exec(result.result.toString())
      if (match && match[1]) {
        const analysisRequest = http.createHttp()
        try {
          await analysisRequest.request(
            ChaoXingApi.URL_AFTER_ANALYSIS2.buildUrl({ 'code': match[1] }).toString(), {
            method: http.RequestMethod.GET,
            header: { 'Cookie': cookies }
          })
        } finally {
          analysisRequest.destroy()
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Post analysis failed: ${(error as Error).message}`)
    } finally {
      httpRequest.destroy()
    }
  }

  static async DoSignInV2(cookies: string, commonQueryParams: CommonSignParams, userQueryParams: UserQueryObject,
    validate?: string) {
    const deviceCode = await Sign.generateDeviceCode()
    // 仅附加有值的可选参数（对齐上游各 Signer 的参数构造）
    const commonParams: CommonSignParams = {
      activeId: commonQueryParams.activeId,
      latitude: commonQueryParams.latitude,
      longitude: commonQueryParams.longitude,
      address: commonQueryParams.address,
      enc: commonQueryParams.enc
    }
    if (commonQueryParams.objectId) {
      commonParams.objectId = commonQueryParams.objectId
    }
    if (commonQueryParams.signCode) {
      commonParams.signCode = commonQueryParams.signCode
    }
    if (commonQueryParams.location) {
      commonParams.location = commonQueryParams.location
    }
    if (commonQueryParams.currentFaceId && commonQueryParams.faceEnc) {
      commonParams.currentFaceId = commonQueryParams.currentFaceId
      commonParams.faceEnc = commonQueryParams.faceEnc
      commonParams.courseId = commonQueryParams.courseId
    }
    const builder = ChaoXingApi.URL_SIGN.buildUrl(commonParams)
      .buildUrl(userQueryParams)
      .buildUrl({
        deviceCode: deviceCode
      })
    if (commonParams.currentFaceId) {
      builder.buildUrl({ 'ifCFP': '0', 'faceCode': '', 'faceEncAid': '' })
    }
    if (validate) {
      builder.buildUrl({ 'validate': validate })
    }
    const url = builder.toString()
    hilog.debug(DOMAIN, TAG, 'Executing sign-in V2 request');
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
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Sign out failed: ${error.message}`);
      throw new Error(`Sign out failed: ${error.message}`)
    }
  }

  /**
   * 获取签到详细信息（包含签退信息）
   * @param cookies 用户 Cookie
   * @param activeId 活动 ID
   * @returns 签到信息对象
   */
  static async GetSignInfo(cookies: string, activityId: string): Promise<SignInfoResult> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_GET_SIGN_INFO.buildUrl({ 'activeId': activityId }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const jsonResult = JSON.parse(result.result as string) as object
      const signOutPublishTimeStamp = (jsonResult?.['signOutPublishTimeStamp'] as number) ?? -1
      return {
        signInId: (jsonResult?.['signInId'] as number) ?? 0,
        signOutId: (jsonResult?.['signOutId'] as number) ?? 0,
        signOutPublishTimeStamp: signOutPublishTimeStamp === NO_SIGN_OFF_EVENT ? 0 : signOutPublishTimeStamp,
        numberCount: (jsonResult?.['numberCount'] as number) ?? 0
      } as SignInfoResult
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Get sign info failed: ${error.message}`);
      throw new Error(`Get sign info failed: ${error.message}`)
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 获取活动完整详情（getPPTActiveInfo 的 data）
   * 包含验证码/人脸/拍照/位置要求等签到前置信息
   */
  static async GetActiveDetail(cookies: string, activityId: string): Promise<SignDetailResult> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_IF_PHOTO.buildUrl({ 'activeId': activityId }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const body = JSON.parse(result.result as string) as object
      const data = (body?.['data'] ?? JSON.parse('{}')) as object
      const signOutPublishTimeStamp = (data?.['signOutPublishTimeStamp'] as number) ?? -1
      const detail: SignDetailResult = {
        signInId: (data?.['signInId'] as number) ?? 0,
        signOutId: (data?.['signOutId'] as number) ?? 0,
        signOutPublishTimeStamp: signOutPublishTimeStamp === NO_SIGN_OFF_EVENT ? 0 : signOutPublishTimeStamp,
        numberCount: (data?.['numberCount'] as number) ?? 0,
        ifNeedVCode: (data?.['ifNeedVCode'] as number) ?? 0,
        openCheckFaceFlag: (data?.['openCheckFaceFlag'] as number) ?? 0,
        ifphoto: (data?.['ifphoto'] as boolean) ?? false,
        locationLatitude: `${data?.['locationLatitude'] ?? ''}`,
        locationLongitude: `${data?.['locationLongitude'] ?? ''}`,
        locationRange: (data?.['locationRange'] as number) ?? 0,
        ifopenAddress: (data?.['ifopenAddress'] as number) ?? 0,
        ifrefreshewm: (data?.['ifrefreshewm'] as number) ?? 0,
        otherId: `${data?.['otherId'] ?? ''}`
      }
      return detail
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Get active detail failed: ${error.message}`);
      throw new Error(`Get active detail failed: ${error.message}`)
    } finally {
      httpRequest.destroy()
    }
  }

  static async GetLocationSignInfo(cookies: string, activityId: string): Promise<object> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_GET_LOCATION_SIGN_INFO.buildUrl({ 'activeId': activityId }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const body = JSON.parse(result.result as string) as object
      return body?.['data'] as object
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Get location sign info failed: ${error.message}`);
      return JSON.parse('{}') as object
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
  static async CheckSignCode(cookies: string, activityId: string, signCode: string): Promise<boolean> {
    const httpRequest = http.createHttp()
    const url = ChaoXingApi.URL_CHECK_SIGN_CODE.buildUrl({
      'activeId': activityId,
      'signCode': signCode
    }).toString()
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      const jsonResult = JSON.parse(result.result as string) as object
      return (jsonResult?.['result'] as number) === 1
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Check sign code failed: ${error.message}`);
      return false
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
      const tokenResponse: string = result.result.toString()
      hilog.debug(DOMAIN, TAG, 'Token response received');
      const token: string = (JSON.parse(tokenResponse) as object)?.['_token'] as string
      hilog.info(DOMAIN, TAG, `token obtained: ${token ? 'success' : 'failed'}`);
      return token
    } catch (error) {
      const errorMsg = `GetToken failed: ${error instanceof Error ? error.message : String(error)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      return errorMsg
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
      const captchaConfig =
        JSON.parse(result.result.toString().replace(`${CAPTCHA_CALLBACK}(`, "").replace(")", "")) as CaptchaConf
      return captchaConfig.t as number
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
  static async getCaptchaPhotos(captchaParams: CaptchaPhotosParam, cookies: string): Promise<CaptchaPhotosResult> {
    const serverTime = await Sign.getCaptchaConf()
    const type = CAPTCHA_TYPE
    const captchaKey = CryptoJS.MD5(serverTime.toString() + ChaoxingUtils.generateUUIDv4()).toString()
    const iv =
      CryptoJS.MD5(ChaoXingApi.CAPTCHA_ID + type + systemDateTime.getTime() + ChaoxingUtils.generateUUIDv4()).toString()
    const token = CryptoJS.MD5(serverTime.toString() + ChaoXingApi.CAPTCHA_ID + type + captchaKey) +
      `:${serverTime + TOKEN_EXPIRY_MS}`

    const referer = ChaoXingApi.URL_PRE_SIGN.buildUrl(captchaParams).toString()
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
      const captchaResult =
        JSON.parse(result.result.toString().replace(`${CAPTCHA_CALLBACK}(`, "").replace(")", "")) as CaptchaPhotosResult
      captchaResult.captchaId = ChaoXingApi.CAPTCHA_ID
      captchaResult.type = type
      captchaResult.version = CAPTCHA_VERSION
      captchaResult.captchaKey = captchaKey
      captchaResult.iv = iv
      return captchaResult
    } finally {
      httpRequest.destroy()
    }
  }

  static async checkCaptchaResult(captcha: CaptchaPhotosResult, xPosition: number, refererParams: CaptchaPhotosParam,
    cookies: string): Promise<string | null> {
    const httpRequest = http.createHttp()
    try {
      const referer = ChaoXingApi.URL_PRE_SIGN.buildUrl(refererParams).toString()
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
      }).toString()

      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'referer': referer, 'Cookie': cookies }
      })

      const body = result.result.toString().replace(`${CAPTCHA_CALLBACK}(`, '').replace(')', '')
      const jsonResult = JSON.parse(body) as object

      if ((jsonResult?.['error'] as number) === 1) {
        hilog.error(DOMAIN, TAG, `Captcha check failed: ${jsonResult?.['msg'] as string}`);
        return null
      }

      if ((jsonResult?.['result'] as boolean)) {
        const extraData = JSON.parse((jsonResult?.['extraData'] as string).replace(/\\"/g, '"')) as object
        return extraData?.['validate'] as string
      }

      return null
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Check captcha result failed: ${(error as Error).message}`);
      return null
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 生成设备码（对齐上游 deviceCode：sha256(双UUID去-) 后 Base64(raw+raw)，88 字符）
   */
  static async generateDeviceCode(): Promise<string> {
    try {
      const uuidRaw = ChaoxingUtils.generateUUIDv4().replace(/-/g, '') + ChaoxingUtils.generateUUIDv4().replace(/-/g, '')
      const md = cryptoFramework.createMd('SHA256')
      await md.update({ data: new util.TextEncoder().encodeInto(uuidRaw) })
      const digest = await md.digest()
      const doubled = new Uint8Array(digest.data.length * 2)
      doubled.set(digest.data, 0)
      doubled.set(digest.data, digest.data.length)
      return new util.Base64Helper().encodeToStringSync(doubled)
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Generate device code failed: ${(error as Error).message}`)
      return ChaoxingUtils.generateUUIDv4()
    }
  }

  /**
   * 解密 clientId（对齐上游 ChaoxingDeviceInfoHelper.decryptClientId：
   * 固定 RSA 公钥 modPow 还原 PKCS1 type-1 块得到 JSON {cid, sc}）
   */
  static decryptClientId(clientId: string): ClientIdInfo | null {
    try {
      const encrypted = new util.Base64Helper().decodeSync(clientId)
      const modulus = BigInt('0x' + Sign.CLIENT_ID_RSA_MODULUS_HEX)
      const exponent = BigInt(Sign.CLIENT_ID_RSA_EXPONENT)
      let output = ''
      for (let offset = 0; offset < encrypted.length; offset += Sign.CLIENT_ID_BLOCK_SIZE) {
        let cipher = 0n
        const end = Math.min(offset + Sign.CLIENT_ID_BLOCK_SIZE, encrypted.length)
        for (let i = offset; i < end; i++) {
          cipher = (cipher << 8n) | BigInt(encrypted[i])
        }
        let result = 1n
        let base = cipher % modulus
        let exp = exponent
        while (exp > 0n) {
          if ((exp & 1n) === 1n) {
            result = (result * base) % modulus
          }
          base = (base * base) % modulus
          exp = exp >> 1n
        }
        const block = new Uint8Array(Sign.CLIENT_ID_BLOCK_SIZE)
        let value = result
        for (let i = Sign.CLIENT_ID_BLOCK_SIZE - 1; i >= 0; i--) {
          block[i] = Number(value & 0xffn)
          value = value >> 8n
        }
        if (!(block.length > 2 && block[0] === 0 && block[1] === 1)) {
          return null
        }
        let separator = -1
        for (let i = 2; i < block.length; i++) {
          if (block[i] === 0) {
            separator = i
            break
          }
        }
        if (separator <= 2) {
          return null
        }
        output += new util.TextDecoder('utf-8').decodeToString(block.subarray(separator + 1, block.length))
      }
      const info = JSON.parse(output) as ClientIdInfo
      if (!info.cid || !info.sc) {
        return null
      }
      return info
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Decrypt client id failed: ${(error as Error).message}`)
      return null
    }
  }

  /**
   * 构造人脸结果 JSON（对齐上游 buildFaceResult，含 signToken）
   */
  static buildFaceResult(objectId: string, clientId?: string): string {
    const cxtime = systemDateTime.getTime().toString()
    const faceResult: FaceResultParam = {
      currentFaceId: objectId,
      LiveDetectionStatus: 1,
      collectStatus: 1,
      cxtime: cxtime
    }
    if (clientId) {
      const deviceInfo = Sign.decryptClientId(clientId)
      if (deviceInfo) {
        faceResult.cxcid = deviceInfo.cid
        const keys: string[] = ['LiveDetectionStatus', 'collectStatus', 'currentFaceId', 'cxcid', 'cxtime']
        const values: string[] = ['1', '1', objectId, deviceInfo.cid, cxtime]
        let raw = ''
        for (let i = 0; i < keys.length; i++) {
          raw += keys[i] + values[i]
        }
        raw += deviceInfo.sc
        faceResult.signToken = CryptoJS.MD5(raw).toString()
      }
    }
    return JSON.stringify(faceResult)
  }

  /**
   * 获取账号默认人脸照片的 objectId
   */
  static async GetProfileFaceObjectId(cookies: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_GET_PROFILE_FACE_IMAGE.toString(), {
        method: http.RequestMethod.GET,
        header: { 'Cookie': cookies }
      })
      const jsonResult = JSON.parse(result.result.toString()) as object
      const oldObjectId = (jsonResult?.['data'] as object)?.['oldObjectId'] as string
      if (!oldObjectId) {
        throw new Error('获取人脸照片ID失败')
      }
      return oldObjectId
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 校验人脸结果并获取 faceEnc（对齐上游 checkFaceResultAndGetEnc）
   * @param clientId 用户信息接口返回的 clientId（可空，用于计算 signToken）
   */
  static async CheckFaceResultAndGetEnc(cookies: string, activeId: string, objectId: string,
    clientId?: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      const url = ChaoXingApi.URL_CHECK_FACE_RESULT.buildUrl({
        'activeId': activeId,
        'faceResult': Sign.buildFaceResult(objectId, clientId)
      }).toString()
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Cookie': cookies }
      })
      const jsonResult = JSON.parse(result.result.toString()) as object
      const enc = jsonResult?.['enc'] as string
      if (!enc) {
        throw new Error('获取faceEnc失败')
      }
      return enc
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 按 objectId 下载云盘人脸照片到指定文件
   */
  static async DownloadFaceImage(objectId: string, filePath: string): Promise<void> {
    const httpRequest = http.createHttp()
    const url = `${ChaoXingApi.URL_FACE_SHARED_IMAGE}${objectId}/origin.jpg`
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 30000
      })
      if (result.responseCode !== 200) {
        throw new Error(`下载人脸照片失败(${result.responseCode})`)
      }
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNCATE)
      fs.writeSync(file.fd, result.result as ArrayBuffer)
      fs.closeSync(file)
    } finally {
      httpRequest.destroy()
    }
  }

  private static async httpGetString(requestUrl: string, cookies: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      const result = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.GET,
        header: { "Cookie": cookies }
      })
      return result.result.toString()
    } finally {
      httpRequest.destroy()
    }
  }
}

export interface SignInfoResult {
  signInId: number;
  signOutId: number;
  signOutPublishTimeStamp: number;
  numberCount: number;
}

// 上游 ChaoxingDeviceInfoHelper 的固定 RSA 公钥（X509）解析出的模数与指数
// 仅用于解密 clientId（modPow 还原明文），不做任何加密用途
// 上游公钥 base64: MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC79d8Ot0hCbxxSISC6x8SCwTBspFSzlLKHJUYqoFNu1TSRaw4hEYkOnvEaL1VyoxV6HXcDrzwYvaFZaZaPQPFnfCHZy5dQwxcmifgSHqS+oKXw40Ys4cVIqnU5d90S7EWSRdBglX489jlqVaNcQSkDx2TYmC+DbAq9FV/BU09ISQIDAQAB

export function parseSignResult(raw: string): SignOutcome {
  if (raw === 'success') {
    return { kind: 'success', message: '签到成功', needCaptcha: false }
  }
  if (raw.startsWith('[face]')) {
    return { kind: 'face', message: `人脸校验未通过: ${raw.substring(6)}`, needCaptcha: false }
  }
  if (raw === 'success2') {
    return { kind: 'ended', message: '迟到或签到已结束', needCaptcha: false }
  }
  if (raw === '签到失败，请重新扫描。') {
    return { kind: 'qrcodeExpired', message: '签到二维码已过期，请重新扫码', needCaptcha: false }
  }
  if (raw.startsWith('errorLocation')) {
    const distance = parseFloat(raw.split('_')[1])
    let message = '位置不在设置范围内'
    if (!isNaN(distance)) {
      message += `，距离签到点${distance}米`
    }
    return { kind: 'wrongPosition', message: message, needCaptcha: false }
  }
  if (raw === '您已签到过了') {
    return { kind: 'already', message: '您已签到过了', needCaptcha: false }
  }
  if (raw.startsWith('validate')) {
    return { kind: 'captcha', message: '需要验证码', needCaptcha: true }
  }
  if (raw.includes('<html') || raw.includes('500 Internal Server Error')) {
    return { kind: 'error', message: '服务端错误 (500)', needCaptcha: false }
  }
  return { kind: 'error', message: raw, needCaptcha: false }
}
