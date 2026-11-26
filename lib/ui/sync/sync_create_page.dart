/// 创建同步任务（对应 MP pages/sync/create/create）
///
/// Step1 选源（整盘 或 浏览单选文件夹，目录对目录）→ Step2 选目标
/// （整盘 / 浏览单选文件夹，百度目标限定 /apps/QianClouds）→ Step3
/// 命名+立即执行+定时计划（最多 2 个）。冲突策略固定 skip（对齐 Web 隐藏设置）。
library;

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

// 百度网盘作为目标盘的可写路径限制（与 Web 端 baiduPath 一致）
const String _kBaiduPathPrefix = '/apps/QianClouds';

class SyncCreatePage extends StatefulWidget {
  const SyncCreatePage({super.key});

  @override
  State<SyncCreatePage> createState() => _SyncCreatePageState();
}

class _SyncCreatePageState extends State<SyncCreatePage> {
  int _step = 1;
  List<Map<String, dynamic>> _drives = [];
  bool _drivesLoaded = false;

  // ===== 源（文件夹单选 或 整个云存储） =====
  String _sourceDriveId = '';
  String _sourceDriveName = '';
  bool _sourceSelected = false; // 是否进入浏览模式
  bool _sourceEntire = false; // 整盘作为源
  String _sourceRadioDriveId = ''; // 整盘单选
  String _folderId = 'myroot';
  List<Map<String, dynamic>> _routeList = [];
  List<Map<String, dynamic>> _items = [];
  String _sourceFolderId = '';
  String _sourceFolderName = '';
  bool _loadingItems = false;

  // ===== 目标 =====
  String _destDriveId = '';
  String _destDriveName = '';
  String _destDriveType = '';
  bool _destSelected = false;
  String _destRadioDriveId = '';
  String _destFolderId = 'myroot';
  List<Map<String, dynamic>> _destRouteList = [];
  List<Map<String, dynamic>> _destItems = [];
  String _destSelectedFolderId = '';
  String _destSelectedFolderName = '';
  String _destSelectedPathDisplay = '';
  bool _entireDest = false;

  // ===== 创建 =====
  String _taskName = '';
  bool _executeNow = true;
  List<Map<String, dynamic>> _plans = [];
  bool _submitting = false;
  final _nameController = TextEditingController();
  final GlobalKey<TimerPlansState> _plansKey = GlobalKey<TimerPlansState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_drivesLoaded) {
      _drivesLoaded = true;
      _loadDrives();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ==================== 云盘列表 ====================

  Future<void> _loadDrives() async {
    final cached = Store.getDrives();
    if (cached != null && cached.isNotEmpty) {
      _renderDrives(cached);
    }
    try {
      final drives = await DriveApi.getDriveList();
      if (drives.isNotEmpty) {
        Store.setDrives(drives);
        _renderDrives(drives);
      }
    } catch (_) {}
  }

  void _renderDrives(List<dynamic> drives) {
    final list = <Map<String, dynamic>>[];
    for (final d in drives) {
      final item = d is Map ? d : {};
      final driveType = item['driveType']?.toString() ?? '';
      final typeName = driveTypeNames[driveType] ?? (driveType.isEmpty ? '云存储' : driveType);
      final username = item['driveUsername']?.toString() ?? '';
      list.add({
        'id': item['id'].toString(),
        'driveType': driveType,
        'name': username.isNotEmpty ? username : typeName,
        'driveDetails': item['driveDetails']?.toString().isNotEmpty == true
            ? item['driveDetails'].toString()
            : typeName,
      });
    }
    setState(() => _drives = list);
  }

  // ==================== Step1: 源 ====================

  void _selectSourceEntireDrive(Map<String, dynamic> drive) {
    setState(() => _sourceRadioDriveId = drive['id'].toString());
  }

  void _confirmSourceEntireDrive() {
    final drive = _drives
        .where((d) => d['id'].toString() == _sourceRadioDriveId)
        .toList();
    if (drive.isEmpty) return;
    setState(() {
      _sourceDriveId = drive[0]['id'].toString();
      _sourceDriveName = drive[0]['name'].toString();
      _sourceEntire = true;
      _sourceSelected = false;
      _step = 2;
    });
  }

  void _selectSourceDrive(Map<String, dynamic> drive) {
    setState(() {
      _sourceDriveId = drive['id'].toString();
      _sourceDriveName = drive['name'].toString();
      _sourceEntire = false;
      _sourceSelected = true;
      _folderId = 'myroot';
      _routeList = [
        {'id': 'myroot', 'name': drive['name']}
      ];
      _sourceFolderId = '';
      _sourceFolderName = '';
      _items = [];
    });
    _loadSourceItems();
  }

  Future<void> _loadSourceItems() async {
    setState(() => _loadingItems = true);
    try {
      final result = await DriveApi.getDriveItemsCached(_sourceDriveId, _folderId);
      final data = result.data;
      final raw = (data is Map ? data['items'] : null) as List? ?? [];
      // 同步只支持目录对目录：仅列出文件夹（与 Web driveSpecialFolders 同口径）
      final items = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it is! Map || it['isDir'] != true) continue;
        final m = Map<String, dynamic>.from(it);
        m['_radioSelected'] = m['id'].toString() == _sourceFolderId;
        items.add(m);
      }
      setState(() {
        _items = items;
        _loadingItems = false;
      });
    } catch (e) {
      setState(() => _loadingItems = false);
      Toast.show(e is ApiException ? e.message : '文件夹加载失败');
    }
  }

  void _selectSourceFolder(Map<String, dynamic> item) {
    setState(() {
      _sourceFolderId = item['id'].toString();
      _sourceFolderName = item['name']?.toString() ?? '';
      for (final it in _items) {
        it['_radioSelected'] = it['id'].toString() == _sourceFolderId;
      }
    });
  }

  void _openSourceFolder(Map<String, dynamic> item) {
    if (item['isDir'] != true) return;
    final id = item['id'].toString();
    if (_routeList.any((r) => r['id'].toString() == id)) return;
    setState(() {
      _folderId = id;
      _routeList.add({'id': item['id'], 'name': item['name']});
      _sourceFolderId = '';
      _sourceFolderName = '';
      _items = [];
    });
    _loadSourceItems();
  }

  void _openSourceRoute(Map<String, dynamic> node) {
    final idx = _routeList.indexWhere((r) => r['id'].toString() == node['id'].toString());
    if (idx == -1) return;
    setState(() {
      _folderId = node['id'].toString();
      _routeList = _routeList.sublist(0, idx + 1);
      _sourceFolderId = '';
      _sourceFolderName = '';
      _items = [];
    });
    _loadSourceItems();
  }

  void _confirmSourceFolder() {
    if (_sourceFolderId.isEmpty) {
      Toast.show('请选择一个源目录');
      return;
    }
    setState(() => _step = 2);
  }

  // ==================== Step2: 目标 ====================

  void _selectDestEntireDrive(Map<String, dynamic> drive) {
    setState(() => _destRadioDriveId = drive['id'].toString());
  }

  void _confirmDestEntireDrive() {
    final drive = _drives
        .where((d) => d['id'].toString() == _destRadioDriveId)
        .toList();
    if (drive.isEmpty) return;
    // 百度网盘目标限定 /apps/QianClouds 子树，整个云存储（根）不可作为目标
    if (drive[0]['driveType'] == 'baidu') {
      _showBaiduRootTip();
      return;
    }
    setState(() {
      _destDriveId = drive[0]['id'].toString();
      _destDriveName = drive[0]['name'].toString();
      _destDriveType = drive[0]['driveType']?.toString() ?? '';
      _destSelected = false;
    });
    _entireDest = true;
    _goToStep3();
  }

  void _selectDestDrive(Map<String, dynamic> drive) {
    _entireDest = false;
    setState(() {
      _destDriveId = drive['id'].toString();
      _destDriveName = drive['name'].toString();
      _destDriveType = drive['driveType']?.toString() ?? '';
      _destSelected = true;
      _destFolderId = 'myroot';
      _destRouteList = [
        {'id': 'myroot', 'name': drive['name']}
      ];
      _destSelectedFolderId = '';
      _destSelectedFolderName = '';
      _destItems = [];
    });
    // 与 Web 一致：百度目标引导进入「我的应用数据」
    if (drive['driveType'] == 'baidu') {
      Toast.show('百度网盘目标请进入「我的应用数据/QianClouds」选择');
    }
    _loadDestItems();
  }

  Future<void> _loadDestItems() async {
    setState(() => _loadingItems = true);
    try {
      final result = await DriveApi.getDriveItemsCached(_destDriveId, _destFolderId);
      final data = result.data;
      final raw = (data is Map ? data['items'] : null) as List? ?? [];
      final items = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it is! Map || it['isDir'] != true) continue;
        final m = Map<String, dynamic>.from(it);
        m['_radioSelected'] = m['id'].toString() == _destSelectedFolderId;
        items.add(m);
      }
      setState(() {
        _destItems = items;
        _loadingItems = false;
      });
    } catch (e) {
      setState(() => _loadingItems = false);
      Toast.show(e is ApiException ? e.message : '文件夹加载失败');
    }
  }

  void _selectDestFolder(Map<String, dynamic> item) {
    _destSelectedPathDisplay = item['pathDisplay']?.toString() ?? '';
    setState(() {
      _destSelectedFolderId = item['id'].toString();
      _destSelectedFolderName = item['name']?.toString() ?? '';
      for (final it in _destItems) {
        it['_radioSelected'] = it['id'].toString() == _destSelectedFolderId;
      }
    });
  }

  void _openDestFolder(Map<String, dynamic> item) {
    if (item['isDir'] != true) return;
    final id = item['id'].toString();
    if (_destRouteList.any((r) => r['id'].toString() == id)) return;
    // 路径链携带 pathDisplay（百度目标校验用）
    setState(() {
      _destFolderId = id;
      _destRouteList.add({
        'id': item['id'],
        'name': item['name'],
        'pathDisplay': item['pathDisplay']?.toString() ?? '',
      });
      _destSelectedFolderId = '';
      _destSelectedFolderName = '';
      _destItems = [];
    });
    _loadDestItems();
  }

  void _openDestRoute(Map<String, dynamic> node) {
    final idx =
        _destRouteList.indexWhere((r) => r['id'].toString() == node['id'].toString());
    if (idx == -1) return;
    setState(() {
      _destFolderId = node['id'].toString();
      _destRouteList = _destRouteList.sublist(0, idx + 1);
      _destSelectedFolderId = '';
      _destSelectedFolderName = '';
      _destItems = [];
    });
    _loadDestItems();
  }

  void _showBaiduRootTip() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示', style: TextStyle(fontSize: 16)),
        content: const Text(
          '百度网盘作为目标时，只能选择「/我的应用数据/QianClouds」文件夹及子项',
          style: TextStyle(fontSize: 14, color: AppColors.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ==================== Step3: 创建 ====================

  void _goToStep3() {
    // 百度目标盘路径校验（与 Web 端 buildTask 校验一致）
    if (_destDriveType == 'baidu') {
      String pathDisplay = '';
      if (_destSelectedFolderId.isNotEmpty) {
        pathDisplay = _destSelectedPathDisplay;
      } else if (_destRouteList.isNotEmpty) {
        pathDisplay = _destRouteList.last['pathDisplay']?.toString() ?? '';
      }
      if (pathDisplay.isEmpty || !pathDisplay.startsWith(_kBaiduPathPrefix)) {
        _showBaiduRootTip();
        return;
      }
    }

    final folderId = _destSelectedFolderId.isNotEmpty ? _destSelectedFolderId : _destFolderId;
    final folderName = _destSelectedFolderName.isNotEmpty
        ? _destSelectedFolderName
        : (_destRouteList.isNotEmpty
            ? _destRouteList.last['name']?.toString() ?? '根目录'
            : '根目录');
    setState(() {
      _destFolderId = folderId;
      _destSelectedFolderName = folderName;
      _step = 3;
    });
    TransferApi.createSyncName().then((name) {
      if (!mounted) return;
      final n = name?.toString();
      setState(() {
        _taskName = (n != null && n.isNotEmpty) ? n : '同步任务${DateTime.now().millisecondsSinceEpoch}';
        _nameController.text = _taskName;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _taskName = '同步任务${DateTime.now().millisecondsSinceEpoch}';
        _nameController.text = _taskName;
      });
    });
  }

  Map<String, dynamic> _buildTimerModel(List<Map<String, dynamic>> plans) {
    if (plans.isEmpty) {
      return {'type': 'Now', 'timezone': currentTimezone(), 'plans': []};
    }
    return {
      'type': _executeNow ? 'Now' : 'Plan',
      'timezone': currentTimezone(),
      'plans': plans,
    };
  }

  Future<void> _submitCreate() async {
    if (_taskName.trim().isEmpty) {
      Toast.show('请输入任务名称');
      return;
    }
    final plans = _plansKey.currentState?.toPlans() ?? _plans;
    if (hasDuplicatePlans(plans)) {
      Toast.show('存在相同的定时计划，请修改');
      return;
    }
    // 未配置任何计划且未开启立即执行：与 Web「确认开始」弹窗一致
    if (plans.isEmpty && !_executeNow) {
      final ok = await showConfirm(
        context,
        title: '确认开始',
        content: '您未配置任何定时计划，是否立即执行一次？',
      );
      if (!ok) return;
      setState(() => _executeNow = true);
      _doCreate();
      return;
    }
    _doCreate();
  }

  Future<void> _doCreate() async {
    // VIP 专属功能（与 Web BuildSync startSync 一致）
    final mainGift = Store.getUserInfo()?['mainGift'];
    final isVip = mainGift is Map && mainGift['isVip'] == true;
    if (!isVip) {
      final upgrade = await showConfirm(
        context,
        title: '付费功能限制',
        content: '该功能为付费用户功能',
        confirmText: '升级订阅',
      );
      if (upgrade && mounted) {
        Navigator.pushNamed(context, '/gift/list');
      }
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    LoadingManager.show('创建中...');
    try {
      // 源 item（整个云存储 或 单选文件夹），nodeList=路径链
      Map<String, dynamic> sourceItem;
      if (_sourceEntire) {
        sourceItem = {
          'id': 'myroot',
          'name': _sourceDriveName,
          'isDir': true,
          'size': 0,
          'driveId': _sourceDriveId,
          'nodeList': [],
        };
      } else {
        sourceItem = {
          'id': _sourceFolderId,
          'name': _sourceFolderName,
          'isDir': true,
          'size': 0,
          'driveId': _sourceDriveId,
          'nodeList': _routeList,
        };
      }

      // 目标 item
      Map<String, dynamic> destinationItem;
      if (_entireDest) {
        destinationItem = {
          'id': 'myroot',
          'name': _destDriveName,
          'isDir': true,
          'size': 0,
          'driveId': _destDriveId,
          'nodeList': [],
        };
      } else if (_destSelectedFolderId.isNotEmpty) {
        destinationItem = {
          'id': _destSelectedFolderId,
          'name': _destSelectedFolderName,
          'isDir': true,
          'size': 0,
          'driveId': _destDriveId,
          'nodeList': _destRouteList,
        };
      } else {
        final lastRoute =
            _destRouteList.isNotEmpty ? _destRouteList.last : null;
        destinationItem = {
          'id': _destFolderId,
          'name': lastRoute != null ? lastRoute['name'] : '根目录',
          'isDir': true,
          'size': 0,
          'driveId': _destDriveId,
          'nodeList': _destRouteList,
        };
      }

      // 同步任务不提供冲突策略选择（对齐 Web：固定 skip）
      final actionModel = {
        'confict': 'skip',
        'notificationEmail': '',
        'filter': {'action': 'exclude', 'list': []},
      };

      final plans = _plansKey.currentState?.toPlans() ?? _plans;

      await TransferApi.createSync(
        _taskName,
        _sourceDriveId,
        sourceItem,
        _destDriveId,
        destinationItem,
        actionModel,
        1,
        _buildTimerModel(plans),
      );

      LoadingManager.hide();
      Toast.show('创建成功');
      // 清空同步列表缓存，并跳回同步任务 Tab
      Store.clearSyncList();
      UiEvents.bumpTasks();
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      Navigator.popUntil(context, (r) => r.isFirst);
      UiEvents.switchTab(2);
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '创建失败');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goBack() {
    // 浏览模式：先退回云盘列表
    if (_step == 1 && _sourceSelected) {
      setState(() {
        _sourceSelected = false;
        _sourceFolderId = '';
        _sourceFolderName = '';
        _items = [];
      });
      return;
    }
    if (_step == 2 && _destSelected) {
      setState(() {
        _destSelected = false;
        _destSelectedFolderId = '';
        _destSelectedFolderName = '';
        _destItems = [];
      });
      return;
    }
    // 从目标返回：已确认整盘源时回到 Step1 重新选源
    if (_step == 2 && _sourceEntire) {
      setState(() {
        _step = 1;
        _sourceRadioDriveId = '';
      });
      return;
    }
    if (_step > 1) {
      setState(() => _step = _step - 1);
    } else {
      Navigator.pop(context);
    }
  }

  // ==================== 视图 ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(
          title: Text('创建同步任务 $_step/3', style: const TextStyle(fontSize: 16)),
          leading: BackButton(onPressed: _goBack),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildStepIndicator(),
              Expanded(
                child: switch (_step) {
                  1 => _sourceSelected ? _buildSourceBrowser() : _buildDrivePickList(isDest: false),
                  2 => _destSelected ? _buildDestBrowser() : _buildDrivePickList(isDest: true),
                  _ => _buildStep3Form(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          _stepDot(1, '选择源'),
          _stepLine(1),
          _stepDot(2, '选择目标'),
          _stepLine(2),
          _stepDot(3, '创建'),
        ],
      ),
    );
  }

  Widget _stepDot(int n, String label) {
    final active = _step >= n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.primary : AppColors.border,
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: active ? AppColors.textMain : AppColors.textWeak)),
      ],
    );
  }

  Widget _stepLine(int before) {
    return Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: _step > before ? AppColors.primary : AppColors.border,
      ),
    );
  }

  /// 云盘选择列表（Step1/Step2 共用）：左 radio 整盘选择，右「浏览」进目录
  Widget _buildDrivePickList({required bool isDest}) {
    final radioId = isDest ? _destRadioDriveId : _sourceRadioDriveId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Text(
            isDest ? '选择目标云存储（整个云存储或浏览选择文件夹）' : '选择源云存储（整个云存储或浏览选择文件夹）',
            style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: _drives.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final drive = _drives[i];
              final checked = drive['id'].toString() == radioId;
              return AppCard(
                onTap: () =>
                    isDest ? _selectDestEntireDrive(drive) : _selectSourceEntireDrive(drive),
                child: Row(
                  children: [
                    Icon(
                      checked ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20,
                      color: checked ? AppColors.primary : AppColors.border,
                    ),
                    const SizedBox(width: 10),
                    DriveIcon(driveType: drive['driveType']?.toString(), size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        drive['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textMain),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => isDest ? _selectDestDrive(drive) : _selectSourceDrive(drive),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary.withValues(alpha:0.5)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text('浏览', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        _buildBottomBar(
          text: isDest ? '选择该云存储' : '确认选择整盘',
          enabled: radioId.isNotEmpty,
          onTap: isDest ? _confirmDestEntireDrive : _confirmSourceEntireDrive,
        ),
      ],
    );
  }

  Widget _buildBottomBar({required String text, required bool enabled, required VoidCallback onTap}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          text: text,
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }

  /// 源文件夹浏览（仅文件夹，单选）
  Widget _buildSourceBrowser() {
    return Column(
      children: [
        _buildBreadcrumb(
          _routeList,
          onNode: _openSourceRoute,
          trailing: _sourceFolderId.isNotEmpty ? '已选：$_sourceFolderName' : null,
        ),
        Expanded(
          child: _loadingItems
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _items.isEmpty
                  ? const EmptyView(text: '没有子文件夹')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: AppColors.border.withValues(alpha:0.5)),
                      itemBuilder: (_, i) => _buildFolderRow(
                        _items[i],
                        selected: _items[i]['_radioSelected'] == true,
                        onSelect: () => _selectSourceFolder(_items[i]),
                        onOpen: () => _openSourceFolder(_items[i]),
                      ),
                    ),
        ),
        _buildBottomBar(
          text: _sourceFolderId.isNotEmpty ? '选择该文件夹' : '下一步',
          enabled: true,
          onTap: _confirmSourceFolder,
        ),
      ],
    );
  }

  /// 目标文件夹浏览（仅文件夹，单选）
  Widget _buildDestBrowser() {
    final currentName = _destSelectedFolderId.isNotEmpty
        ? _destSelectedFolderName
        : (_destRouteList.isNotEmpty ? _destRouteList.last['name']?.toString() ?? '' : '');
    return Column(
      children: [
        _buildBreadcrumb(
          _destRouteList,
          onNode: _openDestRoute,
          trailing: '当前：$currentName',
        ),
        Expanded(
          child: _loadingItems
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _destItems.isEmpty
                  ? const EmptyView(text: '没有子文件夹')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: _destItems.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: AppColors.border.withValues(alpha:0.5)),
                      itemBuilder: (_, i) => _buildFolderRow(
                        _destItems[i],
                        selected: _destItems[i]['_radioSelected'] == true,
                        onSelect: () => _selectDestFolder(_destItems[i]),
                        onOpen: () => _openDestFolder(_destItems[i]),
                      ),
                    ),
        ),
        _buildBottomBar(
          text: _destSelectedFolderId.isNotEmpty ? '选择该文件夹' : '选择当前目录',
          enabled: true,
          onTap: _goToStep3,
        ),
      ],
    );
  }

  Widget _buildFolderRow(
    Map<String, dynamic> item, {
    required bool selected,
    required VoidCallback onSelect,
    required VoidCallback onOpen,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: onSelect,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              const SizedBox(width: 10),
              const FileTypeBadge(type: 'folder'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: AppColors.textMain),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.border),
            ],
          ),
        ),
      ),
    );
  }

  /// 面包屑（横向滚动 + 右侧附加信息）
  Widget _buildBreadcrumb(List<Map<String, dynamic>> routeList,
      {required void Function(Map<String, dynamic>) onNode, String? trailing}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 22,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: routeList.length,
                itemBuilder: (_, i) {
                  final node = routeList[i];
                  final isLast = i == routeList.length - 1;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: isLast ? null : () => onNode(node),
                        child: Text(
                          node['name']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isLast ? AppColors.textMain : AppColors.primary,
                            fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (!isLast)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.chevron_right, size: 14, color: AppColors.textWeak),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (trailing != null && trailing.isNotEmpty)
            Text(trailing, style: const TextStyle(fontSize: 11, color: AppColors.primary)),
        ],
      ),
    );
  }

  /// Step3 表单
  Widget _buildStep3Form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        // 源/目标概览
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: _buildPathColumn(
                  _sourceDriveName,
                  _sourceEntire ? '整个云存储' : _sourceFolderName,
                ),
              ),
              const Icon(Icons.sync_alt, size: 18, color: AppColors.primary),
              Expanded(
                child: _buildPathColumn(
                  _destDriveName,
                  _entireDest
                      ? '整个云存储'
                      : (_destSelectedFolderId.isNotEmpty
                          ? _destSelectedFolderName
                          : (_destRouteList.isNotEmpty
                              ? _destRouteList.last['name']?.toString() ?? ''
                              : '')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 任务名
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('任务名称', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                onChanged: (v) => _taskName = v,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.pageBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 立即执行 + 定时计划
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('立即执行', style: TextStyle(fontSize: 14, color: AppColors.textMain)),
                  ),
                  Switch(
                    value: _executeNow,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setState(() => _executeNow = v),
                  ),
                ],
              ),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 10),
              TimerPlans(
                key: _plansKey,
                max: 2,
                onChanged: (plans) => _plans = plans,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          text: _submitting ? '创建中...' : '开始同步',
          onTap: _submitting ? null : _submitCreate,
        ),
      ],
    );
  }

  Widget _buildPathColumn(String title, String sub) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
        const SizedBox(height: 4),
        Text(
          sub.isEmpty ? '/' : sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
        ),
      ],
    );
  }
}
