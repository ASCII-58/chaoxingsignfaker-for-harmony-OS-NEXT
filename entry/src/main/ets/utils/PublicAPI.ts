// 1. 定义 BuildableUrl 类
class BuildableUrl {
  constructor(public readonly url: string) {
  }

  buildUrl(params?: Record<string, any>): BuildableUrl {
    if (!params) {
      return this;
    }

    const parts = Object.entries(params)
      .filter(([_, value]) => value !== undefined && value !== null)
      .map(([key, value]) => {
        return `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`;
      });

    const queryString = parts.join('&');
    if (queryString === '') {
      return this;
    }

    const separator = this.url.includes('?') ? '&' : '?';
    const newUrl = `${this.url}${separator}${queryString}`
    return new BuildableUrl(newUrl);
  }

  toString() {
    return this.url;
  }

  toJSON() {
    return this.url;
  }

  valueOf() {
    return this.url;
  }
}

// 2. 类型扩展（让 TS 不报错）
declare global {
  interface String {
    buildUrl?(params?: Record<string, any>): string;
  }
}

// 3. 定义 API 常量
export const GITHUB_RUST_API = 'https://api.github.com/repos/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT/releases/tags/v'
/**
 * 超星通用接口
 */
export class ChaoXingApi {
  /**
   * 正式签到基础URL
   */
  static readonly URL_SIGN = new BuildableUrl(
    'https://mobilelearn.chaoxing.com/pptSign/stuSignajax?&clientip=&appType=15&ifTiJiao=1&vpProbability=-1&vpStrategy=');
  /**
   * 预签到基础URL
   */
  static readonly URL_PRE_SIGN = new BuildableUrl(
    'https://mobilelearn.chaoxing.com/newsign/preSign?&general=1&sys=1&ls=1&appType=15&isTeacherViewOpen=0'
  );
  static readonly URL_GET_ACTIVITY_LIST =
    'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist?fid=0&showNotStartedActive=0'
  static readonly URL_GET_COURSE_LIST = 'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1'
  static readonly URL_UPLOAD_PHOTO = new BuildableUrl(
    'https://pan-yz.chaoxing.com/upload?_from=mobilelearn'
  );
  /**
   * 获取图片上传所需的token
   */
  static readonly URL_GET_TOKEN = 'https://pan-yz.chaoxing.com/api/token/uservalid';

  static readonly URL_IF_PHOTO = new BuildableUrl('https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo?')
  /**
   * 登录
   */
  static readonly URL_LOGIN = "https://passport2.chaoxing.com/fanyalogin"
  static readonly URL_GET_USER_INFO = "https://sso.chaoxing.com/apis/login/userLogin4Uname.do"
  static readonly URL_GET_CAPTCHA_CONF =
    new BuildableUrl("https://captcha.chaoxing.com/captcha/get/conf?callback=cx_captcha_function")
  static readonly CAPTCHA_ID = 'Qt9FIw9o4pwRjOyqM6yizZBh682qN2TU'
  static readonly URL_GET_CAPTCHA_PHOTOS =
    new BuildableUrl("https://captcha.chaoxing.com/captcha/get/verification/image")
  static readonly UA =
    '5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0'
  static readonly URL_GET_LOCATION_SIGN_INFO =
    new BuildableUrl('https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo')
  static readonly URL_CHECK_CAPTCHA_RESULT =
    new BuildableUrl('https://captcha.chaoxing.com/captcha/check/verification/result?callback=cx_captcha_function')
  /**
   * 获取签到详细信息（包含签退信息）
   */
  static readonly URL_GET_SIGN_INFO = new BuildableUrl('https://mobilelearn.chaoxing.com/newsign/signDetail')
  /**
   * 检查手势/签到码
   */
  static readonly URL_CHECK_SIGN_CODE =
    new BuildableUrl('https://mobilelearn.chaoxing.com/widget/sign/pcStuSignController/checkSignCode')
  /**
   * 签退
   */
  static readonly URL_SIGN_OUT = new BuildableUrl('https://mobilelearn.chaoxing.com/newsign/signOut')
  /**
   * 签到行为分析（preSign 后调用）
   */
  static readonly URL_ANALYSIS =
    new BuildableUrl('https://mobilelearn.chaoxing.com/pptSign/analysis?vs=1&DB_STRATEGY=RANDOM')
  static readonly URL_AFTER_ANALYSIS2 =
    new BuildableUrl('https://mobilelearn.chaoxing.com/pptSign/analysis2?DB_STRATEGY=RANDOM')
  /**
   * 人脸识别：校验人脸结果并获取 faceEnc
   */
  static readonly URL_CHECK_FACE_RESULT =
    new BuildableUrl('https://mobilelearn.chaoxing.com/pptSign/check-face-result?DB_STRATEGY=PRIMARY_KEY&STRATEGY_PARA=activeId')
  /**
   * 人脸识别：获取账号默认人脸照片 objectId
   */
  static readonly URL_GET_PROFILE_FACE_IMAGE =
    new BuildableUrl('https://mobilelearn.chaoxing.com/v2/apis/sign/collectionfilephotoEnc?DB_STRATEGY=DEFAULT')
  /**
   * 人脸识别：按 objectId 下载云盘人脸照片
   */
  static readonly URL_FACE_SHARED_IMAGE = 'https://p.cldisk.com/star4/'
}

export class InternalPath {
  /**
   * 同context.cacheDir
   */
  static readonly CACHE_PATH = 'internal://cache/'
}
