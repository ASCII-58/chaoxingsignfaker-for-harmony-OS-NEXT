import { image } from '@kit.ImageKit';
import http from '@ohos.net.http';
import { ChaoxingUtils } from './utils';
import { JSON, url } from '@kit.ArkTS';
import { ChaoXingApi } from './PublicAPI';
import { DatabaseManager } from './DataBase';
import { common, StartupTask } from '@kit.AbilityKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import urlTools from './urlTools'
import CryptoJS from '@ohos/crypto-js';

const TAG = 'LoginService';
const DOMAIN = 0x0001;

// 常量定义
const HTTP_TIMEOUT_MS = 60000; // 60秒超时
const ERROR_MAX_REDIRECTS = 'Number of redirects hit maximum amount';
const HTTP_SUCCESS_CODE = 200;
const USER_INFO_CACHE_TTL_MS = 300000; // 5 minutes cache TTL

export interface UserInfo {
  msg: string,
  uname: string,
  pic: string,
  uid: number,
  fid: string,
  puid:string,
  clientId: string
}

export interface LoginResult {
  ok: boolean
  message: string
  cookies?: string
}

// Cache entry interface for user info
interface UserInfoCacheEntry {
  data: UserInfo;
  timestamp: number;
}

// Simple in-memory cache for user info (uses hashed key for efficiency and security)
const userInfoCache: Map<string, UserInfoCacheEntry> = new Map();

/**
 * Generate a short hash key from cookies string for cache lookup
 * This is more efficient and secure than using the full cookies string
 */
function generateCacheKey(cookies: string): string {
  return CryptoJS.MD5(cookies).toString().substring(0, 16);
}

export class loginFunction {
  /**
   * Clear the user info cache
   */
  static clearUserInfoCache(): void {
    userInfoCache.clear();
    hilog.debug(DOMAIN, TAG, 'User info cache cleared');
  }

  /**
   * 登录学习通，获取set-cookie
   * @param {string} LoginString 需要加密的消息
   * @returns {Promise<string>} 求到的cookie,异常为空
   */
  static async LoginChaoXing(LoginString: string): Promise<LoginResult> {
    hilog.debug(DOMAIN, TAG, 'Attempting login');
    const httpRequest = http.createHttp();
    const url = ChaoXingApi.URL_LOGIN;
    const PostBody = LoginString;
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        extraData: PostBody,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest'
        },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS,
      });
      // 处理响应
      if (result.responseCode === HTTP_SUCCESS_CODE) {
        const ResultBody = JSON.parse(result.result.toString()) as object;
        hilog.debug(DOMAIN, TAG, `Login response status: ${ResultBody?.['status']}`);
        if (ResultBody?.['status'] === true) {
          const set_cookies: string[] = result.header['set-cookie']
          hilog.info(DOMAIN, TAG, 'Login successful');
          return {
            ok: true,
            message: '登录成功',
            cookies: ChaoxingUtils.processSetCookieHeaders(set_cookies)
          };
        } else {
          hilog.error(DOMAIN, TAG, 'Login failed: Invalid username or password');
          return {
            ok: false,
            message: '账号或密码错误'
          };
        }
      } else {
        hilog.error(DOMAIN, TAG, `Login failed: Network error (${result.responseCode})`);
        return {
          ok: false,
          message: `网络错误(${result.responseCode})`
        };
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Login exception: ${error.message}`);
      if (error.message === ERROR_MAX_REDIRECTS) {
        return {
          ok: false,
          message: '服务器错误，请稍后重试'
        };
      }
      return {
        ok: false,
        message: '登录失败，请稍后重试'
      };
    } finally {
      // 无论成功或失败，都必须销毁请求对象
      httpRequest.destroy();
    }
  }

  /**
   * 获取用户的用户名和头像
   * @param {string} cookies 用户对应的cookie
   * @param {boolean} useCache 是否使用缓存，默认为true
   * @returns {Promise<UserInfo>} msg : 请求是否成功, uname: 用户名, pic: 头像url地址, uid: 用户uid, fid: 学校id
   */
  static async getUserInfo(cookies: string, useCache: boolean = true): Promise<UserInfo> {
    // Generate a hash-based cache key for efficiency and security
    const cacheKey = generateCacheKey(cookies);

    // Check cache first if caching is enabled
    if (useCache) {
      const cachedEntry = userInfoCache.get(cacheKey);
      if (cachedEntry && (Date.now() - cachedEntry.timestamp < USER_INFO_CACHE_TTL_MS)) {
        hilog.debug(DOMAIN, TAG, 'Returning cached user info');
        return cachedEntry.data;
      }
    }

    const httpRequest = http.createHttp();
    const url = ChaoXingApi.URL_GET_USER_INFO
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          "Cookie": cookies
        }
      })
      if (result.responseCode >= 300 || result.responseCode < 200) {
        hilog.error(DOMAIN, TAG, `Get user info failed: Server error (${result.responseCode})`);
        return {
          'msg': 'service error',
          'uname': '',
          'pic': '',
          'uid': 0,
          'fid': '',
          'puid':'',
          'clientId': ''
        }
      } else {
        const JsonResult = JSON.parse(result.result as string) as object;
        const Json = (JsonResult as object)?.['msg'] as object
        const uname: string = (Json as object)?.['name'] || ''
        const pic: string = (Json as object)?.['pic'] || ''
        const uid: number = (Json as object)?.['uid'] || 0
        const fid: string = (Json as object)?.['fid'] || ''
        const puid: string = (Json as object)?.['puid'] || ''
        const clientId: string = (Json as object)?.['clientId'] || ''
        const userInfo: UserInfo = {
          'msg': (uname && pic) ? 'successful' : 'fetch error',
          'uname': uname,
          'pic': pic,
          'uid': uid,
          'fid': fid,
          'puid':puid,
          'clientId': clientId
        }

        // Cache the successful result using hashed key
        if (userInfo.msg === 'successful') {
          userInfoCache.set(cacheKey, {
            data: userInfo,
            timestamp: Date.now()
          });
          hilog.debug(DOMAIN, TAG, 'User info cached');
        }

        return userInfo;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Get user info failed: ${error.message}`);
      return {
        'msg': 'service error',
        'uname': '',
        'pic': '',
        uid: 0,
        fid: '',
        puid:'',
        clientId: ''
      }
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 通过url添加其他用户
   * @param stringURL
   */
  static async LoginByURL(stringURL: string): Promise<string> {
    // 输入验证
    if (!stringURL || stringURL.trim().length === 0) {
      hilog.error(DOMAIN, TAG, 'LoginByURL: Empty URL provided');
      return '请提供有效的URL'
    }
    
    try {
      let urlParse = urlTools.parseUrlParams(stringURL)
      let phone = urlParse['phone']
      let pwd = urlParse['pwd']
      
      // 验证必需参数
      if (!phone || !pwd) {
        hilog.error(DOMAIN, TAG, 'LoginByURL: Missing phone or password in URL');
        return 'URL格式错误：缺少必需参数'
      }
      
      hilog.debug(DOMAIN, TAG, `Parsing login URL for phone: ${phone?.substring(0, 3)}***`);
      let AESPhone = ChaoxingUtils.encryptByAES(phone)
      let body = ChaoxingUtils.getLoginBody(AESPhone, pwd);
      const loginResult = await loginFunction.LoginChaoXing(body)
      
      if (!loginResult.ok || !loginResult.cookies) {
        hilog.error(DOMAIN, TAG, 'LoginByURL: Failed to get cookie');
        return loginResult.message
      }
      
      const cookie = loginResult.cookies
      let userInfo = await loginFunction.getUserInfo(cookie)
      
      if (userInfo.msg !== 'successful') {
        hilog.error(DOMAIN, TAG, 'LoginByURL: Failed to get user info');
        return '获取用户信息失败'
      }
      
      const dbManager = DatabaseManager.getInstance()
      const insertResult = await dbManager.insertUser({
        phone: phone,
        pwd: pwd,
        uid: userInfo.uid,
        cookies: cookie
      })
      
      if (insertResult === 1) {
        hilog.info(DOMAIN, TAG, 'User added successfully via URL');
        return '添加成功'
      } else {
        hilog.error(DOMAIN, TAG, 'Failed to add user: Invalid credentials or already logged in');
        return '链接的手机号或密码有误或已经登录'
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Login by URL failed: ${error.message}`);
      return '请使用正确的url'
    }
  }

  /**
   * 获取图片数据
   * @param {string} url 头像url
   * @returns {Promise<image.PixelMap>} 头像数据
   * */
  static async GetPic(url: string): Promise<image.PixelMap | null> {
    const httpRequest = http.createHttp();
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent':ChaoXingApi.UA },
        readTimeout: HTTP_TIMEOUT_MS,
        connectTimeout: HTTP_TIMEOUT_MS
      })

      if (result.responseCode === HTTP_SUCCESS_CODE) {
        const RawData = result.result as ArrayBuffer

        // 创建图像源
        let imageSource = image.createImageSource(RawData);
        // 创建PixelMap
        let pixelMap: image.PixelMap = await imageSource.createPixelMap();
        return pixelMap
      } else {
        hilog.error(DOMAIN, TAG, `Failed to fetch image: ${result.responseCode}`);
        return null
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error fetching image: ${error.message}`);
      return null
    }
    finally {
      httpRequest.destroy()
    }
  }
}
