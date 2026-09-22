/// 后台播放服务状态(由 main 在启动时写入,页面读取用于诊断)
///
/// true  = AudioService 初始化成功,播放时通知栏/锁屏会显示控制条
/// false = 初始化失败并降级为普通播放器,通知栏不会有控制条
bool audioServiceReady = false;
