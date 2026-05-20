import { CaptchaComponent } from '../Component/Captcha'

@Builder
export function init(){
  debug()
}

@Component
export default struct debug {

  @Consume('pathInfos') pageInfos: NavPathStack;
  build() {
    NavDestination(){
      CaptchaComponent()
    }
    .height('100%')
    .width('100%')
  }
}
