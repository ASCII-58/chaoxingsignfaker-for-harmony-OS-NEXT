import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager, UserDataAndId } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';

const TAG = 'SignerUsers';
const DOMAIN = 0x0012;

/** 签到用户选择列表中的用户项 */
export interface userMenu {
  uname: string
  id: number
  SignPermission: number
}

/** 签到用户头像 */
@Reusable
@Component
export struct Icon {
  @Prop UserId: number;
  @State ImageData: image.PixelMap | null = null;
  @State isLoaded: boolean = false;

  build() {
    Stack() {
      if (this.ImageData) {
        Image(this.ImageData)
          .width(48)
          .height(48)
          .borderRadius(24) // 圆形
          .objectFit(ImageFit.Cover)
          .border({ width: 1, color: $r('sys.color.comp_divider') }) // 系统分割线颜色
      } else {
        // 加载占位图
        Circle({ width: 48, height: 48 })
          .fill($r('sys.color.ohos_id_color_component_normal')) // 系统组件默认色
      }
    }
    .margin({ right: 12 })
    .onAppear(async () => {
      try {
        const userData = await DatabaseManager.getInstance().getUserById(this.UserId);
        if (userData) {
          const url = (await loginFunction.getUserInfo(userData.cookies)).pic
          this.ImageData = await loginFunction.GetPic(url) as image.PixelMap
          this.isLoaded = true;
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `[Icon] Load failed for user ${this.UserId}:`, e);
      }
    })
  }
}

/** 签到用户列表项（勾选代签用户） */
@Reusable
@Component
export struct userItem {
  @State bgColor: Resource = $r('sys.color.ohos_id_color_card_bg'); // 默认卡片背景
  @Prop user: userMenu
  @Link @Watch('onSelectionChange') signIdArray: number[]

  onSelectionChange() {
    // 选中状态由 Checkbox 呈现，此处预留联动
  }

  private permissionText(): string {
    if (this.user.SignPermission === 1) {
      return '可签到';
    }
    if (this.user.SignPermission === 0) {
      return '已签到';
    }
    if (this.user.SignPermission === 2) {
      return '已截止';
    }
    return '无权限(可强制重签)';
  }

  build() {
    Row() {
      Icon({ UserId: this.user.id })

      Column() {
        Text(this.user.uname)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))

        Text(this.permissionText())
          .fontSize(12)
          .fontColor(this.user.SignPermission === 1 ? $r('sys.color.ohos_id_color_text_secondary') :
            $r('sys.color.ohos_id_color_warning'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 使用 Checkbox 代替纯背景色变化，交互更明确
      Checkbox()
        .select(this.signIdArray.includes(this.user.id))
        .selectedColor($r('sys.color.ohos_id_color_connected'))
        .hitTestBehavior(HitTestMode.None) // 让点击事件穿透到 Row
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.bgColor)
    .borderRadius(12)
    .margin({ bottom: 8 })
  }
}
