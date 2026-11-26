/// 云存储列表 / 首页（对应 MP pages/cloud/list/list）
///
/// 结构：问候页头（刷新 / 添加）→ 总容量概览卡 → 云盘卡片列表。
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

// ============ 首页专用设计令牌 ============

/// 标题墨色（比 textMain 略深、偏蓝，大标题更有层次）
const Color _ink = Color(0xFF1D2233);

/// 主色渐变（概览卡 / 添加按钮 / 容量条）
const List<Color> _brandGradient = [Color(0xFF6C96FF), Color(0xFF3F63F0)];

const double _cardRadius = 18;

/// 卡片柔和投影
List<BoxShadow> get _softShadow => [
      BoxShadow(
        color: const Color(0xFF1F3A8A).withValues(alpha: 0.06),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ];

class CloudListPage extends StatefulWidget {
  const CloudListPage({super.key});

  @override
  State<CloudListPage> createState() => _CloudListPageState();
}

class _CloudListPageState extends State<CloudListPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _drives = [];
  bool _loading = true;
  bool _isEmpty = false;
  bool _refreshing = false;

  /// 页头刷新按钮旋转动画
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

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
    _spin.dispose();
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
      if (!mounted) return;
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
      if (!mounted) return;
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
      list.add({
        'id': id,
        'driveType': driveType,
        'name': _driveName(item, driveType),
        'typeName': driveTypeNames[driveType] ?? '',
        'svipLabel': driveType == 'guangya' ? 'VIP' : 'SVIP',
        // 有缓存先用缓存渲染，刷新结果返回后再覆盖，避免容量闪空
        ..._accountFields(Store.getDriveAccount(id)),
        'accountLoading': refreshAccount,
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

  static num _toNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 账户信息 → 卡片展示字段（account 为空表示尚未取到容量）
  Map<String, dynamic> _accountFields(Map<String, dynamic>? account) {
    if (account == null) {
      return {
        'hasAccount': false,
        'usedBytes': 0,
        'totalBytes': 0,
        'usedText': '',
        'totalText': '',
        'usagePercent': 0,
        'invalid': false,
        'svip': false,
      };
    }
    final total = _toNum(account['totalSpace']);
    final remain = _toNum(account['remainSpace']);
    final num used = total - remain < 0 ? 0 : total - remain;
    final percent =
        total > 0 ? ((used / total) * 100).floor().clamp(0, 100).toInt() : 0;
    return {
      'hasAccount': true,
      'usedBytes': used,
      'totalBytes': total,
      'usedText': Formatters.formatFileSize(used, 1),
      'totalText': Formatters.formatFileSize(total, 1),
      'usagePercent': percent,
      'invalid': account['invalid'] == true,
      'svip': account['svip'] == true,
    };
  }

  /// 并发刷新所有云盘账户信息
  void _loadAccounts(List<Map<String, dynamic>> drives) {
    for (final drive in drives) {
      final id = drive['id'];
      DriveApi.getDriveAccount(id).then((account) {
        if (!mounted) return;
        if (account != null) Store.setDriveAccount(id, account);
        _applyAccount(id, account);
      }).catchError((_) {
        if (mounted) _applyAccount(id, null);
      });
    }
  }

  /// 回填账户信息；account 为空时仅结束该卡片的加载态
  void _applyAccount(dynamic id, Map<String, dynamic>? account) {
    final idx = _drives.indexWhere((d) => d['id'] == id);
    if (idx == -1) return;
    setState(() {
      if (account != null) _drives[idx].addAll(_accountFields(account));
      _drives[idx]['accountLoading'] = false;
    });
  }

  // ============ 交互 ============

  Future<void> _refreshDrives() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    _spin.repeat();
    Store.clearDrives();
    Store.clearDriveAccounts();
    await _loadDrives();
    if (!mounted) return;
    _spin
      ..stop()
      ..reset();
    setState(() => _refreshing = false);
    Toast.show('已刷新');
  }

  void _openAdd() => Navigator.pushNamed(context, '/cloud/add');

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

  /// 刷新容量：卡片进入加载态，接口返回后覆盖
  Future<void> _refreshDriveAccount(Map<String, dynamic> drive) async {
    final id = drive['id'];
    final idx = _drives.indexWhere((d) => d['id'] == id);
    if (idx == -1) return;
    setState(() => _drives[idx]['accountLoading'] = true);
    try {
      final account = await DriveApi.getDriveAccount(id);
      if (!mounted) return;
      if (account != null) Store.setDriveAccount(id, account);
      _applyAccount(id, account);
      if (account != null) Toast.show('已刷新');
    } catch (_) {
      if (mounted) _applyAccount(id, null);
    }
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
      if (!mounted) return;
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

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 13) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final showEmpty = _isEmpty || _drives.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Stack(
        children: [
          // 顶部淡蓝氛围渐变，向下融入页面底色
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE3EBFF), AppColors.pageBg],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? const _HomeSkeleton()
                      : RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: Colors.white,
                          onRefresh: () => _loadDrives(true),
                          child: showEmpty ? _buildEmpty() : _buildList(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textWeak,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '云存储',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          _RoundButton(
            tooltip: '刷新',
            onTap: _refreshDrives,
            child: RotationTransition(
              turns: _spin,
              child: const Icon(Icons.refresh_rounded, size: 20, color: _ink),
            ),
          ),
          const SizedBox(width: 10),
          _RoundButton(
            tooltip: '添加云存储',
            filled: true,
            onTap: _openAdd,
            child: const Icon(Icons.add_rounded, size: 22, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      // 概览卡 + 分组标题 + 云盘卡片
      itemCount: _drives.length + 2,
      itemBuilder: (_, i) {
        if (i == 0) return _buildSummaryCard();
        if (i == 1) return _buildSectionTitle();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildDriveCard(_drives[i - 2]),
        );
      },
    );
  }

  /// 总容量概览卡（汇总所有已取到容量的云盘）
  Widget _buildSummaryCard() {
    num used = 0, total = 0;
    var invalidCount = 0;
    for (final d in _drives) {
      used += (d['usedBytes'] as num?) ?? 0;
      total += (d['totalBytes'] as num?) ?? 0;
      if (d['invalid'] == true) invalidCount++;
    }
    final hasTotal = total > 0;
    final ratio = hasTotal ? (used / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final percent = (ratio * 100).floor();

    // "12.3 GB" → 数字大、单位小
    final usedParts =
        hasTotal ? Formatters.formatFileSize(used, 1).split(' ') : const ['--'];
    final remainText = hasTotal ? Formatters.formatFileSize(total - used, 1) : '--';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _brandGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 装饰光斑
          Positioned(
            right: -46,
            top: -56,
            child: _glowCircle(170, 0.10),
          ),
          Positioned(
            right: 36,
            bottom: -84,
            child: _glowCircle(150, 0.07),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '已用空间',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_done_rounded, size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${_drives.length} 个云盘',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      usedParts.first,
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (usedParts.length > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        usedParts[1],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                    if (hasTotal) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '/ ${Formatters.formatFileSize(total, 1)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _UsageBar(
                  value: ratio,
                  height: 8,
                  trackColor: Colors.white.withValues(alpha: 0.22),
                  colors: const [Colors.white, Colors.white],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      hasTotal ? '已使用 $percent%' : '容量统计中…',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    if (invalidCount > 0) ...[
                      const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFFFE08A)),
                      const SizedBox(width: 3),
                      Text(
                        '$invalidCount 个授权失效',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFFFE08A),
                        ),
                      ),
                    ] else
                      Text(
                        '剩余 $remainText',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
      child: Row(
        children: [
          const Text(
            '我的云盘',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_drives.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriveCard(Map<String, dynamic> drive) {
    final percent = ((drive['usagePercent'] as num?) ?? 0).clamp(0, 100).toInt();
    final invalid = drive['invalid'] == true;
    final svip = drive['svip'] == true;
    final hasAccount = drive['hasAccount'] == true;
    final accountLoading = drive['accountLoading'] == true;
    final driveType = drive['driveType']?.toString() ?? '';
    final name = drive['name']?.toString() ?? '';
    final typeName = drive['typeName']?.toString() ?? '';
    // 名称与类型名相同时不重复展示
    final subtitle = typeName.isNotEmpty && typeName != name ? typeName : '点击查看文件';

    // 容量告警色：≥95% 红，≥80% 橙，其余品牌蓝
    final Color usageColor;
    final List<Color> barColors;
    if (percent >= 95) {
      usageColor = AppColors.danger;
      barColors = const [Color(0xFFFF8A8B), AppColors.danger];
    } else if (percent >= 80) {
      usageColor = AppColors.warning;
      barColors = const [Color(0xFFFFC15C), AppColors.warning];
    } else {
      usageColor = AppColors.primary;
      barColors = const [Color(0xFF7FA6FF), AppColors.primary];
    }

    final String capacityText;
    if (hasAccount) {
      capacityText = '${drive['usedText']} / ${drive['totalText']}';
    } else {
      capacityText = accountLoading ? '容量获取中…' : '暂无容量信息';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: _softShadow,
      ),
      child: Material(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(_cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openFiles(drive),
          onLongPress: () => _deleteDriveConfirm(drive),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // 图标底座
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6FC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: DriveIcon(driveType: driveType, size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _ink,
                                  ),
                                ),
                              ),
                              if (svip) ...[
                                const SizedBox(width: 6),
                                _VipBadge(text: drive['svipLabel']?.toString() ?? 'SVIP'),
                              ],
                              if (invalid) ...[
                                const SizedBox(width: 6),
                                const _InvalidBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
                          ),
                        ],
                      ),
                    ),
                    // 三点菜单
                    IconButton(
                      onPressed: () => _onDriveMenu(drive),
                      tooltip: '更多操作',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_horiz_rounded, size: 22, color: AppColors.textWeak),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              capacityText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                            ),
                          ),
                          if (accountLoading)
                            const SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: AppColors.primary,
                              ),
                            )
                          else if (hasAccount)
                            Text(
                              '$percent%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: usageColor,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _UsageBar(
                        value: percent / 100,
                        height: 6,
                        trackColor: const Color(0xFFEEF1F7),
                        colors: barColors,
                      ),
                      if (invalid) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '授权已失效，请解除后重新添加',
                                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 空态：插画 + 引导文案 + 添加按钮 + 支持的云盘
  Widget _buildEmpty() {
    const previewTypes = ['alicloud', 'baidu', 'quark', 'onedrive', 'google'];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 插画：同心光晕 + 云图标
                Container(
                  width: 148,
                  height: 148,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.06),
                  ),
                  child: Container(
                    width: 104,
                    height: 104,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _brandGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.30),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.cloud_rounded, size: 52, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  '还没有添加云存储',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '连接你的网盘，在一个地方管理、传输和同步所有文件',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textWeak),
                ),
                const SizedBox(height: 28),
                _GradientButton(
                  text: '添加云存储',
                  icon: Icons.add_rounded,
                  onTap: _openAdd,
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in previewTypes)
                      Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: _softShadow,
                        ),
                        child: DriveIcon(driveType: t, size: 22),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '支持阿里云盘、百度网盘、夸克、OneDrive 等多家云存储',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textWeak),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============ 局部组件 ============

/// 页头圆形图标按钮（白底投影 / 主色渐变实心）
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.filled = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? null : Colors.white,
          gradient: filled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _brandGradient,
                )
              : null,
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : _softShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// 渐变胶囊主按钮（空态引导）
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.text, required this.icon, required this.onTap});

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: _brandGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆角渐变容量条（数值变化时平滑过渡）
class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.value,
    required this.height,
    required this.trackColor,
    required this.colors,
  });

  /// 0.0 ~ 1.0
  final double value;
  final double height;
  final Color trackColor;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Container(
        height: height,
        decoration: BoxDecoration(color: trackColor, borderRadius: radius),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(colors: colors),
            ),
          ),
        ),
      ),
    );
  }
}

/// 会员徽标（金色渐变）
class _VipBadge extends StatelessWidget {
  const _VipBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE2A8), Color(0xFFF8C15C)],
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w800,
          color: Color(0xFF8A5A00),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 授权失效徽标（对应 MP invalid 样式）
class _InvalidBadge extends StatelessWidget {
  const _InvalidBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '已失效',
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.danger,
        ),
      ),
    );
  }
}

/// 首屏骨架屏（呼吸动画），替代居中转圈
class _HomeSkeleton extends StatefulWidget {
  const _HomeSkeleton();

  @override
  State<_HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<_HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _block({double? width, required double height, double radius = 8, Color? color}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFEDF0F6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _card() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _block(width: 48, height: 48, radius: 14),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(width: 120, height: 14),
                  const SizedBox(height: 8),
                  _block(width: 72, height: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _block(height: 6, radius: 3),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          _block(height: 156, radius: 24, color: const Color(0xFFDCE5FB)),
          const SizedBox(height: 26),
          Align(
            alignment: Alignment.centerLeft,
            child: _block(width: 84, height: 16, color: const Color(0xFFE4E8F0)),
          ),
          const SizedBox(height: 14),
          _card(),
          _card(),
          _card(),
        ],
      ),
    );
  }
}
