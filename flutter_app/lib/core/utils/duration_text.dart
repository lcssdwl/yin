/// 时长文本(「我的」页的听歌时长用)
///
/// 规则:不足 1 分钟说「不到 1 分钟」,1 小时内按分钟,
/// 24 小时内按「X 小时 Y 分」,再往上按「X 天 Y 小时」。
/// 够用就好——这里是给人看的一句话,不是精确到秒的计时器。
String listenTimeText(int seconds) {
  if (seconds <= 0) return '0 分钟';
  if (seconds < 60) return '不到 1 分钟';
  if (seconds < 3600) return '${seconds ~/ 60} 分钟';

  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours < 24) {
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
  }

  final days = hours ~/ 24;
  final restHours = hours % 24;
  return restHours == 0 ? '$days 天' : '$days 天 $restHours 小时';
}
