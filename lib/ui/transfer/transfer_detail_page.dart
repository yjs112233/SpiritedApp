/// 传输任务详情（对应 MP pages/transfer/detail/detail）
///
/// 基础信息 / 源目标路径 / sessionDone 统计（成功率）/ 失败明细分页（20条/页）。
library;

import 'package:flutter/material.dart';

import '../../api/transfer_api.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class TransferDetailPage extends StatefulWidget {
  const TransferDetailPage({super.key});

  @override
  State<TransferDetailPage> createState() => _TransferDetailPageState();
}

class _TransferDetailPageState extends State<TransferDetailPage> {
  dynamic _taskId;
  bool _loading = true;

  String _taskName = '';
  String _status = '';
  String _sessionId = '';

  String _sourceDriveType = '';
  String _sourcePath = '';
  List<Map<String, dynamic>> _sourceItems = [];
  bool _showAllSources = false;
  String _destDriveType = '';
  String _destPath = '';

  String _time = '';
  String _startTime = '';
  String _endTime = '';
  String _timezone = '';

  int _totalFolder = 0, _successFolder = 0, _totalFile = 0, _successFile = 0, _skipFile = 0;
  String _skipSize = '0 B', _totalSize = '0 B', _successSize = '0 B';
  double _successRate = 0;

  bool _showFailDetails = false;
  int _failNumber = 0;
  final List<Map<String, dynamic>> _failItems = [];
  bool _showFailList = false;
  int _failPage = 1;
  int _failTotal = 0;
  bool _failLoading = false;
  bool _failHasMore = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_taskId == null) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _taskId = args?['id'];
      if (_taskId != null) {
        _loadDetail();
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final task = await TransferApi.getTransferTask(_taskId);
      if (!mounted) return;
      if (task == null) {
        Toast.show('加载失败');
        return;
      }
      _renderDetail(task);
    } catch (e) {
      if (mounted) Toast.show(e is ApiException ? e.message : '加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _renderDetail(Map<String, dynamic> task) {
    final taskName = task['name']?.toString() ?? task['taskName']?.toString() ?? '传输任务';
    final session = (task['session'] as Map?) ?? {};
    final status = session['status']?.toString() ?? task['status']?.toString() ?? '';
    final sourceItemsRaw = (task['sourceItems'] as List?) ?? [];
    final destinationItem = (task['destinationItem'] as Map?) ?? {};
    final drives = Store.getDrives() ?? [];

    Map<String, dynamic>? findDrive(dynamic driveId) {
      if (driveId == null) return null;
      for (final d in drives) {
        if (d is Map && d['id'].toString() == driveId.toString()) {
          return Map<String, dynamic>.from(d);
        }
      }
      return null;
    }

    String driveNameOf(Map<String, dynamic>? drive) {
      if (drive == null) return '云存储';
      final type = drive['driveType']?.toString() ?? '';
      return drive['driveUsername']?.toString().isNotEmpty == true
          ? drive['driveUsername'].toString()
          : (driveTypeNames[type] ?? (type.isEmpty ? '云存储' : type));
    }

    // 完整路径：云存储名/文件夹/文件名
    String buildPath(dynamic nodeArray, dynamic itemName, String driveName) {
      var path = '';
      final nodes = nodeArray is List ? nodeArray : [];
      for (final n in nodes) {
        path += '/${n is Map ? n['name'] : ''}';
      }
      if (itemName != null && itemName.toString().isNotEmpty) {
        path += '/$itemName';
      }
      if (path.startsWith('/')) path = path.substring(1);
      return driveName.isNotEmpty ? '$driveName/$path' : path;
    }

    // === 来源 ===
    final sourceItemsFormatted = <Map<String, dynamic>>[];
    for (final s in sourceItemsRaw) {
      if (s is! Map) continue;
      final drive = findDrive(s['driveId']);
      final nodes = (s['nodeArray'] is List ? s['nodeArray'] : s['nodeList']) ?? [];
      sourceItemsFormatted.add({
        'path': buildPath(nodes, s['name'], driveNameOf(drive)),
        'name': s['name']?.toString() ?? '',
      });
    }

    final firstSource = sourceItemsFormatted.isNotEmpty ? sourceItemsFormatted[0] : null;
    final firstRaw = sourceItemsRaw.isNotEmpty && sourceItemsRaw[0] is Map
        ? sourceItemsRaw[0] as Map
        : null;
    final sourceDrive = findDrive(firstRaw?['driveId']);

    // === 目标 ===
    final destDrive = findDrive(destinationItem['driveId']);
    final destNodes =
        (destinationItem['nodeArray'] is List ? destinationItem['nodeArray'] : destinationItem['nodeList']) ?? [];

    // === sessionDone 统计 ===
    final done = (session['sessionDone'] as Map?) ?? {};
    _sessionId = session['id']?.toString() ?? '';
    final totalFolder = ((done['totalFolder'] ?? 0) as num).toInt();
    final successFolder = ((done['successFolder'] ?? 0) as num).toInt();
    final totalFile = ((done['totalFile'] ?? 0) as num).toInt();
    final successFile = ((done['successFile'] ?? 0) as num).toInt();
    final skipFile = ((done['skipFile'] ?? 0) as num).toInt();
    final totalAll = totalFolder + totalFile;
    final successAll = successFolder + successFile + skipFile;
    final successRate = totalAll > 0 ? (successAll / totalAll * 1000).floor() / 10 : 0.0;

    final sessionTime = session['time'];
    final failFile = ((done['failFile'] ?? 0) as num).toInt();

    setState(() {
      _taskName = taskName;
      _status = status;
      _sourceDriveType = sourceDrive?['driveType']?.toString() ?? '';
      _sourcePath = firstSource?['path'] ?? '';
      _sourceItems = sourceItemsFormatted;
      _destDriveType = destDrive?['driveType']?.toString() ?? '';
      _destPath = buildPath(destNodes, destinationItem['name'], driveNameOf(destDrive));
      _time = sessionTime != null && (sessionTime as num) > 0
          ? Formatters.secondsToTime((sessionTime / 1000).floor())
          : '';
      _startTime = session['startTime']?.toString() ?? '';
      _endTime = session['endTime']?.toString() ?? '';
      _timezone = session['timezone']?.toString() ?? '';
      _totalFolder = totalFolder;
      _successFolder = successFolder;
      _totalFile = totalFile;
      _successFile = successFile;
      _skipFile = skipFile;
      _skipSize = Formatters.formatFileSize(done['skipSize'] ?? 0, 2);
      _totalSize = Formatters.formatFileSize(done['totalSize'] ?? 0, 2);
      _successSize = Formatters.formatFileSize(done['successSize'] ?? 0, 2);
      _successRate = successRate;
      _showFailDetails = failFile > 0;
      _failNumber = failFile;
      _failItems.clear();
      _showFailList = false;
      _failPage = 1;
      _failTotal = failFile;
      _failHasMore = false;
    });
  }

  Future<void> _openFailList() async {
    setState(() => _showFailList = true);
    if (_failItems.isEmpty) {
      await _loadFailPage(1);
    }
  }

  Future<void> _loadFailPage(int page) async {
    if (_failLoading || _sessionId.isEmpty) return;
    setState(() => _failLoading = true);
    try {
      final data = await TransferApi.getTransferErrors(_sessionId, page);
      final map = data is Map ? data : {};
      final errors = (map['errors'] as List?) ?? [];
      final total = ((map['total'] ?? 0) as num).toInt();
      final list = page == 1
          ? errors
          : [..._failItems.map((e) => Map<String, dynamic>.from(e)), ...errors];
      setState(() {
        _failItems
          ..clear()
          ..addAll(errors.map((it) {
            final m = it is Map ? it : {};
            return {
              'itemRelative': m['itemRelative']?.toString() ?? '',
              'filesize': m['filesize'] != null && (m['filesize'] as num) > 0
                  ? Formatters.formatFileSize(m['filesize'], 1)
                  : '-',
              'errorCause': m['errorCause']?.toString().isNotEmpty == true
                  ? m['errorCause'].toString()
                  : '未知错误',
              'dir': m['dir'] == true,
            };
          }));
        _failPage = page;
        _failTotal = total;
        _failHasMore = list.length < total;
      });
    } catch (e) {
      Toast.show(e is ApiException ? e.message : '加载失败');
    } finally {
      if (mounted) setState(() => _failLoading = false);
    }
  }

  // ==================== 视图 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('任务详情', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadDetail),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildBaseCard(),
                  const SizedBox(height: 12),
                  _buildPathCard(),
                  const SizedBox(height: 12),
                  _buildStatsCard(),
                  if (_showFailDetails) ...[
                    const SizedBox(height: 12),
                    _buildFailCard(),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildBaseCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_taskName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
              Text(_status,
                  style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
            ],
          ),
          const Divider(height: 20, color: AppColors.border),
          _kvRow('开始时间', _startTime.isEmpty ? '-' : _startTime),
          _kvRow('结束时间', _endTime.isEmpty ? '-' : _endTime),
          _kvRow('传输用时', _time.isEmpty ? '-' : _time),
          _kvRow('时区', _timezone.isEmpty ? '-' : _timezone),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(k, style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          ),
        ],
      ),
    );
  }

  Widget _buildPathCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('传输路径', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _pathColumn(_sourceDriveType, _sourcePath, '源')),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 18, color: AppColors.primary),
              ),
              Expanded(child: _pathColumn(_destDriveType, _destPath, '目标')),
            ],
          ),
          if (_sourceItems.length > 1)
            GestureDetector(
              onTap: () => setState(() => _showAllSources = !_showAllSources),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _showAllSources ? '收起全部源' : '展开全部源（${_sourceItems.length} 项）',
                  style: const TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ),
            ),
          if (_showAllSources)
            ..._sourceItems.map((s) => Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    s['path']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _pathColumn(String driveType, String path, String label) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
        const SizedBox(height: 4),
        DriveIcon(driveType: driveType, size: 28),
        const SizedBox(height: 4),
        Text(
          path.isEmpty ? '-' : path,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textSub),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('传输统计', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              ),
              Text('成功率 $_successRate%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 12),
          _statGrid(),
          const Divider(height: 20, color: AppColors.border),
          _kvRow('总大小', _totalSize),
          _kvRow('成功大小', _successSize),
          _kvRow('跳过大小', _skipSize),
        ],
      ),
    );
  }

  Widget _statGrid() {
    Widget cell(String label, String value) {
      return Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
        ],
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            cell('文件夹 $_totalFolder', '$_successFolder'),
            cell('文件 $_totalFile', '$_successFile'),
            cell('跳过', '$_skipFile'),
          ],
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('（成功数 / 总数）', style: TextStyle(fontSize: 10, color: AppColors.textWeak)),
          ],
        ),
      ],
    );
  }

  Widget _buildFailCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('失败明细（$_failNumber 项）',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger)),
              ),
              if (!_showFailList)
                GestureDetector(
                  onTap: _openFailList,
                  child: const Text('查看', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                )
              else
                GestureDetector(
                  onTap: () => setState(() => _showFailList = false),
                  child: const Text('收起', style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
                ),
            ],
          ),
          if (_showFailList) ...[
            const SizedBox(height: 8),
            if (_failItems.isEmpty && _failLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              ),
            for (final it in _failItems)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          it['dir'] == true ? Icons.folder : Icons.insert_drive_file_outlined,
                          size: 13,
                          color: AppColors.textWeak,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            it['itemRelative']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.textMain),
                          ),
                        ),
                        Text(it['filesize'].toString(),
                            style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(it['errorCause']?.toString() ?? '',
                        style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                  ],
                ),
              ),
            if (_failHasMore)
              Center(
                child: TextButton(
                  onPressed: _failLoading ? null : () => _loadFailPage(_failPage + 1),
                  child: Text(_failLoading ? '加载中...' : '加载更多（$_failTotal 项）',
                      style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
