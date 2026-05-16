# 超星签到助手 (Chaoxing Sign-in Helper)

一个基于 HarmonyOS 的超星学习通自动签到应用，帮助用户便捷地管理和完成签到任务。

## 功能特性

### 核心功能
- **多账号管理** - 支持添加和管理多个超星账号
- **自动签到** - 支持多种签到类型（普通签到、拍照签到、位置签到、扫码签到）
- **课程管理** - 查看和管理已加入的课程列表
- **活动列表** - 实时查看签到活动状态
- **二维码分享** - 快速分享账号信息
- **签退功能** - 支持签到后的签退操作
- **数据备份** - 支持导出/导入数据库文件，便于数据迁移和备份
- **实名认证引导** - 首次启动引导完成开发者实名认证，定期提醒备份数据

### 签到类型支持
- 普通签到
- 扫码签到
- 位置签到
- 拍照签到 - 支持从图库选择照片

## 开始使用

### 安装步骤

您可以使用[Auto-installer](https://github.com/likuai2010/auto-installer/)或[DevEcho Testing](https://developer.huawei.com/consumer/cn/deveco-testing/)进行安装。

> [!IMPORTANT]
> 华为的签名服务器屏蔽了非中国大陆的IP地址，若要在非中国大陆的国家/地区为HarmonyOS NEXT侧载软件，请使用代理等方式使用中国大陆的IP地址。

> [!NOTE]
> 在HarmonyOS NEXT使用自签名的方式进行侧载的App默认只有14天的有效期，进行[开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)后即可将有效期提升至180天。


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

**方法二：URL导入**
1. 获取包含账号信息的URL
2. 在应用中输入URL
3. 自动解析并添加账号

### 签到操作

1. 在主页选择课程
2. 查看当前签到活动
3. 选择需要签到的活动
4. 根据签到类型完成相应操作：
   - **普通签到**：直接点击签到按钮
   - **位置签到**：打开地图选择位置后签到
   - **拍照签到**：从图库选择照片上传后签到
   - **扫码签到**：扫描教师提供的二维码
5. 签到成功后，部分活动支持签退操作

## 常见问题

### Q: 登录失败怎么办？
A: 
1. 检查网络连接
2. 确认账号密码正确
3. 查看日志输出获取详细错误信息

### Q: 签到失败怎么办？
A: 
1. 确认签到活动还在有效期内
2. 检查是否已经签到过
3. 查看具体的签到类型要求（位置、照片等）

### Q: 如何备份数据？
A: 
进入用户中心 → 设置 → 导出数据库，将通过系统分享保存 JSON 备份文件。
恢复数据：设置 → 导入数据库，选择之前导出的备份文件即可。

### Q: 应用提示调试有效期即将到期？
A: 
1. 尽快导出数据库备份（用户中心 → 设置 → 导出数据库）
2. 前往华为开发者联盟完成[实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)可将有效期延长至 180 天

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件

## 免责声明

本项目仅供学习交流使用，请勿用于非法用途。使用本软件所产生的一切后果由使用者自行承担。

## 联系方式

- 作者：ASCII-58
- GitHub：[https://github.com/ASCII-58/chaoxingsignfacker](https://github.com/ASCII-58/chaoxingsignfacker)
- 参考项目：[https://github.com/aquamarine5/ChaoxingSignFaker](https://github.com/aquamarine5/ChaoxingSignFaker)

## 致谢

感谢所有为本项目做出贡献的开发者！
