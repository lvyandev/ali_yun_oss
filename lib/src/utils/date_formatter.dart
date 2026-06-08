/// 日期格式化工具类
///
/// 提供简单的日期格式化功能,用于替代 intl 包的 DateFormat 类。
/// 目前支持的格式：
/// - yyyyMMdd: 例如 "20240101"
/// - yyyyMMddTHHmmss: 例如 "20240101T123045"
class DateFormatter {
  /// 私有构造函数,防止实例化
  DateFormatter._();

  /// 将日期格式化为 "yyyyMMdd" 格式
  ///
  /// 例如: "20240101"
  ///
  /// [dateTime] 要格式化的日期时间,默认为当前时间
  /// 返回格式化后的字符串
  static String formatYYYYMMDD(DateTime? dateTime) {
    final DateTime dt = (dateTime ?? DateTime.now()).toUtc();
    return _padZero(dt.year, 4) + _padZero(dt.month, 2) + _padZero(dt.day, 2);
  }

  /// 将日期格式化为 "yyyyMMddTHHmmss" 格式
  ///
  /// 例如: "20240101T123045"
  ///
  /// [dateTime] 要格式化的日期时间,默认为当前时间
  /// 返回格式化后的字符串
  static String formatYYYYMMDDTHHMMSS(DateTime? dateTime) {
    final DateTime dt = (dateTime ?? DateTime.now()).toUtc();
    return '${formatYYYYMMDD(dt)}T${_padZero(dt.hour, 2)}${_padZero(dt.minute, 2)}${_padZero(dt.second, 2)}';
  }

  /// 辅助方法：将数字填充为指定长度的字符串
  ///
  /// [number] 要填充的数字
  /// [width] 期望的字符串长度
  /// 返回填充后的字符串
  static String _padZero(int number, int width) {
    return number.toString().padLeft(width, '0');
  }
}
