import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'HttpClient';
const DOMAIN = 0x0010;

/** 对齐上游 chaoxingUserAgent 默认值：官方学习通 Android 客户端 UA（LCR007 排查实验） */
const CHAOXING_APP_UA = 'Dalvik/2.1.0 (Linux; U; Android 12; SM-N9006 Build/8aba9e4.0) ' +
  '(schild:2d97f7b9439f21333c946878fc4d6ccb) (device:SM-N9006) Language/zh_CN ' +
  'com.chaoxing.mobile/ChaoXingStudy_3_6.7.5_android_phone_10941_314 ' +
  '(@Kalimdor)_68f184fd763546c1a04ab3a09b3deebb';

/** 原始响应（body 为文本） */
export interface RawHttpResponse {
  code: number;
  body: string;
}

/**
 * 网络请求统一助手：收敛 http.createHttp/destroy 样板
 * 调用方自行决定如何解释响应码与响应体
 */
export class Http {
  /**
   * GET 请求，返回原始响应
   */
  static async get(url: string, cookies?: string, extraHeaders?: Record<string, string>): Promise<RawHttpResponse> {
    return await Http.request(url, http.RequestMethod.GET, undefined, cookies, extraHeaders);
  }

  /**
   * POST 请求（application/x-www-form-urlencoded），返回原始响应
   */
  static async postForm(url: string, formBody: string, cookies?: string,
    extraHeaders?: Record<string, string>): Promise<RawHttpResponse> {
    return await Http.request(url, http.RequestMethod.POST, formBody, cookies, extraHeaders);
  }

  /**
   * GET 并解析 JSON 响应体
   */
  static async getJson(url: string, cookies?: string, extraHeaders?: Record<string, string>): Promise<object> {
    return JSON.parse((await Http.get(url, cookies, extraHeaders)).body) as object;
  }

  /**
   * GET JSONP 响应（形如 callback({...})）并解析为对象
   */
  static async getJsonp(url: string, callback: string, cookies?: string,
    extraHeaders?: Record<string, string>): Promise<object> {
    const body = (await Http.get(url, cookies, extraHeaders)).body
      .replace(`${callback}(`, '')
      .replace(/\)$/, '');
    return JSON.parse(body) as object;
  }

  /**
   * GET 二进制内容，非 200 抛错
   */
  static async getBuffer(url: string, extraHeaders?: Record<string, string>): Promise<ArrayBuffer> {
    const httpRequest = http.createHttp();
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: extraHeaders,
        connectTimeout: 30000,
        readTimeout: 30000
      });
      if (result.responseCode !== 200) {
        throw new Error(`下载失败(${result.responseCode})`);
      }
      return result.result as ArrayBuffer;
    } finally {
      httpRequest.destroy();
    }
  }

  private static async request(url: string, method: http.RequestMethod, extraData?: string, cookies?: string,
    extraHeaders?: Record<string, string>): Promise<RawHttpResponse> {
    const header: Record<string, string> = {};
    if (cookies) {
      header['Cookie'] = cookies;
    }
    if (method === http.RequestMethod.POST) {
      header['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (extraHeaders) {
      const headerKeys = Object.keys(extraHeaders);
      for (let i = 0; i < headerKeys.length; i++) {
        header[headerKeys[i]] = extraHeaders[headerKeys[i]];
      }
    }
    if (!header['User-Agent']) {
      header['User-Agent'] = CHAOXING_APP_UA;
    }
    const httpRequest = http.createHttp();
    try {
      const result = await httpRequest.request(url, {
        method: method,
        extraData: extraData,
        header: header
      });
      return {
        code: result.responseCode,
        body: result.result.toString()
      };
    } finally {
      httpRequest.destroy();
    }
  }
}

/**
 * 将二进制内容写入文件
 */
export function writeBufferToFile(filePath: string, buffer: ArrayBuffer): void {
  const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, buffer);
  fs.closeSync(file);
  hilog.debug(DOMAIN, TAG, `Wrote ${buffer.byteLength} bytes to file`);
}
