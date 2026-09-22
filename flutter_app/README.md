# music_app(云韵音乐 App)

Flutter 工程。项目说明、目录结构、打包方式请看**仓库根目录的 `README.md`**。

```bash
flutter pub get
flutter run
```

打包：

| 目标 | 做法 |
|---|---|
| 安卓 APK | `flutter build apk --release --target-platform android-arm64`（见根目录 `编译2.txt`） |
| iOS 未签名 ipa | 需要 macOS；没有 Mac 走 GitHub Actions（见 `编译4.txt`） |
| Windows 桌面版 | `flutter build windows --release` |
| 三端云端打包 | GitHub Actions 手动 Run workflow（见 `编译5.txt`） |
