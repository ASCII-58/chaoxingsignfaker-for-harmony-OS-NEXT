import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DatabaseManager } from '../utils/DataBase';

const SIGN_TIME = 'sign_time';
const VERSION = 'version';
const SIGN_EXPIRY_MS = 12 * 30 * 24 * 60 * 60 * 1000;
const BACKUP_REMINDER_MS = 11 * 30 * 24 * 60 * 60 * 1000;

@Component
export struct DebugPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State dbInfo: string = '';
  @Consume('pathInfos') pathInfos: NavPathStack;

  async aboutToAppear() {
    await this.loadInfo();
  }

  async loadInfo() {
    try {
      const dbManager = DatabaseManager.getInstance();
      const hostCount = await dbManager.getTableCount('HostUser');
      const otherCount = await dbManager.getTableCount('OtherUser');
      const signInfo = await this.getSignInfo();
      this.dbInfo = `HostUser: ${hostCount} 条, OtherUser: ${otherCount} 条\n\n${signInfo}`;
    } catch (e) {
      this.dbInfo = '加载失败';
    }
  }

  async getSignInfo(): Promise<string> {
    let pref = await preferences.getPreferences(this.context, 'settings');
    const signTime = await pref.get(SIGN_TIME, 0) as number;
    const ver = await pref.get(VERSION, '') as string;
    if (signTime === 0) {
      return '签名时间: 未记录\n版本: 未记录';
    }
    const date = new Date(signTime);
    const elapsed = Date.now() - signTime;
    const days = Math.floor(elapsed / (24 * 60 * 60 * 1000));
    let statusLine: string;
    if (elapsed >= SIGN_EXPIRY_MS) {
      statusLine = '状态: 已过期';
    } else if (elapsed >= BACKUP_REMINDER_MS) {
      const remain = Math.ceil((SIGN_EXPIRY_MS - elapsed) / (24 * 60 * 60 * 1000));
      statusLine = `状态: 即将过期 (剩余约${remain}天)`;
    } else {
      statusLine = '状态: 有效';
    }
    return `签名时间: ${date.toISOString().substring(0, 10)}\n版本: ${ver}\n${statusLine}\n已过 ${days} 天`;
  }

  async resetSignState() {
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.delete(SIGN_TIME);
      await pref.delete(VERSION);
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: '签名状态已重置' });
    } catch (e) {
      promptAction.showToast({ message: '重置失败' });
    }
  }

  async setSignTimeToTriggerReminder() {
    try {
      const target = Date.now() - BACKUP_REMINDER_MS - 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(SIGN_TIME, target);
      await pref.put(VERSION, '1.0.0-debug');
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: '签名时间已设为11个月前，下次启动将触发备份提醒' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  async setSignTimeExpired() {
    try {
      const target = Date.now() - SIGN_EXPIRY_MS - 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(SIGN_TIME, target);
      await pref.put(VERSION, '1.0.0-debug');
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: '签名时间已设为过期' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败' });
    }
  }

  async setSignDaysAgo(days: number) {
    try {
      const target = Date.now() - days * 24 * 60 * 60 * 1000;
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(SIGN_TIME, target);
      await pref.put(VERSION, '1.0.0-debug');
      await pref.flush();
      this.dbInfo = '';
      promptAction.showToast({ message: `签名时间已设为 ${days} 天前` });
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
            Text('签名状态')
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
                Text('重置签名状态')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.resetSignState() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设11个月前签名（触发备份提醒）')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignTimeToTriggerReminder() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设过期签名（12个月前）')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignTimeExpired() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设1天前签名')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignDaysAgo(1) })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('设365天前签名')
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.setSignDaysAgo(365) })
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }
        ListItem(){
          Column(){
            Text('打开Debug详情页')
          }.onClick(()=>{ this.pathInfos.pushPath({ name: 'Debug' }) })
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
