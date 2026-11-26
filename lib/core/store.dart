/// 本地存储层（对应 MP utils/store.js）
///
/// 封装 SharedPreferences，键名与 MP 完全一致，
/// 便于后续两端数据口径对齐与问题排查。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Store {
  Store._();

  static const String tokenKey = 'Authorization';
  static const String userInfoKey = 'userInfo';
  static const String drivesKey = 'cache_drives';
  static const String driveAccountPrefix = 'cache_drive_account_';
  static const String driveFilePrefix = 'cache_drive_file_';
  static const String transferListKey = 'cache_transfer_list';
  static const String syncListKey = 'cache_sync_list';
  static const String tokenExpiredKey = 'tokenExpired';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    assert(_prefs != null, 'Store.init() 必须在 runApp 前调用');
    return _prefs!;
  }

  // ===================== Token =====================

  static void saveToken(String token) => _p.setString(tokenKey, token);

  static String getToken() => _p.getString(tokenKey) ?? '';

  static void clearToken() => _p.remove(tokenKey);

  static bool get tokenExpired => _p.getBool(tokenExpiredKey) ?? false;

  static set tokenExpired(bool v) => _p.setBool(tokenExpiredKey, v);

  // ===================== 用户信息 =====================

  static void saveUserInfo(Map<String, dynamic>? info) {
    if (info != null) {
      _p.setString(userInfoKey, jsonEncode(info));
    } else {
      _p.remove(userInfoKey);
    }
  }

  static Map<String, dynamic>? getUserInfo() {
    final raw = _p.getString(userInfoKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static void clearUserInfo() => _p.remove(userInfoKey);

  // ===================== 云盘列表缓存 =====================

  static List<dynamic>? getDrives() => _getJson(drivesKey) as List<dynamic>?;

  static void setDrives(List<dynamic> data) => _setJson(drivesKey, data);

  static void clearDrives() => _p.remove(drivesKey);

  /// 从缓存的云盘列表中移除一条（删除云盘后同步）
  static void removeDrive(dynamic id) {
    final drives = getDrives();
    if (drives != null) {
      setDrives(drives.where((d) => d['id'] != id).toList());
    }
  }

  // ===================== 传输任务列表缓存 =====================

  static List<dynamic>? getTransferList() =>
      _getJson(transferListKey) as List<dynamic>?;

  static void setTransferList(List<dynamic> data) =>
      _setJson(transferListKey, data);

  static void clearTransferList() => _p.remove(transferListKey);

  static void removeTransfer(dynamic id) {
    final list = getTransferList();
    if (list != null) {
      setTransferList(list.where((t) => t['id'] != id).toList());
    }
  }

  static void updateTransfer(Map<String, dynamic> item) =>
      _updateListItem(transferListKey, item);

  // ===================== 同步任务列表缓存 =====================

  static List<dynamic>? getSyncList() => _getJson(syncListKey) as List<dynamic>?;

  static void setSyncList(List<dynamic> data) => _setJson(syncListKey, data);

  static void clearSyncList() => _p.remove(syncListKey);

  static void removeSync(dynamic id) {
    final list = getSyncList();
    if (list != null) {
      setSyncList(list.where((t) => t['id'] != id).toList());
    }
  }

  static void updateSync(Map<String, dynamic> item) =>
      _updateListItem(syncListKey, item);

  static void _updateListItem(String key, Map<String, dynamic> item) {
    final list = _getJson(key) as List<dynamic>?;
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      if (list[i]['id'] == item['id']) {
        list[i] = item;
        _setJson(key, list);
        return;
      }
    }
  }

  // ===================== 单云盘账户缓存 =====================

  static Map<String, dynamic>? getDriveAccount(dynamic authId) =>
      _getJson('$driveAccountPrefix$authId') as Map<String, dynamic>?;

  static void setDriveAccount(dynamic authId, Map<String, dynamic> data) =>
      _setJson('$driveAccountPrefix$authId', data);

  static void clearDriveAccounts() => _clearByPrefix(driveAccountPrefix);

  // ===================== 文件列表缓存 =====================

  /// key: cache_drive_file_{authId}_{folderId}
  static dynamic getFileItems(dynamic authId, String folderId) =>
      _getJson('$driveFilePrefix${authId}_$folderId');

  static void setFileItems(dynamic authId, String folderId, dynamic data) =>
      _setJson('$driveFilePrefix${authId}_$folderId', data);

  static void clearFileItems(dynamic authId, String folderId) =>
      _p.remove('$driveFilePrefix${authId}_$folderId');

  static void clearAllFileItems() => _clearByPrefix(driveFilePrefix);

  // ===================== 通用 =====================

  static dynamic _getJson(String key) {
    final raw = _p.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  static void _setJson(String key, dynamic value) {
    _p.setString(key, value is String ? value : jsonEncode(value));
  }

  static void _clearByPrefix(String prefix) {
    final keys = _p.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _p.remove(k);
    }
  }

  /// 清空登录态相关数据（退出登录/注销账户用）
  static Future<void> clear() async {
    await _p.clear();
  }
}
