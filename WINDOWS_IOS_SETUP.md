# LyricFlow 构建与安装状态

## 已完成

- 工程目录：H:\Project\musicplayer。
- Flutter 3.47.8 / Dart 3.13.7：H:\Program\flutter。
- GitHub CLI：H:\Program\GitHubCLI；依赖缓存：H:\Program\PubCache。
- Sideloadly：H:\Program\Sideloadly。
- iLoader 2.4.0：H:\Program\iLoader。
- 已生成 iOS 原生工程，最低系统版本 iOS 15。
- flutter analyze 无问题；6 项测试全部通过。
- GitHub macOS 构建、release 真机编译、IPA 打包和上传均成功。
- 已下载 IPA，并与云端产物 SHA-256 校验一致。

## 工程与构建

公开仓库（用户已确认公开）：https://github.com/mretry/LyricFlow

成功构建：https://github.com/mretry/LyricFlow/actions/runs/40315213757

对应源码提交：e8ab6ecf2c6ff9f89102e156e8c16c2775e56368

IPA：H:\Project\musicplayer\build\ios\ipa\LyricFlow-unsigned.ipa

SHA-256：44139d9de3a3822cefcd490b6d9e9eb7a4c921375942a98378263431aba82dfb

应用名 LyricFlow，版本 0.1.0，Bundle ID 为 com.lyricflow.personal.lyricflow。

## 当前安装状态

Sideloadly 已识别 USB 手机（iOS 27.0.1），已载入 IPA，但 Apple 登录返回 -80046：This action cannot be completed at this time。

已从官方 GitHub 发布页下载并校验 iLoader 2.4.0，安装在 H:\Program\iLoader，作为免费替代签名工具。iLoader 已识别手机，等待用户在本机界面完成 Apple 账号登录与验证码验证。不要把密码发到聊天中。

IPA 目前仍是未签名文件，尚未确认成功安装到手机。iOS 编译通过不等于实机功能验收通过。

## 安装及续签

1. 在 iLoader 左侧填写 Apple 账号和密码，点击 Login，完成验证。
2. 选择已连接手机，使用 Install IPA / 导入 IPA 选择上述 LyricFlow-unsigned.ipa。无需安装 SideStore 或 LiveContainer 来安装本应用。
3. 完成签名安装后，按手机提示信任开发者，并在系统要求时开启开发者模式。
4. 打开 LyricFlow，验证 MP3+LRC、MP4+SRT 的文件导入、播放和点句跳转。
5. 免费个人签名有效期约 7 天。后续保持同一账号和应用标识，重新签名覆盖安装。不要先删除应用，以免删除沙盒内媒体。

当前 MVP 没有后台音频及锁屏控制。

## 后续构建

代码推送到 main 会自动构建；也可以在 GitHub Actions → Build iOS IPA → Run workflow 手动运行。成功后下载 LyricFlow-unsigned-ios 产物。仓库中的 codemagic.yaml 仅作为替代构建配置，当前无需 Codemagic 账号。

## 官方参考

- iLoader 官方发布：https://github.com/nab138/iloader/releases/tag/v2.4.0
- Sideloadly：https://sideloadly.io/
- Apple 免费账号限制：https://developer.apple.com/help/account/basics/about-your-developer-account/
