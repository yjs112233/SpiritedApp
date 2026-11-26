/// 加密/签名工具层（对应 MP utils/crypto.js）
///
/// 与 Web 端 HttpRequest.js、MP utils/crypto.js 逻辑完全一致：
/// - AES-128-CBC 解密网关响应 data（v2 随机 IV / 旧格式固定 IV）
/// - MD5 签名（X-IDE 头）
/// - 防重放盐值（X-APPL 头）
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as c;
import 'package:encrypt/encrypt.dart' as e;

import '../config.dart';

class CryptoUtil {
  CryptoUtil._();

  /// MD5 哈希
  static String md5Hash(String str) => c.md5.convert(utf8.encode(str)).toString();

  /// AES-CBC 解密
  /// [ciphertext] Base64 编码的密文（v2 格式前缀 "v2:" + Base64(IV) + "." + Base64(密文)）
  static String decryptAes(String ciphertext) {
    final key = e.Key.fromUtf8(AppConfig.aesKey);
    e.IV useIv;
    String srcs;

    if (ciphertext.startsWith('v2:')) {
      final parts = ciphertext.substring(3).split('.');
      useIv = e.IV.fromBase64(parts[0]);
      srcs = parts[1];
    } else {
      useIv = e.IV.fromUtf8(AppConfig.aesIV);
      srcs = ciphertext;
    }

    final encrypter = e.Encrypter(e.AES(key, mode: e.AESMode.cbc, padding: 'PKCS7'));
    return encrypter.decrypt64(srcs, iv: useIv);
  }

  /// 生成防重放盐值（X-APPL）
  ///
  /// 结构：pad(z,3) + uuid32 + pad(t,3)
  /// 其中 time 为毫秒时间戳，suf = time % 1e6，z = suf / 1000，t = suf % 1000
  static String generateSalt() {
    final time = DateTime.now().millisecondsSinceEpoch;
    final suf = time % 1000000;
    final z = suf ~/ 1000;
    final t = suf % 1000;
    final id = generateUuid().replaceAll('-', '');
    return _padNum(z, 3) + id + _padNum(t, 3);
  }

  static String _padNum(int num, int length) {
    return num.toString().padLeft(length, '0');
  }

  /// 生成 UUID v4
  static String generateUuid() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// JS 风格的值字符串化（X-IDE 签名的 values 拼接规则）
  ///
  /// MP/Web 端：`let values = ''; for (const key in data) { values += data[key] }`
  /// JS 隐式转换规则：
  /// - String → 原样；num → 数字串；bool → "true"/"false"；null → "null"
  /// - Array → 元素递归转换后逗号连接（null/undefined 元素为空串）
  /// - Object → "[object Object]"
  static String jsToString(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return v;
    if (v is bool) return v ? 'true' : 'false';
    if (v is int) return v.toString();
    if (v is double) {
      // JS Number：整数值 double 不带小数点（1.0 → "1"）
      if (v == v.truncateToDouble() && v.abs() < 1e21) {
        return v.truncateToDouble().toString();
      }
      return v.toString();
    }
    if (v is List) {
      return v.map((el) => el == null ? '' : jsToString(el)).join(',');
    }
    // Map 及其他对象
    return '[object Object]';
  }

  /// X-IDE 的 POST values 拼接："" 开头 + 各参数值顺序拼接
  static String buildIdeValues(Map<String, dynamic> data) {
    final buf = StringBuffer('');
    for (final v in data.values) {
      buf.write(jsToString(v));
    }
    return buf.toString();
  }

  /// 解密响应 data 字段为动态对象（JSON 串 → Map/List，否则保持字符串）
  static dynamic decryptData(String raw) {
    final dec = decryptAes(raw);
    if ((dec.contains('{') && dec.contains('}')) ||
        (dec.contains('[') && dec.contains(']'))) {
      try {
        return jsonDecode(dec);
      } catch (_) {
        return dec;
      }
    }
    return dec;
  }
}
