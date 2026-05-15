
import {DatabaseManager} from '../utils/DataBase'
const TAG = 'InitPage';
const DOMAIN = 0x0001;


@Entry
@Component
struct UI {

  @Provide('pathInfos') pathInfos: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pathInfos) {}
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .hideBackButton(true)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .borderRadius($r('sys.float.corner_radius_level8'))
    .height('100%')
    .width('100%')
    .onAppear(async () => {
      const dbManager = DatabaseManager.getInstance()
      const isHostLogin: boolean = !(await dbManager.isHostUserTableEmpty())
      if (isHostLogin) {
        this.pathInfos.replacePath({name:"HomePage"},false)
      }else this.pathInfos.replacePath({name:"LoginPage"},false)
    })

  }
}
