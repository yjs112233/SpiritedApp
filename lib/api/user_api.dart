/// 用户相关 API（对应 MP api/user.js）
library;

import '../core/crypto_util.dart';
import '../core/http_client.dart';
import '../core/store.dart';
import '../utils/formatters.dart';

class UserApi {
  UserApi._();
  static final ApiClient _req = ApiClient.instance;

  /// 获取图形验证码图片（data 为 {key, img: data URI}，2 分钟有效）
  /// 用途：① 密码登录连续失败达阈值后 /user/signin 要求携带；② 发码前人机验证
  static Future<ApiResult> getKaptcha(String key) {
    return _req.get('/user/kaptcha?key=$key');
  }

  /// 发送登录短信验证码（App 端 2026-11-24 起改图形验证码人机验证；
  /// 后端同日起支持 kaptcha 通道，auth 滑块通道保留给 Web/MP）
  static Future<ApiResult> sendSmsLoginCode(
      String phoneNumber, String kaptchaKey, String kaptchaValue) {
    return _req.postForm('/user/sms/login', {
      'phoneNumber': phoneNumber,
      'kaptchaKey': kaptchaKey,
      'kaptchaValue': kaptchaValue,
    });
  }

  /// 手机号验证码登录（新手机号自动创建账户），成功后保存 token
  static Future<ApiResult> smsLogin(String phoneNumber, String code) async {
    final result = await _req.postForm('/user/smslogin', {
      'phoneNumber': phoneNumber,
      'code': code,
      'rememberMe': true,
      'timezone': Formatters.getTimezone(),
      'device': 'mobile',
    });
    if (result.data is String && (result.data as String).isNotEmpty) {
      Store.saveToken(result.data as String);
    }
    return result;
  }

  /// 账号密码登录（账号支持手机号或邮箱，与官网同一账户体系）
  /// 连续失败达阈值后端要求图形验证码（reason=maxAuthenticatedFail）
  static Future<ApiResult> signIn(String account, String password,
      {String kaptchaKey = '', String kaptchaValue = ''}) async {
    final data = <String, dynamic>{
      'account': account,
      'password': password,
      'rememberMe': true,
      'timezone': Formatters.getTimezone(),
      'device': 'mobile',
    };
    if (kaptchaKey.isNotEmpty) {
      data['kaptchaKey'] = kaptchaKey;
      data['kaptchaValue'] = kaptchaValue;
    }
    final result = await _req.postForm('/user/signin', data);
    if (result.data is String && (result.data as String).isNotEmpty) {
      Store.saveToken(result.data as String);
    }
    return result;
  }

  /// 获取用户信息（成功后写入缓存）
  static Future<Map<String, dynamic>?> getUserInfo() async {
    final result = await _req.get('/user/info');
    if (result.data is Map<String, dynamic>) {
      Store.saveUserInfo(result.data as Map<String, dynamic>);
      return result.data;
    }
    return null;
  }

  /// 退出登录
  static Future<void> signOut() async {
    try {
      await _req.postForm('/user/logout', {});
    } finally {
      await Store.clear();
    }
  }

  /// 注销账号
  static Future<void> delUser(String reason) async {
    try {
      await _req.postForm('/user/del/user', {'reason': reason});
    } finally {
      await Store.clear();
    }
  }

  /// 上传头像
  static Future<ApiResult> resetHeadimg(String filePath) {
    return _req.uploadFile('/user/info/reset/headimg', filePath, 'file');
  }

  /// 修改昵称
  static Future<ApiResult> resetNickname(String nickname) {
    return _req.postForm('/user/info/reset/nickname', {'nickname': nickname});
  }

  /// 发送绑定手机验证码
  static Future<ApiResult> sendSmsCode(String phoneNumber) {
    return _req.postForm('/user/sms/bind', {'phoneNumber': phoneNumber});
  }

  /// 绑定手机号（返回 data=合并场景老账户新签发的 token）
  static Future<ApiResult> resetPhone(String phoneNumber, String code) {
    return _req.postForm('/user/info/reset/phone', {
      'phoneNumber': phoneNumber,
      'code': code,
    });
  }

  /// 留言反馈
  static Future<ApiResult> saveMessage(String message) {
    return _req.postForm('/user/message/write', {'message': message});
  }

  /// 提交工单（与 Web 端 HelpDialog 同一接口）
  static Future<ApiResult> submitTicket(String description, String contact) {
    return _req.postForm('/user/message/ticket', {
      'description': description,
      'contact': contact,
    });
  }

  /// ==================== 微信登录（留桩，待微信开放平台 AppID） ====================
  ///
  /// 小程序端走 /user/wechat/miniappLogin（code 由 wx.login 获取）。
  /// App 端微信登录需：微信开放平台账号 + 移动应用审核通过 + fluwx SDK 唤起授权，
  /// 拿到 code 后调用后端专用接口换取 token。待用户提供开放平台信息后接入。

  /// 生成 36 位缓存标识（图形验证码 key）
  static String newCaptchaKey() => CryptoUtil.generateUuid();
}
