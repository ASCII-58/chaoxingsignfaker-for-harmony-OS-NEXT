import { DatabaseManager, UserDataAndId } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import image from '@ohos.multimedia.image';
import { ClassInfo, CourseAndActivity } from '../utils/classFun';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { curves, UIContext } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import promptAction from '@ohos.promptAction';
import { loginByCommon, loginByURL } from '../Component/LoginCom';
import { OtherUserItem } from '../Component/OtherUserCom';
import ShareUtils from '../utils/shareUtils';
import { systemShare } from '@kit.ShareKit';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common, Want } from '@kit.AbilityKit';
import { SettingsComponent } from '../Component/SettingsComponent';
import { DebugPage } from '../Component/DebugPage';

const TAG = 'IndexPage';
const DOMAIN = 0x0004;

AppStorage.setOrCreate('userHostName', $r('app.string.defaultUname'))
AppStorage.setOrCreate('userHostPhone', $r('app.string.defaultPhone'))
AppStorage.setOrCreate('userUrl', '')
AppStorage.setOrCreate('userQRValue', '')

interface UserInfoComponentInterface {
  hostName: Resource | string
  hostPhone: Resource | string
  QRvalue: string
  url: string
  onLogout: () => void
}

@Reusable
@Component
struct ClassListItem {
  @Prop classInfo: ClassInfo;
  @Consume('pathInfos') pathInfos: NavPathStack;
  @State isPressed: boolean = false;

  build() {
    Row() {
      ClassIcon({ imageurl: this.classInfo.imageurl })
      Column() {
        Text(this.classInfo.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.classInfo.teacherfactor)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(14).height(14)
        .fillColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height(68)
    .backgroundColor($r('app.color.card_background'))
    .padding({ left: 16, right: 16 })
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
  }
}

@Reusable
@Component
struct ClassIcon {
  @Prop imageurl: string;
  @State ImageData: image.PixelMap | null = null;
  @State isLoaded: boolean = false;

  build() {
    Column() {
      Image(this.ImageData)
        .width(44).height(44)
        .borderColor($r('app.color.class_icon_border'))
        .borderWidth(2).borderRadius(12)
        .alt($r('app.media.foreground'))
    }
    .width(44).height(44).borderRadius(12).clip(true)
    .onAppear(async () => {
      if (!this.isLoaded) {
        this.ImageData = await loginFunction.GetPic(this.imageurl)
        this.isLoaded = true
      }
    })
  }
}

@Builder
export function init(name: string) {
  HomePage()
}

@Component
struct UserInfoComponent {
  @State HostImageData: image.PixelMap | Resource = $r('app.media.foreground')
  @Prop url: string
  @Prop hostName: Resource | string
  @Prop hostPhone: Resource | string
  @Prop QRvalue: string
  onLogout: () => void = () => {}
  @State activeSheet: number = -1
  @State sheetVisible: boolean = false
  @State iconPressed: number = -1
  @State shareLoading: boolean = false
  @State isReady: boolean = false
  @State avatarTapCount: number = 0
  @State debugPwdInput: string = ''
  private avatarTapTimer: number = -1
  private uiContext: UIContext = this.getUIContext();
  private context: Context = this.uiContext.getHostContext() as Context;

  aboutToAppear() {
    animateTo({ duration: 400, curve: curves.interpolatingSpring(0, 1, 300, 28) }, () => {
      this.isReady = true
    })
  }

  @Builder UnifiedSheet() {
    if (this.activeSheet === -2) {
      Column() {
        Text('输入调试密码')
          .fontSize(24).fontWeight(FontWeight.Bold)
          .width('100%').textAlign(TextAlign.Start)
          .padding({ left: 20, bottom: 20 })
        TextInput({ placeholder: '请输入密码', text: $$this.debugPwdInput })
          .type(InputType.Password)
          .width('90%').height(50)
          .backgroundColor($r('sys.color.ohos_id_color_text_field_sub_bg'))
          .borderRadius(12)
          .margin({ bottom: 20 })
        Button('确认')
          .width('90%').height(50)
          .fontColor($r('app.color.text_on_primary'))
          .backgroundColor($r('app.color.class_button'))
          .borderRadius(25)
          .onClick(() => {
            if (this.debugPwdInput === 'ASCII58DEBUG') {
              this.sheetVisible = false;
              this.debugPwdInput = '';
              this.activeSheet = 2;
              setTimeout(() => { this.sheetVisible = true; }, 300);
            } else {
              promptAction.showToast({ message: '密码错误' });
              this.debugPwdInput = '';
            }
          })
        Blank()
      }
      .width('100%').height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    } else if (this.activeSheet === 0) {
      SettingsComponent()
    } else if (this.activeSheet === 1) {
      Column() {
        Text('二维码名片').fontSize(24).fontWeight(FontWeight.Bold)
          .width('100%').textAlign(TextAlign.Start).padding({ left: 20, bottom: 20 })
        if (this.QRvalue) {
          Column() {
            Column() { QRCode(this.QRvalue).width(200).height(200) }
              .padding(20).backgroundColor($r('app.color.card_background'))
              .borderRadius(16).shadow({ radius: 12, color: '#00000010', offsetY: 4 })
            Text(this.hostName).fontSize(20).fontWeight(FontWeight.Medium)
              .margin({ top: 20 }).fontColor($r('sys.color.ohos_id_color_text_primary'))
          }
          .width('100%').alignItems(HorizontalAlign.Center).margin({ bottom: 40 })
          Button(this.shareLoading ? '准备中...' : '分享名片').width('90%').height(50)
            .fontColor($r('app.color.text_on_primary'))
            .backgroundColor($r('app.color.class_button')).borderRadius(25)
            .enabled(!this.shareLoading)
            .onClick(async () => {
              this.shareLoading = true
              const shareUtils = new ShareUtils(this.context, this.QRvalue)
              const ok = await shareUtils.prepare()
              if (ok) {
                this.doShare(shareUtils.FileUri, this.QRvalue)
              } else {
                promptAction.showToast({ message: '生成分享图片失败' })
              }
              this.shareLoading = false
            })
        } else {
          Column() {
            LoadingProgress().width(60).height(60).color($r('sys.color.ohos_id_color_text_secondary'))
            Text('正在加载用户信息...').fontSize(16)
              .fontColor($r('sys.color.ohos_id_color_text_secondary')).margin({ top: 20 })
          }
          .height(300).justifyContent(FlexAlign.Center)
        }
      }
      .width('100%').height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    } else if (this.activeSheet === 2) {
      DebugPage()
    }
  }

  build() {
    Row() {
      Image(this.HostImageData)
        .width(60).height(60).borderRadius(30)
        .objectFit(ImageFit.Cover).alt($r('app.media.foreground'))
        .onAppear(async () => {
          if (this.url !== '') this.HostImageData = await loginFunction.GetPic(this.url) as PixelMap
        })
        .onClick(() => {
          this.avatarTapCount++;
          clearTimeout(this.avatarTapTimer);
          if (this.avatarTapCount >= 10) {
            this.avatarTapCount = 0;
            this.debugPwdInput = '';
            this.activeSheet = -2;
            this.sheetVisible = true;
          } else {
            this.avatarTapTimer = setTimeout(() => { this.avatarTapCount = 0; }, 2000);
          }
        })
      Column() {
        Text(this.hostName).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.hostPhone).fontSize(13).fontColor($r('app.color.secondary_text'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12 })
      Row({ space: 4 }) {
        Column() {
          Image($r('app.media.settings')).width(22).height(22)
            .fillColor($r('app.color.icon'))
        }
        .width(40).height(40).borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .scale({ x: this.iconPressed === 0 ? 0.85 : 1, y: this.iconPressed === 0 ? 0.85 : 1 })
        .animation({ duration: 300, curve: curves.interpolatingSpring(0, 1, 328, 28) })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.iconPressed === 0 ? hdsEffect.PointLightSourceType.BRIGHT
              : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.iconPressed = 0
          } else {
            setTimeout(() => { this.iconPressed = -1 }, 200)
          }
        })
        .onClick(() => {
          this.activeSheet = 0
          this.sheetVisible = true
        })

        Column() {
          Image($r('app.media.share')).width(22).height(22)
            .fillColor($r('app.color.icon'))
        }
        .width(40).height(40).borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .scale({ x: this.iconPressed === 1 ? 0.85 : 1, y: this.iconPressed === 1 ? 0.85 : 1 })
        .animation({ duration: 300, curve: curves.interpolatingSpring(0, 1, 328, 28) })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.iconPressed === 1 ? hdsEffect.PointLightSourceType.BRIGHT
              : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.iconPressed = 1
          } else {
            setTimeout(() => { this.iconPressed = -1 }, 200)
          }
        })
        .onClick(() => {
          this.activeSheet = 1
          this.sheetVisible = true
        })

        Column() {
          Image($r('app.media.ic_public_quit')).width(22).height(22)
            .fillColor($r('app.color.unsignable'))
        }
        .width(40).height(40).borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .scale({ x: this.iconPressed === 2 ? 0.85 : 1, y: this.iconPressed === 2 ? 0.85 : 1 })
        .animation({ duration: 300, curve: curves.interpolatingSpring(0, 1, 328, 28) })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.iconPressed === 2 ? hdsEffect.PointLightSourceType.BRIGHT
              : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.iconPressed = 2
          } else {
            setTimeout(() => { this.iconPressed = -1 }, 200)
          }
        })
        .onClick(() => { this.onLogout() })
      }
    }
    .width('100%').padding(16).backgroundColor($r('app.color.card_background'))
    .opacity(this.isReady ? 1 : 0)
    .translate({ y: this.isReady ? 0 : -16 })
    .bindSheet($$this.sheetVisible, this.UnifiedSheet, {
      height: 'auto', detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      onWillDismiss: () => { this.sheetVisible = false }
    })
  }

  private async doShare(ShareUri: string, ShareStr: string) {
    const ctx = this.uiContext.getHostContext() as common.UIAbilityContext;
    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.IMAGE, uri: ShareUri,
      title: '分享二维码', description: '分享二维码', label: '二维码'
    });
    try {
      shareData.addRecord({
        utd: utd.UniformDataType.PLAIN_TEXT, content: ShareStr,
        title: '分享url', description: '可通过分享的url添加账号', label: 'url'
      });
    } catch (e) { console.error(`addRecord: ${e?.message}`); }
    let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    controller.show(ctx, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    }).catch((error: BusinessError) => { console.error(`Share error: ${error?.message}`); });
  }
}

@Component
export default struct HomePage {
  @State currentIndex: number = 0;
  @State titleName: string = '首页';
  @State classList: ClassInfo[] | null = null;
  @State otherUserList: UserDataAndId[] = [];
  @State expandedSection: number = -1;
  @State loginSheetVisible: boolean = false;
  @State loginSheetType: number = -1;
  @State btnAddPressed: boolean = false;
  @State actionPressed: string = '';
  @State installInfo: string = '';
  @StorageLink('userHostName') userHostName: Resource | string = $r('app.string.defaultUname')
  @StorageLink('userHostPhone') userHostPhone: Resource | string = $r('app.string.defaultPhone')
  @StorageLink('userUrl') userUrl: string = ''
  @StorageLink('userQRValue') userQRValue: string = ''
  private pageInfos: NavPathStack = new NavPathStack();
  private controller: TabsController = new TabsController();
  private openLinkContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @Builder tabBuilder(title: string, targetIndex: number) {
    Column() {
      Text(title)
        .fontColor(this.currentIndex === targetIndex ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Bold : FontWeight.Regular)
        .fontSize(this.currentIndex === targetIndex ? $r('sys.float.Caption_L') : $r('sys.float.Caption_M'))
        .onClick(() => { this.currentIndex = targetIndex; this.controller.changeIndex(targetIndex); })
      if (this.currentIndex === targetIndex) {
        Divider().strokeWidth(2).color($r('sys.color.icon_emphasize')).width(20).margin({ top: 4 })
      }
    }
    .width('25%').height(20).justifyContent(FlexAlign.Center)
  }

  @Builder loginSheetContent() {
    if (this.loginSheetType === 0) {
      loginByCommon({ isShow: $loginSheetVisible, otherUserList: $otherUserList })
    } else if (this.loginSheetType === 1) {
      loginByURL({ isShow: $loginSheetVisible, otherUserList: $otherUserList })
    }
  }

  @Builder AddUserMenu() {
    Menu() {
      MenuItem({ content: '扫码添加', startIcon: $r('app.media.qrcode') })
        .onClick(() => this.startScan())
      MenuItem({ content: '账号登录', startIcon: $r('app.media.selector') })
        .onClick(() => { this.loginSheetType = 0; this.loginSheetVisible = true })
      MenuItem({ content: '链接登录', startIcon: $r('app.media.paperclip') })
        .onClick(() => { this.loginSheetType = 1; this.loginSheetVisible = true })
    }
  }

  @Builder ActionItem(icon: Resource, label: string, onClickAction: () => void, iconColor?: ResourceColor) {
    Row() {
      Image(icon).width(24).height(24).fillColor(iconColor ?? $r('app.color.icon'))
      Text(label).fontSize(16).fontColor($r('app.color.primary_text')).margin({ left: 12 })
      Blank()
      Image($r('sys.media.ohos_ic_public_arrow_right')).width(14).height(14)
        .fillColor($r('app.color.secondary_text'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .scale({ x: this.actionPressed === label ? 0.97 : 1, y: this.actionPressed === label ? 0.97 : 1 })
    .animation({ duration: 300, curve: curves.interpolatingSpring(0, 1, 328, 28) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.actionPressed = label
      } else {
        setTimeout(() => { this.actionPressed = '' }, 200)
      }
    })
    .onClick(() => onClickAction())
  }

  @Builder SectionHeader(title: string, count: number, sectionIndex: number, showAdd: boolean = false) {
    Row() {
      Image($r('app.media.arrow_right'))
        .width(14).height(14)
        .fillColor($r('app.color.secondary_text'))
        .rotate({ angle: this.expandedSection === sectionIndex ? 90 : 0 })
        .animation({ duration: 300, curve: curves.interpolatingSpring(0, 1, 280, 26) })
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.primary_text'))
        .margin({ left: 8 })
        .layoutWeight(1)
      if (count > 0) {
        Text(`(${count})`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .margin({ right: 4 })
      }
      if (showAdd) {
        Column() {
          Image($r('app.media.ic_contacts_addcontact'))
            .width(18).height(18)
            .fillColor($r('app.color.text_on_primary'))
        }
        .width(32).height(32).borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.class_button'))
        .margin({ left: 8 })
        .scale({ x: this.btnAddPressed ? 0.85 : 1, y: this.btnAddPressed ? 0.85 : 1 })
        .animation({ duration: 300, curve: curves.interpolatingSpring(0, 1, 328, 28) })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.btnAddPressed ? hdsEffect.PointLightSourceType.BRIGHT
              : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.btnAddPressed = true
          } else {
            setTimeout(() => { this.btnAddPressed = false }, 200)
          }
        })
        .bindMenu(this.AddUserMenu)
      }
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      animateTo({ duration: 400, curve: curves.interpolatingSpring(0, 1, 280, 26) }, () => {
        this.expandedSection = this.expandedSection === sectionIndex ? -1 : sectionIndex
      })
    })
  }

  build() {
    NavDestination() {
      Tabs({ controller: this.controller, index: this.currentIndex }) {
        TabContent() {
          List({ space: 0 }) {
            ListItem() {
              Search({ placeholder: '搜索课程...' })
                .height(44).borderRadius(20)
                .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
                .placeholderColor($r('sys.color.ohos_id_color_text_secondary'))
                .geometryTransition('SEARCH_ONE_SHOT_DEMO_TRANSITION_ID', { follow: true })
                .shadow({ radius: 6, color: '#00000020', offsetX: 0, offsetY: 2 })
                .onTouch((event: TouchEvent) => { if (event.type === TouchType.Up) this.showSearchPage(); })
            }.width('100%').padding({ left: 16, right: 16, top: 56, bottom: 12 })

            ForEach(this.classList, (classInfo: ClassInfo, index: number) => {
              ListItem() { ClassListItem({ classInfo: classInfo }) }.width('100%')
                .onClick(() => { this.pageInfos.pushPath({ name: 'ActivityListPage', param: classInfo }); })
            }, (classInfo: ClassInfo) => classInfo.id)
          }
          .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider'), startMargin: 72, endMargin: 16 })
          .width('100%').scrollBar(BarState.Off)
        }
        .height('100%').width('100%')
        .tabBar($r('app.string.class_list'))
        .onAppear(async () => {
          const cookies = (await this.getHostUser()).cookies
          this.classList = (await CourseAndActivity.getClassList(cookies)).classList
        })

        TabContent() {
          Column() {
            UserInfoComponent({
              hostName: this.userHostName,
              hostPhone: this.userHostPhone,
              url: this.userUrl,
              QRvalue: this.userQRValue,
              onLogout: () => { this.showLogoutDialog() }
            })
              .margin({ top: 48 })

            Row().height(10).width('100%').backgroundColor($r('app.color.page_background'))

            Column() {
              this.SectionHeader('其他用户', this.otherUserList.length, 0, true)
              if (this.expandedSection === 0 && this.otherUserList.length > 0) {
                Column() {
                  List({ space: 0 }) {
                    ForEach(this.otherUserList, (item: UserDataAndId, index) => {
                      ListItem() {
                        OtherUserItem({ userData: item, otherUserList: this.otherUserList, index: index })
                      }.width('100%')
                    }, (item: UserDataAndId) => item.id.toString())
                  }
                  .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider'), startMargin: 72, endMargin: 16 })
                  .scrollBar(BarState.Off)
                  .constraintSize({ maxHeight: 360 })
                }
                .transition(TransitionEffect.OPACITY
                  .combine(TransitionEffect.translate({ y: -10 }))
                  .animation({ duration: 400, curve: curves.interpolatingSpring(0, 1, 280, 26) }))
              }
            }
            .backgroundColor($r('app.color.card_background'))

            Row().height(10).width('100%').backgroundColor($r('app.color.page_background'))
            Column() {
              this.ActionItem($r('app.media.github'), '反馈问题', () => {
                this.openLinkContext.openLink('https://github.com/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT/issues/new')
                  .catch((e: BusinessError<void>) => { hilog.error(0x0000, 'Link', `${e.code}`); });
              })
              this.ActionItem($r('app.media.envelope'), '联系我们', () => {
                let want: Want = { action: 'ohos.want.action.viewData', uri: 'mailto:xyxy1029@petalmail.com' };
                this.openLinkContext.startAbility(want)
                  .catch((e: BusinessError) => { hilog.error(0x0000, 'Mail', `${e.code}`); });
              })
            }
            .backgroundColor($r('app.color.card_background'))

            Row().height(10).width('100%').backgroundColor($r('app.color.page_background'))

            Column() {
              if (this.installInfo !== '') {
                Row() {
                  Text('使用时长')
                    .fontSize(16)
                    .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  Blank()
                  Text(this.installInfo)
                    .fontSize(14)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                }
                .width('100%').padding(12)
              }
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .padding({ left: 4, right: 4 })

            Row().height(20).width('100%').backgroundColor($r('app.color.page_background'))
          }
          .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .bindSheet($$this.loginSheetVisible, this.loginSheetContent, {
            height: 'auto', detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
            onWillDismiss: () => { this.loginSheetVisible = false }
          })
        }
        .tabBar($r('app.string.user'))
      }
      .height('100%').barWidth('100%').barHeight(50).vertical(false)
      .barPosition(BarPosition.End).backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
      .fadingEdge(true).barMode(BarMode.Fixed).animationDuration(0)
      .backgroundColor($r('app.color.page_background'))
      .divider({ strokeWidth: '1px', color: $r('sys.color.comp_divider') }).scrollable(false)
      .onChange((index) => {
        this.titleName = index === 0 ? '首页' : '用户中心'
        this.currentIndex = index
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .backgroundColor($r('app.color.page_background'))
    .title(this.titleName, {
      backgroundBlurStyle: BlurStyle.BACKGROUND_THIN, barStyle: BarStyle.STACK,
      backgroundBlurStyleOptions: {
        colorMode: ThemeColorMode.LIGHT, adaptiveColor: AdaptiveColor.DEFAULT,
        blurOptions: { grayscale: [8, 8] }, scale: 1
      }
    })
    .hideBackButton(true).backgroundImageSize({ width: '100%', height: '100%' })
    .borderRadius($r('sys.float.corner_radius_level8')).height('100%').width('100%')
    .onReady((ctx: NavDestinationContext) => { this.pageInfos = ctx.pathStack; })
    .onAppear(async () => {
      try {
        const dbManager = DatabaseManager.getInstance()
        const hostUser = await this.getHostUser()
        const HostUser = await loginFunction.getUserInfo(hostUser.cookies)
        if (HostUser.msg !== 'successful') {
          hilog.error(DOMAIN, TAG, `Failed to fetch host user info: ${HostUser.msg}`);
          this.pageInfos.replacePath({ name: "LoginPage" }, false); return;
        }
        this.otherUserList = await dbManager.getAllUsers()
        this.userHostName = HostUser.uname
        this.userHostPhone = hostUser.phone
        this.userUrl = HostUser.pic
        this.userQRValue = `http://cdn.aquamarine5.fun/?phone=${hostUser.phone}&pwd=${encodeURIComponent(hostUser.pwd)}&name=${encodeURIComponent(HostUser.uname)}`
      } catch (e) { hilog.error(DOMAIN, TAG, `Error in onAppear: ${e.message}`); }
      await this.loadInstallInfo();
    })

    .onBackPressed(() => {
      if (this.currentIndex === 1) { this.currentIndex = 0; this.controller.changeIndex(0); return true; }
      return true;
    })
  }

  private async loadInstallInfo() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let pref = await preferences.getPreferences(context, 'settings');
      const firstInstall = await pref.get('first_install_time', 0) as number;
      if (firstInstall > 0) {
        const days = Math.floor((Date.now() - firstInstall) / (24 * 60 * 60 * 1000));
        if (days < 1) {
          this.installInfo = '已使用不到1天';
        } else if (days < 30) {
          this.installInfo = `已使用 ${days} 天`;
        } else if (days < 365) {
          const months = Math.floor(days / 30);
          this.installInfo = `已使用 ${months} 个月`;
        } else {
          const years = Math.floor(days / 365);
          const remainMonths = Math.floor((days % 365) / 30);
          if (remainMonths > 0) {
            this.installInfo = `已使用 ${years} 年 ${remainMonths} 个月`;
          } else {
            this.installInfo = `已使用 ${years} 年`;
          }
        }
      }
    } catch (e) {
      console.error('Failed to load install info', e);
    }
  }

  private showLogoutDialog() {
    AlertDialog.show({
      title: '退出登录', message: '确认退出登录吗？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '退出',
        action: async () => {
          try { await DatabaseManager.getInstance().clearHostUserTable() }
          catch (e) { hilog.error(DOMAIN, TAG, `Failed to clear host user: ${e.message}`); }
          this.pageInfos.replacePath({ name: "LoginPage" }, false)
        }
      }
    })
  }

  private async getHostUser(): Promise<UserDataAndId> {
    return await DatabaseManager.getInstance().getUserByPosition(1, true) as UserDataAndId
  }

  private showSearchPage(): void {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 342, 38)
    }, () => { this.pageInfos.pushPath({ name: 'SearchCoursePage' }, false); })
  }

  private startScan(): void {
    let options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL], enableMultiMode: true, enableAlbum: true
    };
    try {
      if (canIUse("SystemCapability.Multimedia.Scan.ScanBarcode")) {
        scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options)
          .then(async (r: scanBarcode.ScanResult) => {
            let msg = await loginFunction.LoginByURL(r.originalValue)
            promptAction.showToast({ message: msg })
            this.otherUserList = await DatabaseManager.getInstance().getAllUsers()
          }).catch((e: BusinessError) => { hilog.error(0x0001, 'Scan', `${e.code}`); });
      }
    } catch (e) { hilog.error(0x0001, 'Scan', 'Scan error'); }
  }
}
