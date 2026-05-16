import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DatabaseManager } from '../utils/DataBase';

const PREF_FIRST_INSTALL_TIME = 'first_install_time';
const PREF_REAL_NAME_VERIFIED = 'real_name_verified';

@Component
export struct DebugPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State dbInfo: string = '';

  async aboutToAppear() {
    await this.loadDbInfo();
  }

  async loadDbInfo() {
    try {
      const dbManager = DatabaseManager.getInstance();
      const hostCount = await dbManager.getTableCount('HostUser');
      const otherCount = await dbManager.getTableCount('OtherUser');
      this.dbInfo = `HostUser: ${hostCount} 条, OtherUser: ${otherCount} 条`;
    } catch (e) {
      this.dbInfo = '加载失败';
    }
  }

  async getInstallInfo(): Promise<string> {
    let pref = await preferences.getPreferences(this.context, 'settings');
    const firstInstall = await pref.get(PREF_FIRST_INSTALL_TIME, 0) as number;
    const verified = await pref.get(PREF_REAL_NAME_VERIFIED, false) as boolean;
    if (firstInstall === 0) {
      return '首次安装时间: 未记录\n实名认证: 未设置';
    }
    const date = new Date(firstInstall);
    const days = Math.floor((Date.now() - firstInstall) / (24 * 60 * 60 * 1000));
    return `首次安装: ${date.toISOString().substring(0, 10)}\n已使用: ${days} 天\n实名认证: ${verified ? '已认证' : '未认证'}`;
  }

  async resetInstallState() {
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.delete(PREF_FIRST_INSTALL_TIME);
      await pref.delete(PREF_REAL_NAME_VERIFIED);
      await pref.flush();
      promptAction.showToast({ message: '安装状态已重置' });
    } catch (e) {
      promptAction.showToast({ message: '重置失败' });
    }
  }

  async setInstallTimeTo23Months() {
    try {
      const target = Date.now() - 23 * 30 * 24 * 60 * 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(PREF_FIRST_INSTALL_TIME, target);
      await pref.put(PREF_REAL_NAME_VERIFIED, true);
      await pref.flush();
      promptAction.showToast({ message: '安装时间已设为23个月前，下次启动将触发备份提醒' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  async setInstallDays(days: number) {
    try {
      const target = Date.now() - days * 24 * 60 * 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(PREF_FIRST_INSTALL_TIME, target);
      await pref.flush();
      promptAction.showToast({ message: `安装时间已设为 ${days} 天前` });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  build() {
    Column() {
      Text('Debug 调试面板')
        .fontSize(24).fontWeight(FontWeight.Bold)
        .width('100%').textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 20 })

      List({ space: 12 }) {
        ListItem() {
          Column() {
            Text('安装状态')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              Row() {
                Text(this.dbInfo !== '' ? this.dbInfo : '加载中...')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              }
              .width('100%').padding(12)
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }

        ListItem() {
          Column() {
            Text('调试操作')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              Row() {
                Text('重置安装状态')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.resetInstallState() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设23个月前安装（触发备份提醒）')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setInstallTimeTo23Months() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设1天前安装')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setInstallDays(1) })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设365天前安装')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setInstallDays(365) })
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }
      }
      .width('100%').layoutWeight(1)
      .padding({ left: 16, right: 16 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }
}
