/// 云存储列表（对应 MP pages/cloud/list/list）
///
/// 卡片：图标/名称/SVIP 徽标/失效徽标/容量条；三点菜单（刷新容量/修改名称/
/// 解除授权并删除）；缓存优先渲染 + 异步刷账户信息。
library;

import 'package:flutter/material.dart';

import '../../api/drive_api.dart';
import '../../core/events.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class CloudListPage extends StatefulWidget {
  const CloudListPage({super.key});

  @override
  State<CloudListPage> createState() => _CloudListPageState();
}

class _CloudListPageState extends State<CloudListPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _drives = [];
  bool _loading = true;
  bool _isEmpty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UiEvents.driveListVersion.addListener(_onDrivesChanged);
    _loadDrives();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UiEvents.driveListVersion.removeListener(_onDrivesChanged);
    super.dispose();
  }

  /// 授权/删除后（含从浏览器完成 OAuth 回到前台）触发刷新
  void _onDrivesChanged() {
    _loadDrives(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 对应 MP onShow：从浏览器/其他应用切回时刷新（OAuth 授权在外部完成）
    if (state == AppLifecycleState.resumed) {
      _loadDrives(true);
    }
  }

  // ============ 数据加载（缓存优先） ============

  Future<void> _loadDrives([bool force = false]) async {
    // 游客态不发请求，直接空态（点击授权时由授权页提示登录）
    if (Store.getToken().isEmpty) {
      setState(() {
        _drives = [];
        _isEmpty = true;
        _loading = false;
      });
      return;
    }

    final cached = Store.getDrives();
    if (!force && cached != null && cached.isNotEmpty) {
      _renderDrives(cached, false);
      setState(() {
        _loading = false;
        _isEmpty = false;
      });
      return;
    }

    if (cached == null || cached.isEmpty) {
      setState(() => _loading = true);
    }

    try {
      final drives = await DriveApi.getDriveList();
      if (drives.isEmpty) {
        Store.clearDrives();
        setState(() {
          _drives = [];
          _isEmpty = true;
          _loading = false;
        });
        return;
      }
      Store.setDrives(drives);
      _renderDrives(drives, true);
      setState(() {
        _isEmpty = false;
        _loading = false;
      });
    } catch (_) {
      if (cached == null || cached.isEmpty) {
        setState(() {
          _loading = false;
          _isEmpty = true;
        });
      }
    }
  }

  void _renderDrives(List<dynamic> drives, bool refreshAccount) {
    final list = <Map<String, dynamic>>[];
    for (final d in drives) {
      final item = d is Map ? d : <String, dynamic>{};
      final driveType = (item['driveType'] ?? '').toString();
      final id = item['id'];
      final cachedAccount = Store.getDriveAccount(id);
      String usedText = '', totalText = '';
      int usagePercent = 0;
      bool invalid = false, svip = false;
      if (cachedAccount != null && !refreshAccount) {
        final totalSpace = (cachedAccount['totalSpace'] ?? 0) as num;
        final remainSpace = (cachedAccount['remainSpace'] ?? 0) as num;
        final usedSpace = totalSpace - remainSpace;
        usagePercent = totalSpace > 0
            ? (((usedSpace / totalSpace) * 100).floor()).clamp(0, 100)
            : 0;
        usedText = Formatters.formatFileSize(usedSpace, 1);
        totalText = Formatters.formatFileSize(totalSpace, 1);
        invalid = cachedAccount['invalid'] == true;
        svip = cachedAccount['svip'] == true;
      }
      list.add({
        'id': id,
        'driveType': driveType,
        'name': _driveName(item, driveType),
        'usedText': usedText,
        'totalText': totalText,
        'usagePercent': usagePercent,
        'invalid': invalid,
        'svip': svip,
        'svipLabel': driveType == 'guangya' ? 'VIP' : 'SVIP',
      });
    }
    setState(() => _drives = list);
    if (refreshAccount) _loadAccounts(list);
  }

  String _driveName(Map item, String driveType) {
    final username = item['driveUsername']?.toString() ?? '';
    return username.isNotEmpty
        ? username
        : (driveTypeNames[driveType] ?? (driveType.isEmpty ? '未知云存储' : driveType));
  }

  /// 并发刷新所有云盘账户信息
  void _loadAccounts(List<Map<String, dynamic>> drives) {
    for (var i = 0; i < drives.length; i++) {
      DriveApi.getDriveAccount(drives[i]['id']).then((account) {
        if (!mounted || account == null) return;
        Store.setDriveAccount(drives[i]['id'], account);
        _applyAccount(i, account);
      }).catchError((_) {});
    }
  }

  void _applyAccount(int idx, Map<String, dynamic> account) {
    final totalSpace = (account['totalSpace'] ?? 0) as num;
    final remainSpace = (account['remainSpace'] ?? 0) as num;
    final usedSpace = totalSpace - remainSpace;
    final percent = totalSpace > 0
        ? (((usedSpace / totalSpace) * 100).floor()).clamp(0, 100)
        : 0;
    if (idx < 0 || idx >= _drives.length) return;
    setState(() {
      _drives[idx]['usedText'] = Formatters.formatFileSize(usedSpace, 1);
      _drives[idx]['totalText'] = Formatters.formatFileSize(totalSpace, 1);
      _drives[idx]['usagePercent'] = percent;
      _drives[idx]['invalid'] = account['invalid'] == true;
      _drives[idx]['svip'] = account['svip'] == true;
    });
  }

  // ============ 交互 ============

  Future<void> _refreshDrives() async {
    Store.clearDrives();
    Store.clearDriveAccounts();
    await _loadDrives();
    Toast.show('已刷新');
  }

  void _openFiles(Map<String, dynamic> drive) {
    Navigator.pushNamed(context, '/cloud/files', arguments: {
      'authId': drive['id'],
      'name': drive['name'],
      'type': drive['driveType'],
    });
  }

  Future<void> _onDriveMenu(Map<String, dynamic> drive) async {
    final idx = await showActionSheet(context, actions: ['刷新容量', '修改名称', '解除授权并删除']);
    if (idx == null) return;
    if (idx == 0) {
      _refreshDriveAccount(drive);
    } else if (idx == 1) {
      _renameDriveDialog(drive);
    } else if (idx == 2) {
      _deleteDriveConfirm(drive);
    }
  }

  /// 刷新容量：先归零形成加载过渡，接口返回后覆盖
  Future<void> _refreshDriveAccount(Map<String, dynamic> drive) async {
    final idx = _drives.indexWhere((d) => d['id'] == drive['id']);
    if (idx == -1) return;
    setState(() {
      _drives[idx]['usedText'] = '0M';
      _drives[idx]['totalText'] = '0M';
      _drives[idx]['usagePercent'] = 0;
    });
    try {
      final account = await DriveApi.getDriveAccount(drive['id']);
      if (!mounted || account == null) return;
      Store.setDriveAccount(drive['id'], account);
      _applyAccount(idx, account);
      Toast.show('已刷新');
    } catch (_) {}
  }

  Future<void> _renameDriveDialog(Map<String, dynamic> drive) async {
    final newName = await showInputDialog(
      context,
      title: '修改名称',
      placeholder: '请输入名称',
      initialValue: drive['name']?.toString() ?? '',
    );
    if (newName == null) return;
    final name = newName.trim();
    if (name.isEmpty || name == drive['name']) return;
    try {
      await DriveApi.renameDrive(drive['id'], name);
      final idx = _drives.indexWhere((d) => d['id'] == drive['id']);
      if (idx != -1) setState(() => _drives[idx]['name'] = name);
      // 同步列表缓存（name 渲染自 driveUsername）
      final cached = Store.getDrives();
      if (cached != null) {
        for (final d in cached) {
          if (d is Map && d['id'] == drive['id']) {
            d['driveUsername'] = name;
          }
        }
        Store.setDrives(cached);
      }
      Toast.show('已修改');
    } catch (_) {}
  }

  Future<void> _deleteDriveConfirm(Map<String, dynamic> drive) async {
    final ok = await showConfirm(
      context,
      title: '解除授权并删除',
      content: '如果该云盘有任务正在进行中，移除云盘将会停止并删除与该云盘相关的所有任务，确定要继续移除吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    try {
      await DriveApi.deleteDrive(drive['id']);
      Store.removeDrive(drive['id']);
      Toast.show('已删除');
      _loadDrives();
    } catch (_) {
      Toast.show('删除失败');
    }
  }

  // ============ 视图 ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: '云存储',
              onRefresh: _refreshDrives,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _isEmpty || _drives.isEmpty
                      ? EmptyView(
                          text: '还没有添加云存储',
                          actionText: '去添加',
                          onAction: () => Navigator.pushNamed(context, '/cloud/add'),
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () => _loadDrives(true),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _drives.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _buildDriveCard(_drives[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveCard(Map<String, dynamic> drive) {
    final percent = (drive['usagePercent'] as int? ?? 0).clamp(0, 100);
    final invalid = drive['invalid'] == true;
    final svip = drive['svip'] == true;
    final driveType = drive['driveType']?.toString() ?? '';

    return AppCard(
      onLongPress: () => _deleteDriveConfirm(drive),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DriveIcon(driveType: driveType, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            drive['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMain,
                            ),
                          ),
                        ),
                        if (svip) ...[
                          const SizedBox(width: 6),
                          _buildBadge(
                            drive['svipLabel']?.toString() ?? 'SVIP',
                            AppColors.warning,
                          ),
                        ],
                        if (invalid) ...[
                          const SizedBox(width: 6),
                          const _InvalidBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${drive['usedText'] ?? ''} / ${drive['totalText'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
                    ),
                  ],
                ),
              ),
              // 三点菜单
              GestureDetector(
                onTap: () => _onDriveMenu(drive),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.more_horiz, size: 20, color: AppColors.textWeak),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 容量条
          GestureDetector(
            onTap: () => _openFiles(drive),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 6,
                  backgroundColor: AppColors.primaryLight,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _openFiles(drive),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.folder_open, size: 14, color: AppColors.primary),
                  SizedBox(width: 2),
                  Text('查看文件', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// 授权失效徽标（红色描边，对应 MP invalid 样式）
class _InvalidBadge extends StatelessWidget {
  const _InvalidBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.danger),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '已失效',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.danger),
      ),
    );
  }
}
