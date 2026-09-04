# 贡献指南 (Contributing)

感谢你对 **随地大小签** 的关注！请先阅读本指南，了解开发环境、项目结构与注意事项。

## 开发环境

| 依赖 | 要求 |
|---|---|
| DevEco Studio | 6.0 及以上（含 HarmonyOS SDK） |
| SDK | target/compatible **6.0.0(20)**，stage 模型 |
| 真机 | HarmonyOS NEXT 设备（`arm64-v8a`） |
| 构建 | Hvigor（随 DevEco Studio 附带，无需 npm） |

## 快速开始

```bat
git clone https://github.com/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT.git
```

1. 用 DevEco Studio 打开项目根目录，等待依赖同步（oh-package.json5）
2. File → Project Structure → Signing Configs，勾选 *Automatically generate signature*（需登录华为开发者账号）
3. 连接真机，点击 Run

### 命令行构建（与 IDE 同引擎）

```bat
set DEVECO_SDK_HOME=D:\你的路径\DevEco Studio\sdk
"D:\你的路径\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap
```

签名产物在 `entry/build/default/outputs/default/entry-default-signed.hap`。

- 清理构建产物：DevEco → Build → Clean，或直接删除 `entry/build`
- 单元测试：`entry/src/test/`（本地）与 `entry/src/ohosTest/`（真机），经 DevEco 测试框架运行

## 项目结构

```
AppScope/app.json5                  # 应用级配置（bundleName、版本号）
entry/src/main/ets/
  entryability/                     # EntryAbility（数据库初始化、Cookie 刷新）
  pages/                            # initPage、Index(首页)、LoginPage、SignerPage 等
  Component/                        # UI 组件（Captcha 滑块、DebugPage、LoginCom 等）
  utils/
    sign/                           # 核心签到 API
    captchaApi.ets                  # 验证码 API
    faceApi.ets                     # 人脸识别 API
    httpClient.ets                  # 统一 Http 助手（新代码禁止手写 createHttp）
    onnx/                           # OnnxRunner（通用封装）+ CaptchaDetector（滑块检测）
entry/src/main/cpp/                 # NAPI 封装 + 精简版 onnxruntime（见 cpp/README.md）
entry/src/main/resources/rawfile/   # 模型文件（rawfile/models/）
model/captcha/                      # 模型源文件与转换脚本
```

## 开发注意事项

### ArkTS / UI

- 函数类型组件属性必须声明为可选（`onX?:`）
- `ImagePacker` 用 `packToData`（不是 `pack`）；文件打开用 `fs.OpenMode.TRUNC`（不是 TRUNCATE）
- 所有资源一律用项目本地引用 `$r('app.xxx')`，**禁止** `$r('sys.xxx.yyy')`；新增资源需同时提供 `base/` 与 `dark/` 两套（适配深色模式）
- NavDestination `.title(..., {barStyle: STACK})` 会渲染悬浮标题栏，页面内容需自行让位（参考课程 Tab 搜索框 `padding-top: 56`），勿"清理"成小数值
- 网络请求统一走 `utils/httpClient.ets` 的 `Http` 助手
- 签到/签退编排集中在 `SignerPage`，手势/密码组件只负责输入校验

### Native / ONNX

- 本项目**仅支持 arm64-v8a**，`entry/build-profile.json5` 的 `abiFilters` 不要加回 x86_64
- `libonnxruntime.so` 是预编译的精简版（1.16.3，仅 fp16 检测路径必需算子），位于
  `entry/src/main/cpp/libs/arm64-v8a/`；**替换 .so 后必须删除 `entry/build` 全量重编**，hvigor 增量构建感知不到该目录变化
- 模型迭代流程：`model/captcha/` 转换/修复 → 拷入 `rawfile/models/` → **换新文件名**（沙箱按文件名缓存，同名旧模型不会自动更新）
- NAPI 接口与推理细节见 [entry/src/main/cpp/README.md](entry/src/main/cpp/README.md)
- 调试入口：首页长按头像 0.8s（或连点 5 次）→ 密码 `nnn` → Debug 面板，内含 ONNX 滑块检测自测（test.jpg 基准 x_offset=258）

### 版本号

发版前在 `AppScope/app.json5` 更新 `versionName` / `versionCode`（versionCode 必须单调递增）。

## 提交规范

- Commit message 用英文祈使句概括变更，如 `Add-slider-auto-detect`、`Fix-login-crash-on-api20`
- 一个 PR 聚焦一件事；跨模块重构请先开 Issue 讨论
- 提交前确认：能构建通过、Debug 面板自测通过（ONNX 检测返回 257±1）

## Pull Request 流程

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/AmazingFeature`
3. 提交更改：`git commit -m 'Add some AmazingFeature'`
4. 推送分支：`git push origin feature/AmazingFeature`
5. 发起 Pull Request，说明改动动机与验证方式（设备型号 / 系统版本）

## 报告 Issue

请附上：

- 设备型号与 HarmonyOS 版本
- 复现步骤（越具体越好）
- 相关日志（hilog 中 `OnnxTest` 等标签）
- 截图或录屏（如涉及 UI）
