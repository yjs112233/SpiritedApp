/// 通用工具函数（对应 MP utils/tools.js + TaskUtils + SyncTaskUtils + 盘类型映射）
library;

import 'dart:math';

class Formatters {
  Formatters._();

  /// 格式化文件大小（bytes 可为 num 或字符串形式的纯数字）
  static String formatFileSize(dynamic bytes, [int decimalPoint = 2]) {
    final b = _toNum(bytes);
    if (b == 0) return '0 B';
    if (b == null) return '';

    const k = 1024.0;
    final dm = decimalPoint;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(b) / log(k)).floor();

    // 修正：不足 1TB 但对数进到 4 的场景
    if (i >= 4 && b < k * k * k * k) i = 3;
    if (i > sizes.length - 1) i = sizes.length - 1;
    if (i < 0) i = 0;

    if (decimalPoint == 0) {
      return '${(b / pow(k, i)).ceil()} ${sizes[i]}';
    }
    final v = (b / pow(k, i)).toStringAsFixed(dm);
    return '$v ${sizes[i]}';
  }

  static double? _toNum(dynamic v) {
    if (v == null || v == '') return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// 终身判定（时长天数超过 10 年）
  static bool isLifetimeDays(dynamic days) {
    final n = _toNum(days);
    return n != null && n > 3650;
  }

  /// 终身判定：到期时间串（如 2036-01-01）距今超过 10 年
  static bool isLifetimeEndTime(String? endTime) {
    if (endTime == null || endTime.isEmpty) return false;
    final time = DateTime.tryParse(endTime.replaceAll('/', '-'))?.millisecondsSinceEpoch;
    if (time == null) return false;
    return time - DateTime.now().millisecondsSinceEpoch > 3650 * 24 * 3600 * 1000;
  }

  /// 秒数 → 时间格式（X天XX时XX分 / XX分XX秒）
  static String secondsToTime(dynamic sRaw) {
    final s = _toNum(sRaw)?.floor() ?? -1;
    if (s < 0) return '';
    final day = s ~/ 86400;
    final hour = (s ~/ 3600) % 24;
    final min = (s ~/ 60) % 60;
    final sec = s % 60;

    final buf = StringBuffer();
    if (day > 0) buf.write('${day < 10 ? '0$day' : day}天');
    if (hour > 0) {
      buf.write('${hour < 10 ? '0$hour' : hour}时');
    } else if (day > 0) {
      buf.write('0$hour时');
    }
    buf.write('${min < 10 ? '0' : ''}$min分');
    if (!buf.toString().contains('天')) {
      buf.write('${sec < 10 ? '0' : ''}$sec秒');
    }
    return buf.toString();
  }

  /// 格式化日期时间
  static String formatDateTime(dynamic timestamp) {
    final ms = _toNum(timestamp);
    if (ms == null || ms == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.truncate());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// 格式化日期
  static String formatDate(dynamic timestamp) {
    final ms = _toNum(timestamp);
    if (ms == null || ms == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.truncate());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 解析 "15.96M"/"66.29KB" 形式的速度串为 MB/s（任务监控同款格式）
  static double? parseSpeedToMb(String? speed) {
    if (speed == null || speed.isEmpty) return null;
    final m = RegExp(r'^\s*([\d.]+)\s*(B|[KMGT]B?)', caseSensitive: false).firstMatch(speed);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    final unit = (m.group(2) ?? 'B').toUpperCase().replaceAll('B', '');
    const order = {'': 0, 'K': 1, 'M': 2, 'G': 3, 'T': 4};
    return v / pow(1024, (order[unit] ?? 0) - 2);
  }

  /// 计算使用量百分比
  static int computeTrafficPercent(dynamic usedRaw, dynamic totalRaw) {
    final used = _toNum(usedRaw) ?? 0;
    final total = _toNum(totalRaw) ?? 0;
    if (total == -1) {
      final param = min(1.0, used / (10.0 * 1024 * 1024 * 1024));
      return min(20, (param * 100).floor());
    }
    if (total == 0) return 0;
    return (used / total * 100).floor();
  }

  /// 获取时区（UTC+08:00 形式，后端 timerModel.timezone 可解析）
  static String getTimezone() {
    final off = DateTime.now().timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final h = off.inHours;
    final m = off.inMinutes % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return 'UTC$sign${two(h)}:${two(m)}';
  }

  /// 生成 uuid（查询类 POST 跳过网关 1 秒幂等拦截）
  static String getUuid() {
    final rnd = Random.secure();
    const chars = '0123456789abcdef';
    String gen(int n) => List.generate(n, (_) => chars[rnd.nextInt(16)]).join();
    return '${gen(8)}-${gen(4)}-4${gen(3)}-a${gen(3)}-${gen(12)}';
  }

  // ==================== 文件类型图标 ====================

  static const Map<String, Set<String>> _extMap = {
    'image': {'bmp', 'rle', 'dib', 'jpg', 'jpeg', 'jpe', 'jpf', 'jpx', 'jp2', 'j2c', 'j2k', 'jpc', 'jps', 'png', 'tif', 'tiff', 'pbm', 'pgm', 'ppm', 'pnm', 'pfm', 'pam', 'mpo', 'gif', 'hevc', 'heif', 'webp', 'svg'},
    'video': {'mpeg', 'mpg', 'dat', 'avi', 'mov', 'asf', 'wmv', 'navi', '3gp', 'ra', 'rm', 'rmx', 'mkv', 'flv', 'f4v', 'rmvb', 'webm', 'qsv', 'mp4'},
    'audio': {'cda', 'wav', 'aiff', 'mp3', 'mid', 'wma', 'vqf', 'ogg', 'arm', 'ape', 'flac', 'aac'},
    'doc': {'txt', 'log', 'doc', 'docm', 'docx', 'dot', 'odt', 'wps'},
    'pdf': {'pdf', 'pdp'},
    'excel': {'xls', 'xlsb', 'xlsm', 'xlsx', 'xlt', 'xltm', 'xltx', 'xps', 'csv', 'dbf', 'dif', 'ods', 'prn', 'slk', 'xla', 'xlam'},
    'ppt': {'ppt', 'pptm', 'pptx', 'odp', 'pot', 'potm', 'potx', 'ppa', 'ppam', 'pps', 'ppsm', 'ppsx'},
    'html': {'xhtml', 'html', 'mht', 'mhtml', 'htm'},
    'archive': {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'cab', 'iso', 'jar', 'lz', 'lzma', 'z', 'ace', 'arc', 'arj', 'uue', 'xz', 'zstd'},
    'code': {'js', 'ts', 'java', 'py', 'css', 'json', 'xml', 'c', 'cpp', 'h', 'php', 'rb', 'go', 'rs', 'sh', 'sql'},
  };

  /// 获取文件类型（按扩展名）
  static String getFileType(String? name) {
    if (name == null || !name.contains('.')) return 'file';
    final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    for (final e in _extMap.entries) {
      if (e.value.contains(ext)) return e.key;
    }
    return 'file';
  }

  /// 根据文件类型获取颜色
  static Color3 getFileColor(String type) {
    const colorMap = {
      'folder': 0xFFFFB300,
      'image': 0xFFEA5455,
      'video': 0xFF424242,
      'audio': 0xFFEA5455,
      'doc': 0xFF495C83,
      'pdf': 0xFFEA5455,
      'excel': 0xFF159895,
      'ppt': 0xFFEA5455,
      'html': 0xFF2196F3,
      'archive': 0xFF245953,
      'code': 0xFF7C4DFF,
      'file': 0xFF999999,
    };
    return Color3(colorMap[type] ?? 0xFF999999);
  }

  /// 根据文件类型获取短标签
  static String getFileLabel(String type) {
    const labelMap = {
      'image': 'IMG',
      'video': 'MP4',
      'audio': 'MP3',
      'doc': 'DOC',
      'pdf': 'PDF',
      'excel': 'XLS',
      'ppt': 'PPT',
      'html': 'WEB',
      'archive': 'ZIP',
      'code': '{}',
      'file': 'FILE',
    };
    return labelMap[type] ?? 'FILE';
  }
}

/// 轻量颜色值（避免本文件依赖 flutter material）
class Color3 {
  Color3(this.value);
  final int value;
}

/// 传输任务状态判定（移植自 Web 端 TaskUtils.js）
class TaskUtils {
  TaskUtils._();

  static bool isDone(String? status) => status != null && status.contains('done');
  static bool isWaiting(String? status) => status == 'waiting';
  static bool isPause(String? status) => status == 'pause';
  static bool isRunning(String? status) => status == 'running';
  static bool isSuccess(String? status) => status == 'done_fully_success';
  static bool isFail(String? status) => status == 'done_none_success';
  static bool isLessSuccess(String? status) => status == 'done_less_success';
  static bool isMostSuccess(String? status) => status == 'done_most_success';
  static bool isCanceled(String? status) => status == 'done_canceled';
}

/// 同步任务状态判定（移植自 Web 端 SyncTaskUtils.js）
///
/// 停止态 = stop(手动停止) / complate(同步完成)；运行中 = 其余非空状态(init/relax/compare/execute)
class SyncTaskUtils {
  SyncTaskUtils._();

  static bool isStopped(String? status) {
    if (status == null || status.isEmpty) return true;
    return status == 'stop' || status == 'complate';
  }

  static bool isRunning(String? status) {
    if (status == null || status.isEmpty) return false;
    return !isStopped(status);
  }
}

/// driveType → 中文名映射（driveUsername 为空时兜底）
const Map<String, String> driveTypeNames = {
  'baidu': '百度网盘',
  'alicloud': '阿里云盘',
  'tencent': '腾讯微云',
  'onedrive': '微软云盘',
  'google': 'Google Drive',
  'dropbox': 'Dropbox',
  'quark': '夸克网盘',
  'drive115': '115网盘',
  'thunder': '迅雷云盘',
  'drive123': '123云盘',
  'webdav': 'WebDAV',
  'ftp': 'FTP',
  'sftp': 'SFTP',
  'guangya': '光鸭云盘',
  'wps': 'WPS云盘',
  'jianguoyun': '坚果云',
  'cow': '奶牛快传',
  'ai360': '360AI云盘',
  'drive139': '移动云盘',
  'drive189': '天翼云盘',
  'uc': 'UC网盘',
};

/// 云盘图标资源路径（缺图回退 folder_icon）
String driveIconAsset(String? driveType) {
  return 'assets/images/${(driveType ?? '').isNotEmpty ? driveType : 'folder_icon'}.png';
}
