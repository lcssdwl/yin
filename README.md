# 云韵音乐 App

Flutter 音乐 Android App + ThinkPHP 6 后端。**免登录(游客)可完整听歌**,登录仅用于云同步与社交功能。

## 一、目录结构

```
音乐/
├── backend/                    # ThinkPHP 6 后端
│   ├── app/
│   │   ├── controller/         # 控制器(User/Song/Home/Singer/Playlist/Rank/Search/Comment)
│   │   ├── service/            # JWT 服务 / 鉴权上下文
│   │   ├── middleware/         # OptionalAuth(全局,游客放行) / JwtAuth(必须登录)
│   │   └── common.php
│   ├── config/                 # database / jwt / middleware
│   ├── route/app.php           # 所有 API 路由
│   ├── composer.json
│   ├── .example.env            # 复制为 .env
│   └── database/music.sql      # 建库 SQL + Mock 种子数据
│
├── flutter_app/                # Flutter 工程
│   ├── lib/
│   │   ├── config/             # 接口地址 / 主题 / 常量
│   │   ├── core/
│   │   │   ├── network/        # Dio 封装(自动带 Token/设备ID)
│   │   │   ├── storage/        # 本地存储(游客收藏/历史/歌单)
│   │   │   ├── audio/          # 后台播放 + 歌词解析
│   │   │   └── utils/
│   │   ├── data/               # 模型 + 仓储
│   │   ├── providers/          # Auth / Player / Theme
│   │   ├── widgets/            # 旋转唱片 / 歌曲项 / 迷你播放器
│   │   └── pages/              # 启动/首页/搜索/我的/歌单/播放页
│   └── android/.../AndroidManifest.xml   # 权限 + 后台播放服务
```

## 二、后端启动

环境:PHP >= 7.2.5、Composer、MySQL 8.0

```bash
cd backend

# 1. 安装依赖
composer install

# 2. 配置环境
cp .example.env .env        # Windows: copy .example.env .env
# 编辑 .env:填写 DATABASE 用户名/密码

# 3. 导入数据库(含 Mock 歌曲数据)
mysql -u root -p < database/music.sql

# 4. 启动
php think run               # 默认 http://127.0.0.1:8000
```

验证:`curl http://127.0.0.1:8000/api/v1/ping` 应返回 pong。

> Mock 数据中的歌曲是**公开可访问的示例 mp3**,导入即可在 App 里真实播放。

## 三、Flutter 启动

环境:Flutter 3.x(Dart >= 3.0)

```bash
cd flutter_app

# 1. 生成平台目录(android/ios)
flutter create --org com.yunyun --project-name music_app .

# 2. 若 AndroidManifest.xml 被覆盖,请把仓库中的文件复制回
#    android/app/src/main/AndroidManifest.xml
#    (含后台播放 service、通知权限、usesCleartextTraffic)

# 3. 安装依赖
flutter pub get

# 4. 运行
flutter run
```

### 接口地址配置

`lib/config/api_config.dart`:

| 场景 | 地址 |
|------|------|
| Android 模拟器 | `http://10.0.2.2:8000`(默认) |
| 真机 / 局域网 | 改成电脑局域网 IP,如 `http://192.168.1.100:8000` |

也可运行时指定:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

> 后端用 HTTP,Android 9+ 默认禁止明文流量,已在 AndroidManifest 开启 `usesCleartextTraffic="true"`。

## 四、免登录设计

| 能力 | 游客 | 登录 |
|------|------|------|
| 浏览/搜索/榜单/歌单 | ✅ | ✅ |
| 在线播放 + 后台 + 锁屏 + 歌词 | ✅ | ✅ |
| 收藏/历史 | ✅(存本地) | ✅(云同步) |
| 评论/点赞/建云端歌单 | ❌ | ✅ |

实现要点:

- **全局中间件 `OptionalAuth`**:带 Token 写入登录态,不带则游客放行,始终放行不拦截
- **`->middleware('auth')`**:标记必须登录的接口,未登录返回 401
- **游客数据存 Hive 本地**,登录后调 `POST /api/v1/user/sync` 一次性合并到云端(收藏并集、历史去重、本地歌单上传),合并成功后清空本地
- 前端 `AuthProvider` + `PlayerProvider` 内部分流:收藏/历史自动判断写云端还是本地

## 五、接口清单

统一前缀 `/api/v1`,返回 `{code, msg, data}`。🟢 公开 / 🔴 需登录(Header:`Authorization: Bearer <token>`)

### 首页 🟢
```
GET  /home/index        首页聚合(banner+歌单+榜单+推荐+最新)
GET  /home/banner
GET  /home/recommend    推荐歌曲(分页)
GET  /home/newest       最新歌曲
GET  /home/genre        分类
```

### 搜索 🟢
```
GET  /search?keyword=&type=   type:1单曲 2专辑 3歌手 4歌单
GET  /search/hot
GET  /search/suggest
```

### 歌曲
```
GET  /song/:id          🟡 详情(登录时返回 is_collected)
GET  /song/url?id=&quality=   🟢 128/320/flac
GET  /song/lyric?id=    🟢
GET  /song/similar?id=  🟢
GET  /song/batch?ids=   🟢
POST /song/play/:id     🟡 上报播放(登录写历史)
POST /song/collect      🔴 收藏/取消收藏
```

### 榜单 🟢
```
GET  /rank/list
GET  /rank/:id/songs
```

### 歌手 🟢
```
GET  /singer/list?area=&initial=
GET  /singer/:id
GET  /singer/:id/songs
GET  /singer/:id/albums
```

### 歌单
```
GET  /playlist/hot          🟢
GET  /playlist/:id          🟢
GET  /playlist/:id/songs    🟢
GET  /playlist/my           🔴
POST /playlist/create       🔴
POST /playlist/addSong      🔴
POST /playlist/removeSong   🔴
POST /playlist/collect      🔴
```

### 评论
```
GET  /comment/list?target_id=&target_type=   🟢
POST /comment/add    🔴
POST /comment/like   🔴
```

### 用户
```
POST /user/register   🟢  {username, password, nickname?}
POST /user/login      🟢  {username, password}
POST /user/logout     🔴
GET  /user/info       🔴
POST /user/update     🔴
POST /user/sync       🔴  游客数据合并(登录后调一次)
GET  /user/collects   🔴  ?type=1歌曲 2歌单
GET  /user/history    🔴
```

## 六、安全提醒

- 上线前修改 `.env` 中的 `JWT.SECRET`
- 音频地址建议改为 OSS 私有 Bucket + 签名 URL(现为公开示例地址)
- 生产环境关闭 `APP_DEBUG`
