/// 创建传输任务（对应 MP pages/transfer/create/create）
///
/// Step1 选源（整盘单选 / 浏览多选）→ Step2 选目标（整盘 / 浏览选文件夹）
/// → Step3 命名+冲突策略提交。支持文件页「传输到」预设源直达 Step2。
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

class TransferCreatePage extends StatefulWidget {
  const TransferCreatePage({super.key});

  @override
  State<TransferCreatePage> createState() => _TransferCreatePageState();
}

class _TransferCreatePageState extends State<TransferCreatePage> {
  int _step = 1;
  List<Map<String, dynamic>> _drives = [];

  // ===== 源 =====
  String _sourceDriveId = '';
  String _sourceDriveName = '';
  String _sourceDriveDetails = '';
  bool _sourceSelected = false; // 是否进入浏览模式
  String _sourceRadioDriveId = ''; // 整盘单选
  String _folderId = 'myroot';
  List<Map<String, dynamic>> _routeList = [];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _selectedItems = [];
  bool _loadingItems = false;
  bool _presetSource = false;

  // ===== 目标 =====
  String _destDriveId = '';
  String _destDriveName = '';
  String _destDriveDetails = '';
  bool _destSelected = false;
  String _destRadioDriveId = '';
  String _destFolderId = 'myroot';
  List<Map<String, dynamic>> _destRouteList = [];
  List<Map<String, dynamic>> _destItems = [];
  String _destSelectedFolderId = '';
  String _destSelectedFolderName = '';

  // ===== 创建 =====
  String _taskName = '';
  String _conflict = 'skip';
  bool _showSettings = false;
  bool _submitting = false;
  final _nameController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_drives.isEmpty && !_drivesLoaded) {
      _drivesLoaded = true;
      _handlePreset();
      _loadDrives();
    }
  }

  bool _drivesLoaded = false;

  void _handlePreset() {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null || args['preset'] != true || args['driveId'] == null) return;
    final item = args['item'];
    final nodeList = args['nodeList'];
    if (item is Map && item['id'] != null) {
      final driveType = args['driveType']?.toString() ?? '';
      final typeName = driveTypeNames[driveType] ?? (driveType.isEmpty ? '云存储' : driveType);
      _presetSource = true;
      _sourceDriveId = args['driveId'].toString();
      _sourceDriveName = args['driveName']?.toString().isNotEmpty == true
          ? args['driveName'].toString()
          : typeName;
      _sourceDriveDetails = typeName;
      _routeList = nodeList is List && nodeList.isNotEmpty
          ? nodeList.map((r) => Map<String, dynamic>.from(r as Map)).toList()
          : [
              {'id': 'myroot', 'name': typeName}
            ];
      _selectedItems = [
        {
          'id': item['id'],
          'name': item['name'],
          'isDir': item['isDir'] == true,
          'size': item['size'] ?? 0,
        }
      ];
      _step = 2;
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
      final id = item['id'].toString();
      final typeName = driveTypeNames[driveType] ?? (driveType.isEmpty ? '云存储' : driveType);
      final username = item['driveUsername']?.toString() ?? '';
      list.add({
        'id': id,
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
    final drive = _drives.where((d) => d['id'].toString() == _sourceRadioDriveId).toList();
    if (drive.isEmpty) return;
    setState(() {
      _sourceDriveId = drive[0]['id'].toString();
      _sourceDriveName = drive[0]['name'].toString();
      _sourceDriveDetails = drive[0]['driveDetails'].toString();
      _routeList = [
        {'id': 'myroot', 'name': drive[0]['name']}
      ];
      _selectedItems = [
        {'id': 'myroot', 'name': '整个云存储', 'isDir': true, 'size': 0}
      ];
      _step = 2;
    });
  }

  void _selectSourceDrive(Map<String, dynamic> drive) {
    setState(() {
      _sourceDriveId = drive['id'].toString();
      _sourceDriveName = drive['name'].toString();
      _sourceDriveDetails = drive['driveDetails'].toString();
      _sourceSelected = true;
      _folderId = 'myroot';
      _routeList = [
        {'id': 'myroot', 'name': drive['name']}
      ];
      _selectedItems = [];
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
      final items = <Map<String, dynamic>>[];
      for (final it in raw) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final isDir = m['isDir'] == true;
        m['_fileType'] = isDir ? 'folder' : Formatters.getFileType(m['name']?.toString() ?? '');
        final size = m['size'];
        m['_fileSize'] = size != null && (size as num) > 0
            ? Formatters.formatFileSize(size, 1)
            : '';
        m['_selected'] = _selectedItems.any((s) => s['id'] == m['id']);
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

  void _openSourceFolder(Map<String, dynamic> item) {
    if (item['isDir'] != true) return;
    final id = item['id'].toString();
    if (_routeList.any((r) => r['id'].toString() == id)) return;
    setState(() {
      _folderId = id;
      _routeList.add({'id': item['id'], 'name': item['name']});
      _items = [];
      _selectedItems = [];
    });
    _loadSourceItems();
  }

  void _openSourceRoute(Map<String, dynamic> node) {
    final idx = _routeList.indexWhere((r) => r['id'].toString() == node['id'].toString());
    if (idx == -1) return;
    setState(() {
      _folderId = node['id'].toString();
      _routeList = _routeList.sublist(0, idx + 1);
      _items = [];
      _selectedItems = [];
    });
    _loadSourceItems();
  }

  void _toggleSelectItem(Map<String, dynamic> item) {
    setState(() {
      final idx = _selectedItems.indexWhere((s) => s['id'] == item['id']);
      if (idx > -1) {
        _selectedItems.removeAt(idx);
      } else {
        _selectedItems.add({
          'id': item['id'],
          'name': item['name'],
          'size': item['size'] ?? 0,
          'isDir': item['isDir'] == true,
        });
      }
      for (final it in _items) {
        it['_selected'] = _selectedItems.any((s) => s['id'] == it['id']);
      }
    });
  }

  void _goToStep2() {
    if (_selectedItems.isEmpty) {
      Toast.show('请至少选择一个文件或文件夹');
      return;
    }
    setState(() => _step = 2);
  }

  // ==================== Step2: 目标 ====================

  void _selectDestEntireDrive(Map<String, dynamic> drive) {
    setState(() => _destRadioDriveId = drive['id'].toString());
  }

  void _confirmDestEntireDrive() {
    final drive = _drives.where((d) => d['id'].toString() == _destRadioDriveId).toList();
    if (drive.isEmpty) return;
    setState(() {
      _destDriveId = drive[0]['id'].toString();
      _destDriveName = drive[0]['name'].toString();
      _destDriveDetails = drive[0]['driveDetails'].toString();
      _destFolderId = 'myroot';
      _destRouteList = [
        {'id': 'myroot', 'name': drive[0]['name']}
      ];
      _destSelectedFolderId = '';
      _destSelectedFolderName = '';
    });
    _goToStep3();
  }

  void _selectDestDrive(Map<String, dynamic> drive) {
    setState(() {
      _destDriveId = drive['id'].toString();
      _destDriveName = drive['name'].toString();
      _destDriveDetails = drive['driveDetails'].toString();
      _destSelected = true;
      _destFolderId = 'myroot';
      _destRouteList = [
        {'id': 'myroot', 'name': drive['name']}
      ];
      _destSelectedFolderId = '';
      _destSelectedFolderName = '';
      _destItems = [];
    });
    _loadDestItems();
  }

  Future<void> _loadDestItems() async {
    setState(() => _loadingItems = true);
    try {
      final result = await DriveApi.getDriveItemsCached(_destDriveId, _destFolderId);
      final data = result.data;
      final raw = (data is Map ? data['items'] : null) as List? ?? [];
      // 目标只展示文件夹
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
    setState(() {
      _destFolderId = id;
      _destRouteList.add({'id': item['id'], 'name': item['name']});
      _destSelectedFolderId = '';
      _destSelectedFolderName = '';
      _destItems = [];
    });
    _loadDestItems();
  }

  void _openDestRoute(Map<String, dynamic> node) {
    final idx = _destRouteList.indexWhere((r) => r['id'].toString() == node['id'].toString());
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

  // ==================== Step3: 创建 ====================

  void _goToStep3() {
    // 目标文件夹：优先单选的，否则当前目录
    setState(() {
      _destFolderId = _destSelectedFolderId.isNotEmpty
          ? _destSelectedFolderId
          : _destFolderId;
      _step = 3;
    });
    TransferApi.createTransferName().then((name) {
      if (!mounted) return;
      final n = name?.toString();
      setState(() {
        _taskName = (n != null && n.isNotEmpty) ? n : '传输任务${DateTime.now().millisecondsSinceEpoch}';
        _nameController.text = _taskName;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _taskName = '传输任务${DateTime.now().millisecondsSinceEpoch}';
        _nameController.text = _taskName;
      });
    });
  }

  Future<void> _submitCreate() async {
    if (_taskName.trim().isEmpty) {
      Toast.show('请输入任务名称');
      return;
    }
    // 免费用户不支持文件夹作为源
    final mainGift = Store.getUserInfo()?['mainGift'];
    final isVip = mainGift is Map && mainGift['isVip'] == true;
    if (!isVip && _selectedItems.any((item) => item['isDir'] == true)) {
      final upgrade = await showConfirm(
        context,
        title: '付费功能限制',
        content: '免费用户不支持文件夹作为源，请升级订阅或选择单个文件',
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
      final sourceItems = _selectedItems.map((item) => {
            'id': item['id'],
            'name': item['name'],
            'isDir': item['isDir'] == true,
            'size': item['size'] ?? 0,
            'driveId': _sourceDriveId,
            'nodeList': _routeList,
          }).toList();

      Map<String, dynamic> destinationItem;
      if (_destSelectedFolderId.isNotEmpty) {
        destinationItem = {
          'id': _destSelectedFolderId,
          'name': _destSelectedFolderName,
          'driveId': _destDriveId,
          'nodeList': _destRouteList,
        };
      } else {
        final lastRoute = _destRouteList.isNotEmpty
            ? _destRouteList[_destRouteList.length - 1]
            : null;
        destinationItem = {
          'id': _destFolderId,
          'name': lastRoute != null ? lastRoute['name'] : '根目录',
          'driveId': _destDriveId,
          'nodeList': _destRouteList,
        };
      }

      final actionModel = {
        'confict': _conflict,
        'notificationEmail': '',
        'filter': {'action': 'exclude', 'list': []},
      };

      // 任务名追加(源云盘-目标云盘)
      final taskDetailsName =
          '$_taskName($_sourceDriveDetails-$_destDriveDetails)';

      await TransferApi.createTransfer(
        taskDetailsName,
        _sourceDriveId,
        sourceItems,
        _destDriveId,
        destinationItem,
        actionModel,
        null,
      );

      LoadingManager.hide();
      Toast.show('创建成功');
      Store.clearTransferList();
      UiEvents.bumpTasks();
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      if (_presetSource) {
        // 「传输到」进入：回到根并切到传输 Tab
        Navigator.popUntil(context, (r) => r.isFirst);
        UiEvents.switchTab(1);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '创建失败');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goBack() {
    // 预设源：Step2 返回即退出创建页
    if (_presetSource && _step == 2) {
      Navigator.pop(context);
      return;
    }
    if (_sourceSelected && _step == 1) {
      setState(() {
        _sourceSelected = false;
        _selectedItems = [];
      });
      return;
    }
    if (_destSelected && _step == 2) {
      setState(() {
        _destSelected = false;
        _destSelectedFolderId = '';
        _destSelectedFolderName = '';
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
          title: Text('创建传输任务 $_step/3', style: const TextStyle(fontSize: 16)),
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
            isDest ? '选择目标云存储（整个云存储或浏览选择文件夹）' : '选择源云存储（整个云存储或浏览选择文件）',
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
                onTap: () => isDest ? _selectDestEntireDrive(drive) : _selectSourceEntireDrive(drive),
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
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textMain),
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

  /// 源文件浏览（多选）
  Widget _buildSourceBrowser() {
    return Column(
      children: [
        _buildBreadcrumb(
          _routeList,
          onNode: _openSourceRoute,
          trailing: '已选 ${_selectedItems.length} 项',
        ),
        Expanded(
          child: _loadingItems
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _items.isEmpty
                  ? const EmptyView(text: '文件夹为空')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: AppColors.border.withValues(alpha:0.5)),
                      itemBuilder: (_, i) => _buildSourceItemRow(_items[i]),
                    ),
        ),
        _buildBottomBar(
          text: '下一步（已选 ${_selectedItems.length} 项）',
          enabled: _selectedItems.isNotEmpty,
          onTap: _goToStep2,
        ),
      ],
    );
  }

  Widget _buildSourceItemRow(Map<String, dynamic> item) {
    final selected = item['_selected'] == true;
    final isDir = item['isDir'] == true;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => isDir ? _openSourceFolder(item) : _toggleSelectItem(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _toggleSelectItem(item),
                child: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              const SizedBox(width: 10),
              FileTypeBadge(type: item['_fileType']?.toString() ?? 'file'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: AppColors.textMain),
                ),
              ),
              if ((item['_fileSize'] ?? '').toString().isNotEmpty)
                Text(item['_fileSize'].toString(),
                    style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
            ],
          ),
        ),
      ),
    );
  }

  /// 目标文件夹浏览（仅文件夹，单选）
  Widget _buildDestBrowser() {
    final selectedName = _destSelectedFolderId.isNotEmpty
        ? _destSelectedFolderName
        : (_destRouteList.isNotEmpty ? _destRouteList.last['name']?.toString() : '');
    return Column(
      children: [
        _buildBreadcrumb(
          _destRouteList,
          onNode: _openDestRoute,
          trailing: '当前：${selectedName ?? ''}',
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
                      itemBuilder: (_, i) => _buildDestItemRow(_destItems[i]),
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

  Widget _buildDestItemRow(Map<String, dynamic> item) {
    final selected = item['_radioSelected'] == true;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openDestFolder(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _selectDestFolder(item),
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
                child: _buildPathColumn(_sourceDriveName, _summarizeItems(_selectedItems)),
              ),
              const Icon(Icons.arrow_forward, size: 18, color: AppColors.primary),
              Expanded(
                child: _buildPathColumn(
                  _destDriveName,
                  _destSelectedFolderId.isNotEmpty
                      ? _destSelectedFolderName
                      : (_destRouteList.isNotEmpty ? _destRouteList.last['name']?.toString() ?? '' : ''),
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
        // 文件策略（冲突处理）
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => setState(() => _showSettings = !_showSettings),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('文件策略', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                    ),
                    Icon(
                      _showSettings ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.textWeak,
                    ),
                  ],
                ),
              ),
              if (_showSettings) ...[
                const SizedBox(height: 4),
                _buildConflictOption('skip', '跳过', '同名文件跳过，速度更快'),
                _buildConflictOption('rename', '重命名', '同名文件保留两份'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          text: _submitting ? '创建中...' : '开始传输',
          onTap: _submitting ? null : _submitCreate,
        ),
      ],
    );
  }

  String _summarizeItems(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0]['name']?.toString() ?? '';
    return '${items[0]['name']} 等${items.length}项';
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

  Widget _buildConflictOption(String value, String title, String desc) {
    final checked = _conflict == value;
    return GestureDetector(
      onTap: () => setState(() => _conflict = value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: checked ? AppColors.primary : AppColors.border,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: AppColors.textMain)),
                  Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
