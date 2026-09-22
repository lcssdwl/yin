# 云韵音乐 App

Flutter 音乐播放器，支持 **Android / iOS / Windows 桌面**。**免登录(游客)可完整听歌**，登录仅用于云同步与社交功能。

> **本仓库只包含 App 源码。**
> 服务端(Go 后端 `go_backend/`、旧 PHP `backend/`、`tp/`)与歌曲文件、缓存数据库、
> 打包产物一律**不在此仓库**，已在 `.gitignore` 中排除。

## 一、目录结构

```
flutter_app/                    # Flutter 工程(本仓库主体)
├── lib/
│   ├── config/                 # 接口地址 / 主题 / 常量
│   ├── core/
│   │   ├── network/            # Dio 封装(参数 AES 加密 / 自动带 Token / 设备ID)
│   │   ├── storage/            # 本地存储(游客收藏 / 历史 / 歌单 / 音效设置)
│   │   ├── audio/              # 后台播放 + 歌词解析 + 音效(Android 均衡器)
│   │   └── utils/
│   ├── data/                   # 模型 + 仓储(接口调用)
│   ├── providers/              # Auth / Player / Theme
│   ├── widgets/                # 歌曲项 / 迷你播放器 / 弹窗组件
│   └── pages/                  # 启动 / 发现 / 搜索 / 我的 / 歌单 / 播放页
├── android/                    # 权限、后台播放服务、通知图标
├── ios/                        # Info.plist(后台音频/ATS)、Podfile
├── packages/audio_service/     # 本地补丁版(修 Android 13/14 媒体通知按钮)
└── test/                       # 单元测试

.github/workflows/              # 云端打包(全部手动触发,见 编译5.txt)
编译2.txt / 编译4.txt / 编译5.txt  # 打包说明(安卓本地 / iOS / 云端三端)
```

## 二、运行与打包

环境：Flutter 3.47.x（Dart >= 3.6）

```bash
cd flutter_app
flutter pub get
flutter run                                   # 调试运行
```

| 目标 | 命令 | 说明 |
|---|---|---|
| 安卓 APK | `flutter build apk --release --target-platform android-arm64` | 见 `编译2.txt` |
| iOS(未签名 ipa) | 只能在 macOS 上编 | 见 `编译4.txt`(无 Mac 走 GitHub Actions) |
| Windows 桌面版 | `flutter build windows --release` | — |
| 云端三端 | GitHub Actions 手动 Run workflow | 见 `编译5.txt` |

### 接口地址配置

`lib/config/api_config.dart`（默认值），或运行时用 `--dart-define` 覆盖：

| 场景 | 地址 |
|------|------|
| Android 模拟器 | `http://10.0.2.2:8000` |
| 真机 / 局域网 | `http://192.168.x.x:8000`（电脑局域网 IP） |
| 外网测试 | devtunnel 的 https 地址 |

```bash
flutter run --dart-define=API_BASE_URL=https://xxx.devtunnels.ms
```

> 服务端走 HTTP 时，Android 需 `usesCleartextTraffic="true"`(已配置)，iOS 需 ATS 例外(已配置)。

## 三、免登录设计

| 能力 | 游客 | 登录 |
|------|------|------|
| 浏览 / 搜索 / 榜单 / 歌单 / 分类 | ✅ | ✅ |
| 在线播放 + 后台 + 锁屏 + 歌词 | ✅ | ✅ |
| 收藏 / 历史 | ✅(存本地) | ✅(云同步) |
| 评论 / 点赞 / 建云端歌单 | ❌ | ✅ |

实现要点：

- App 端 `AuthProvider` + `PlayerProvider` 内部分流：收藏/历史自动判断写云端还是本地
- 游客数据存本地(Hive)，登录后调 `POST /user/sync` 一次性合并到云端(收藏并集、历史去重、本地歌单上传)，合并成功后清空本地
- 需登录的接口返回 401 时，App 弹居中登录引导(不打断浏览)

## 四、接口约定(服务端需实现)

统一前缀 `/api/v1`，请求参数以 AES-256-CBC 加密后放在 `enc` 字段，返回 `{code, msg, data}`。
🟢 公开 / 🔴 需登录(Header：`Authorization: Bearer <token>`)

```
首页    GET  /home/index          banner + 歌单 + 榜单 + 分类 + 推荐 + 最新
        GET  /home/genre          分类列表(含 song_count)
        GET  /home/recommend|newest|banner
分类    GET  /genre/{id}/songs     某分类下歌曲(分页)
搜索    GET  /search?keyword=&type=     /search/hot    /search/suggest
歌曲    GET  /song/{id}  /song/url?id=&quality=  /song/lyric?id=  /song/batch?ids=
        POST /song/play/{id}       POST /song/collect   🔴
榜单    GET  /rank/list     /rank/{id}/songs
歌手    GET  /singer/list?area=&initial=   /singer/{id}   /singer/{id}/songs   /singer/{id}/albums
专辑    GET  /album/{id}    /album/{id}/songs
歌单    GET  /playlist/hot  /playlist/{id}  /playlist/{id}/songs
        GET  /playlist/my   POST /playlist/create|addSong|removeSong|collect   🔴
评论    GET  /comment/list   POST /comment/add|like   🔴
用户    POST /user/register|login   GET /user/info   POST /user/update|sync|logout
        GET  /user/collects?type=   /user/history          🔴
```

## 五、安全提醒

- 本仓库为**私有仓库**：`lib/` 内含接口加密密钥与接口地址，**不要改成公开**
- 服务端配置(数据库、密钥、管理员账号)不在本仓库，注意另行备份
- 音频建议用私有 Bucket + 签名 URL(工程已支持时效签名播放地址)
