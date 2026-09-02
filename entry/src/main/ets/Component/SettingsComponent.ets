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
const COLOR_MODE_ICONS: Resource[] = [
  $r('app.media.ic_theme_auto'),
  $r('app.media.ic_theme_light'),
  $r('app.media.ic_theme_dark')
];

@Component
export struct SettingsComponent {
  @State version: string = '';
  @State colorModeIndex: number = 0;
  onImportDone: () => void = () => {};
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

  confirmClearCache() {
    AlertDialog.show({
      message: '确定清除缓存吗？临时文件与图片缓存将被删除。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清除',
        fontColor: $r('app.color.unsignable'),
        action: () => {
          this.clearCache()
        }
      }
    });
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
        this.onImportDone();
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

  @Builder
  SectionHeader(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.secondary_text'))
      .width('100%')
      .margin({ bottom: 8, left: 4 })
  }

  @Builder
  SettingsDivider() {
    Divider()
      .color($r('sys.color.comp_divider'))
      .margin({ left: 16, right: 16 })
  }

  /** 通用栏行文案:标题 + 可选副标题 */
  @Builder
  SettingTexts(title: string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.primary_text'))
      if (subtitle !== '') {
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .margin({ top: 2 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  Chevron() {
    Image($r('app.media.arrow_right'))
      .width(14).height(14)
      .fillColor($r('app.color.icon'))
  }

  build() {
    Column() {
      // 半屏弹层拖拽指示条
      Column()
        .width(36).height(4).borderRadius(2)
        .backgroundColor($r('sys.color.comp_divider'))
        .margin({ top: 10 })

      Text('设置')
        .fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%').textAlign(TextAlign.Start)
        .padding({ left: 20, top: 12, bottom: 16 })

      List({ space: 16 }) {
        // 外观：三张可点选的模式卡片(整卡可点,选中态高亮)
        ListItem() {
          Column() {
            this.SectionHeader('外观')
            Row({ space: 10 }) {
              ForEach([0, 1, 2], (idx: number) => {
                Column({ space: 8 }) {
                  Stack() {
                    Row()
                      .width(52).height(52)
                      .borderRadius(14)
                      .backgroundColor(this.colorModeIndex === idx
                        ? $r('app.color.selected') : $r('app.color.icon'))
                      .opacity(this.colorModeIndex === idx ? 0.16 : 0.32)
                    Image(COLOR_MODE_ICONS[idx])
                      .width(26).height(26)
                  }
                  Text(COLOR_MODE_LABELS[idx])
                    .fontSize(13)
                    .fontWeight(this.colorModeIndex === idx ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(this.colorModeIndex === idx
                      ? $r('app.color.selected') : $r('app.color.secondary_text'))
                }
                .layoutWeight(1)
                .padding({ top: 14, bottom: 14 })
                .borderRadius(14)
                .backgroundColor($r('app.color.card_background'))
                .border({
                  width: 2,
                  color: this.colorModeIndex === idx
                    ? $r('app.color.selected') : Color.Transparent
                })
                .onClick(() => {
                  this.setColorMode(idx)
                })
              }, (idx: number) => idx.toString())
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
        }

        // 通用：两行式设置行(标题 + 说明)
        ListItem() {
          Column() {
            this.SectionHeader('通用')
            Column() {
              Row() {
                this.SettingTexts('版本', '当前应用版本')
                Text(this.version)
                  .fontSize(14)
                  .fontColor($r('app.color.secondary_text'))
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })

              this.SettingsDivider()

              Row() {
                this.SettingTexts('清除缓存', '清理临时文件与图片缓存')
                this.Chevron()
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .onClick(() => {
                this.confirmClearCache()
              })

              this.SettingsDivider()

              Row() {
                this.SettingTexts('导出数据库', '备份用户数据为 JSON 文件')
                this.Chevron()
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .onClick(() => {
                this.exportDatabase()
              })

              this.SettingsDivider()

              Row() {
                this.SettingTexts('导入数据库', '从 JSON 备份文件恢复数据')
                this.Chevron()
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .onClick(() => {
                this.importDatabase()
              })

              this.SettingsDivider()

              Row() {
                this.SettingTexts('更新日志', '查看最近的更新内容')
                this.Chevron()
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .onClick(() => {
                this.showChangelog()
              })

              this.SettingsDivider()

              Row() {
                Image($r('app.media.github'))
                  .width(20).height(20).margin({ right: 10 })
                  .fillColor($r('app.color.primary_text'))
                this.SettingTexts('项目地址', '在 GitHub 上查看源码')
                this.Chevron()
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .onClick(() => {
                this.openUrl('https://github.com/ASCII-58/chaoxingsignfacker')
              })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
          }
        }
      }
      .width('100%').layoutWeight(1)
      .padding({ left: 16, right: 16, bottom: 24 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }
}
