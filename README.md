# LyricFlow — iPhone / iPad 音视频逐句跳转播放器

**版本：0.2.0（功能修订源码）** · **技术：Flutter + Dart** · **本地优先**

LyricFlow 将 Apple Music 风格的逐句歌词交互扩展到用户自己的音频和视频：歌词/字幕随播放进度高亮，点击任意句子即可跳转播放。当前交付仍是源码项目，不是已经签名、可直接安装的 IPA；本环境没有 Flutter SDK、Xcode 和 Apple 签名证书。

## 本次修订内容

- **长字幕不再固定三行截断**：字幕列表按内容动态计算高度，自动换行；可调整并记忆字幕字体大小（14–36 pt）。
- **iOS 文件 App 管理**：构建时自动为 `ios/Runner/Info.plist` 设置 `UIFileSharingEnabled` 和 `LSSupportsOpeningDocumentsInPlace`。安装后可在「文件 → 浏览 → 我的 iPhone/iPad → LyricFlow」查看应用 Documents 目录下的 `media` 文件夹。
- **导入失败清理**：媒体先写入 `.partial` 临时文件，校验完整字节数后再提交；失败时清理部分文件及本次媒体目录。批量导入会报告单项失败，不让失败文件残留占空间。
- **手动校准时间轴**：滑块 ±30 秒、手动输入 ±600 秒、±1000/100/10 ms 微调；校准值保存到当前媒体，并同时作用于当前句高亮与点击跳转。
- **ASS 字幕**：支持 `.ass` 的事件时间轴、按 `Format:` 字段解析、逗号文本、`\\N`/`\\n` 换行和基础覆盖样式标签剥离。
- **Windows 局域网二维码导入**：配套电脑脚本生成二维码。iPhone/iPad 在 App 内扫描后直接列出电脑共享目录中的媒体/字幕文件，选择后通过局域网流式下载并直接导入 App；不需要云盘中转，也不先把大视频完整下载到临时目录。

## 基础功能

- 音频：以动态歌词为主的沉浸式界面。
- 视频：竖屏上方视频、下方独立字幕；iPad/横屏宽屏可以视频和字幕左右分栏。
- 支持媒体扩展名：MP3/M4A/AAC/WAV/FLAC、MP4/MOV/M4V（具体编码仍取决于 iOS 解码器）。
- 支持字幕：LRC/SRT/VTT/ASS，UTF-8（含 BOM）。
- 可同时导入同名媒体和字幕文件自动配对；播放中也可单独替换字幕。
- 播放/暂停、进度拖动、前后 10 秒、0.5–2× 倍速、字幕偏移校准。
- 本地保存媒体清单、字幕关联、上次播放进度、每个媒体的时间偏移。
- 无账号和云端存储。局域网传输只在用户启动 Windows 共享脚本后开放，并使用随机令牌保护共享链接。

## Windows 上运行电脑二维码共享工具

### 一次性准备

1. 在 Windows 安装 Python 3（推荐 Python 3.10+）。
2. 解压项目源码。
3. 双击 `scripts/start_pc_share.bat`，或在项目目录运行：

   ```powershell
   py -m pip install -r scripts/requirements-pc-share.txt
   py scripts/pc_lan_share_server.py
   ```

4. 选择要共享的文件夹。电脑会打开一个显示二维码的浏览器页面。
5. 确保电脑与 iPhone/iPad 在同一个 Wi-Fi 网络。打开 LyricFlow，点击右上角二维码图标，扫描电脑网页中的二维码。
6. 在手机/平板选择要导入的媒体和字幕。可同时选择 `movie.mp4` + `movie.ass`，同名文件会自动配对。
7. 导入结束后，在电脑终端按 `Ctrl+C` 停止共享。

### 局域网安全说明

- 共享服务只开放当前选择的文件夹中受支持的媒体和字幕文件，不接受上传，也不允许浏览该目录之外的文件。
- 二维码 URL 含随机访问令牌。不要把它发给不信任的人；在可信的家庭/私人 Wi-Fi 下使用。
- Windows 防火墙提示时，只允许 Python 在**专用网络**中通信。若扫描后连接失败，检查手机与电脑是否处于同一 Wi-Fi、VPN/访客网络隔离以及防火墙设置。
- 默认端口为 `8765`。若端口被占用，可用 `py scripts/pc_lan_share_server.py --port 8766`。
- 工具只会共享当前选定目录中的受支持扩展名；支持递归查找子文件夹。

## Windows 开发和 iOS 构建

1. 安装 Flutter SDK（项目要求 Dart SDK ≥3.12）及 VS Code Flutter/Dart 扩展。
2. 在项目目录运行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_windows.ps1
   ```

   脚本会生成 iOS 原生工程外壳、设置文件共享/相机/局域网权限、拉取依赖并执行 `flutter analyze` 与 `flutter test`。
3. Windows 可以编辑业务源码和运行部分 Dart 测试，但不能用 Xcode 编译、签名或部署 iOS App。
4. 将项目推送到私有 Git 仓库，连接 Codemagic 等 macOS 构建服务。`codemagic.yaml` 会在生成 iOS 工程后再次配置 `Info.plist`。
5. 未签名构建仅用于编译检查，不能直接安装。安装到 iPhone/iPad 需要 Apple 代码签名；TestFlight 测试通常需要 Apple Developer Program 会员、App Store Connect 配置和签名资料。

## 项目结构与扩展接口

```text
lib/
  models/                     # 媒体、通用字幕 cue 数据结构
  subtitles/
    subtitle_parser.dart      # TimedTextParser + LRC/SRT/VTT/ASS
    cue_sync.dart             # 统一毫秒时间轴、偏移、高亮与点击跳转
  playback/
    media_playback.dart       # 播放器抽象接口
    playback_factory.dart     # 按媒体类型选择播放器
  storage/
    library_repository.dart   # 本地媒体库接口与文件管理
    app_settings_repository.dart # 独立用户设置
  services/
    file_import_service.dart  # 文件选择、流式导入、校验与失败清理
    lan_share_client.dart     # 局域网文件清单与流式下载
  screens/
    library_screen.dart
    player_screen.dart
    lan_share_import_screen.dart
  widgets/
    cue_list.dart             # 动态高度、可点击、可滚动字幕列表
scripts/
  pc_lan_share_server.py      # Windows 局域网共享服务与二维码页面
  configure_ios_files.py      # iOS Info.plist 配置
  bootstrap_windows.ps1
```

扩展设计：

- 新字幕格式实现 `TimedTextParser` 并注册到 `SubtitleParsers`。
- 逐字高亮可增加 `TimedWord` 模型，不需要改动播放器接口。
- SQLite/iCloud 可替换 `LibraryRepository` 实现。
- 后台播放、AirPlay 或更换播放引擎可扩展 `MediaPlayback` / `PlaybackFactory`。
- 双语字幕、单句循环、当前句起止时间编辑、主题等可作为独立功能继续添加。

## 已知边界与验收

- ASS 目前提取时间与纯文本；不完整保留字体、位置、颜色、卡拉 OK 特效和矢量绘图。复杂 ASS 特效与逐字高亮不是当前版本目标。
- 字幕解析按 UTF-8 读取；GBK、Big5、UTF-16 暂未做自动转码。
- 视频实际 seek 精度仍受源文件关键帧与 iOS 解码器影响。
- 导入媒体会占用设备本地存储；文件 App 中手动删除媒体后，应用媒体库记录也需要在 App 内删除。
- **当前执行环境没有 Flutter/Dart SDK 与 Xcode，因此本次尚未运行 `flutter analyze`、`flutter test`、iOS 编译或真机测试。** 电脑端 Python 工具会先做语法检查；Flutter 项目需在有 Flutter SDK 的环境完成编译和验收。

### 建议验收顺序

- [ ] 超长中英字幕自动换行、字体调整后仍能完整阅读
- [ ] 文件 App 中能看到 `LyricFlow/media` 目录
- [ ] 中断/失败导入后没有 `.partial` 或孤立媒体目录
- [ ] 偏移设为 +1.250 秒后高亮和点击跳转都一致偏移
- [ ] ASS 导入后时间、逗号文本、多行字幕显示正确
- [ ] Windows 共享工具显示二维码，iPhone/iPad 扫码并直接导入媒体/字幕
- [ ] `flutter analyze` 无错误、`flutter test` 全通过
- [ ] 在 iPhone 与 iPad 真机验证播放、文件共享、相机权限、局域网和长字幕布局
