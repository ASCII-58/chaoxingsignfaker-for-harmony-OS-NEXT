import { curves, promptAction, UIContext } from '@kit.ArkUI';
import { bundleManager, common, Want, ConfigurationConstant } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { systemShare } from '@kit.ShareKit';
import { DatabaseManager } from '../utils/DataBase';

const PREF_COLOR_MODE_KEY = 'app_color_mode';
const COLOR_MODE_LABELS = ['自动', '浅色', '深色'];

@Component
export struct SettingsComponent {
  @State version: string = '';
  @State colorModeIndex: number = 0;
  private context = getContext(this) as common.UIAbilityContext;

  async aboutToAppear() {
    this.getVersion();
    await this.loadColorMode();
  }

  async getVersion() {
    try {
      let bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.version = bundleInfo.versionName;
    } catch (error) {
      console.error('Failed to get bundle info', error);
      this.version = 'Unknown';
    }
  }

  async loadColorMode() {
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      this.colorModeIndex = await pref.get(PREF_COLOR_MODE_KEY, 0) as number;
    } catch (e) {
      this.colorModeIndex = 0;
    }
  }

  async setColorMode(index: number) {
    this.colorModeIndex = index;
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(PREF_COLOR_MODE_KEY, index);
      await pref.flush();
    } catch (e) {
      console.error('Failed to save color mode', e);
    }

    const appContext = this.context.getApplicationContext();
    setTimeout(() => {
      let mode: ConfigurationConstant.ColorMode;
      if (index === 0) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      } else if (index === 1) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      appContext.setColorMode(mode);
    }, 80);
  }

  async clearCache() {
    try {
      let cacheDir = this.context.cacheDir;
      let filenames = await fs.listFile(cacheDir);
      for (let filename of filenames) {
        let path = cacheDir + '/' + filename;
        try {
          let stat = await fs.stat(path);
          if (stat.isDirectory()) {
            await fs.rmdir(path);
          } else {
            await fs.unlink(path);
          }
        } catch (e) {
          // Ignore individual file errors
        }
      }
      promptAction.showToast({ message: '缓存已清除' });
    } catch (error) {
      console.error('Failed to clear cache', error);
      promptAction.showToast({ message: '清除缓存失败' });
    }
  }

  async exportDatabase() {
    try {
      const dbManager = DatabaseManager.getInstance();
      const jsonData = await dbManager.exportToJSON();

      const tempPath = this.context.cacheDir + '/chaoxing_backup.json';
      const encoder = new util.TextEncoder();
      const uint8 = encoder.encode(jsonData);
      const ff = await fs.open(tempPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      await fs.write(ff.fd, uint8.buffer);
      await fs.close(ff);

      const uriObj = new fileUri.FileUri(tempPath);
      let shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        uri: uriObj.toString(),
        title: '导出数据库',
        description: '超星签到助手数据库备份',
        label: '数据库备份'
      });

      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let controller = new systemShare.ShareController(shareData);
      controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).catch((error: BusinessError) => {
        console.error('Share error', JSON.stringify(error));
        promptAction.showToast({ message: '分享失败' });
      });

      promptAction.showToast({ message: '数据库已导出，请选择保存位置' });
    } catch (error) {
      const err = error as BusinessError;
      promptAction.showToast({ message: `导出失败: ${err.code} ${err.message}` });
    }
  }

  async importDatabase() {
    try {
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select(selectOptions);

      if (!uris || uris.length === 0) {
        return;
      }

      const uri = uris[0];
      const statInfo = await fs.stat(uri);
      const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const arrayBuffer = new ArrayBuffer(statInfo.size);
      await fs.read(file.fd, arrayBuffer);
      await fs.close(file);

      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      const jsonData = decoder.decodeWithStream(new Uint8Array(arrayBuffer), { stream: false });

      const dbManager = DatabaseManager.getInstance();
      const result = await dbManager.importFromJSON(jsonData);

      if (result.success) {
        promptAction.showToast({ message: result.message });
      } else {
        promptAction.showToast({ message: result.message });
      }
    } catch (error) {
      console.error('Import failed', JSON.stringify(error));
      promptAction.showToast({ message: '导入失败：文件读取错误' });
    }
  }

  openUrl(url: string) {
    let want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    this.context.startAbility(want).catch((err: BusinessError) => {
      console.error('Failed to open URL', err);
      promptAction.showToast({ message: '无法打开链接' });
    });
  }

  showChangelog() {
    AlertDialog.show({
      title: '更新日志 (2026-05-16)',
      message: '新增功能：\n' +
        '• 数据库导出/导入 — 设置页支持将用户数据导出为JSON文件并通过分享保存，支持导入并自动校验格式\n' +
        '• 实名认证引导 — 首次启动询问是否已完成开发者实名认证，未认证/有效期将尽时弹出备份提醒\n' +
        '• 使用时长显示 — 用户中心新增已使用时长\n' +
        '• 二维码分享图片质量提升至100\n' +
        '• 修复主用户登录后无法跳转首页的问题\n' +
        '• 修复多个弹窗冲突导致设置页无法打开的问题',
      confirm: { value: '知道了', action: () => {} }
    });
  }

  build() {
    Column() {

      Text('设置')
        .fontSize(24).fontWeight(FontWeight.Bold)
        .width('100%').textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 20 })

      List({ space: 12 }) {
        // Appearance Section
        ListItem() {
          Column() {
            Text('外观')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              ForEach([0, 1, 2], (idx: number) => {
                Row() {
                  Text(COLOR_MODE_LABELS[idx])
                    .fontSize(16)
                    .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  Blank()
                  Radio({ value: `mode_${idx}`, group: 'colorModeGroup' })
                    .checked(this.colorModeIndex === idx)
                    .onChange((checked: boolean) => {
                      if (checked) this.setColorMode(idx)
                    })
                }
                .width('100%').padding(12)

                if (idx < 2) {
                  Divider()
                    .color($r('sys.color.ohos_id_color_list_separator'))
                    .margin({ left: 12, right: 12 })
                }
              })
            }
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .borderRadius(16)
          }
        }

        // General Section
        ListItem() {
          Column() {
            Text('通用')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ bottom: 8, left: 4 })

            Column() {
              Row() {
                Text('版本')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Text(this.version)
                  .fontSize(14)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              }
              .width('100%').padding(12)

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('清除缓存')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.clearCache() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('导出数据库')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.exportDatabase() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('导入数据库')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.importDatabase() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Text('更新日志')
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => { this.showChangelog() })

              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 12, right: 12 })

              Row() {
                Row() {
                  Image($r('app.media.github'))
                    .width(20).height(20).margin({ right: 8 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                  Text('项目地址')
                    .fontSize(16)
                    .fontColor($r('sys.color.ohos_id_color_text_primary'))
                }
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(16).height(16)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              }
              .width('100%').padding(12)
              .onClick(() => {
                this.openUrl('https://github.com/ASCII-58/chaoxingsignfacker')
              })
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
