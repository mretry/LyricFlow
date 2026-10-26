# LyricFlow：Windows 编译准备与免费签名

> 2026-10-26 更新：已安装 Flutter 3.47.8、GitHub CLI 和 Sideloadly，安装目录均位于 `H:\Program`。
> 已生成 iOS 工程并加入 GitHub Actions 工作流；用户选择使用公开仓库 `mretry/LyricFlow`。
> 当前采用 GitHub Actions 编译，不需要另行注册 Codemagic。下文“本次部署”和 Codemagic 步骤为初始记录。
> GitHub 构建：进入仓库 Actions → Build iOS IPA → Run workflow，成功后下载 LyricFlow-unsigned-ios 产物。

## 本次部署

- 源码目录：`H:\Project\musicplayer`，直接放置工程内容，没有额外套一层目录。
- 原始压缩包保留在 `H:\Edge下载\LyricFlow_MVP_Source_v0.1.0.zip`。
- 新增工具的安装目录按用户要求使用 `H:\Program`。本次尚未安装软件。
- 原包 25 个文件解压后已逐一进行 SHA-256 一致性校验。
- 修改了 `codemagic.yaml`，增加未签名 IPA 打包脚本。尚未执行 Flutter 分析、测试、iOS 编译或真机安装。
- 用户提供系统版本：iOS 27.0.1；具体设备型号未提供。

## 选择的路线

Windows 保存源码 → Codemagic 的 macOS/Xcode 构建机编译 → 下载未签名 IPA → Windows 的 Sideloadly 使用个人 Apple 账号签名并安装。

Flutter 的 iOS 编译需要 macOS 和 Xcode；Windows 上安装 Flutter 也不能代替这一步。免费 Apple 账号签名有效期 7 天，每台设备最多同时安装 3 个此类应用。云构建是否免费取决于服务当前额度和账户条件，免费签名不等于无限免费云编译。

## 第一次云编译

1. 在自己的 GitHub 账号创建私有仓库，并上传本工程。仓库根目录应包含 `pubspec.yaml`、`lib/`、`scripts/`、`codemagic.yaml`。这一步会把源码传到 GitHub；本次没有替你创建或上传仓库。
2. 登录 Codemagic，连接该仓库，采用仓库中的 YAML 配置。
3. 选择工作流 `ios-unsigned-check`，显示名称为“iOS 未签名 IPA（下载后用 Sideloadly 签名）”。
4. 工作流会生成缺失的 iOS 原生工程、解析依赖、运行静态分析和现有测试，然后执行 release 无签名构建。
5. 成功后从构建产物下载 `LyricFlow-unsigned.ipa` 和对应 SHA-256 文件。未签名 IPA 仍不能直接安装，需要下一步签名。

此工作流不需要 Apple 开发者会员、签名证书或 App Store Connect API Key。源码中要求 Dart >=3.12，云端 Flutter 必须满足要求；依赖解析或编译失败时应按真实构建日志修复，当前未验证构建成功。

## Windows 签名安装

1. 从 https://sideloadly.io/ 获取官方 Windows 版本。如果安装器支持选择目录，使用 `H:\Program\Sideloadly`；若不能自定义目录，先停止，不默认装到 C 盘。
2. 按 Sideloadly 官方要求检查 Apple 的桌面版 iTunes/iCloud 依赖。机器上已存在 `H:\Program\iTunes` 目录，但尚未核实版本和驱动状态，不要仅凭目录存在就认定可用，也不要未经检查卸载已有软件。Apple 驱动和系统组件可能仍需写入系统目录。
3. USB 连接并解锁手机，按手机提示信任电脑。若系统要求开发者模式，按系统引导开启并重启。
4. 在 Sideloadly 中选择设备，加载下载的 IPA，并由你在本机软件中输入自己的 Apple 账号及验证信息，不需要把密码发给聊天。
5. 完成签名与安装；按系统提示信任开发者后启动 LyricFlow。
6. 后续更新或续签保持相同 Apple 账号和应用标识，优先覆盖安装。删除应用会删除其沙盒内导入的媒体。

Sideloadly 官网声明支持 iOS 27+，但本工程与 iOS 27.0.1 的组合尚未真机验证。签名成功也不代表媒体导入和播放都已验证。

## 续签与验收

- 免费签名约每 7 天需要续签。Sideloadly 提供自动续签；电脑须运行相关服务并能够通过 USB 或配置好的局域网连接手机。
- 先导入一个 MP3 + 同名 LRC，再导入一个 MP4 + 同名 SRT，验证播放、点句跳转、进度恢复和字幕偏移。
- 当前 MVP 没有后台音频和锁屏控制；如果要锁屏听歌，需要另行开发该功能。

## 官方参考

- Flutter iOS 构建：https://docs.flutter.dev/deployment/ios
- Codemagic Flutter YAML：https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/
- Apple 免费账号限制：https://developer.apple.com/help/account/basics/about-your-developer-account/
- Sideloadly 下载与系统要求：https://sideloadly.io/
- Sideloadly 有效期和续签：https://sideloadly.io/faq

原始 README 中的付费会员/TestFlight 路线属于原作者建议；本次按用户选择采用免费个人签名。
