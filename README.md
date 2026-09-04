# 随地大小签 (Chaoxing Sign-in Helper for HarmonyOS NEXT)

一个基于 **HarmonyOS NEXT** 的超星学习通自动签到应用 —— [ChaoxingSignFaker](https://github.com/aquamarine5/ChaoxingSignFaker) 的鸿蒙移植版，帮助用户便捷地管理和完成签到任务。

![GitHub 下载总量](https://img.shields.io/github/downloads/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT/total?style=flat-square&label=%E4%B8%8B%E8%BD%BD%E9%87%8F)
![最新版下载](https://img.shields.io/github/downloads/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT/latest/total?style=flat-square&label=%E6%9C%80%E6%96%B0%E7%89%88%E4%B8%8B%E8%BD%BD)
![版本](https://img.shields.io/badge/%E7%89%88%E6%9C%AC-1.18.0-green?style=flat-square)
![平台](https://img.shields.io/badge/HarmonyOS_NEXT-API_20-blue?style=flat-square)
![架构](https://img.shields.io/badge/架构-arm64__v8a-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

## 功能特性

### 核心功能

- **多账号管理** - 支持添加和管理多个超星账号
- **自动签到** - 支持多种签到类型（普通签到、拍照签到、位置签到、扫码签到）
- **滑块验证码自动识别** - 本地 ONNX 离线推理，无需联网、无需打码平台
- **课程管理** - 查看和管理已加入的课程列表
- **活动列表** - 实时查看签到活动状态
- **二维码分享** - 快速分享账号信息
- **签退功能** - 支持签到后的签退操作
- **数据备份** - 支持导出/导入数据库文件，便于数据迁移和备份
- **实名认证引导** - 首次启动引导完成开发者实名认证，定期提醒备份数据

### 签到类型支持

| 签到类型 | 说明 |
|---|---|
| 普通签到 | 一键签到 |
| 扫码签到 | 扫描教师提供的二维码 |
| 位置签到 | 地图选点签到 |
| 拍照签到 | 从图库选择照片上传 |
| 滑块验证码 | **本地 ONNX 模型自动完成**，约 0.2s 出结果 |

### 本地滑块识别（ONNX）

应用内置经过精简的 onnxruntime（约 6 MB，仅保留必需算子）与量化为 fp16 的 YOLO 检测模型，
滑块缺口位置在**设备本地**完成推理，全过程：

```
截图(RGBA PixelMap) → CaptchaDetector.detect() → 滑块 x 偏移（一个数值）
```

- 离线运行，不上传任何截图
- 单次推理约 200 ms（真机实测），模型会话进程级复用
- 仅支持 `arm64-v8a`

技术细节见 [entry/src/main/cpp/README.md](entry/src/main/cpp/README.md)。

## 下载安装

前往 [Releases](https://github.com/ASCII-58/chaoxingsignfaker-for-harmony-OS-NEXT/releases) 下载 `.hap` 安装包，
使用 [Auto-installer](https://github.com/likuai2010/auto-installer/) 或 [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/) 安装。

> [!IMPORTANT]
> 华为的签名服务器屏蔽了非中国大陆的 IP 地址。若要在非中国大陆的国家/地区为 HarmonyOS NEXT 侧载软件，请使用代理等方式获取中国大陆的 IP 地址。

> [!NOTE]
> 自签名侧载的 App 默认只有 14 天有效期；完成[开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)后可提升至 180 天。

## 从源码构建

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（需 HarmonyOS SDK 6.0.0(20)）
2. 克隆仓库并用 DevEco Studio 打开，等待依赖同步
3. 配置调试签名（File → Project Structure → Signing Configs，勾选 Automatically generate signature）
4. 连接真机，点击 Run

命令行构建：

```bat
set DEVECO_SDK_HOME=D:\路径\DevEco Studio\sdk
"D:\路径\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`

详细的开发环境与贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 使用说明

### 首次登录

1. 启动应用后进入登录页面
2. 输入超星学习通账号和密码
3. 点击登录按钮完成主账号登录

### 添加其他账号

**方法一：二维码扫描**

1. 在主页点击"添加账号"
2. 使用其他设备的应用生成二维码
3. 扫描二维码完成添加

**方法二：URL 导入**

1. 获取包含账号信息的 URL
2. 在应用中输入 URL
3. 自动解析并添加账号

### 签到操作

1. 在主页选择课程
2. 查看当前签到活动
3. 选择需要签到的活动
4. 根据签到类型完成相应操作（滑块验证码会自动识别完成）
5. 签到成功后，部分活动支持签退操作

## 常见问题

### Q: 登录失败怎么办？

1. 检查网络连接
2. 确认账号密码正确
3. 查看日志输出获取详细错误信息

### Q: 签到失败怎么办？

1. 确认签到活动还在有效期内
2. 检查是否已经签到过
3. 检查具体的签到类型要求（位置、照片、滑块等）

### Q: 如何备份数据？

进入用户中心 → 设置 → 导出数据库，通过系统分享保存 JSON 备份文件。
恢复数据：设置 → 导入数据库，选择之前导出的备份文件即可。

### Q: 应用提示调试有效期即将到期？

1. 尽快导出数据库备份（用户中心 → 设置 → 导出数据库）
2. 前往华为开发者联盟完成[实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)可将有效期延长至 180 天

## 贡献

欢迎提交 Issue 和 Pull Request！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 了解开发环境、项目结构与注意事项。

## 许可证

本项目采用 [MIT](LICENSE) 许可证。

## 免责声明

本项目仅供学习交流使用，请勿用于非法用途。使用本软件所产生的一切后果由使用者自行承担。

## 致谢

- 上游项目：[aquamarine5/ChaoxingSignFaker](https://github.com/aquamarine5/ChaoxingSignFaker)（Android 版）
- 感谢所有为本项目做出贡献的开发者！
