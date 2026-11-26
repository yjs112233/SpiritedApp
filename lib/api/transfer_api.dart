/// 传输/同步任务 API（对应 MP api/transfer.js）
library;

import '../core/http_client.dart';
import '../utils/formatters.dart';

class TransferApi {
  TransferApi._();
  static final ApiClient _req = ApiClient.instance;

  // ==================== 传输任务 ====================

  /// 创建传输任务
  static Future<ApiResult> createTransfer(
    String taskName,
    dynamic sourceDriveId,
    List<dynamic> sourceItems,
    dynamic destinationDriveId,
    Map<String, dynamic> destinationItem,
    Map<String, dynamic> actionModel,
    Map<String, dynamic>? timerModel,
  ) {
    final timer = timerModel ?? {'type': 'Now', 'timezone': Formatters.getTimezone(), 'plan': []};
    timer['timezone'] = Formatters.getTimezone();
    return _req.postJson('/task/transfer/add', {
      'name': taskName,
      'sourceDriveId': sourceDriveId,
      'sourceItems': sourceItems,
      'destinationDriveId': destinationDriveId,
      'destinationItem': destinationItem,
      'actionModel': actionModel,
      'timerModel': timer,
    });
  }

  /// 生成传输任务名称
  static Future<dynamic> createTransferName() async {
    final result = await _req.get('/task/transfer/name');
    return result.data;
  }

  /// 获取传输任务列表
  /// 查询接口带 uuid 跳过网关幂等：空 body 的 POST X-IDE 恒为 md5(""),
  /// 1 秒内重复请求会被网关拒 code 100 静默失败
  static Future<List<dynamic>> getTransferList({bool silent = false}) async {
    final result = await _req.postJson('/task/transfer/list', {
      'uuid': Formatters.getUuid(),
    }, showLoading: !silent ? true : false, silent: false);
    if (result.data is List) return result.data;
    // 轮询/静默失败（code 100 等）返回空列表，由调用方按缓存兜底
    return [];
  }

  /// 暂停传输
  static Future<ApiResult> pauseTransfer(dynamic jobId, dynamic sessionId) {
    return _req.postForm('/task/transfer/pause', {'jobId': jobId, 'sessionId': sessionId});
  }

  /// 恢复传输
  static Future<ApiResult> resumeTransfer(dynamic jobId, dynamic sessionId) {
    return _req.postForm('/task/transfer/recovery', {'jobId': jobId, 'sessionId': sessionId});
  }

  /// 执行传输任务（续传）
  static Future<ApiResult> executeTransfer(dynamic jobId, dynamic sessionId, bool continueStart) {
    return _req.postForm('/task/transfer/execute', {
      'jobId': jobId,
      'continueStart': continueStart,
      'sessionId': sessionId,
      'timezone': Formatters.getTimezone(),
    });
  }

  /// 删除传输任务
  static Future<ApiResult> deleteTransfer(dynamic id) {
    return _req.postJson('/task/transfer/del', {'id': id});
  }

  /// 停止传输
  static Future<ApiResult> stopTransfer(dynamic sessionId) {
    return _req.postForm('/task/transfer/stop', {'sessionId': sessionId});
  }

  /// 获取传输任务详情（flushTask 用）
  static Future<Map<String, dynamic>?> getTransferTask(dynamic id) async {
    final result = await _req.get('/task/transfer/getTask/$id');
    return result.data is Map<String, dynamic> ? result.data : null;
  }

  /// 获取传输错误明细分页（20 条/页）
  static Future<dynamic> getTransferErrors(dynamic sessionId, int page) async {
    final result = await _req.get('/task/transfer/error/$sessionId?page=$page');
    return result.data;
  }

  /// 获取传输进度（轮询用）
  static Future<Map<String, dynamic>?> getTransferProgress(dynamic sessionId) async {
    final result = await _req.get('/task/transfer/progress?sessionId=$sessionId');
    return result.data is Map<String, dynamic> ? result.data : null;
  }

  /// 重试失败项
  static Future<ApiResult> retryTransfer(dynamic sessionId, List<dynamic> ids) {
    return _req.postForm('/task/transfer/retry', {'sessionId': sessionId, 'ids': ids});
  }

  // ==================== 同步任务 ====================

  /// 创建同步任务（type: 1 单向 / 2 双向，与 Web 端一致仅开放单向）
  static Future<ApiResult> createSync(
    String taskName,
    dynamic sourceDriveId,
    Map<String, dynamic> sourceItem,
    dynamic destinationDriveId,
    Map<String, dynamic> destinationItem,
    Map<String, dynamic> actionModel,
    int type,
    Map<String, dynamic>? timerModel,
  ) {
    final timer = timerModel ?? {'type': 'Now', 'timezone': Formatters.getTimezone(), 'plans': []};
    timer['timezone'] = Formatters.getTimezone();
    return _req.postJson('/task/sync/add', {
      'name': taskName,
      'sourceDriveId': sourceDriveId,
      'sourceItem': sourceItem,
      'destinationDriveId': destinationDriveId,
      'destinationItem': destinationItem,
      'actionModel': actionModel,
      'type': type,
      'timerModel': timer,
    });
  }

  /// 生成同步任务名称
  static Future<dynamic> createSyncName() async {
    final result = await _req.get('/task/sync/name');
    return result.data;
  }

  /// 同步任务列表（带 uuid 跳过网关幂等）
  static Future<List<dynamic>> getSyncList({bool silent = false}) async {
    final result = await _req.postJson('/task/sync/list', {
      'uuid': Formatters.getUuid(),
    }, showLoading: !silent ? true : false, silent: false);
    if (result.data is List) return result.data;
    return [];
  }

  /// 同步任务详情
  static Future<Map<String, dynamic>?> getSyncTask(dynamic id) async {
    final result = await _req.get('/task/sync/get/$id');
    return result.data is Map<String, dynamic> ? result.data : null;
  }

  /// 同步日志（按同步周期分页，10 条/页）
  static Future<dynamic> getSyncLog(dynamic id, int page) async {
    final result = await _req.get('/task/sync/log/$id?page=$page');
    return result.data;
  }

  /// 获取同步定时计划
  static Future<Map<String, dynamic>?> getSyncTimer(dynamic id) async {
    final result = await _req.get('/task/sync/timer/$id');
    return result.data is Map<String, dynamic> ? result.data : null;
  }

  /// 更新同步定时计划
  static Future<ApiResult> updateSyncTimer(dynamic id, Map<String, dynamic> timerModel) {
    return _req.postJson('/task/sync/timer/update', {'id': id, 'timerModel': timerModel});
  }

  /// 删除同步任务
  static Future<ApiResult> deleteSync(dynamic id) {
    return _req.postJson('/task/sync/del', {'id': id});
  }

  /// 停止同步
  static Future<ApiResult> stopSync(dynamic id) {
    return _req.postForm('/task/sync/stop', {'id': id});
  }

  /// 恢复同步
  static Future<ApiResult> resumeSync(dynamic id) {
    return _req.postForm('/task/sync/resume', {'id': id});
  }
}
