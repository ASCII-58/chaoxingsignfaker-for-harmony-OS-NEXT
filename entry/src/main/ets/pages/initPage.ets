import { DatabaseManager } from '../utils/DataBase';
import { preferences } from '@kit.ArkData';
import { bundleManager, common, ConfigurationConstant } from '@kit.AbilityKit';
import { JSON } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { GITHUB_RUST_API } from '../utils/PublicAPI';

const TAG = 'InitPage';
const DOMAIN = 0x0001;
const PREF_COLOR_MODE_KEY = 'app_color_mode';
const SIGN_TIME = 'sign_time';
const VERSION = 'version'
// 仅定义需要访问的部分
interface ReleaseInfo {
  created_at: string;          // Release 的创建时间
  assets?: AssetInfo[];        // 资产数组（可选）
}

interface AssetInfo {
  created_at: string;          // 资产的创建时间
  // 其他字段可省略
}
// 常量定义
const HTTP_TIMEOUT_MS = 10000;
const ERROR_MAX_REDIRECTS = 'Number of redirects hit maximum amount';
const HTTP_SUCCESS_CODE = 200;

@Entry
@Component
struct UI {
  @Provide('pathInfos') pathInfos: NavPathStack = new NavPathStack();

  async aboutToAppear() {
    await this.applyColorMode()
  }

  build() {
    Navigation(this.pathInfos) {
    }
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .hideBackButton(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM])
    .backgroundImageSize({ width: '100%', height: '100%' })
    .borderRadius($r('sys.float.corner_radius_level8'))
    .height('100%')
    .width('100%')
    .onAppear(async () => {
      await this.checkAppStatus();
      const dbManager = DatabaseManager.getInstance()
      const isHostLogin: boolean = !(await dbManager.isHostUserTableEmpty())
      if (isHostLogin) {
        this.pathInfos.replacePath({ name: "HomePage" }, false)
      } else {
        this.pathInfos.replacePath({
          name: "LoginPage"
        }, false)
      }
    })

  }

  async applyColorMode() {
    try {
      const context = getContext(this) as common.UIAbilityContext
      let pref = await preferences.getPreferences(context, 'settings')
      const index = await pref.get(PREF_COLOR_MODE_KEY, 0) as number
      let mode: ConfigurationConstant.ColorMode
      if (index === 0) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      } else if (index === 1) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      } else {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      }
      context.getApplicationContext().setColorMode(mode)
    } catch (e) {
      console.error('Failed to apply color mode', e)
    }
  }
  async getUpdateTime(pref: preferences.Preferences, versionNow: string) {
    const httpRequest = http.createHttp();
    const url = GITHUB_RUST_API + versionNow;
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest'
        },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS,
      })
      if (result.responseCode === HTTP_SUCCESS_CODE) {
        const ResultBody = JSON.parse(result.result.toString()) as ReleaseInfo;
        const SignTimeStr = (ResultBody.assets as AssetInfo[])[0].created_at
        let SignTime = new Date(SignTimeStr).getTime()
        await pref.put(SIGN_TIME, SignTime);
        await pref.put(VERSION, versionNow);
        await pref.flush();
        return;
      }
    } catch (error) {
      console.log('get github error', JSON.stringify(error))
    } finally {
      httpRequest.destroy();
    }
    const signTime = await pref.get(SIGN_TIME, 0) as number;
    if (signTime === 0) {
      await pref.put(SIGN_TIME, Date.now());
    }
    await pref.put(VERSION, versionNow);
    await pref.flush();
  }
  async checkAppStatus() {
    const context = getContext(this) as common.UIAbilityContext;
    let pref = await preferences.getPreferences(context, 'settings');
    const signTime = await pref.get(SIGN_TIME, 0) as number;
    if (signTime === 0) {
      let bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      await this.getUpdateTime(pref, bundleInfo.versionName)
    }
  }
}
