import { curves, promptAction, UIContext } from '@kit.ArkUI';
import { bundleManager, common, Want, ConfigurationConstant } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { systemShare } from '@kit.ShareKit';
import { DatabaseManager } from '../utils/DataBase';
import { MsCaptchaDetector } from '../utils/detector/MsCaptchaDetector';

const PREF_COLOR_MODE_KEY = 'app_color_mode';
const PREF_MODEL_CAPTCHA_KEY = 'model_captcha_enabled';
// 模型测试结果状态：0 未测试 / 1 通过 / 2 失败
const MODEL_TEST_IDLE = 0;
const MODEL_TEST_PASSED = 1;
const MODEL_TEST_FAILED = 2;
const COLOR_MODE_LABELS = ['自动', '浅色', '深色'];

// 应用内更新日志数据结构（来源：rawfile/changelog.json，更新日志只需编辑该文件）
interface ChangelogSection {
  title: string;
  items: string[];
}

interface ChangelogRelease {
  version: string;
  date: string;
  sections: ChangelogSection[];
}

interface ChangelogFile {
  releases: ChangelogRelease[];
}
const COLOR_MODE_ICONS: Resource[] = [
  $r('app.media.ic_theme_auto'),
  $r('app.media.ic_theme_light'),
  $r('app.media.ic_theme_dark')
];

@Component
export struct SettingsComponent {
  @State version: string = '';
  @State colorModeIndex: number = 0;
  @State modelCaptchaEnabled: boolean = false;
  @State modelTestRunning: boolean = false;
  @State modelTestState: number = MODEL_TEST_IDLE;
  onImportDone: () => void = () => {};
  private context = getContext(this) as common.UIAbilityContext;

  async aboutToAppear() {
    this.getVersion();
    await this.loadColorMode();
    await this.loadModelCaptcha();
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

  async loadModelCaptcha() {
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      this.modelCaptchaEnabled = await pref.get(PREF_MODEL_CAPTCHA_KEY, false) as boolean;
    } catch (e) {
      this.modelCaptchaEnabled = false;
    }
  }

  async saveModelCaptcha(enabled: boolean) {
    this.modelCaptchaEnabled = enabled;
    if (!enabled) {
      this.modelTestState = MODEL_TEST_IDLE;
    }
    try {
      let pref = await preferences.getPreferences(this.context, 'settings');
      await pref.put(PREF_MODEL_CAPTCHA_KEY, enabled);
      await pref.flush();
    } catch (e) {
      console.error('Failed to save model captcha switch', e);
    }
  }

  /** Beta 开关：开启前警告；取消则回弹开关，关闭直接生效 */
  onModelCaptchaToggle(value: boolean) {
    if (!value) {
      this.saveModelCaptcha(false);
      return;
    }
    AlertDialog.show({
      title: '开启模型自动验证？',
      message: '该功能处于 Beta 阶段：遇到验证码时将调用本地模型自动完成滑块验证，可能失败或存在误判风险；' +
        '失败时会退回手动拖动验证。确定开启吗？',
      primaryButton: {
        value: '取消',
        action: () => {
          this.modelCaptchaEnabled = false;
        }
      },
      secondaryButton: {
        value: '开启',
        fontColor: $r('app.color.selected'),
        action: () => {
          this.saveModelCaptcha(true);
        }
      }
    });
  }

  /** 模型可用性测试：仅展示通过/失败，不展示检测细节 */
  async runModelTest() {
    if (this.modelTestRunning) {
      return;
    }
    this.modelTestRunning = true;
    this.modelTestState = MODEL_TEST_IDLE;
    try {
      const passed = await MsCaptchaDetector.selfTest(this.context);
      this.modelTestState = passed ? MODEL_TEST_PASSED : MODEL_TEST_FAILED;
    } finally {
      this.modelTestRunning = false;
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

  /**
   * 从 rawfile/changelog.json 加载更新日志并展示最新版本
   * 新增版本时只需在 changelog.json 的 releases 数组头部追加一条，无需改代码
   */
  async showChangelog() {
    try {
      const raw = await this.context.resourceManager.getRawFileContent('changelog.json');
      const text = util.TextDecoder.create('utf-8', { ignoreBOM: true })
        .decodeWithStream(raw, { stream: false });
      const file = JSON.parse(text) as ChangelogFile;
      if (!file.releases || file.releases.length === 0) {
        throw new Error('changelog.json has no releases');
      }
      const latest = file.releases[0];
      let message = '';
      for (const section of latest.sections) {
        message += `${section.title}：\n`;
        for (const item of section.items) {
          message += `• ${item}\n`;
        }
        message += '\n';
      }
      AlertDialog.show({
        title: `更新日志 v${latest.version} (${latest.date})`,
        message: message.trim(),
        confirm: { value: '知道了', action: () => {} }
      });
    } catch (error) {
      console.error('Failed to load changelog', JSON.stringify(error));
      AlertDialog.show({
        title: '更新日志',
        message: '更新日志加载失败',
        confirm: { value: '知道了', action: () => {} }
      });
    }
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

        // 验证码：模型自动验证（Beta）
        ListItem() {
          Column() {
            this.SectionHeader('验证码')
            Column() {
              Row() {
                this.SettingTexts('模型自动验证', '使用本地模型自动完成滑块验证码')
                Text('Beta')
                  .fontSize(10)
                  .fontColor(Color.White)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor($r('app.color.beta_badge'))
                  .margin({ right: 10 })
                Toggle({ type: ToggleType.Switch, isOn: this.modelCaptchaEnabled })
                  .selectedColor($r('app.color.selected'))
                  .onChange((value: boolean) => {
                    this.onModelCaptchaToggle(value)
                  })
              }
              .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })

              if (this.modelCaptchaEnabled) {
                this.SettingsDivider()

                Row() {
                  this.SettingTexts('模型测试', '验证模型可用性与准确度')
                  Button(this.modelTestRunning ? '测试中...' : '测试')
                    .fontSize(14)
                    .height(32)
                    .padding({ left: 16, right: 16 })
                    .enabled(!this.modelTestRunning)
                    .onClick(() => {
                      this.runModelTest()
                    })
                }
                .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 13 })

                if (this.modelTestState !== MODEL_TEST_IDLE && !this.modelTestRunning) {
                  Text(this.modelTestState === MODEL_TEST_PASSED ? '模型可用，准确度正常' : '模型不可用或准确度异常')
                    .fontSize(12)
                    .fontColor(this.modelTestState === MODEL_TEST_PASSED
                      ? $r('app.color.signed') : $r('app.color.unsignable'))
                    .width('100%')
                    .padding({ left: 16, right: 16, bottom: 12 })
                }
              }
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
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
