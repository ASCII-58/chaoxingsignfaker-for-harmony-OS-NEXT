import { ChaoXingApi } from './PublicAPI';
import { Http } from './httpClient';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JSON, util } from '@kit.ArkTS';
import { systemDateTime } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ChaoxingUtils } from './utils';

const TAG = 'SignService';
const DOMAIN = 0x0002; // 日志域（自定义即可）

// 常量定义
const SIGN_TIME_MARKER = '<p class="signtime">';
const SIGN_EXPIRED_MARKER = '下次早点哦';
const SIGN_NO_PERMISSION_MARKER = '校验失败，未查询到活动数据';
const NO_SIGN_OFF_EVENT = 4999; // 上游约定：signOutPublishTimeStamp==4999 表示无签退
const NEXT_SIGN_INTERVAL_MS = 200; // 对齐上游：代签用户之间的间隔

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
  validate?: string;
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

export interface SignInfoResult {
  signInId: number;
  signOutId: number;
  signOutPublishTimeStamp: number;
  numberCount: number;
}

export function parseSignResult(raw: string): SignOutcome {
  if (raw === 'success') {
    return { kind: 'success', message: '签到成功', needCaptcha: false };
  }
  if (raw.startsWith('[face]')) {
    return { kind: 'face', message: `人脸校验未通过: ${raw.substring(6)}`, needCaptcha: false };
  }
  if (raw === 'success2') {
    return { kind: 'ended', message: '迟到或签到已结束', needCaptcha: false };
  }
  if (raw === '签到失败，请重新扫描。') {
    return { kind: 'qrcodeExpired', message: '签到二维码已过期，请重新扫码', needCaptcha: false };
  }
  if (raw.startsWith('errorLocation')) {
    const distance = parseFloat(raw.split('_')[1]);
    let message = '位置不在设置范围内';
    if (!isNaN(distance)) {
      message += `，距离签到点${distance}米`;
    }
    return { kind: 'wrongPosition', message: message, needCaptcha: false };
  }
  if (raw === '您已签到过了') {
    return { kind: 'already', message: '您已签到过了', needCaptcha: false };
  }
  if (raw.startsWith('validate')) {
    return { kind: 'captcha', message: '需要验证码', needCaptcha: true };
  }
  if (raw.includes('<html') || raw.includes('500 Internal Server Error')) {
    return { kind: 'error', message: '服务端错误 (500)', needCaptcha: false };
  }
  return { kind: 'error', message: raw, needCaptcha: false };
}

/**
 * 超星签到核心：预签到/行为分析/执行签到/签退/签到详情
 * 验证码见 captchaApi.ets，人脸见 faceApi.ets
 */
export class Sign {
  static readonly NEXT_SIGN_INTERVAL_MS = NEXT_SIGN_INTERVAL_MS;

  /**
   * 预签到（对齐上游：POST ext 表单 + 分析回传）
   * @returns -1 = 无权限 | 0 = 已签到 | 1 = 可签到 | 2 = 已截止
   */
  static async PreSignIn(activePrimaryId: string, classId: string, courseId: string, uid: number,
    cookies: string, ext: string = ''): Promise<number> {
    const url = ChaoXingApi.URL_PRE_SIGN.buildUrl({
      activePrimaryId: activePrimaryId,
      classId: classId,
      courseId: courseId,
      uid: uid
    }).toString();
    const response = await Http.postForm(url, `ext=${encodeURIComponent(ext)}`, cookies);
    hilog.debug(DOMAIN, TAG, 'PreSignIn request sent');
    if (response.code === 302 || response.body.includes(SIGN_NO_PERMISSION_MARKER)) {
      return -1;
    }
    await Sign.postAnalysis(cookies, activePrimaryId);
    if (response.body.includes(SIGN_EXPIRED_MARKER)) {
      return 2;
    }
    if (response.body.includes(SIGN_TIME_MARKER)) {
      return 0;
    }
    return 1;
  }

  /**
   * 签到行为分析回传（对齐上游 postAnalysis/postAfterAnalysis），失败不阻断签到
   */
  static async postAnalysis(cookies: string, activeId: string): Promise<void> {
    try {
      const response = await Http.get(ChaoXingApi.URL_ANALYSIS.buildUrl({ 'aid': activeId }).toString(), cookies);
      const match = /code='\+'([a-f0-9]+)'/.exec(response.body);
      if (match && match[1]) {
        await Http.get(ChaoXingApi.URL_AFTER_ANALYSIS2.buildUrl({ 'code': match[1] }).toString(), cookies);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Post analysis failed: ${(error as Error).message}`);
    }
  }

  /**
   * 执行签到（对齐上游各 Signer 的参数构造，仅附加有值的可选参数）
   */
  static async DoSignInV2(cookies: string, commonQueryParams: CommonSignParams, userQueryParams: UserQueryObject,
    validate?: string): Promise<string> {
    const deviceCode = await Sign.generateDeviceCode();
    const commonParams: CommonSignParams = {
      activeId: commonQueryParams.activeId,
      latitude: commonQueryParams.latitude,
      longitude: commonQueryParams.longitude,
      address: commonQueryParams.address,
      enc: commonQueryParams.enc
    };
    if (commonQueryParams.objectId) {
      commonParams.objectId = commonQueryParams.objectId;
    }
    if (commonQueryParams.signCode) {
      commonParams.signCode = commonQueryParams.signCode;
    }
    if (commonQueryParams.location) {
      commonParams.location = commonQueryParams.location;
    }
    if (commonQueryParams.currentFaceId && commonQueryParams.faceEnc) {
      commonParams.currentFaceId = commonQueryParams.currentFaceId;
      commonParams.faceEnc = commonQueryParams.faceEnc;
      commonParams.courseId = commonQueryParams.courseId;
    }
    let builder = ChaoXingApi.URL_SIGN.buildUrl(commonParams)
      .buildUrl(userQueryParams)
      .buildUrl({ deviceCode: deviceCode });
    if (commonParams.currentFaceId) {
      builder = builder.buildUrl({ 'ifCFP': '0', 'faceCode': '', 'faceEncAid': '' });
    }
    if (validate) {
      builder = builder.buildUrl({ 'validate': validate });
    }
    return (await Http.get(builder.toString(), cookies)).body;
  }

  /**
   * 签退
   */
  static async DoSignOut(cookies: string, signInId: number, signOutId: number): Promise<string> {
    const url = ChaoXingApi.URL_SIGN_OUT.buildUrl({
      'signInId': signInId,
      'signOutId': signOutId
    }).toString();
    return (await Http.get(url, cookies)).body;
  }

  /**
   * 获取签到详细信息（newsign/signDetail，含签退信息；4999 视为无签退归零）
   */
  static async GetSignInfo(cookies: string, activityId: string): Promise<SignInfoResult> {
    const url = ChaoXingApi.URL_GET_SIGN_INFO.buildUrl({ 'activeId': activityId }).toString();
    const jsonResult = await Http.getJson(url, cookies);
    const signOutPublishTimeStamp = (jsonResult?.['signOutPublishTimeStamp'] as number) ?? -1;
    return {
      signInId: (jsonResult?.['signInId'] as number) ?? 0,
      signOutId: (jsonResult?.['signOutId'] as number) ?? 0,
      signOutPublishTimeStamp: signOutPublishTimeStamp === NO_SIGN_OFF_EVENT ? 0 : signOutPublishTimeStamp,
      numberCount: (jsonResult?.['numberCount'] as number) ?? 0
    };
  }

  /**
   * 获取活动完整详情（getPPTActiveInfo 的 data，含验证码/人脸/拍照/位置要求）
   */
  static async GetActiveDetail(cookies: string, activityId: string): Promise<SignDetailResult> {
    const url = ChaoXingApi.URL_IF_PHOTO.buildUrl({ 'activeId': activityId }).toString();
    const body = await Http.getJson(url, cookies);
    const data = (body?.['data'] ?? JSON.parse('{}')) as object;
    const signOutPublishTimeStamp = (data?.['signOutPublishTimeStamp'] as number) ?? -1;
    return {
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
    };
  }

  /**
   * 获取位置签到要求信息（getPPTActiveInfo 的 data）
   */
  static async GetLocationSignInfo(cookies: string, activityId: string): Promise<object> {
    try {
      const url = ChaoXingApi.URL_GET_LOCATION_SIGN_INFO.buildUrl({ 'activeId': activityId }).toString();
      const body = await Http.getJson(url, cookies);
      return body?.['data'] as object ?? JSON.parse('{}') as object;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Get location sign info failed: ${error.message}`);
      return JSON.parse('{}') as object;
    }
  }

  /**
   * 检查手势/签到码是否正确
   */
  static async CheckSignCode(cookies: string, activityId: string, signCode: string): Promise<boolean> {
    try {
      const url = ChaoXingApi.URL_CHECK_SIGN_CODE.buildUrl({
        'activeId': activityId,
        'signCode': signCode
      }).toString();
      const jsonResult = await Http.getJson(url, cookies);
      return (jsonResult?.['result'] as number) === 1;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Check sign code failed: ${error.message}`);
      return false;
    }
  }

  /**
   * 获取云盘上传 token
   */
  static async GetToken(cookies: string): Promise<string> {
    try {
      const jsonResult = await Http.getJson(ChaoXingApi.URL_GET_TOKEN, cookies);
      const token: string = jsonResult?.['_token'] as string;
      hilog.info(DOMAIN, TAG, `token obtained: ${token ? 'success' : 'failed'}`);
      return token;
    } catch (error) {
      const errorMsg = `GetToken failed: ${error instanceof Error ? error.message : String(error)}`;
      hilog.error(DOMAIN, TAG, errorMsg);
      return errorMsg;
    }
  }

  /**
   * 生成设备码（对齐上游 deviceCode：sha256(双UUID去-) 后 Base64(raw+raw)，88 字符）
   */
  static async generateDeviceCode(): Promise<string> {
    try {
      const uuidRaw =
        ChaoxingUtils.generateUUIDv4().replace(/-/g, '') + ChaoxingUtils.generateUUIDv4().replace(/-/g, '');
      const md = cryptoFramework.createMd('SHA256');
      await md.update({ data: new util.TextEncoder().encodeInto(uuidRaw) });
      const digest = await md.digest();
      const doubled = new Uint8Array(digest.data.length * 2);
      doubled.set(digest.data, 0);
      doubled.set(digest.data, digest.data.length);
      return new util.Base64Helper().encodeToStringSync(doubled);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Generate device code failed: ${(error as Error).message}`);
      return ChaoxingUtils.generateUUIDv4();
    }
  }
}
