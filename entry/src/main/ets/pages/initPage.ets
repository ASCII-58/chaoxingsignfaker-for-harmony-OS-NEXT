import { DatabaseManager } from '../utils/DataBase';
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';

const TAG = 'InitPage';
const DOMAIN = 0x0001;
const PREF_COLOR_MODE_KEY = 'app_color_mode';
const PREF_FIRST_INSTALL_TIME = 'first_install_time';
const PREF_REAL_NAME_VERIFIED = 'real_name_verified';
const BACKUP_REMINDER_MS = 23 * 30 * 24 * 60 * 60 * 1000;


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
      const dbManager = DatabaseManager.getInstance()
      const isHostLogin: boolean = !(await dbManager.isHostUserTableEmpty())
      if (isHostLogin) {
        this.pathInfos.replacePath({ name: "HomePage" }, false)
      } else {
        this.pathInfos.replacePath({
          name: "LoginPage"
        }, false)
      }
      await this.checkAppStatus();
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

  async checkAppStatus() {
    const context = getContext(this) as common.UIAbilityContext;
    let pref = await preferences.getPreferences(context, 'settings');
    const now = Date.now();

    let firstInstall = await pref.get(PREF_FIRST_INSTALL_TIME, 0) as number;
    const isFirstLaunch = firstInstall === 0;

    if (isFirstLaunch) {
      firstInstall = now;
      await pref.put(PREF_FIRST_INSTALL_TIME, now);
      await pref.flush();

      AlertDialog.show({
        title: '实名认证',
        message: '是否已完成华为开发者实名认证？\n实名认证可将应用调试有效期从14天延长至2年。',
        primaryButton: {
          value: '未认证',
          action: async () => {
            await pref.put(PREF_REAL_NAME_VERIFIED, false);
            await pref.flush();
            AlertDialog.show({
              title: '提示',
              message: '建议前往华为开发者联盟完成实名认证，以获得2年调试时长（未认证仅14天）。\n\n实名认证文档：\nhttps://developer.huawei.com/consumer/cn/doc/start/itrna-0000001076878172',
              primaryButton: {
                value: '查看文档',
                action: () => {
                  let want: Want = {
                    action: 'ohos.want.action.viewData',
                    entities: ['entity.system.browsable'],
                    uri: 'https://developer.huawei.com/consumer/cn/doc/start/itrna-0000001076878172'
                  };
                  context.startAbility(want).catch(() => {});
                }
              },
              secondaryButton: { value: '知道了', action: () => {} }
            });
          }
        },
        secondaryButton: {
          value: '已认证',
          action: async () => {
            await pref.put(PREF_REAL_NAME_VERIFIED, true);
            await pref.flush();
          }
        }
      });
      return;
    }

    const verified = await pref.get(PREF_REAL_NAME_VERIFIED, false) as boolean;
    const elapsed = now - firstInstall;

    if (!verified) {
      AlertDialog.show({
        title: '备份提醒',
        message: '未进行实名认证，调试有效期仅14天，请及时备份数据库文件以免数据丢失。\n\n备份方法：用户中心 → 设置 → 导出数据库',
        confirm: { value: '知道了', action: () => {} }
      });
    } else if (elapsed >= BACKUP_REMINDER_MS) {
      AlertDialog.show({
        title: '备份提醒',
        message: '您的应用调试有效期即将到期，请尽快备份数据库文件以免数据丢失。\n\n备份方法：用户中心 → 设置 → 导出数据库',
        confirm: { value: '知道了', action: () => {} }
      });
    }
  }
}
