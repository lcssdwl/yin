# 云韵音乐 App

Flutter 音乐播放器，支持 **Android / iOS / Windows 桌面**。**免登录(游客)可完整听歌**，登录仅用于云同步与社交功能。

> **本仓库只包含 App 源码。**
> 服务端(Go 后端 `go_backend/`、旧 PHP `backend/`、`tp/`)与歌曲文件、缓存数据库、
> 打包产物一律**不在此仓库**，已在 `.gitignore` 中排除。

## 下载

编译好的安装包统一在 **[Releases](https://github.com/lcssdwl/yin/releases)** 页面下载。

| 发布 | 内容 |
|---|---|
| 安卓 APK(最新) | 两个包:`YunYunMusic-arm64.apk`(真机手机用)、`YunYunMusic-universal.apk`(云手机 / 模拟器用,含 x86_64 与 32 位) |
| Windows 桌面版(最新) | 免安装 zip(music_app.exe + dll + data) |
| iOS 未签名 ipa(最新) | 未签名 ipa;云真机 / 云测平台可直接上传由平台重签,自己的手机则用 Sideloadly / AltStore 自签 |

> 每次在 Actions 里手动跑对应工作流,这几条发布会自动覆盖更新。
> 私有仓库需要登录 GitHub 才能下载。

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

后端地址**运行时从 `url.txt` 读取**，不写死在代码里。改地址只改这个文件即可，不用改代码、Windows 端甚至不用重新打包。

| 平台 | 改哪个文件 | 是否需重编 | 说明 |
|------|-----------|-----------|------|
| Android | `flutter_app/assets/url.txt` | **需要**重编 APK | 内容随 APK 固化，安装后不可再改；改完执行 `flutter build apk` |
| Windows | exe 同目录 `url.txt`（发布包：`云韵音乐-vX.X.X-win64\url.txt`；本地调试：`build\windows\x64\runner\Release\url.txt`） | **不需要** | 记事本改完保存，重启 App 即生效 |

`url.txt` 文件格式：一行纯地址，例如 `http://192.168.1.10:8000` 或 `https://xxxx.devtunnels.ms`，前后空格会被自动去掉；不要写注释、不要加引号。文件缺失或为空时，自动回退到默认地址 `http://10.126.126.10:8000`。

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

统一前缀 `/api/v1`；请求参数以 AES-256-CBC 加密后放在 `enc` 字段；返回 `{code, msg, data}`。

标记说明：**【需登录】** 必须带 `Authorization: Bearer <token>`；没写标记的即 **【公开】**，游客可用。
（下面每一条**都是已实现**的接口，已与 Go 服务端路由逐条核对。）

```
首页    【公开】GET  /home/index          banner + 歌单 + 榜单 + 分类 + 推荐 + 最新
        【公开】GET  /home/banner         /home/recommend(分页)   /home/newest
        【公开】GET  /home/genre          分类列表(含 song_count)
分类    【公开】GET  /genre/{id}/songs     某分类下歌曲(分页)
搜索    【公开】GET  /search?keyword=&type=      /search/hot     /search/suggest
歌曲    【公开】GET  /song/{id}   /song/url?id=&quality=   /song/lyric?id=
        【公开】GET  /song/similar?id=   /song/batch?ids=
        【公开】POST /song/play/{id}      上报播放
        【需登录】POST /song/collect       收藏 / 取消收藏
        【需登录】POST /song/listen        上报"实际听了多少秒"
榜单    【公开】GET  /rank/list      /rank/{id}/songs
歌手    【公开】GET  /singer/list?area=&initial=    /singer/{id}
        【公开】GET  /singer/{id}/songs    /singer/{id}/albums
专辑    【公开】GET  /album/{id}     /album/{id}/songs
歌单    【公开】GET  /playlist/hot   /playlist/{id}   /playlist/{id}/songs
        【需登录】GET  /playlist/my
        【需登录】POST /playlist/create  /addSong  /removeSong  /collect  /delete
评论    【公开】GET  /comment/list
        【需登录】POST /comment/add   /comment/like
用户    【公开】POST /user/register   /user/login
        【需登录】POST /user/logout   /user/update   /user/password   /user/sync
        【需登录】GET  /user/info   /user/collects?type=   /user/history
        【需登录】POST /user/history/clear
其它    【公开】GET  /ping   /app/config   /app/stats
        【公开】POST /app/report
        【公开】GET  /media/audio?id=&quality=&sign=    /media/cover?id=   时效签名防盗链
        【公开】GET  /scan?token=xxx    外部定时扫描(需在后台配置 scan_token)
```

## 五、安全提醒

- 本仓库为**私有仓库**：`lib/` 内含接口加密密钥与接口地址，**不要改成公开**
- 服务端配置(数据库、密钥、管理员账号)不在本仓库，注意另行备份
- 音频建议用私有 Bucket + 签名 URL(工程已支持时效签名播放地址)

## 提交历史

在 GitHub 仓库页面点 **Commits（提交）** 按钮即可查看提交历史，对应路径为 [`../commits/main`](https://github.com/lcssdwl/yin/commits/main)（将 `main` 换成实际默认分支名）。

本项目的代码分布在两个独立仓库，提交历史需分别查看：

- App（本仓库 `yin`）：[`../commits/main`](https://github.com/lcssdwl/yin/commits/main)
- 后端（`yunyun-server`）：[`../commits/main`](https://github.com/lcssdwl/yunyun-server/commits/main)
