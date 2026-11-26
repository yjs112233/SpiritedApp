/// 传输任务列表（对应 MP pages/transfer/list/list）
///
/// 缓存优先加载；running 任务 while 循环逐任务轮询进度（5s，生成计数器
/// 控制生命周期）；waiting 任务统一轮询等状态迁移；done 任务拉取成功/失败
/// 计数；暂停/恢复/停止/删除/续传全套操作。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/drive_api.dart';
import '../../api/transfer_api.dart';
import '../../core/events.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class TransferListPage extends StatefulWidget {
  const TransferListPage({super.key});

  @override
  State<TransferListPage> createState() => _TransferListPageState();
}

class _TransferListPageState extends State<TransferListPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _isEmpty = false;

  int _pollGeneration = 0;
  bool _isWaitPolling = false;
  bool _pageHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UiEvents.taskListVersion.addListener(_onTasksChanged);
    _loadList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UiEvents.taskListVersion.removeListener(_onTasksChanged);
    _pageHidden = true;
    _pollGeneration++;
    super.dispose();
  }

  void _onTasksChanged() {
    _loadList(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 对应 MP onShow/onHide：切后台停轮询，切回重启
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pageHidden = true;
      _pollGeneration++;
      _isWaitPolling = false;
    } else if (state == AppLifecycleState.resumed) {
      _pageHidden = false;
      _loadList(force: true);
    }
  }

  Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

  // ===================== 数据加载 =====================

  Future<void> _loadList({bool silent = false, bool force = false}) async {
    if (Store.getToken().isEmpty) {
      setState(() {
        _list = [];
        _isEmpty = true;
        _loading = false;
      });
      return;
    }

    if (!silent) setState(() => _loading = true);

    if (!force) {
      final cached = Store.getTransferList();
      if (cached != null && cached.isNotEmpty) {
        final formatted = _formatList(cached);
        setState(() {
          _list = formatted;
          _isEmpty = false;
          _loading = false;
        });
        _pollGeneration++;
        _pageHidden = false;
        _startProgressPolling(formatted);
        _startWaitPolling(formatted);
        _loadDoneDetails(formatted);
        return;
      }
    }

    try {
      final fresh = await TransferApi.getTransferList(silent: silent);
      Store.setTransferList(fresh);
      final formatted = _formatList(fresh);
      setState(() {
        _list = formatted;
        _isEmpty = fresh.isEmpty;
        _loading = false;
      });
      _pollGeneration++;
      _pageHidden = false;
      _startProgressPolling(formatted);
      _startWaitPolling(formatted);
      _loadDoneDetails(formatted);
    } catch (_) {
      if (!silent) setState(() => _loading = false);
    }
  }

  // ===================== 格式化 =====================

  /// 源/目标路径（对应 Web TaskShowUtils.buildItemPath）
  static String buildTransferPath(dynamic items) {
    if (items == null) return '';
    final item = items is List ? (items.isNotEmpty ? items[0] : null) : items;
    if (item is! Map) return '';
    var path = '';
    final nodeArray = item['nodeArray'];
    if (nodeArray is List) {
      for (var n = 0; n < nodeArray.length; n++) {
        final node = nodeArray[n];
        path += (n > 0 ? '/' : '') + ((node is Map ? node['name'] : '') ?? '');
      }
    }
    path += (path.isNotEmpty ? '/' : '') + (item['name']?.toString() ?? '');
    if (items is List && items.length > 1) {
      path += ' 等${items.length}项';
    }
    return path;
  }

  /// 源/目标云盘 driveType（按首项取）
  static String buildTransferDriveType(dynamic items) {
    final item = items is List ? (items.isNotEmpty ? items[0] : null) : items;
    if (item is Map && item['driveType'] != null) {
      return item['driveType'].toString();
    }
    return '';
  }

  List<Map<String, dynamic>> _formatList(List<dynamic> list) {
    return list.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final status = item['status']?.toString();
      final session = item['session'];
      final s = _getStatusInfo(status);
      item['sessionId'] = session is Map ? session['id'] : '';
      item['sourceDriveType'] = buildTransferDriveType(item['sourceItems']);
      item['sourcePath'] = buildTransferPath(item['sourceItems']);
      item['destDriveType'] = buildTransferDriveType(item['destinationItem']);
      item['destPath'] = buildTransferPath(item['destinationItem']);
      item['statusLabel'] = s.label;
      item['statusColor'] = s.color;
      item['isRunning'] = TaskUtils.isRunning(status);
      item['isWaiting'] = TaskUtils.isWaiting(status);
      item['isPause'] = TaskUtils.isPause(status);
      item['isDone'] = TaskUtils.isDone(status);
      item['percent'] = item['percent'] ?? 0.0;
      item['speed'] = item['speed'] ?? '';
      item['timeRemaining'] = item['timeRemaining'] ?? '';
      item['totalAll'] = item['totalAll'] ?? 0;
      item['successCount'] = item['successCount'] ?? 0;
      item['failedCount'] = item['failedCount'] ?? 0;
      item['totalSize'] = item['totalSize'] ?? '';
      item['streamSize'] = item['streamSize'] ?? '';
      item['streamItems'] = item['streamItems'] ?? <dynamic>[];
      item['expanded'] = item['expanded'] ?? false;
      return item;
    }).toList();
  }

  static const List<int> _statusColors = [
    0xFF4C7DFF, // running
    0xFF999999, // waiting
    0xFFFF9500, // pause
    0xFF00C48F, // success
    0xFFFF4D4F, // fail
    0xFFFF9500, // less success
    0xFF9EB34D, // most success
    0xFF999999, // canceled
    0xFFCCCCCC, // unknown
  ];

  static ({String label, int color}) _getStatusInfo(String? status) {
    if (TaskUtils.isRunning(status)) return (label: '运行中', color: _statusColors[0]);
    if (TaskUtils.isWaiting(status)) return (label: '等待', color: _statusColors[1]);
    if (TaskUtils.isPause(status)) return (label: '暂停', color: _statusColors[2]);
    if (TaskUtils.isSuccess(status)) return (label: '成功', color: _statusColors[3]);
    if (TaskUtils.isFail(status)) return (label: '失败', color: _statusColors[4]);
    if (TaskUtils.isLessSuccess(status)) return (label: '部分成功', color: _statusColors[5]);
    if (TaskUtils.isMostSuccess(status)) return (label: '大部分成功', color: _statusColors[6]);
    if (TaskUtils.isCanceled(status)) return (label: '取消', color: _statusColors[7]);
    return (label: '未知', color: _statusColors[8]);
  }

  // ===================== done 任务详情 =====================

  void _loadDoneDetails(List<Map<String, dynamic>> list) {
    for (final task in list) {
      if (task['isDone'] != true) continue;
      TransferApi.getTransferTask(task['id']).then((detail) {
        if (!mounted || detail == null) return;
        final session = detail['session'];
        final done = session is Map ? session['sessionDone'] : null;
        var successCount = 0, failedCount = 0, totalAll = 0;
        if (done is Map) {
          successCount = ((done['successFolder'] ?? 0) as num).toInt() +
              ((done['successFile'] ?? 0) as num).toInt() +
              ((done['skipFile'] ?? 0) as num).toInt();
          totalAll = ((done['totalFolder'] ?? 0) as num).toInt() +
              ((done['totalFile'] ?? 0) as num).toInt();
          failedCount = ((done['failFile'] ?? 0) as num).toInt();
        }
        final idx = _list.indexWhere((t) => t['id'] == task['id']);
        if (idx == -1) return;
        setState(() {
          _list[idx]['successCount'] = successCount;
          _list[idx]['failedCount'] = failedCount;
          _list[idx]['totalAll'] = totalAll;
        });
      }).catchError((_) {});
    }
  }

  // ===================== 进度轮询（while 循环模式） =====================

  void _startProgressPolling(List<Map<String, dynamic>> list) {
    final gen = _pollGeneration;
    for (final task in list) {
      if (task['isRunning'] == true && (task['sessionId'] ?? '') != '') {
        _pollProgress(task, gen);
      }
    }
  }

  Future<void> _pollProgress(Map<String, dynamic> task, int gen) async {
    Map<String, dynamic>? progress;

    try {
      progress = await TransferApi.getTransferProgress(task['sessionId']);
      if (progress != null && progress['finishedJob'] != true) {
        _applyProgress(task['id'], progress);
      }
    } catch (_) {}

    while (mounted && !_pageHidden && gen == _pollGeneration) {
      await _sleep(5000);
      if (!mounted || _pageHidden || gen != _pollGeneration) break;

      final currentItem = _list.where((t) => t['id'] == task['id']).toList();
      if (currentItem.isEmpty || !TaskUtils.isRunning(currentItem[0]['status']?.toString())) {
        break;
      }

      try {
        progress = await TransferApi.getTransferProgress(currentItem[0]['sessionId']);
        if (progress == null) continue;
        if (progress['finishedJob'] == true) break;
        _applyProgress(task['id'], progress);
      } catch (_) {}
    }

    if (progress != null &&
        progress['finishedJob'] == true &&
        mounted &&
        !_pageHidden &&
        gen == _pollGeneration) {
      _flushTask(task['id']);
    }
  }

  /// 单任务刷新（不刷新整个列表）
  Future<void> _flushTask(dynamic taskId) async {
    try {
      final detail = await TransferApi.getTransferTask(taskId);
      if (!mounted || detail == null) return;
      Store.updateTransfer(detail);
      final idx = _list.indexWhere((t) => t['id'] == taskId);
      if (idx == -1) return;
      final formatted = _formatList([detail])[0];
      setState(() => _list[idx] = formatted);
      if (formatted['isRunning'] == true && (formatted['sessionId'] ?? '') != '') {
        _pollProgress(formatted, _pollGeneration);
      }
      if (formatted['isDone'] == true) {
        _loadDoneDetails([formatted]);
      }
    } catch (_) {}
  }

  /// 应用进度到任务（严格对应 Web caclulaterItem）
  void _applyProgress(dynamic taskId, Map<String, dynamic> progress) {
    final idx = _list.indexWhere((t) => t['id'] == taskId);
    if (idx == -1) return;
    final item = _list[idx];

    final totalFiles = ((progress['totalFiles'] ?? 0) as num).toDouble();
    final totalFolders = ((progress['totalFolders'] ?? 0) as num).toDouble();
    final successFolders = ((progress['successFolders'] ?? 0) as num).toDouble();
    final failedFiles = ((progress['failedFiles'] ?? 0) as num).toDouble();
    final complateFiles = ((progress['complateFiles'] ?? 0) as num).toDouble();
    final overCount = progress['overCount'] == true;
    final totalAll = (totalFiles + totalFolders).toInt();

    // 成功计数（对应 Web 显示逻辑：完成数 + 成功文件夹数）
    final successCount = (complateFiles + successFolders).toInt();
    final failedCount = failedFiles.toInt();

    final totalSize = (progress['totalSize'] ?? 0) as num;
    final stream = (progress['stream'] ?? 0) as num;
    final totalSizeText = totalSize > 0 ? Formatters.formatFileSize(totalSize, 2) : '0 B';
    final streamSizeText = stream > 0 ? Formatters.formatFileSize(stream, 2) : '0 B';
    final speed = progress['speed']?.toString() ?? '';
    final remainTime = progress['remainTime'];
    final timeRemaining = remainTime != null && (remainTime as num) > 0
        ? Formatters.secondsToTime(remainTime)
        : '';

    // 进度百分比：计数中（overCount=false）比例封顶 5%
    var rate = (progress['rate'] ?? 0) as num;
    if (!overCount) {
      rate = totalSize == 0
          ? 0
          : ((stream / totalSize) * 10000).floor() / 100;
      if (rate > 5) rate = 5;
    }
    var val = totalSize == 0 ? 0.0 : rate.toDouble();
    final oldPercent = (item['percent'] ?? 0) is num
        ? ((item['percent'] ?? 0) as num).toDouble()
        : double.tryParse(item['percent'].toString()) ?? 0;
    if (val < oldPercent) val = oldPercent; // 进度不回退
    if (val >= 100) val = 99.99;

    // 文件级详情
    final streamItems = <Map<String, dynamic>>[];
    final items = progress['items'];
    if (items is List) {
      for (final it in items) {
        if (it is! Map) continue;
        final itTotal = (it['totalSize'] ?? 0) as num;
        final itStream = (it['stream'] ?? 0) as num;
        streamItems.add({
          'filename': it['filename'] ?? '未知文件',
          'dir': it['dir'] == true,
          'isRunning': it['run'] != false,
          'percent': itTotal == 0 ? 0 : ((itStream / itTotal) * 100).floor(),
          'sizeText': itTotal > 0 ? Formatters.formatFileSize(itTotal, 1) : '',
        });
      }
    }

    setState(() {
      _list[idx]['percent'] = val;
      _list[idx]['speed'] = speed;
      _list[idx]['timeRemaining'] = timeRemaining;
      _list[idx]['totalAll'] = totalAll;
      _list[idx]['successCount'] = successCount;
      _list[idx]['failedCount'] = failedCount;
      _list[idx]['totalSize'] = totalSizeText;
      _list[idx]['streamSize'] = streamSizeText;
      _list[idx]['streamItems'] = streamItems;
    });
  }

  // ===================== waiting 统一轮询 =====================

  void _startWaitPolling(List<Map<String, dynamic>> list) {
    final hasWaiting = list.any((t) => t['isWaiting'] == true);
    if (hasWaiting && !_isWaitPolling) {
      _isWaitPolling = true;
      _waitPoll(_pollGeneration);
    }
    if (!hasWaiting) {
      _isWaitPolling = false;
    }
  }

  Future<void> _waitPoll(int gen) async {
    while (_isWaitPolling && !_pageHidden && gen == _pollGeneration) {
      await _sleep(5000);
      if (!_isWaitPolling || !mounted || _pageHidden || gen != _pollGeneration) break;

      try {
        final fresh = await TransferApi.getTransferList(silent: true);
        Store.setTransferList(fresh);
        var statusChanged = false;
        for (final raw in fresh) {
          final freshItem = raw as Map;
          final local = _list.where((t) => t['id'] == freshItem['id']).toList();
          if (local.isEmpty) continue;
          if (!TaskUtils.isWaiting(local[0]['status']?.toString())) continue;
          if (local[0]['status'] == freshItem['status']) continue;
          if (TaskUtils.isRunning(freshItem['status']?.toString())) {
            statusChanged = true;
            break;
          }
        }
        if (statusChanged) {
          _isWaitPolling = false;
          _loadList(silent: true);
        }
      } catch (_) {}
    }
  }

  // ===================== 操作 =====================

  /// 新建任务（无云盘时引导授权）
  Future<void> _goCreate() async {
    if (Store.getToken().isEmpty) {
      Toast.show('请先登录');
      Navigator.pushNamed(context, '/login');
      return;
    }
    var drives = Store.getDrives();
    if ((drives == null || drives.isEmpty) && Store.getToken().isNotEmpty) {
      LoadingManager.show('检查云存储...');
      try {
        drives = await DriveApi.getDriveList();
      } catch (_) {
        drives = [];
      }
      LoadingManager.hide();
    }
    if (!mounted) return;
    if (drives == null || drives.isEmpty) {
      Toast.show('请先授权云存储');
      Navigator.pushNamed(context, '/cloud/add');
      return;
    }
    Navigator.pushNamed(context, '/transfer/create');
  }

  void _goDetail(Map<String, dynamic> task) {
    Navigator.pushNamed(context, '/transfer/detail', arguments: {
      'id': task['id'],
      'task': task,
    });
  }

  Future<void> _pauseTask(Map<String, dynamic> task) async {
    if ((task['sessionId'] ?? '') == '') {
      Toast.show('任务信息异常');
      return;
    }
    try {
      await TransferApi.pauseTransfer(task['id'], task['sessionId']);
      Toast.show('已暂停');
      final idx = _list.indexWhere((t) => t['id'] == task['id']);
      if (idx != -1) {
        setState(() {
          _list[idx]['status'] = 'pause';
          _list[idx]['isRunning'] = false;
          _list[idx]['isPause'] = true;
          _list[idx]['statusLabel'] = '暂停';
          _list[idx]['statusColor'] = 0xFFFF9500;
        });
      }
    } catch (e) {
      Toast.show(e is ApiException ? e.message : '操作失败');
    }
  }

  Future<void> _resumeTask(Map<String, dynamic> task) async {
    if ((task['sessionId'] ?? '') == '') {
      Toast.show('任务信息异常');
      return;
    }
    try {
      await TransferApi.resumeTransfer(task['id'], task['sessionId']);
      Toast.show('已恢复');
      _flushTask(task['id']);
    } catch (e) {
      Toast.show(e is ApiException ? e.message : '操作失败');
    }
  }

  Future<void> _stopTask(Map<String, dynamic> task) async {
    if ((task['sessionId'] ?? '') == '') {
      Toast.show('任务信息异常');
      return;
    }
    final ok = await showConfirm(
      context,
      title: '停止传输',
      content: '是否要停止当前正在运行的任务？',
      confirmText: '停止',
      danger: true,
    );
    if (!ok) return;
    try {
      await TransferApi.stopTransfer(task['sessionId']);
      Toast.show('已停止');
      _flushTask(task['id']);
    } catch (e) {
      Toast.show(e is ApiException ? e.message : '操作失败');
    }
  }

  /// 续传：skip 冲突策略 → 断点续传；rename → 从头重传
  Future<void> _continueTask(Map<String, dynamic> task) async {
    if ((task['sessionId'] ?? '') == '') {
      Toast.show('任务信息异常');
      return;
    }
    final action = task['action'];
    final confict = action is Map ? action['confict'] : null;
    final continueStart = confict == null || confict == 'skip';
    LoadingManager.show('续传中...');
    try {
      await TransferApi.executeTransfer(task['id'], task['sessionId'], continueStart);
      LoadingManager.hide();
      Toast.show('已开始续传');
      _flushTask(task['id']);
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '续传失败');
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final ok = await showConfirm(
      context,
      title: '删除任务',
      content: '确定删除该传输任务？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await TransferApi.deleteTransfer(task['id']);
      Toast.show('已删除');
      Store.removeTransfer(task['id']);
      setState(() {
        _list = _list.where((t) => t['id'] != task['id']).toList();
        _isEmpty = _list.isEmpty;
      });
    } catch (e) {
      Toast.show(e is ApiException ? e.message : '删除失败');
    }
  }

  /// 更多操作（done 任务）
  Future<void> _moreActions(Map<String, dynamic> task) async {
    final canContinue = task['isDone'] == true &&
        !TaskUtils.isSuccess(task['status']?.toString());
    final actions = canContinue ? ['续传', '任务详情', '删除任务'] : ['任务详情', '删除任务'];
    final idx = await showActionSheet(context, actions: actions);
    if (idx == null) return;
    final action = canContinue ? ['cont', 'detail', 'del'][idx] : ['detail', 'del'][idx];
    if (action == 'cont') {
      _continueTask(task);
    } else if (action == 'detail') {
      _goDetail(task);
    } else if (action == 'del') {
      _deleteTask(task);
    }
  }

  void _toggleExpand(Map<String, dynamic> task) {
    setState(() => task['expanded'] = !(task['expanded'] == true));
  }

  // ===================== 视图 =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: '传输',
              onRefresh: () => _loadList(force: true),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _isEmpty || _list.isEmpty
                      ? EmptyView(
                          text: '暂无传输任务',
                          actionText: '新建传输任务',
                          onAction: _goCreate,
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () => _loadList(force: true),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                            itemCount: _list.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _buildTaskCard(_list[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _goCreate,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final isRunning = task['isRunning'] == true;
    final percent = _num(task['percent']);
    final statusColor = Color(task['statusColor'] is int ? task['statusColor'] : 0xFFCCCCCC);

    return AppCard(
      onTap: () => _goDetail(task),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行 + 状态
          Row(
            children: [
              Expanded(
                child: Text(
                  task['name']?.toString() ?? '传输任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMain),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  task['statusLabel']?.toString() ?? '未知',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 源/目标路径
          _buildPathRow(task, isRunning),
          const SizedBox(height: 12),
          // 进度区（running/waiting）
          if (isRunning || task['isWaiting'] == true) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: isRunning ? percent / 100 : null,
                  minHeight: 6,
                  backgroundColor: AppColors.primaryLight,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isRunning
                        ? '${percent.toStringAsFixed(1)}%  ${task['speed'] ?? ''}'
                        : '排队等待中...',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
                if (isRunning && (task['timeRemaining'] ?? '').toString().isNotEmpty)
                  Text(
                    '剩余 ${task['timeRemaining']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                  ),
              ],
            ),
          ],
          // done 计数
          if (task['isDone'] == true) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                const SizedBox(width: 2),
                Text('成功 ${_num(task['successCount']).toInt()}',
                    style: const TextStyle(fontSize: 12, color: AppColors.success)),
                const SizedBox(width: 12),
                if (_num(task['failedCount']) > 0) ...[
                  const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
                  const SizedBox(width: 2),
                  Text('失败 ${_num(task['failedCount']).toInt()}',
                      style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ] else
                  Text('共 ${_num(task['totalAll']).toInt()} 项',
                      style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
              ],
            ),
          ],
          // 运行中文件明细（可展开）
          if (isRunning && (task['streamItems'] as List).isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _toggleExpand(task),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task['expanded'] == true ? '收起明细' : '展开明细',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                  Icon(
                    task['expanded'] == true ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
            if (task['expanded'] == true)
              ..._buildStreamItems(task['streamItems'] as List),
          ],
          const SizedBox(height: 10),
          // 操作按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isRunning) ...[
                _actionChip('暂停', Icons.pause, AppColors.warning, () => _pauseTask(task)),
                const SizedBox(width: 8),
                _actionChip('停止', Icons.stop, AppColors.danger, () => _stopTask(task)),
              ],
              if (task['isPause'] == true)
                _actionChip('恢复', Icons.play_arrow, AppColors.success, () => _resumeTask(task)),
              if (task['isDone'] == true) ...[
                _actionChip('详情', Icons.info_outline, AppColors.primary, () => _goDetail(task)),
                const SizedBox(width: 8),
                _actionChip('更多', Icons.more_horiz, AppColors.textSub, () => _moreActions(task)),
              ] else ...[
                _actionChip('详情', Icons.info_outline, AppColors.primary, () => _goDetail(task)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStreamItems(List items) {
    return [
      Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.pageBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            for (final it in items)
              if (it is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        it['dir'] == true ? Icons.folder : Icons.insert_drive_file_outlined,
                        size: 13,
                        color: it['dir'] == true ? AppColors.warning : AppColors.textWeak,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          it['filename']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: it['isRunning'] == true ? AppColors.textMain : AppColors.textWeak,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${it['sizeText']} ${it['percent']}%',
                        style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    ];
  }

  /// 源/目标路径行（左右两栏 + 中间箭头）
  Widget _buildPathRow(Map<String, dynamic> task, bool isRunning) {
    return Row(
      children: [
        Expanded(
          child: _buildPathColumn(task['sourceDriveType'], task['sourcePath']),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: isRunning
              ? Image.asset('assets/images/transfer-right.gif', width: 22, height: 22,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.arrow_forward, size: 18, color: AppColors.primary))
              : const Icon(Icons.arrow_forward, size: 18, color: AppColors.border),
        ),
        Expanded(
          child: _buildPathColumn(task['destDriveType'], task['destPath']),
        ),
      ],
    );
  }

  Widget _buildPathColumn(String? driveType, String? path) {
    return Column(
      children: [
        DriveIcon(driveType: driveType ?? '', size: 24),
        const SizedBox(height: 4),
        Text(
          (path ?? '').isEmpty ? '/' : path!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textSub),
        ),
      ],
    );
  }

  Widget _actionChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha:0.5)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
