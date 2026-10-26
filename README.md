# LyricFlow — iPhone / iPad 音视频逐句跳转播放器

**版本：0.1.0（基础版源码）**　**技术：Flutter + Dart**　**存储：完全本地、无账号/无云端服务器**

## Windows 个人签名构建（2026-10-26 更新）

本工程现已包含 iOS 原生工程、锁定的依赖，以及 GitHub Actions 工作流。
使用 Flutter 3.47.8 / Dart 3.13.7，最低 iOS 15。原文后续关于“尚无 iOS 外壳”的描述为初始交付记录。

- 在 GitHub 的 Actions 中运行 **Build iOS IPA**；推送到 main 也会触发构建。
- 工作流会执行静态分析、测试、release 真机编译并生成 `LyricFlow-unsigned-ios` 下载包。
- 将下载包里的 `LyricFlow-unsigned.ipa` 放入 Windows 版 Sideloadly，用自己的 Apple 账号签名安装。
- 不需要付费开发者会员；免费签名有效期 7 天，需要续签。未签名 IPA 不能直接安装。
- 原有 Codemagic 配置仍保留作为另一种构建方式。详细操作见 `WINDOWS_IOS_SETUP.md`。

本地检查不能代替 macOS 编译与 iPhone 实机验证，请以 Actions 构建结果及实机验收为准。

这个仓库交付了完整的 Flutter 业务源码、文件导入与本地媒体库、两种播放模式、可扩展字幕时间轴、单元测试及云端 iOS 编译配置。**它不是已经编译好的 IPA**：本交付环境没有 Flutter SDK、Xcode 和 Apple 签名证书，尚未执行 Flutter 静态分析、真机测试或 iOS 打包。项目通过 `flutter create` 生成 Apple 原生外壳后才能构建。

## 已实现的基础功能

- 通过系统「文件」选择器导入本地兼容音频和视频：MP3/M4A/AAC/WAV/FLAC，MP4/MOV/M4V（具体编码需 iOS 解码器支持，尤其 FLAC/非常规编码）。
- 可同时选中 `lesson.mp4` 与 `lesson.srt`、`music.mp3` 与 `music.lrc` 等同名文件进行自动配对。也可以进入播放器后右上角单独导入或替换字幕。
- 支持 UTF-8 编码的 LRC、SRT、WebVTT；逐句时间高亮，点任何句子定位播放。对于 SRT/VTT，有间隔时不会错误地高亮上一句。
- 手动滚动歌词会暂停跟随；「跟随播放」按钮重新跟踪当前句。
- 音频：以歌词为主的沉浸式界面。视频：竖屏上方视频/下方字幕；横屏宽屏下可以视频左侧/字幕右侧。
- 播放/暂停、前后 10 秒、进度拖动、0.5～2x 倍速、字幕整体 ±5 秒校准（250 毫秒一档）。
- 复制到 App 沙盒私有目录并保存本地媒体列表、字幕关联、上次进度、字幕偏移；可删除副本。
- 默认离线运行，没有隐藏网络访问接口或安全后门。

## 在 Windows 上准备（无 Mac）

1. 安装当前稳定版 Flutter SDK（其 Dart SDK 需 ≥3.12），在 PowerShell 中运行 `flutter --version`。建议使用 VS Code + Flutter / Dart 扩展。
2. 解压本文件夹，例如 `H:\\Program\\Projects\\LyricFlow_MVP`，在该目录打开 PowerShell。
3. 运行 `powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_windows.ps1`；脚本运行 `flutter create --platforms=ios --project-name lyricflow --org com.example .`、安装依赖并执行分析/测试。
4. 在项目目录运行 `flutter test` 检查字幕逻辑。在 Windows 无法使用 Xcode 编译、启动 iOS Simulator 或将本 App 直接部署到 iPhone。
5. 用 Git 将代码推送到 GitHub 私有仓库，连接 Codemagic 等带 macOS/Xcode 的构建服务。
6. **第一次编译检查（无需 Apple 签名）**：Codemagic 选择 `ios-unsigned-check` 工作流，执行 `flutter analyze`、`flutter test`、`flutter build ios --release --no-codesign`。成功只得到无法直接安装的未签名 `.app`，不等于实机测试通过。
7. **安装 iPhone / iPad**：需要完成 Apple 代码签名与分发。推荐加入 Apple Developer Program（付费），在 Codemagic 中设置 App Store Connect API、证书、Bundle ID 和 profile，生成已签名 IPA，上传 TestFlight 后在手机和平板上安装。也可以采用其他符合 Apple 规则的签名流程。未签名产物无法直接安装。
8. `com.example.lyricflow` 只是测试用 Bundle ID；正式签名/发布时必须改为你拥有的唯一 Bundle ID。

说明：工具 `file_picker` v13 需要 iOS 14+，`codemagic.yaml` 会把 CocoaPods 最低版本设为 iOS 14；如果以后提交生成的 `ios/` 目录，也要保证其中的 `Podfile` 与 Xcode Deployment Target 至少为 14.0。签名配置不应放进 Git 仓库。

## 业务结构与升级接口

```
lib/
  models/
    media_entry.dart           # 持久化媒体结构，包含进度和字幕偏移
    timed_cue.dart            # 通用字幕开始/结束/内容（后续可做词级扩展）
  subtitles/
    subtitle_parser.dart      # TimedTextParser 接口 + LRC/SRT/VTT + 注册器
    cue_sync.dart             # 时间轴匹配 + 点击反向跳转，毫秒精度
  playback/
    media_playback.dart       # MediaPlayback 抽象接口
    audio_playback.dart       # just_audio 实现
    video_playback.dart       # video_player 实现
    playback_factory.dart     # 播放器工厂，可替换引擎
  storage/
    library_repository.dart   # LibraryRepository 抽象与本地实现
  services/
    file_import_service.dart  # 系统文件导入 + 流式复制 + 字幕配对
  widgets/
    cue_list.dart             # 可滚动点击字幕列表
  screens/
    library_screen.dart
    player_screen.dart
```

推荐后续升级顺序（不是 V1 已实现功能）：

- **V1.1**：双语字幕、字体大小、主题、上下句跳转、单句 A/B 循环。
- **V1.2**：词级时间戳数据模型（`TimedWord`）、逐字高亮、增强型 LRC/ASS 可插拔解析器。
- **V1.3**：自动语音识别及强制对齐（做成可选 AI 转写服务；可本地或用户显式授权云端）。
- **V2**：文件分享导入、系统分享扩展、播放列表/iCloud 同步、画中画/后台播放、AirPlay。

接口扩展举例：想支持 ASS 字幕，实现 `TimedTextParser` 并在 `SubtitleParsers.register(...)` 注册；想替换视频内核，实现 `MediaPlayback`，然后替换 `PlaybackFactory`；想由 JSON 存储改为 SQLite 或 iCloud，实现 `LibraryRepository` 并让 UI 依赖该接口。

## 字幕规则

- 只要字幕文件与媒体文件主文件名相同（不区分大小写），同一批导入时即自动配对；例如 `abc.MP4` 与 `abc.srt`。
- UTF-8（含 BOM）受支持。GBK、Big5、UTF-16 尚未做转换，建议先转 UTF-8；外挂字幕必须带有效时间戳，普通 TXT 不能直接跳转。
- LRC 支持 `[mm:ss.xx]`、`[mm:ss.xxx]`、同一歌词多个时间戳、全局 `[offset:+/-毫秒]`；末句显示至播放器结束（内部设置为一日，实际以媒体时长为限）。
- SRT/VTT 用字幕开始和结束时间；时间区间外无当前高亮。VTT cue 定位属性、基础 HTML 标签会忽略，保留纯文本；富文本样式不是 V1 范围。
- 点击字幕依据时间戳向播放器调用 `seek`；实际视频帧定位精度与源文件编码、关键帧/平台 seek 行为有关，不保证所有视频逐毫秒无误差。

## 边界与注意事项

- 导入本地文件时，会复制媒体到 App 私有文档目录。大视频会占用设备两份空间；复制使用字节流，不整段一次性加载到内存。
- **iOS 实机测试尚未执行**。尤其需要验证文件导入器能否在不同云盘来源下取到完整本地文件、不同编码/格式、超大媒体文件及 iPad 布局。
- 本版本没有 DRM 受保护 Apple Music 歌曲导入、在线流媒体解析、自动生成字幕、后台音频、锁屏控制、画中画或云同步。
- 这里提供的是独立的播放/歌词交互实现，不包含 Apple 商标、歌词授权数据或受版权保护的 Apple Music 资源。
- 若在更新系统或测试机前做备份，注意备份 App 沙盒文件；删除 App 通常会同时删除其私有媒体副本。

## 第一轮验收清单

- [ ] `flutter analyze` 无错误，`flutter test` 全通过（在有 Flutter 的机器/CI 执行）
- [ ] iPhone 导入 `song.mp3 + song.lrc`；自动高亮和点击跳转正常
- [ ] iPhone 导入 `clip.mp4 + clip.srt`；竖屏上下分屏，点击下方字幕同步视频
- [ ] iPad 横屏视频左右分屏
- [ ] 用户滚动字幕时自动跟随停止；点跟随或字幕后恢复
- [ ] 调整字幕 +1000ms 后高亮和点击跳转一起偏移
- [ ] 退出重新进入后恢复配对和播放位置
- [ ] 导入大视频时内存占用稳定，文件存在应用内存储
- [ ] 删除媒体时清理复制文件

## 文档

- Flutter： https://docs.flutter.dev/
- Codemagic Flutter iOS build： https://docs.codemagic.io/flutter/flutter-projects/
- Codemagic iOS 签名： https://docs.codemagic.io/flutter-code-signing/ios-code-signing/
