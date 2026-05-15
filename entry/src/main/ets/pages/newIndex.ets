import { DatabaseManager, UserDataAndId } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import image from '@ohos.multimedia.image';
import { ClassInfo, CourseAndActivity } from '../utils/classFun';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { curves, UIContext,  } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import promptAction from '@ohos.promptAction';
import { loginByCommon, loginByURL } from '../Component/LoginCom';
import { OtherUserItem } from '../Component/OtherUserCom';
import ShareUtils from '../utils/shareUtils';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common, Want } from '@kit.AbilityKit';
import { AnimButton } from '../Component/AnimButton';
import { SettingsComponent } from '../Component/SettingsComponent';

const TAG = 'IndexPage';
const DOMAIN = 0x0004;

interface UserInfoComponentInterface {
  hostName: Resource | string
  hostPhone: Resource | string
  QRvalue: string,
  url:string
}

@Reusable
@Component
struct ClassListItem {
  @Prop classInfo: ClassInfo;
  @Prop index: number;
  @State animScale: number = 1;
  @Consume('pathInfos') pathInfos: NavPathStack;
  @State itemOpacity: number = 0;
  @State itemTranslateY: number = 50;
  @State isPressed: boolean = false;

  aboutToAppear() {
    animateTo({
      duration: 600,
      curve: curves.springMotion(0.6, 0.8),
      delay: (this.index || 0) < 15 ? (this.index || 0) * 50 : 0
    }, () => {
      this.itemOpacity = 1;
      this.itemTranslateY = 0;
    })
  }

  build() {
    Row() {
      ClassIcon({ imageurl: this.classInfo.imageurl })
      Column() {
        Text(this.classInfo.name)
          .fontSize(16)
          .width('100%')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.classInfo.teacherfactor)
          .fontSize(12)
          .textAlign(TextAlign.Start)
          .width('100%')
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width(200)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(80)
    .backgroundColor($r('app.color.class_button'))
    .borderRadius(20)
    .padding({ left: 5, right: 15 })
    .scale({ x: this.animScale, y: this.animScale })
    .opacity(this.itemOpacity)
    .translate({ y: this.itemTranslateY })
    .shadow(this.isPressed ? {
      radius: 20,
      color: 'rgba(10, 89, 247, 0.3)',
      offsetX: 0,
      offsetY: 0
    } : {
      radius: 10,
      color: '#00000020',
      offsetX: 0,
      offsetY: 3
    })
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.3)' })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.animScale = 0.97
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.animScale = 1
        this.isPressed = false
      }
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
        .width(60)
        .height(60)
        .borderColor($r('app.color.class_icon_border'))
        .borderWidth(3)
        .borderRadius(15)
        .margin(10)
        .alt($r('app.media.foreground'))
        .onAppear(async () => {
          if (!this.isLoaded) {
            this.ImageData = await loginFunction.GetPic(this.imageurl)
            this.isLoaded = true
          }
        })
    }
  }
}

@Builder
export function init(name: string) {
  HomePage()
}

@Component
struct UserInfoComponent {
  @State HostImageData: image.PixelMap | Resource =$r('app.media.foreground')
  @Prop url:string
  @Prop hostName: Resource | string
  @Prop hostPhone: Resource | string
  @Prop QRvalue: string
  @State QRCode: image.PixelMap | null =null
  @State QRCodeDialogIsShow: boolean = false
  @State isSettingsOpen: boolean = false
  @State shareButtonScale: number = 1
  @State userHeaderOpacity: number = 1
  @State userHeaderTranslateY: number = 0
  @State userHeaderScale: number = 1
  private pageInfos: NavPathStack | null = null
  private uiContext: UIContext = this.getUIContext();
  private context: Context = this.uiContext.getHostContext() as Context;

  @Builder
  SettingsBuilder() {
    SettingsComponent({ isShow: $isSettingsOpen })
  }

  @Builder
  HeaderBtnContent(img: Resource, fill: ResourceColor) {
    Column() {
      Image(img)
        .height(30).width(30)
        .fillColor(fill)
    }
    .height(45).width(45)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  QRCodeDialog() {
    Column() {
      // Handle bar
      Row()
        .width(40)
        .height(5)
        .backgroundColor($r('sys.color.ohos_id_color_text_tertiary'))
        .borderRadius(2.5)
        .margin({ top: 10, bottom: 20 })

      Text('二维码名片')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 20 })

      if (this.QRvalue) {
        Column() {
          Column() {
            QRCode(this.QRvalue)
              .width(200)
              .height(200)
          }
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .shadow({ radius: 12, color: '#00000010', offsetY: 4 })

          Text(this.hostName)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20 })
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 40 })

        Button() {
          Row() {
            Image($r('app.media.share'))
              .height(24)
              .width(24)
              .fillColor($r('sys.color.ohos_id_color_text_primary_activated'))
              .margin({ right: 8 })
            Text('分享名片')
              .fontSize(18)
              .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
              .fontWeight(FontWeight.Medium)
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('90%')
        .height(50)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(25)
        .shadow({ radius: 8, color: '#00000020', offsetY: 4 })
        .scale({ x: this.shareButtonScale, y: this.shareButtonScale })
        .animation({ duration: 200, curve: Curve.EaseInOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.shareButtonScale = 0.96
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.shareButtonScale = 1
          }
        })
        .onClick(async () => {
          if (!this.QRvalue) {
            promptAction.showToast({ message: '请等待数据加载完成' })
            return
          }
          const shareUtils = new ShareUtils(this.context, this.QRvalue)
          await shareUtils.getQRCode()
          await shareUtils.write(true)
          this.share(shareUtils.FileUri, this.QRvalue)
        })
      } else {
        Column() {
          LoadingProgress()
            .width(60)
            .height(60)
            .color($r('sys.color.ohos_id_color_text_secondary'))
          Text('正在加载用户信息...')
            .fontSize(16)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .margin({ top: 20 })
        }
        .height(300)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  build() {
    Column() {
      Row() {
        Image(this.HostImageData)
          .width(50)
          .height(50)
          .borderRadius(90)// 设置圆角
          .objectFit(ImageFit.Cover)// 图片填充模式
          .alt($r('app.media.foreground'))
          .margin({ left: 7.5 }).onAppear(async ()=>{
          if (this.url!=='') {
            this.HostImageData = await loginFunction.GetPic(this.url) as PixelMap
          }
        })

        Column() {
          Text(this.hostName)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.hostPhone)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .margin({ left: 10 })
        .alignItems(HorizontalAlign.Start)

        Blank().layoutWeight(1)

        AnimButton({
          content: () => {
            this.HeaderBtnContent($r('app.media.settings'), $r('app.color.icon'))
          },
          onClickAction: () => {
            this.isSettingsOpen = !this.isSettingsOpen
          }
        })
          .margin({ right: 10 })
          .bindSheet($$this.isSettingsOpen, this.SettingsBuilder(), {
            height: 'auto',
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
            onWillDismiss: () => {
              this.isSettingsOpen = false
            }
          })

        AnimButton({
          content: () => {
            this.HeaderBtnContent($r('app.media.share'), $r('app.color.icon'))
          },
          onClickAction: () => {
            this.QRCodeDialogIsShow = !this.QRCodeDialogIsShow
          }
        })
          .margin({ right: 10 })
          .bindSheet($$this.QRCodeDialogIsShow, this.QRCodeDialog, {
            height: 'auto',
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
            onWillDismiss: () => {
              this.QRCodeDialogIsShow = false
            }
          })

        AnimButton({
          content: () => {
            this.HeaderBtnContent($r('app.media.ic_public_quit'), Color.Red)
          },
          onClickAction: () => {
            this.showLogoutDialog()
          }
        })
          .margin({ right: 10 })
      }
      .width('97%')
      .height(70)
      .backgroundColor($r('app.color.header_background'))
      .borderRadius(35)
      .padding({ left: 5, right: 5 })
      .zIndex(999999)
      .shadow({
        radius: 10,
        color: '#00000025',
        offsetX: 0,
        offsetY: 4
      })
      .scale({ x: this.userHeaderScale, y: this.userHeaderScale })
      .opacity(this.userHeaderOpacity)
      .translate({ y: this.userHeaderTranslateY })
    }.width('100%')
    .justifyContent(FlexAlign.Start)
  }

  private async share(ShareUri: string, ShareStr: string) {
    const uiContext: UIContext = this.getUIContext();

    let uri: string | undefined = undefined;
    try {
      uri = ShareUri
    } catch (error) {
      console.error(`getUriFromPath error. Code: ${error?.code}, message: ${error?.message}`);
    }

    if (!uri) {
      console.error('getUriFromPath error.');
      return;
    }

    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.IMAGE,
      uri: uri,
      title: '分享二维码',
      description: '分享二维码',
      label: '二维码'
    });

    try {
      shareData.addRecord({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: ShareStr,
        title: '分享url',
        description: '可通过分享的url添加账号',
        label: 'url',
      });
    } catch (error) {
      console.error(`addRecord error. Code: ${error?.code}, message: ${error?.message}`);
    }

    let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    const context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL,
    }).then(() => {
      console.info('ShareController show success.');
    }).catch((error: BusinessError) => {
      console.error(`ShareController show error. code: ${error?.code}, message: ${error?.message}`);
    });
  }

  private async showLogoutDialog() {
    AlertDialog.show({
      title: '退出登录',
      message: `确认退出登录吗？\n`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        action: async () => {
          const dbManager = DatabaseManager.getInstance()
          try {
            await dbManager.clearHostUserTable()
          } catch (error) {
            hilog.error(DOMAIN, TAG, `Failed to clear host user: ${error.message}`);
          }
          if (this.pageInfos !== null) {
            this.pageInfos.replacePath({ name: "LoginPage" }, false)
          }
        }
      }
    })
  }
}

@Component
export default struct HomePage {
  @State UserListIsShow: boolean = false; // 在 animateTo 中被读取和修改
  @State UserListHeight: number = 0; // 在 animateTo 中被修改，在 List 的 .height() 中被读取
  @State footerHeight: number = 80; // 在 animateTo 中被修改，在 Row 的 .height() 中被读取
  @State arrowAngle: number = 0; // 在 animateTo 中被修改，在 ArrowButtonContent 的 .rotate() 中被读取
  @State currentIndex: number = 0; // 在 tabBuilder 中被读取和修改，在 Tabs 的 .onChange() 中被修改
  @State titleName: string = '首页'; // 在 Tabs 的 .onChange() 中被修改，在 NavDestination 的 .title() 中被读取
  @State classList: ClassInfo[] | null = null; // 在 ForEach 中被读取，在 .onAppear 中被赋值
  @State LoginCommonIsShow: boolean = false; // 在 .onClick 和 .onWillDismiss 中被修改，在 .bindSheet 中被读取
  @State LoginURLIsSHow: boolean = false; // 在 .onClick 和 .onWillDismiss 中被修改，在 .bindSheet 中被读取
  @State otherUserList: UserDataAndId[] = []; // 在 ForEach 中被读取，在异步回调中被赋值
  @State buttonRowOpacity: number = 1;
  @State buttonRowTranslateY: number = 0;
  @State userListOpacity: number = 1;
  @State buttonRowScale: number = 1;
  @State githubEmailOpacity: number = 1;
  @State UserInfoComponentData: UserInfoComponentInterface = {
    hostName: $r('app.string.defaultUname'),
    hostPhone: $r('app.string.defaultPhone'),
    QRvalue: '',
    url:''
  }
  private pageInfos: NavPathStack = new NavPathStack();
  private controller: TabsController = new TabsController();
  private openLinkContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @Builder
  tabBuilder(title: string, targetIndex: number) {
    Column() {
      Text(title)
        .fontColor(this.currentIndex === targetIndex ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Bold : FontWeight.Regular)
        .fontSize(this.currentIndex === targetIndex ? $r('sys.float.Caption_L') : $r('sys.float.Caption_M'))
        .onClick(() => {
          this.currentIndex = targetIndex;
          this.controller.changeIndex(targetIndex);
        })

      if (this.currentIndex === targetIndex) {
        Divider()
          .strokeWidth(2)
          .color($r('sys.color.icon_emphasize'))
          .width(20)
          .margin({ top: 4 })
      }
    }
    .width('25%')
    .height(20)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  loginCommon() {
    loginByCommon({ isShow: this.LoginCommonIsShow, otherUserList: this.otherUserList })
  }

  @Builder
  loginURL() {
    loginByURL({ isShow: this.LoginURLIsSHow, otherUserList: this.otherUserList })
  }

  build() {
    NavDestination() {
      Tabs({ controller: this.controller ,index:this.currentIndex}) {
        TabContent() {
          Column() {
            // 固定的搜索框
            Search({ placeholder: '搜索课程...' })
              .height(44)
              .width('100%')
              .borderRadius(20)
              .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
              .placeholderColor($r('sys.color.ohos_id_color_text_secondary'))
              .geometryTransition('SEARCH_ONE_SHOT_DEMO_TRANSITION_ID', { follow: true })
              .shadow({
                radius: 6,
                color: '#00000020',
                offsetX: 0,
                offsetY: 2
              })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Up) {
                  this.showSearchPage();
                }
              })
              .margin({ left: '5%', right: '5%', top: 56, bottom: 12 })

            // 课程列表（可滚动）
            List({ space: 12 }) {
              ForEach(this.classList, (classInfo: ClassInfo, index: number) => {
                ListItem() {
                  ClassListItem({ classInfo: classInfo, index: index })
                }
                .width('100%')
                .onClick(() => {
                  this.pageInfos.pushPath({ name: 'ActivityListPage', param: classInfo });
                })
              }, (classInfo: ClassInfo) => classInfo.id)
            }
            .layoutWeight(1)  // 撑满剩余空间
            .width('100%')
          }
          .height('100%')
          .width('100%')
        }
        .tabBar($r('app.string.class_list'))
        .onAppear(async () => {
          const cookies = (await this.getHostUser()).cookies
          hilog.debug(DOMAIN, TAG, 'Loading class list');
          this.classList = (await CourseAndActivity.getClassList(cookies)).classList
        })

        TabContent() {
          Column() {
            Column().height(56)
            UserInfoComponent(this.UserInfoComponentData)

            Column() {
              Row() {
                AnimButton({
                  content: () => {
                    this.IconBtnContent($r('app.media.qrcode'))
                  },
                  onClickAction: () => {
                    let options: scanBarcode.ScanOptions = {
                      scanTypes: [scanCore.ScanType.ALL],
                      enableMultiMode: true,
                      enableAlbum: true
                    };
                    try {
                      // 可调用getHostContext接口获取当前页面关联的Context
                      if (canIUse("SystemCapability.Multimedia.Scan.ScanBarcode")) {
                        scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options)
                          .then(async (result: scanBarcode.ScanResult) => {
                            let loginMSG = await loginFunction.LoginByURL(result.originalValue)
                            promptAction.showToast({ message: loginMSG })
                            let dbManager = DatabaseManager.getInstance();
                            this.otherUserList = await dbManager.getAllUsers()
                            // 解析码值结果跳转应用服务页
                            hilog.info(0x0001, '[Scan CPSample]',
                              `Succeeded in getting ScanResult by promise with options, result is ${JSON.stringify(result)}`);
                          })
                          .catch((error: BusinessError) => {
                            hilog.error(0x0001, '[Scan CPSample]',
                              `Failed to get ScanResult by promise with options. Code:${error.code}, message: ${error.message}`);
                          });
                      } else {
                        // Fallback for unsupported SystemCapability
                      }
                    } catch (error) {
                      hilog.error(0x0001, '[Scan CPSample]',
                        `Failed to start the scanning service. Code:${error.code}, message: ${error.message}`);
                    }
                  }
                })

                AnimButton({
                  content: () => {
                    this.IconBtnContent($r('app.media.selector'))
                  },
                  onClickAction: () => {
                    this.LoginCommonIsShow = !this.LoginCommonIsShow
                  }
                })
                  .bindSheet($$this.LoginCommonIsShow, this.loginCommon, {
                    height: 'auto',
                    detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                    backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
                    onWillDismiss: () => {
                      this.LoginCommonIsShow = false
                    }
                  })

                AnimButton({
                  content: () => {
                    this.IconBtnContent($r('app.media.paperclip'))
                  },
                  onClickAction: () => {
                    this.LoginURLIsSHow = true
                  }
                })
                  .bindSheet($$this.LoginURLIsSHow, this.loginURL(), {
                    height: 'auto',
                    detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                    backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
                    onWillDismiss: () => {
                      this.LoginURLIsSHow = false
                    }
                  })

                AnimButton({
                  content: () => {
                    this.ArrowButtonContent()
                  },
                  onClickAction: () => {
                    animateTo({ curve: curves.springMotion(0.6, 0.8) }, () => {
                      this.UserListIsShow = !this.UserListIsShow;
                      this.arrowAngle = this.UserListIsShow ? 180 : 0;
                      this.UserListHeight = this.UserListIsShow ? 400 : 0;
                      this.footerHeight = this.UserListIsShow ? 0 : 80;
                      this.githubEmailOpacity = this.UserListIsShow ? 0 : 1;
                      this.userListOpacity = this.UserListIsShow ? 1 : 0;
                    })
                  }
                })
                  .margin({ right: 15 })

              }
              .padding({ top: 15, bottom: 15 })
              .justifyContent(FlexAlign.SpaceAround)
              .width('100%')

              Column() {
                List() {
                  ForEach(this.otherUserList, (item: UserDataAndId, index) => {
                    ListItem() {
                      OtherUserItem({ userData: item, otherUserList: this.otherUserList, index: index })
                    }.width('98%')
                    .margin({ bottom: '1%', top: '1%' })
                  }, (item: UserDataAndId) => item.id.toString())
                }
                .borderRadius(20)
                .margin(5)
                .scrollBar(BarState.Off)
                .width('98%')
                .opacity(this.userListOpacity)
                .alignListItem(ListItemAlign.Center)
                .height(this.UserListHeight)

                Row() {
                  Text('联系我').fontSize(20).fontWeight(FontWeight.Bold).margin({ left: 15 })
                  Blank()
                  AnimButton({
                    content: () => {
                      this.GithubButtonContent()
                    },
                    onClickAction: () => {
                      this.openLinkContext.openLink('https://github.com/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT/issues/new')
                        .catch((error: BusinessError<void>) => {
                          hilog.error(0x0000, 'testTag', 'Execution failed, code = %{public}d, message = %{public}s',
                            error.code, error.message);
                        });
                    }
                  })
                    .margin({ right: 30 })

                  AnimButton({
                    content: () => {
                      this.IconBtnContent($r('app.media.envelope'))
                    },
                    onClickAction: () => {
                      let want: Want = {
                        action: 'ohos.want.action.viewData',
                        uri: 'mailto:xyxy1029@petalmail.com'
                      };
                      this.openLinkContext.startAbility(want)
                        .catch((error: BusinessError) => {
                          hilog.error(0x0000, 'testTag',
                            'Start ability failed, code = %{public}d, message = %{public}s',
                            error.code, error.message);
                        });
                    }
                  }).margin({ right: 15 })
                }
                .justifyContent(FlexAlign.Center)
                .width('96%')
                .height(this.footerHeight)
                .opacity(this.githubEmailOpacity)
                .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
                .borderRadius(20)
                .shadow({
                  radius: 30,
                  color: 'rgba(10, 89, 247, 0.2)',
                  offsetX: 0,
                  offsetY: 5
                })
                .border({ width: 1, color: 'rgba(255, 255, 255, 0.6)' })
                .margin({ bottom: '2%' })
              }
              .width('100%')
            }
            .width('97%')
            .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
            .borderRadius(25)
            .margin({ top: 15 })
            .scale({ x: this.buttonRowScale, y: this.buttonRowScale })
            .opacity(this.buttonRowOpacity)
            .translate({ y: this.buttonRowTranslateY })
            .shadow({
              radius: 30,
              color: 'rgba(10, 89, 247, 0.2)',
              offsetX: 0,
              offsetY: 5
            })
            .border({ width: 1, color: 'rgba(255, 255, 255, 0.6)' })
          }.height('100%')
        }.tabBar($r('app.string.user'))
      }
      .height('100%')
      .barWidth('100%')
      .barHeight(50)
      .vertical(false)
      .barPosition(BarPosition.End)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
      .fadingEdge(true)
      .barMode(BarMode.Fixed)
      .animationDuration(0)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .divider({ strokeWidth: '1px', color: $r('sys.color.comp_divider') })
      .scrollable(false)
      .onChange((index) => {
        this.titleName = index === 0 ? '首页' : '用户中心'
        this.currentIndex =index
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .title(this.titleName, {
      backgroundBlurStyle: BlurStyle.BACKGROUND_THICK, barStyle: BarStyle.STACK, backgroundBlurStyleOptions: {
        colorMode: ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.AVERAGE,
        blurOptions: { grayscale: [20, 20] },
        scale: 1
      }
    })
    .hideBackButton(true)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .borderRadius($r('sys.float.corner_radius_level8'))
    .height('100%')
    .width('100%')
    .onReady((ctx: NavDestinationContext) => {
      this.pageInfos = ctx.pathStack;
    })
    .onAppear(async () => {
      try {
        const dbManager = DatabaseManager.getInstance()
        const hostUser = await this.getHostUser()
        const HostUser =
          await loginFunction.getUserInfo(hostUser.cookies)
        if (HostUser.msg !== 'successful') {
          hilog.error(DOMAIN, TAG, `Failed to fetch host user info: ${HostUser.msg}`);
          this.pageInfos.replacePath({ name: "LoginPage" }, false)
          return
        }
        this.otherUserList = await dbManager.getAllUsers()
        hilog.debug(DOMAIN, TAG, `Loaded ${this.otherUserList.length} other users`);
        let url = HostUser.pic
        this.UserInfoComponentData.url = url
        this.UserInfoComponentData.hostName = HostUser.uname
        this.UserInfoComponentData.hostPhone = hostUser.phone
        this.UserInfoComponentData.QRvalue =
          `http://cdn.aquamarine5.fun/?phone=${this.UserInfoComponentData.hostPhone}&pwd=${encodeURIComponent(hostUser.pwd)}&name=${decodeURIComponent(this.UserInfoComponentData.hostName)}`
      } catch (e) {
        hilog.error(DOMAIN, TAG, `Error in onAppear: ${e.message}`);
      }
    })
    .onBackPressed(() => {
      if (this.currentIndex === 1) {
          this.currentIndex = 0;
          this.controller.changeIndex(0);
          return true;
        }
      return true;
    })
    // .onBackPressed(() => {
    //
    //   return true;
    // })
  }

  @Builder
  HeaderBtnContent(img: Resource, fill: ResourceColor) {
    Column() {
      Image(img)
        .height(30).width(30)
        .fillColor(fill)
    }
    .height(45).width(45)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  IconBtnContent(img: Resource) {
    Image(img)
      .height(30).width(30)
      .fillColor($r('app.color.icon'))
      .margin(15)
  }

  @Builder
  ArrowButtonContent() {
    Image($r('sys.media.ohos_ic_public_arrow_down'))
      .height(30)
      .width(30)
      .fillColor($r('app.color.icon'))
      .margin(15)
      .rotate({ angle: this.arrowAngle })
      .animation({ duration: 300, curve: Curve.FastOutSlowIn })
  }

  @Builder
  GithubButtonContent() {
    Image($r('app.media.github'))
      .height(40).width(40)
      .fillColor($r('app.color.icon'))
      .margin(10)
  }

  private async getHostUser(): Promise<UserDataAndId> {
    return await DatabaseManager.getInstance().getUserByPosition(1, true) as UserDataAndId
  }

  private showSearchPage(): void {
    // 使用animateTo包裹页面跳转，实现一镜到底动画
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 342, 38)
    }, () => {
      this.pageInfos.pushPath({ name: 'SearchCoursePage' }, false);
    })
  }
}
