/// 云盘相关 API（对应 MP api/drive.js）
library;

import 'dart:typed_data';

import '../core/crypto_util.dart';
import '../core/http_client.dart';
import '../core/store.dart';

class DriveApi {
  DriveApi._();
  static final ApiClient _req = ApiClient.instance;

  // ==================== 云盘授权 ====================

  /// OAuth 跳转授权（百度/阿里/迅雷/OneDrive 等）
  /// 返回整包 result：229（达到添加上限）等业务拒绝码的提示语在 data，
  /// 由页面判断 code 后再决定是否进入授权流程
  static Future<ApiResult> authNewDrive(String type) {
    final id = CryptoUtil.generateUuid();
    // channel=mp：随 state 加密进授权链接，授权回调后落静态结果页提示回到应用
    return _req.postForm('/drives/auth/new', {'type': type, 'id': id, 'channel': 'mp'});
  }

  /// AppKey/AppSecret 授权（123云盘/360 等）
  static Future<ApiResult> authSecretDrive(String type, String appKey, String appSecret) {
    final id = CryptoUtil.generateUuid();
    return _req.postForm('/drives/auth/new_secret', {
      'type': type,
      'id': id,
      'appKey': appKey,
      'appSecret': appSecret,
    });
  }

  /// WebDAV 授权
  static Future<ApiResult> authWebdav(String type, String username, String password, String weburl) {
    return _req.postForm('/drives/auth/new_webdav', {
      'type': type,
      'username': username,
      'password': password,
      'weburl': weburl,
    });
  }

  /// Cookie 授权（夸克 等）
  static Future<ApiResult> authCookieDrive(String type, String cookie) {
    final id = CryptoUtil.generateUuid();
    return _req.postForm('/drives/auth/new_cookie', {'type': type, 'id': id, 'cookie': cookie});
  }

  /// PKCE 扫码授权（115/夸克/光鸭 等）
  /// code_verifier 由后端生成并封入加密 state，前端无需传递
  static Future<ApiResult> getPkceQrcode(String type) {
    return _req.postForm('/drives/auth/new_pkce', {'type': type});
  }

  /// 轮询 PKCE 扫码状态
  static Future<ApiResult> getPkceQrcodeStatus(String type, String state) {
    return _req.postForm('/drives/auth/get_qrcode_status', {
      'type': type,
      'state': state,
    }, showLoading: false, silent: true);
  }

  /// PKCE 回调（code_verifier 后端自持，仅回传 state）
  static Future<ApiResult> pkceCallback(String type, String state) {
    return _req.postForm('/drives/auth/pkce_callback', {'type': type, 'state': state});
  }

  /// FTP/SFTP 授权
  static Future<ApiResult> authFtpDrive(Map<String, dynamic> data) {
    return _req.postForm('/drives/auth/new_ftp', data);
  }

  // ==================== 云盘管理 ====================

  /// 获取云盘列表
  static Future<List<dynamic>> getDriveList() async {
    final result = await _req.get('/drives/manager/clouds');
    return (result.data as List?)?.toList() ?? [];
  }

  /// 删除云盘
  static Future<ApiResult> deleteDrive(dynamic cloudId) {
    return _req.postForm('/drives/manager/del/$cloudId', {});
  }

  /// 重命名云盘
  static Future<ApiResult> renameDrive(dynamic cloudId, String newName) {
    return _req.postForm('/drives/manager/update/name', {
      'authId': cloudId,
      'newName': newName,
    });
  }

  /// 获取云盘账户信息（容量/会员）
  static Future<Map<String, dynamic>?> getDriveAccount(dynamic authId) async {
    final result = await _req.get('/drives/$authId/account');
    return result.data is Map<String, dynamic> ? result.data : null;
  }

  // ==================== 文件操作 ====================

  /// 获取文件列表（isFirst 首次加载分页）
  static Future<ApiResult> getDriveItems(dynamic authId, String folderId,
      {bool isFirst = true, int num = 1, String folderPath = ''}) {
    if (isFirst) {
      return _req.postForm('/drives/$authId/items', {
        'isFirst': true,
        'num': num,
        'folderId': folderId,
        'uuid': CryptoUtil.generateUuid(),
      });
    }
    return _req.postForm('/drives/$authId/items/$folderId', {
      'isFirst': false,
      'num': num,
      'folderPath': folderPath,
    });
  }

  /// 获取文件夹列表（仅文件夹，创建任务时目录选择用）
  static Future<ApiResult> getDriveFolders(dynamic authId, String folderId) {
    return _req.postForm('/drives/items/folders', {
      'authId': authId,
      'folderId': folderId,
    });
  }

  // ==================== 缓存层 ====================

  /// 获取文件列表（带缓存：优先读缓存，无缓存则请求并写入缓存）
  static Future<ApiResult> getDriveItemsCached(dynamic authId, String folderId) async {
    final cached = Store.getFileItems(authId, folderId);
    if (cached is Map && cached.containsKey('data')) {
      return ApiResult(code: 200, data: cached['data']);
    }
    final result = await getDriveItems(authId, folderId);
    _safeCacheItems(authId, folderId, result.data);
    return result;
  }

  /// 强制刷新文件列表（清缓存后重新请求）
  static Future<ApiResult> getDriveItemsRefresh(dynamic authId, String folderId) async {
    Store.clearFileItems(authId, folderId);
    final result = await getDriveItems(authId, folderId);
    _safeCacheItems(authId, folderId, result.data);
    return result;
  }

  /// 缓存写入容错：失败仅放弃缓存，不影响本次返回
  static void _safeCacheItems(dynamic authId, String folderId, dynamic data) {
    try {
      if (data != null) {
        Store.setFileItems(authId, folderId, {'data': data});
      }
    } catch (_) {}
  }

  /// 新建文件夹后更新缓存
  static void updateCacheOnMkdir(dynamic authId, String folderId, Map<String, dynamic> newFolder) {
    _mutateCache(authId, folderId, (items) => items.insert(0, newFolder));
  }

  /// 删除文件后更新缓存
  static void updateCacheOnDelete(dynamic authId, String folderId, dynamic itemId) {
    _mutateCache(authId, folderId, (items) => items.removeWhere((it) => it['id'] == itemId));
  }

  static void _mutateCache(dynamic authId, String folderId, void Function(List) fn) {
    final cached = Store.getFileItems(authId, folderId);
    if (cached is Map && cached['data'] is Map && cached['data']['items'] is List) {
      final items = cached['data']['items'] as List;
      fn(items);
      Store.setFileItems(authId, folderId, cached);
    }
  }

  /// 创建文件夹
  static Future<ApiResult> mkdir(dynamic authId, String folderId, String name) {
    return _req.postForm('/drives/mkdir', {'authId': authId, 'folderId': folderId, 'name': name});
  }

  /// 重命名
  static Future<ApiResult> rename(dynamic authId, dynamic itemId, String name) {
    return _req.postForm('/drives/rename', {'authId': authId, 'itemId': itemId, 'name': name});
  }

  /// 删除
  static Future<ApiResult> delete(dynamic authId, dynamic itemId) {
    return _req.postForm('/drives/delete', {'authId': authId, 'itemId': itemId});
  }

  /// 下载文件（二进制流）
  static Future<(Uint8List, String)> downloadItem(dynamic authId, dynamic itemId, dynamic parentId) {
    return _req.postFormBuffer('/drives/download', {
      'authId': authId,
      'itemId': itemId,
      'parentId': parentId,
    });
  }
}
