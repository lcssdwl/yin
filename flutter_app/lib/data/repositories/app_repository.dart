import '../../config/api_config.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/storage_service.dart';

/// App 使用统计(打开次数 / 使用心跳)
///
/// 后端按设备号累加,并把「在线 / 客户端数」算出来给后台看。
/// 具体什么时候上报见 `core/usage/app_usage.dart`。
class AppRepository {
  final DioClient _client = DioClient.instance;

  /// 上报一次
  ///
  /// [event] `open` = 打开(启动 / 从后台切回),`use` = 使用心跳。
  Future<void> report({
    required String event,
    String platform = '',
    String version = '',
  }) async {
    await _client.post(Api.appReport, data: {
      'event': event,
      'device_id': StorageService.deviceId,
      'platform': platform,
      'version': version,
    });
  }
}
