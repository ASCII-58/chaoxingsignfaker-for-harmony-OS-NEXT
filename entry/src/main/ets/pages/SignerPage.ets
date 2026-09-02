import { ActivityInfo, SignType } from './ActivityListPage';
import { CommonSignParams, parseSignResult, Sign, SignDetailResult, SignOutcome, UserQueryObject } from '../utils/sign';
import { FaceApi } from '../utils/faceApi';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager, UserDataAndId } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import { ChaoxingUtils } from '../utils/utils';
import { FunctionalButton, functionalButtonComponentManager } from '@kit.ScenarioFusionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { GestureSignComponent } from '../Component/GestureSignComponent';
import { PasswordSignComponent } from '../Component/PasswordSignComponent';
import { userItem, userMenu } from '../Component/SignerUsers';
import { QRCodeLocation, QRCodePosition } from '../Component/QRCodeLocationCard';
import { photoPicker } from '../Component/PhotoPicker';
import { facePicker } from '../Component/FacePicker';
import { LightButton } from '../Component/LightButton';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import UrlTools from '../utils/urlTools';
import { CaptchaComponent, CaptchaUserParam } from '../Component/Captcha';

const TAG = 'SignerPage';
const DOMAIN = 0x0008;

/** 导航入口 Builder */
@Builder
export function initSignInfo(name: string, activityInfo: ActivityInfo) {
  SignPage({ activityInfo: activityInfo })
}

/**
 * 签到详情页：统一编排所有签到类型的执行流程
 * （组件只负责输入与准备，真正的签到/签退全部走 executeSignFlow / executeSignOutFlow）
 */
@Component
export struct SignPage {
  @State canSign: boolean = true;
  @State activityInfo: null | ActivityInfo = null
  @State commonQueryParams: CommonSignParams = {
    activeId: '',
    latitude: '',
    longitude: '',
    address: '',
    enc: ''
  }
  @State otherUser: Array<userMenu> = []
  @State signIdArray: Array<number> = []
  @State ifPhoto: boolean = false
  @State otherUserDialogIsShow: boolean = false
  @State objectidArr: string[] = []
  @State DestinationLocationName: string = '获取中...' // 初始状态
  @State hostCookies: string = ''
  @State signDetail: SignDetailResult | null = null
  @State faceRequired: boolean = false
  @State faceObjectIdArr: string[] = []
  @State qrPosition: QRCodePosition | null = null
  @State captchaSheetShow: boolean = false
  @State captchaUser: CaptchaUserParam | null = null
  private captchaResolver: ((validate: string | null) => void) | null = null
  // 手势/签到码组件校验通过后回传的码
  @State pendingSignCode: string = ''

  @Builder
  otherUserMenu() {
    List() {
      ForEach(this.otherUser, (user: userMenu) => {
        ListItem() {
          userItem({ user: user, signIdArray: this.signIdArray })
        }
        .onClick(() => {
          if (user.SignPermission === -1) {
            promptAction.showToast({ message: '该用户不在班级', duration: 1500 })
            return
          }
          if (user.SignPermission === 2) {
            promptAction.showToast({ message: '该签到对此用户已截止', duration: 1500 })
            return
          }
          if (this.signIdArray.includes(user.id)) {
            this.signIdArray = this.signIdArray.filter(num => num !== user.id)
          } else {
            this.signIdArray.push(user.id)
          }
        })
      })
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  @Builder
  UserSelectionCard() {
    Column() {
      Row() {
        Text('签到用户')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)

        Button('选择用户')
          .fontSize(13)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.otherUserDialogIsShow = true
          })
          .bindSheet($$this.otherUserDialogIsShow, this.otherUserMenu, {
            title: { title: $r('app.string.other_user') },
            backgroundColor: $r('sys.color.ohos_id_color_dialog_bg'),
            detents: [SheetSize.MEDIUM, SheetSize.LARGE]
          })
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.signIdArray.length === 0) {
        Text('请选择至少一个用户进行签到')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ top: 8, bottom: 4 })
      } else {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.otherUser.filter(u => this.signIdArray.includes(u.id)), (user: userMenu) => {
            Row() {
              Text(user.uname)
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
              Image($r('sys.media.ohos_ic_public_close'))
                .width(14).height(14)
                .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
                .margin({ left: 4 })
            }
            .padding({
              left: 10,
              right: 10,
              top: 5,
              bottom: 5
            })
            .backgroundColor($r('sys.color.ohos_id_color_emphasize', 0.1))
            .borderRadius(14)
            .margin({ right: 8, bottom: 6 })
            .onClick(() => {
              this.signIdArray = this.signIdArray.filter(num => num !== user.id)
            })
          })
        }
      }
    }
    .padding(14)
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(14)
    .margin({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  LocationCard() {
    Column() {
      Row() {
        Text('要求位置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row() {
        Text(this.DestinationLocationName)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
      .borderRadius(10)
      .border({ width: 1, color: $r('sys.color.comp_divider') })
      .onClick(() => {
        if (this.DestinationLocationName !== '获取中...' && this.DestinationLocationName !== '该签到无要求位置') {
          ChaoxingUtils.copyText(this.DestinationLocationName)
        }
      })

      if (this.commonQueryParams.address) {
        Column() {
          Text(`已选: ${this.commonQueryParams.address}`)
            .fontSize(13).fontColor($r('sys.color.ohos_id_color_text_primary')).margin({ top: 10 })
          Row({ space: 12 }) {
            Text(`经度 ${this.commonQueryParams.longitude.substring(0, 10)}`)
              .fontSize(11).fontColor($r('sys.color.ohos_id_color_text_tertiary'))
            Text(`纬度 ${this.commonQueryParams.latitude.substring(0, 10)}`)
              .fontSize(11).fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          }.margin({ top: 4 })
        }.alignItems(HorizontalAlign.Start).width('100%')
      } else {
        Text('请点击下方按钮选择位置')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .margin({ top: 12, bottom: 6 })
          .width('100%')
      }

      Column() {
        FunctionalButton({
          params: {
            openType: functionalButtonComponentManager.OpenType.CHOOSE_LOCATION,
            label: '打开地图选点',
            styleOption: {
              bgColor: functionalButtonComponentManager.ColorType.DEFAULT,
              size: functionalButtonComponentManager.SizeType.DEFAULT,
              plain: false,
              disabled: false,
              loading: false,
              hoverClass: functionalButtonComponentManager.HoverClassType.HOVER_CLASS,
              hoverStartTime: 0,
              hoverStayTime: 0,
              styleConfig: new functionalButtonComponentManager.ButtonConfig().fontSize(15)
            },
          },
          controller: new functionalButtonComponentManager.FunctionalButtonController()
            .onChooseLocation((err, data) => {
              if (err) {
                hilog.error(0x0000, "Sign", "Location Error: %{public}s", err.message);
                return;
              }
              const LoginLocation = ChaoxingUtils.gcj02_to_bd09(data.latitude, data.longitude)
              this.commonQueryParams.address = data.name as string;
              this.commonQueryParams.longitude = LoginLocation.lon.toString();
              this.commonQueryParams.latitude = LoginLocation.lat.toString();
            })
        })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(14)
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(14)
  }

  @Builder
  QRCodeCard() {
    QRCodeLocation({
      ActivityId: this.activityInfo?.ActivityId.toString() || '',
      onPositionChange: (position: QRCodePosition) => {
        this.qrPosition = position
      }
    })
  }

  @Builder
  GestureSignCard() {
    Column() {
      if (this.hostCookies) {
        GestureSignComponent({
          activityId: this.activityInfo?.ActivityId || '',
          hostCookies: this.hostCookies,
          onSignCode: (code: string) => {
            this.pendingSignCode = code
          }
        })
      } else {
        Text('加载用户信息中...')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin(20)
      }
    }
    .width('100%')
  }

  @Builder
  PasswordSignCard() {
    Column() {
      if (this.hostCookies) {
        PasswordSignComponent({
          activityId: this.activityInfo?.ActivityId || '',
          hostCookies: this.hostCookies,
          codeLength: this.signDetail?.numberCount || 0,
          onSignCode: (code: string) => {
            this.pendingSignCode = code
          }
        })
      } else {
        Text('加载用户信息中...')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin(20)
      }
    }
    .width('100%')
  }

  @Builder
  CaptchaSheetBuilder() {
    if (this.captchaUser) {
      CaptchaComponent({
        captchaUser: this.captchaUser,
        onValidated: (validate: string) => {
          this.captchaSheetShow = false
          this.captchaResolver?.(validate)
          this.captchaResolver = null
        },
        onSkip: () => {
          this.captchaSheetShow = false
          this.captchaResolver?.(null)
          this.captchaResolver = null
        }
      })
    }
  }

  build() {
    NavDestination() {
      if (this.activityInfo) {
        Column() {
          Column() {
            Row() {
              Text('签到详情')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .padding({ left: 16, top: 20, bottom: 16 })
              Blank()
            }.width('100%')

            this.UserSelectionCard()

            if (this.faceRequired && (this.activityInfo?.signType === SignType.NORMAL ||
              this.activityInfo?.signType === SignType.LOCATION ||
              this.activityInfo?.signType === SignType.QRCODE)) {
              Column() {
                facePicker({
                  signIdArray: this.signIdArray,
                  faceObjectIdArr: this.faceObjectIdArr,
                  otherUserDialogIsShow: this.otherUserDialogIsShow,
                  otherUser: this.otherUser
                })
              }
              .margin({ left: 16, right: 16, bottom: 12 })
            }

            if (this.activityInfo?.signType === SignType.NORMAL) {
              if (this.ifPhoto) {
                photoPicker({
                  signIdArray: this.signIdArray,
                  objectidArray: this.objectidArr,
                  otherUserDialogIsShow: this.otherUserDialogIsShow,
                  otherUser: this.otherUser
                })
                  .margin({ left: 16, right: 16 })
              } else {
                Column() {
                  Text('点击下方按钮直接签到')
                    .fontSize(16)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .padding({ top: 12, left: 16 })
              }
            } else if (this.activityInfo?.signType === SignType.LOCATION) {
              Column() {
                this.LocationCard()
              }
              .margin({ left: 16, right: 16 })
            } else if (this.activityInfo?.signType === SignType.GESTURE) {
              Column() {
                this.GestureSignCard()
              }
              .margin({ left: 16, right: 16 })
            } else if (this.activityInfo.signType === SignType.QRCODE) {
              Column() {
                this.QRCodeCard()
              }
              .margin({ left: 16, right: 16 })
            } else if (this.activityInfo.signType === SignType.PASSWORD) {
              Column() {
                this.PasswordSignCard()
              }
              .margin({ left: 16, right: 16 })
            } else {
              Text('未支持的签到类型')
                .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                .padding(32)
            }
          }
          .width('100%')
          .layoutWeight(1)

          Column() {
            if (this.prepareHint() !== '') {
              Text(this.prepareHint())
                .fontSize(13)
                .fontColor($r('app.color.unsignable'))
                .margin({ bottom: 8 })
            }
            Row({ space: 12 }) {
              if (this.signOutAvailable()) {
                LightButton({
                  label: '签退',
                  btnEnabled: this.canSign,
                  bgColor: $r('app.color.unsignable'),
                  btnFontSize: 18,
                  btnHeight: 48,
                  onButton: () => {
                    this.executeSignOutFlow()
                  }
                })
                  .layoutWeight(1)
              }
              LightButton({
                label: '立即签到',
                btnEnabled: this.canSign && this.prepareHint() === '',
                bgColor: $r('app.color.class_button'),
                btnFontSize: 18,
                btnHeight: 48,
                onButton: () => {
                  this.showSignConfirmDialog()
                }
              })
                .layoutWeight(1)
            }
            .width('90%')
          }
          .width('100%')
          .padding({ top: 8, bottom: 16 })
          .backgroundColor($r('sys.color.ohos_id_color_background'))
        }
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
        .bindSheet($$this.captchaSheetShow, this.CaptchaSheetBuilder, {
          title: { title: '签到验证码' },
          backgroundColor: $r('sys.color.ohos_id_color_dialog_bg'),
          detents: [SheetSize.MEDIUM, SheetSize.LARGE]
        })
      } else {
        Column() {
          Text('参数加载失败').fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        }.justifyContent(FlexAlign.Center).height('100%')
      }
    }
    .hideTitleBar(false)
    .title('签到', {
      backgroundColor: $r('sys.color.ohos_id_color_background')
    })
    .onAppear(() => {
      this.initPageData(); // 统一数据初始化入口
    })
  }

  // ---------------- 初始化 ----------------

  private async initPageData() {
    const dbManager = DatabaseManager.getInstance()
    // 获取当前用户信息
    const currentUser = await dbManager.getUserByPosition(1, true) as UserDataAndId;

    if (!this.activityInfo || !currentUser) {
      return;
    }

    this.hostCookies = currentUser.cookies;
    this.commonQueryParams.activeId = this.activityInfo.ActivityId

    // 获取活动完整详情（验证码/人脸/拍照要求）
    try {
      this.signDetail = await Sign.GetActiveDetail(currentUser.cookies, this.activityInfo.ActivityId)
      this.faceRequired = this.signDetail.openCheckFaceFlag === 1
      this.ifPhoto = this.signDetail.ifphoto
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Failed to load active detail: ${e.message}`);
      this.ifPhoto = false
    }

    // 如果是位置签到，获取位置信息
    if (this.activityInfo.signType === SignType.LOCATION) {
      try {
        const locName =
          (await Sign.GetLocationSignInfo(currentUser.cookies, this.activityInfo.ActivityId))['locationText'] as string
        this.DestinationLocationName = locName ? locName : '该签到无要求位置'
      } catch (e) {
        this.DestinationLocationName = '位置信息获取失败'
      }
    }

    // 加载其他可签到用户
    this.loadOtherUsers(dbManager, this.activityInfo);
  }

  private async loadOtherUsers(dbManager: DatabaseManager, actInfo: ActivityInfo) {
    const newUserList: userMenu[] = []
    const autoSelectIds: number[] = [] // 自动选择未签到的用户

    // Get user count first
    const userCount = await dbManager.getTableCount('OtherUser')

    // Load main user and other users in parallel
    const loadMainUserPromise = this.loadSingleUser(dbManager, actInfo, 0, true);

    // Create promises for all other users
    const otherUserPromises: Promise<userMenu | null>[] = [];
    for (let i = 1; i <= userCount; i++) {
      otherUserPromises.push(this.loadSingleUser(dbManager, actInfo, i, false));
    }

    // Execute all promises in parallel using allSettled for better error handling
    const results = await Promise.allSettled([
      loadMainUserPromise,
      ...otherUserPromises
    ]);

    // Process main user result
    const mainUserSettled = results[0];
    if (mainUserSettled.status === 'fulfilled' && mainUserSettled.value) {
      const mainUserResult = mainUserSettled.value;
      newUserList.push(mainUserResult);
      if (mainUserResult.SignPermission === 1) {
        autoSelectIds.push(mainUserResult.id);
      }
    }

    // Process other user results
    for (let i = 1; i < results.length; i++) {
      const userSettled = results[i];
      if (userSettled.status === 'fulfilled' && userSettled.value) {
        const userResult = userSettled.value;
        newUserList.push(userResult);
        if (userResult.SignPermission === 1) {
          autoSelectIds.push(userResult.id);
        }
      }
    }

    this.otherUser = newUserList;
    // 默认选中所有未签到的用户
    this.signIdArray = autoSelectIds;
  }

  /**
   * 加载单个用户的可签到状态（0=主用户，N=OtherUser 第 N 条）
   */
  private async loadSingleUser(
    dbManager: DatabaseManager,
    actInfo: ActivityInfo,
    position: number,
    isHost: boolean
  ): Promise<userMenu | null> {
    try {
      const userInfo = await dbManager.getUserById(position);
      if (!userInfo) {
        return null;
      }

      const loginInfo = await loginFunction.getUserInfo(userInfo.cookies);
      const permission = await Sign.PreSignIn(
        actInfo.ActivityId,
        actInfo.ClassId,
        actInfo.CourseId,
        loginInfo.puid ? parseInt(loginInfo.puid) : loginInfo.uid,
        userInfo.cookies,
        actInfo.ext
      );

      return {
        uname: isHost ? loginInfo.uname + ' (主用户)' : loginInfo.uname,
        id: isHost ? 0 : position,
        SignPermission: permission
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Failed to load user at position ${position}`, e);
      return null;
    }
  }

  // ---------------- 签到/签退编排 ----------------

  /**
   * 就绪检查：返回就绪提示文案，空串表示可以签到
   */
  private prepareHint(): string {
    if (this.signIdArray.length === 0) {
      return '请先选择签到用户'
    }
    const selected = this.signIdArray.length
    if (this.ifPhoto) {
      const uploaded = this.objectidArr.filter(id => id).length
      if (uploaded < selected) {
        return `等待签到图片上传 (${uploaded}/${selected})`
      }
    }
    if (this.faceRequired) {
      const faces = this.faceObjectIdArr.filter(id => id).length
      if (faces < selected) {
        return `该签到需要人脸识别，请先为所选用户准备人脸照片 (${faces}/${selected})`
      }
    }
    if (this.activityInfo?.signType === SignType.LOCATION && !this.commonQueryParams.latitude) {
      return '请先选择签到位置'
    }
    if (this.activityInfo?.signType === SignType.GESTURE && !this.pendingSignCode) {
      return '请先绘制并校验手势'
    }
    if (this.activityInfo?.signType === SignType.PASSWORD && !this.pendingSignCode) {
      return '请先输入并校验签到码'
    }
    return ''
  }

  private signOutAvailable(): boolean {
    return this.signDetail !== null && this.signDetail.signOutId > 0 &&
      this.signDetail.signOutPublishTimeStamp > 0
  }

  /**
   * 构造本轮签到的基础公共参数（签到过程中不可变）
   */
  private buildBaseParams(signCode: string, enc: string): CommonSignParams {
    return {
      activeId: this.activityInfo?.ActivityId || '',
      latitude: this.commonQueryParams.latitude,
      longitude: this.commonQueryParams.longitude,
      address: this.commonQueryParams.address,
      enc: enc,
      signCode: signCode
    }
  }

  // 3. 逻辑方法：显示签到确认对话框
  private showSignConfirmDialog() {
    if (this.signIdArray.length === 0) {
      AlertDialog.show({
        title: '提示',
        message: '请先选择至少一个用户',
        confirm: {
          value: '知道了',
          action: () => {
            this.otherUserDialogIsShow = true
          }
        }
      })
      return
    }

    const selectedUsers = this.otherUser.filter(u => this.signIdArray.includes(u.id));
    const userNames = selectedUsers.map(u => u.uname).join('、');

    AlertDialog.show({
      title: '确认签到',
      message: `即将为以下用户签到：\n${userNames}\n\n是否继续？`,
      primaryButton: {
        value: '修改用户',
        action: () => {
          this.otherUserDialogIsShow = true
        }
      },
      secondaryButton: {
        value: '确认签到',
        action: () => {
          this.handleSignAction()
        }
      }
    })
  }

  private async handleSignAction() {
    const hint = this.prepareHint()
    if (hint) {
      promptAction.showToast({ message: hint })
      return
    }

    this.canSign = false
    if (this.activityInfo?.signType === SignType.QRCODE) {
      // 二维码签到：对齐上游 lat/lng 固定 -1，自选位置以 location JSON 提交
      this.commonQueryParams.latitude = '-1'
      this.commonQueryParams.longitude = '-1'
      this.commonQueryParams.address = ''
      if (this.qrPosition) {
        const position = this.qrPosition
        this.commonQueryParams.location =
          `{"result":1,"latitude":"${position.latitude.toFixed(6)}","longitude":"${position.longitude.toFixed(6)}","address":"${position.address}","mockData":"{\\"strategy\\":0,\\"probability\\":-1}"}`
      } else {
        this.commonQueryParams.location = ''
      }

      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: true,
        enableAlbum: true
      };
      try {
        if (canIUse("SystemCapability.Multimedia.Scan.ScanBarcode")) {
          scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options)
            .then(async (result: scanBarcode.ScanResult) => {
              try {
                const parse = UrlTools.parseUrlParams(result.originalValue)

                if (!parse || !parse['enc']) {
                  promptAction.showToast({ message: '二维码格式错误' });
                  this.canSign = true;
                  return;
                }

                const enc = parse['enc']
                hilog.info(DOMAIN, TAG, `Scan successful, enc: ${enc}`);

                // 扫码成功后，执行统一签到流程
                await this.executeSignFlow('', enc)
              } catch (error) {
                const errorMsg = error instanceof Error ? error.message : String(error);
                hilog.error(DOMAIN, TAG, `Failed to process scan result: ${errorMsg}`);
                promptAction.showToast({ message: '处理扫码结果失败' });
                this.canSign = true;
              }
            })
            .catch((error: BusinessError) => {
              hilog.error(DOMAIN, TAG,
                `Failed to get ScanResult. Code:${error.code}, message: ${error.message}`);
              promptAction.showToast({ message: '扫码失败或已取消' });
              this.canSign = true;
            });
          // 扫码签到需要等待扫码结果，直接返回
          return;
        } else {
          promptAction.showToast({ message: '不支持扫码功能' });
          this.canSign = true;
          return;
        }
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        hilog.error(DOMAIN, TAG,
          `Failed to start the scanning service: ${errorMsg}`);
        promptAction.showToast({ message: '启动扫码失败' });
        this.canSign = true;
        return;
      }
    }

    // 非扫码签到：统一签到流程
    await this.executeSignFlow(this.pendingSignCode, this.commonQueryParams.enc)
  }

  /**
   * 统一签到流程：所有签到类型共用同一条执行路径
   * 逐个用户签到（间隔 200ms，对齐上游），支持验证码与人脸，二维码过期中断剩余用户
   */
  private async executeSignFlow(signCode: string, enc: string): Promise<void> {
    const hashTable = new Map<string, string[]>()
    const baseParams = this.buildBaseParams(signCode, enc)
    // 快照勾选列表，避免签到过程中修改勾选导致错位
    const targetIds = this.signIdArray.slice()

    for (let i = 0; i < targetIds.length; i++) {
      try {
        const userInfo = await this.requireUser(targetIds[i])
        const outcome =
          await this.signSingleUser(userInfo, this.objectidArr[i] || '', this.faceObjectIdArr[i] || '',
            baseParams, hashTable)
        if (outcome.kind === 'qrcodeExpired') {
          promptAction.showToast({ message: '签到二维码已过期，请重新扫码', duration: 2000 })
          break
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `User ${targetIds[i]} sign error`, e)
      }
      // 对齐上游代签用户间隔
      if (i < targetIds.length - 1) {
        await new Promise<void>((resolve) => setTimeout(resolve, Sign.NEXT_SIGN_INTERVAL_MS))
      }
    }

    this.showSignResult(hashTable);
    await this.refreshUserPermissions()
    this.canSign = true
  }

  /**
   * 为单个用户执行签到（每个用户使用独立的参数对象，避免共享可变状态）
   */
  private async signSingleUser(userInfo: UserDataAndId, photoObjId: string, faceObjId: string,
    baseParams: CommonSignParams, map: Map<string, string[]>): Promise<SignOutcome> {
    const loginInfo = await loginFunction.getUserInfo(userInfo.cookies)
    const uidForSign = loginInfo.puid ? loginInfo.puid : userInfo.uid.toString()

    const params: CommonSignParams = {
      activeId: baseParams.activeId,
      latitude: baseParams.latitude,
      longitude: baseParams.longitude,
      address: baseParams.address,
      enc: baseParams.enc,
      signCode: baseParams.signCode
    }
    if (this.ifPhoto && photoObjId) {
      params.objectId = photoObjId
    }
    // 人脸识别参数（对齐上游 addFaceRecognitionParameter）
    if (faceObjId) {
      params.courseId = this.activityInfo?.CourseId || ''
      params.currentFaceId = faceObjId
      try {
        params.faceEnc = await FaceApi.CheckFaceResultAndGetEnc(userInfo.cookies,
          this.activityInfo?.ActivityId || '', faceObjId, loginInfo.clientId)
      } catch (e) {
        hilog.error(DOMAIN, TAG, `Get faceEnc failed: ${(e as Error).message}`)
        params.courseId = ''
        params.currentFaceId = ''
        params.faceEnc = ''
      }
    }

    const userQueryParams: UserQueryObject = {
      uid: uidForSign,
      name: loginInfo.uname,
      fid: loginInfo.fid.toString()
    }

    let raw = await Sign.DoSignInV2(userInfo.cookies, params, userQueryParams)
    let outcome = parseSignResult(raw)

    // 需要验证码：弹窗完成后带 validate 重新签到（对齐上游 signWithCaptcha）
    if (outcome.needCaptcha) {
      const validate = await this.requestCaptcha(userInfo.cookies, loginInfo.uname, uidForSign)
      if (validate) {
        raw = await Sign.DoSignInV2(userInfo.cookies, params, userQueryParams, validate)
        outcome = parseSignResult(raw)
      } else {
        outcome = { kind: 'error', message: '验证码校验被跳过', needCaptcha: false }
      }
    }

    this.recordOutcome(map, outcome, loginInfo.uname)
    return outcome
  }

  /**
   * 页面级签退：为所有勾选用户逐个签退
   */
  private async executeSignOutFlow() {
    if (this.signIdArray.length === 0) {
      promptAction.showToast({ message: '请选择至少一个用户' })
      return
    }

    this.canSign = false
    const hashTable = new Map<string, string[]>()
    const targetIds = this.signIdArray.slice()
    for (let i = 0; i < targetIds.length; i++) {
      const label = targetIds[i] === 0 ? '主用户' : `用户${targetIds[i]}`
      try {
        const userInfo = await this.requireUser(targetIds[i])
        const info = await Sign.GetSignInfo(userInfo.cookies, this.activityInfo?.ActivityId || '')
        if (info.signOutId <= 0) {
          this.recordOutcome(hashTable, { kind: 'none', message: '该用户无可用签退', needCaptcha: false }, label)
        } else {
          await Sign.DoSignOut(userInfo.cookies, info.signInId, info.signOutId)
          this.recordOutcome(hashTable, { kind: 'success', message: '签退成功', needCaptcha: false }, label)
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `User ${targetIds[i]} sign out error`, e)
        this.recordOutcome(hashTable,
          { kind: 'error', message: `签退失败: ${(e as Error).message}`, needCaptcha: false }, label)
      }
      if (i < targetIds.length - 1) {
        await new Promise<void>((resolve) => setTimeout(resolve, Sign.NEXT_SIGN_INTERVAL_MS))
      }
    }

    this.showSignResult(hashTable)
    await this.refreshUserPermissions()
    this.canSign = true
  }

  private async requireUser(userId: number): Promise<UserDataAndId> {
    const userInfo = await DatabaseManager.getInstance().getUserById(userId)
    if (!userInfo) {
      throw new Error(`用户 ${userId} 不存在`)
    }
    return userInfo
  }

  /**
   * 弹出滑块验证码并等待用户完成校验
   * @returns validate 值；用户跳过返回 null
   */
  private requestCaptcha(userCookies: string, uname: string, uid: string): Promise<string | null> {
    this.captchaUser = {
      cookies: userCookies,
      uname: uname,
      refererParams: {
        courseId: this.activityInfo?.CourseId || '',
        classId: this.activityInfo?.ClassId || '',
        activePrimaryId: this.activityInfo?.ActivityId || '',
        uid: uid
      }
    }
    this.captchaSheetShow = true
    return new Promise<string | null>((resolve) => {
      this.captchaResolver = resolve
    })
  }

  /**
   * 按用户名聚合同类签到结果（key = kind|message）
   */
  private recordOutcome(map: Map<string, string[]>, outcome: SignOutcome, uname: string) {
    const key = `${outcome.kind}|${outcome.message}`
    if (map.has(key)) {
      map.get(key)!.push(uname)
    } else {
      map.set(key, [uname])
    }
  }

  /**
   * 签到/签退结束后刷新用户权限状态（已签到/可签到/无权限）
   */
  private async refreshUserPermissions() {
    if (!this.activityInfo) {
      return
    }
    try {
      await this.loadOtherUsers(DatabaseManager.getInstance(), this.activityInfo)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Refresh user permissions failed: ${(e as Error).message}`)
    }
  }

  private showSignResult(hashTable: Map<string, string[]>) {
    let message = '';
    hashTable.forEach((names, key) => {
      const separator = key.indexOf('|')
      const kind = separator >= 0 ? key.substring(0, separator) : 'error'
      const result = separator >= 0 ? key.substring(separator + 1) : key
      const displayNames = names.filter(name => name).join(', ')
      if (kind === 'success') {
        message += displayNames ? `✅ ${result}: ${displayNames}\n` : `✅ ${result}\n`
      } else if (kind === 'already') {
        message += displayNames ? `⚠️ ${result}: ${displayNames}\n` : `⚠️ ${result}\n`
      } else {
        message += displayNames ? `❌ ${result}: ${displayNames}\n` : `❌ ${result}\n`
      }
    });

    if (message === '') {
      message = '未进行任何签到操作';
    }

    AlertDialog.show({
      title: '签到结果',
      message: message,
      confirm: {
        value: '确定',
        action: () => {
        }
      }
    })
  }
}
