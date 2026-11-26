/// 同步任务列表（对应 MP pages/sync/list/list）
///
/// 运行任务（含 relax 待执行）5s 逐任务轮询；停止/恢复/删除；
/// 同步日志弹窗（10 条/页）；定时设置弹窗（TimerPlans 组件）。
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
import '../../widgets/timer_plans.dart';

class SyncListPage extends StatefulWidget {
  const SyncListPage({super.key});

  @override
  State<SyncListPage> createState() => _SyncListPageState();
}

class _SyncListPageState extends State<SyncListPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _isEmpty = false;

  int _pollGeneration = 0;
  bool _pageHidden = false;
  final Set<dynamic> _syncPolling = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UiEvents.taskListVersion.addListener(_onTasksChanged);
    _loadSyncList();
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
    _loadSyncList(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pageHidden = true;
      _pollGeneration++;
    } else if (state == AppLifecycleState.resumed) {
      _pageHidden = false;
      _loadSyncList(force: true);
    }
  }

  Future<void> _sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

  // ===================== 加载 =====================

  Future<void> _loadSyncList({bool silent = false, bool force = false}) async {
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
      final cached = Store.getSyncList();
      if (cached != null && cached.isNotEmpty) {
        final formatted = _formatSyncList(cached);
        setState(() {
          _list = formatted;
          _isEmpty = false;
          _loading = false;
        });
        _pollGeneration++;
        _pageHidden = false;
        _startSyncPolling(formatted);
        return;
      }
    }

    try {
      final fresh = await TransferApi.getSyncList(silent: silent);
      Store.setSyncList(fresh);
      final formatted = _formatSyncList(fresh);
      setState(() {
        _list = formatted;
        _isEmpty = fresh.isEmpty;
        _loading = false;
      });
      _pollGeneration++;
      _pageHidden = false;
      _startSyncPolling(formatted);
    } catch (_) {
      if (!silent) setState(() => _loading = false);
    }
  }

  // ===================== 格式化 =====================

  List<Map<String, dynamic>> _formatSyncList(List<dynamic> list) {
    return list
        .map((raw) => _formatSyncItem(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Map<String, dynamic> _formatSyncItem(Map<String, dynamic> item) {
    final status = item['status']?.toString();
    final running = SyncTaskUtils.isRunning(status);
    final statusInfo = _getSyncStatusInfo(status);
    final progress =
        (status == 'execute' || status == 'compare') ? (item['progress'] as Map?) : null;

    final streamItems = <Map<String, dynamic>>[];
    if (status == 'execute' && progress != null && progress['items'] is List) {
      for (final it in progress['items'] as List) {
        if (it is! Map) continue;
        final total = (it['totalSize'] ?? 0) as num;
        final stream = (it['stream'] ?? 0) as num;
        streamItems.add({
          'filename': it['filename'] ?? '未知文件',
          'dir': it['dir'] == true,
          'isRunning': it['run'] != false,
          'percent': total == 0 ? 0 : ((stream / total) * 100).floor(),
          'sizeText': total > 0 ? Formatters.formatFileSize(total, 1) : '',
        });
      }
    }

    return {
      ...item,
      'isRunning': running,
      'statusLabel': statusInfo.label,
      'statusColor': statusInfo.color,
      'statusText': _enrichSyncStatus(item),
      'sourcePath': _buildSyncPath(item['sourceItem']),
      'destPath': _buildSyncPath(item['destinationItem']),
      'sourceDriveType': item['sourceItem'] is Map
          ? (item['sourceItem']['driveType'] ?? '').toString()
          : '',
      'destDriveType': item['destinationItem'] is Map
          ? (item['destinationItem']['driveType'] ?? '').toString()
          : '',
      'percent': progress != null && progress['rate'] != null
          ? _parseSyncRate(progress['rate'])
          : 0.0,
      'speed': progress != null ? (progress['speed']?.toString() ?? '') : '',
      'streamItems': streamItems,
      'expanded': false,
    };
  }

  static ({String label, int color}) _getSyncStatusInfo(String? status) {
    switch (status) {
      case 'compare':
        return (label: '比对中', color: 0xFF4C7DFF);
      case 'execute':
        return (label: '同步中', color: 0xFF4C7DFF);
      case 'relax':
        return (label: '待执行', color: 0xFF00C48F);
      case 'init':
        return (label: '准备中', color: 0xFFFF9500);
      case 'complate':
        return (label: '已完成', color: 0xFF00C48F);
      case 'stop':
        return (label: '已停止', color: 0xFF999999);
      default:
        return (label: '未知', color: 0xFFCCCCCC);
    }
  }

  /// 富化状态描述（对应 Web convertSyncTime）
  String _enrichSyncStatus(Map<String, dynamic> item) {
    final status = item['status']?.toString();
    final desc = item['statusDesc']?.toString() ?? '';
    final progress = item['progress'] as Map?;
    if (status == 'compare' && progress != null) {
      return '$desc(${progress['totalCount'] ?? 0}项,${Formatters.formatFileSize(progress['totalSize'] ?? 0, 2)})';
    }
    if (status == 'execute') {
      if (progress != null && progress['rate'] != null) {
        final speed = progress['speed']?.toString() ?? '0M';
        return '$desc(${progress['rate']}%,$speed/s)';
      }
      return '$desc(0.00%)';
    }
    if (status == 'relax') {
      const prefix = '下次同步时间：';
      var timeStr = desc;
      if (timeStr.startsWith(prefix)) {
        timeStr = timeStr.substring(prefix.length);
      }
      final target = DateTime.tryParse(timeStr.replaceAll('/', '-'))?.millisecondsSinceEpoch;
      if (target == null) return desc;
      var seconds = ((target - DateTime.now().millisecondsSinceEpoch) / 1000).floor();
      if (seconds < 0) seconds = 0;
      String timeDesc;
      if (seconds < 60) {
        timeDesc = '$seconds秒';
      } else {
        final hours = seconds ~/ 3600;
        final minutes = (seconds % 3600) ~/ 60;
        timeDesc = '$hours时$minutes分';
      }
      return '$prefix还有$timeDesc';
    }
    return desc;
  }

  static String _buildSyncPath(dynamic item) {
    if (item is! Map) return '';
    var path = '';
    final nodeArray = item['nodeArray'];
    if (nodeArray is List && nodeArray.isNotEmpty) {
      path = nodeArray.map((n) => n is Map ? n['name'] : '').join('/');
    }
    final name = item['name']?.toString() ?? '';
    return path.isNotEmpty ? '$path/$name' : name;
  }

  static double _parseSyncRate(dynamic rate) {
    final n = double.tryParse(rate?.toString() ?? '');
    if (n == null) return 0;
    return n.clamp(0, 100);
  }

  // ===================== 轮询 =====================

  void _startSyncPolling(List<Map<String, dynamic>> list) {
    final gen = _pollGeneration;
    for (final task in list) {
      if (task['isRunning'] == true) {
        _pollSyncTask(task['id'], gen);
      }
    }
  }

  Future<void> _pollSyncTask(dynamic taskId, int gen) async {
    if (_syncPolling.contains(taskId)) return;
    _syncPolling.add(taskId);
    try {
      while (mounted && !_pageHidden && gen == _pollGeneration) {
        await _sleep(5000);
        if (!mounted || _pageHidden || gen != _pollGeneration) break;

        final cur = _list.where((t) => t['id'] == taskId).toList();
        if (cur.isEmpty || !SyncTaskUtils.isRunning(cur[0]['status']?.toString())) break;

        try {
          final item = await TransferApi.getSyncTask(taskId);
          if (item == null || item['id'] == null) break;
          _applySyncItem(item);
          if (!SyncTaskUtils.isRunning(item['status']?.toString())) break;
        } catch (_) {
          // 瞬时失败继续下一轮
        }
      }
    } finally {
      _syncPolling.remove(taskId);
    }
  }

  /// 原地刷新（保留展开态）
  Map<String, dynamic>? _applySyncItem(Map<String, dynamic> item) {
    final idx = _list.indexWhere((t) => t['id'] == item['id']);
    if (idx == -1) return null;
    final old = _list[idx];
    final formatted = _formatSyncItem(item);
    formatted['expanded'] = old['expanded'];
    setState(() => _list[idx] = formatted);
    Store.updateSync(item);
    return formatted;
  }

  Future<Map<String, dynamic>?> _flushSyncTask(dynamic taskId) async {
    try {
      final item = await TransferApi.getSyncTask(taskId);
      if (item == null || item['id'] == null) return null;
      if (!mounted) return null;
      return _applySyncItem(item);
    } catch (_) {
      return null;
    }
  }

  // ===================== 操作 =====================

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
    Navigator.pushNamed(context, '/sync/create');
  }

  Future<void> _stopSyncTask(Map<String, dynamic> task) async {
    final ok = await showConfirm(
      context,
      title: '停止同步',
      content: '是否要停止当前正在运行的同步任务？',
      confirmText: '停止',
      danger: true,
    );
    if (!ok) return;
    LoadingManager.show('停止中...');
    try {
      await TransferApi.stopSync(task['id']);
      // 等后端状态落库后再刷新
      await _sleep(3000);
      await _flushSyncTask(task['id']);
      LoadingManager.hide();
      Toast.show('已停止');
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '操作失败');
    }
  }

  Future<void> _resumeSyncTask(Map<String, dynamic> task) async {
    final isDone = task['status']?.toString() == 'complate';
    final ok = await showConfirm(
      context,
      title: isDone ? '重新同步' : '恢复同步',
      content: '是否立即恢复同步',
    );
    if (!ok) return;
    LoadingManager.show('恢复中...');
    try {
      await TransferApi.resumeSync(task['id']);
      await _sleep(2000);
      final item = await _flushSyncTask(task['id']);
      LoadingManager.hide();
      Toast.show(isDone ? '已开始同步' : '已恢复');
      if (item != null && item['isRunning'] == true) {
        _pollSyncTask(task['id'], _pollGeneration);
      }
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '操作失败');
    }
  }

  Future<void> _deleteSyncTask(Map<String, dynamic> task) async {
    final ok = await showConfirm(
      context,
      title: '删除任务',
      content: '确定删除该同步任务？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await TransferApi.deleteSync(task['id']);
      Toast.show('已删除');
      Store.removeSync(task['id']);
      setState(() {
        _list = _list.where((t) => t['id'] != task['id']).toList();
        _isEmpty = _list.isEmpty;
      });
    } catch (e) {
      Toast.show(e is ApiException ? e.message : '删除失败');
    }
  }

  /// 更多操作：同步日志 / 定时设置 / 删除任务（运行中不可删）
  Future<void> _moreActions(Map<String, dynamic> task) async {
    final canDelete = task['isRunning'] != true;
    final actions =
        canDelete ? ['同步日志', '定时设置', '删除任务'] : ['同步日志', '定时设置'];
    final idx = await showActionSheet(context, actions: actions);
    if (idx == null) return;
    if (idx == 0) {
      _openSyncLog(task);
    } else if (idx == 1) {
      _openTimerSetting(task);
    } else if (canDelete && idx == 2) {
      _deleteSyncTask(task);
    }
  }

  void _toggleExpand(Map<String, dynamic> task) {
    setState(() => task['expanded'] = !(task['expanded'] == true));
  }

  // ===================== 同步日志弹窗 =====================

  Future<void> _openSyncLog(Map<String, dynamic> task) async {
    var page = 1;
    var pages = 1;
    final items = <Map<String, dynamic>>[];
    var logLoading = true;

    Future<void> loadPage(int p) async {
      try {
        final res = await TransferApi.getSyncLog(task['id'], p);
        final map = res is Map ? res : {};
        final logs = (map['logs'] as List?) ?? [];
        final total = ((map['total'] ?? 0) as num).toInt();
        page = p;
        pages = total == 0 ? 1 : (total / 10).ceil();
        items
          ..clear()
          ..addAll(logs.map((l) => l is Map ? Map<String, dynamic>.from(l) : {}));
      } catch (_) {}
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          Future<void> refresh(int p) async {
            setDialog(() => logLoading = true);
            await loadPage(p);
            setDialog(() => logLoading = false);
          }

          if (logLoading && items.isEmpty) {
            refresh(1);
          }

          return AlertDialog(
            title: Text(task['name']?.toString() ?? '同步日志',
                style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: logLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                    )
                  : items.isEmpty
                      ? const Text('暂无日志', style: TextStyle(fontSize: 13, color: AppColors.textWeak))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: AppColors.border.withValues(alpha:0.5)),
                          itemBuilder: (_, i) {
                            final log = items[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log['name']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${log['startTime'] ?? ''} ~ ${log['endTime'] ?? ''}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                                  ),
                                  if ((log['statusDesc'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        log['statusDesc'].toString(),
                                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                onPressed: page > 1 ? () => refresh(page - 1) : null,
                child: Text('上一页', style: TextStyle(fontSize: 13, color: page > 1 ? AppColors.primary : AppColors.border)),
              ),
              Text('$page/$pages',
                  style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
              TextButton(
                onPressed: page < pages ? () => refresh(page + 1) : null,
                child: Text('下一页', style: TextStyle(fontSize: 13, color: page < pages ? AppColors.primary : AppColors.border)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭', style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===================== 定时设置弹窗 =====================

  Future<void> _openTimerSetting(Map<String, dynamic> task) async {
    LoadingManager.show('加载中...');
    List<Map<String, dynamic>> backendPlans;
    try {
      final timerModel = await TransferApi.getSyncTimer(task['id']);
      LoadingManager.hide();
      backendPlans = ((timerModel?['plans'] as List?) ?? [])
          .map((p) => p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{})
          .toList();
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '加载失败');
      return;
    }

    // 后端模型 → 组件模型
    final plans = backendPlans
        .map((p) => {
              'type': p['planType'] ?? 'day',
              'num': p['num'] ?? 1,
              'time': p['time'] ?? '08:00',
            })
        .toList();

    if (!mounted) return;
    var saving = false;
    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            title: const Text('定时设置', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: TimerPlans(
                key: ValueKey('timer_${task['id']}_${backendPlans.length}'),
                initialPlans: plans,
                max: 2,
                onChanged: (p) => backendPlans = p,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: AppColors.textWeak)),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (hasDuplicatePlans(backendPlans)) {
                          Toast.show('存在相同的定时计划，请修改');
                          return;
                        }
                        setDialog(() => saving = true);
                        try {
                          // 任务已存在恒按计划态保存（showExecuteNow=false）
                          await TransferApi.updateSyncTimer(task['id'], {
                            'type': 'Plan',
                            'timezone': Formatters.getTimezone(),
                            'plans': backendPlans,
                          });
                          await _sleep(1000);
                          await _flushSyncTask(task['id']);
                          if (ctx.mounted) Navigator.pop(ctx);
                          Toast.show('已保存');
                        } catch (e) {
                          setDialog(() => saving = false);
                          Toast.show(e is ApiException ? e.message : '保存失败');
                        }
                      },
                child: Text(saving ? '保存中...' : '保存',
                    style: const TextStyle(color: AppColors.primary)),
              ),
            ],
          );
        },
      ),
    );
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
              title: '同步',
              onRefresh: () => _loadSyncList(force: true),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _isEmpty || _list.isEmpty
                      ? EmptyView(
                          text: '暂无同步任务',
                          actionText: '新建同步任务',
                          onAction: _goCreate,
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () => _loadSyncList(force: true),
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
    final status = task['status']?.toString();
    final statusColor = Color(task['statusColor'] is int ? task['statusColor'] : 0xFFCCCCCC);
    final percent = (task['percent'] as num?)?.toDouble() ?? 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行 + 状态徽标
          Row(
            children: [
              Expanded(
                child: Text(
                  task['name']?.toString() ?? '同步任务',
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
          const SizedBox(height: 10),
          // 源/目标两栏
          Row(
            children: [
              Expanded(
                child: _pathColumn(task['sourceDriveType']?.toString(), task['sourcePath']?.toString()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    if (isRunning)
                      Image.asset('assets/images/running.gif', width: 22, height: 22,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.sync, size: 18, color: AppColors.primary)),
                    const Text('单向同步', style: TextStyle(fontSize: 10, color: AppColors.primary)),
                  ],
                ),
              ),
              Expanded(
                child: _pathColumn(task['destDriveType']?.toString(), task['destPath']?.toString()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 富化状态
          if ((task['statusText'] ?? '').toString().isNotEmpty)
            Text(
              task['statusText'].toString(),
              style: TextStyle(
                fontSize: 11,
                color: status == 'relax' ? AppColors.success : AppColors.primary,
              ),
            ),
          // 进度条（execute）
          if (status == 'execute') ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 5,
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 5,
                  backgroundColor: AppColors.primaryLight,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
          ],
          // execute 文件明细
          if (status == 'execute' && (task['streamItems'] as List).isNotEmpty) ...[
            const SizedBox(height: 6),
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
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    for (final it in task['streamItems'] as List)
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
          ],
          const SizedBox(height: 10),
          // 操作行
          Row(
            children: [
              Expanded(
                child: Text(
                  '创建于 ${Formatters.formatDateTime(task['createTimeTs'] ?? task['createTime'])}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                ),
              ),
              if (isRunning) ...[
                _actionChip('停止', Icons.stop, AppColors.danger, () => _stopSyncTask(task)),
                const SizedBox(width: 8),
              ] else ...[
                _actionChip(
                  status == 'complate' ? '重新同步' : '恢复',
                  Icons.play_arrow,
                  AppColors.success,
                  () => _resumeSyncTask(task),
                ),
                const SizedBox(width: 8),
              ],
              _actionChip('更多', Icons.more_horiz, AppColors.textSub, () => _moreActions(task)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pathColumn(String? driveType, String? path) {
    return Column(
      children: [
        DriveIcon(driveType: driveType ?? '', size: 28),
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
}
