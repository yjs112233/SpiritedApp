/// 全局配置（对应 MP config.js）
///
/// baseURL 与小程序端一致，指向 qianclouds 网关。
/// AES 配置与 Web/MP 端保持一致（响应 data v2 解密）。
class AppConfig {
  AppConfig._();

  /// 生产环境网关
  static const String baseUrl = 'https://ext.qianclouds.com/api';

  /// AES-128-CBC 密钥（与 Web HttpRequest.js / MP utils/crypto.js 一致）
  static const String aesKey = 's56!@3SD3%2~wdsa';

  /// 旧格式固定 IV（v2 格式随机 IV 随密文传输）
  static const String aesIV = '33AB00C0B0Q00F12';

  static const String appVersion = '1.0.0';
}
