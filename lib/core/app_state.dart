/// 全局登录态（ChangeNotifier，provider 提供）
library;

import 'package:flutter/foundation.dart';

import 'store.dart';
import 'http_client.dart';

class AppState extends ChangeNotifier {
  Map<String, dynamic>? _userInfo;

  Map<String, dynamic>? get userInfo => _userInfo;

  bool get isLoggedIn => Store.getToken().isNotEmpty;

  /// 是否 VIP（isVip/vipLevel 嵌套在 mainGift 中，与 Web MineHome 一致）
  bool get isVip {
    final gift = _userInfo?['mainGift'];
    return gift is Map && (gift['isVip'] == true);
  }

  /// 刷新用户信息（缓存优先渲染 + 接口覆盖）
  Future<void> refresh() async {
    final cached = Store.getUserInfo();
    if (cached != null) {
      _userInfo = cached;
      notifyListeners();
    }
    if (!isLoggedIn) {
      _userInfo = null;
      notifyListeners();
      return;
    }
    try {
      final info = await _fetch();
      if (info != null) {
        _userInfo = info;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final result = await ApiClient.instance.get('/user/info');
    if (result.data is Map<String, dynamic>) {
      Store.saveUserInfo(result.data as Map<String, dynamic>);
      return result.data;
    }
    return null;
  }

  /// 登录成功后调用（拉取用户信息并广播）
  Future<void> onLoginSuccess() async {
    await refresh();
  }

  /// 退出登录
  Future<void> logout() async {
    try {
      await ApiClient.instance.postForm('/user/logout', {});
    } finally {
      await Store.clear();
      _userInfo = null;
      notifyListeners();
    }
  }
}
