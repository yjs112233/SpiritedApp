/// 云盘文件浏览（对应 MP pages/cloud/files/files）
///
/// 面包屑导航 + 缓存优先加载 + 新建文件夹 + 三点菜单
/// （文件夹：打开/传输到/重命名/删除；文件：传输到/重命名/删除）。
/// 文件下载预览：图片 App 内预览，其他格式提示走 Web 端（无系统打开插件）。
library;

import 'package:flutter/material.dart';

import '../../api/drive_api.dart';
import '../../core/http_client.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class CloudFilesPage extends StatefulWidget {
  const CloudFilesPage({super.key});

  @override
  State<CloudFilesPage> createState() => _CloudFilesPageState();
}

class _CloudFilesPageState extends State<CloudFilesPage> {
  dynamic _authId;
  String _driveName = '';
  String _driveType = '';
  String _folderId = 'myroot';
  List<Map<String, dynamic>> _routeList = [];
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _isEmpty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_authId == null) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _authId = args?['authId'];
      _driveName = args?['name']?.toString() ?? '';
      _driveType = args?['type']?.toString() ?? '';
      _routeList = [
        {'id': 'myroot', 'name': _driveName}
      ];
      _loadFiles();
    }
  }

  Future<void> _loadFiles({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    try {
      final result = forceRefresh
          ? await DriveApi.getDriveItemsRefresh(_authId, _folderId)
          : await DriveApi.getDriveItemsCached(_authId, _folderId);
      final data = result.data;
      final rawItems = (data is Map ? data['items'] : null) as List? ?? [];
      final items = <Map<String, dynamic>>[];
      for (final it in rawItems) {
        final item = it is Map ? Map<String, dynamic>.from(it) : <String, dynamic>{};
        final isDir = item['isDir'] == true;
        final name = item['name']?.toString() ?? '';
        item['_fileType'] = isDir ? 'folder' : Formatters.getFileType(name);
        final size = item['size'];
        item['_fileSize'] =
            size != null && (size as num) > 0 ? Formatters.formatFileSize(size, 1) : '';
        items.add(item);
      }
      setState(() {
        _items = items;
        _isEmpty = items.isEmpty;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _isEmpty = true;
      });
    }
  }

  // ============ 导航 ============

  void _enterFolder(Map<String, dynamic> item) {
    // 去重：已在路径链中则不处理
    final id = item['id']?.toString() ?? '';
    if (_routeList.any((r) => r['id'].toString() == id)) return;
    setState(() {
      _folderId = item['id']?.toString() ?? 'myroot';
      _routeList.add({'id': item['id'], 'name': item['name']?.toString() ?? ''});
      _items = [];
    });
    _loadFiles();
  }

  void _openRoute(Map<String, dynamic> node) {
    final folderId = node['id'].toString();
    final idx = _routeList.indexWhere((r) => r['id'].toString() == folderId);
    if (idx == -1) return;
    setState(() {
      _folderId = folderId;
      _routeList = _routeList.sublist(0, idx + 1);
      _items = [];
    });
    _loadFiles();
  }

  Future<void> _refreshFiles() async {
    await _loadFiles(forceRefresh: true);
    Toast.show('已刷新');
  }

  // ============ 新建文件夹 ============

  Future<void> _toggleMkdir() async {
    final name = await showInputDialog(
      context,
      title: '新建文件夹',
      placeholder: '请输入文件夹名称',
      initialValue: '新建文件夹',
    );
    if (name == null) return;
    final n = name.trim();
    if (n.isEmpty) {
      Toast.show('请输入文件夹名称');
      return;
    }
    try {
      await DriveApi.mkdir(_authId, _folderId, n);
      Toast.show('创建成功');
      _loadFiles(forceRefresh: true);
    } catch (_) {
      Toast.show('创建失败');
    }
  }

  // ============ 文件下载/预览 ============

  Future<void> _openFile(Map<String, dynamic> item) async {
    final size = item['size'];
    if (size != null && (size as num) > 100 * 1024 * 1024) {
      Toast.show('文件超过100M，请使用Web端下载');
      return;
    }
    final name = item['name']?.toString() ?? '';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
    if (!imageExts.contains(ext)) {
      Toast.show('暂不支持预览此格式，请使用Web端下载');
      return;
    }
    try {
      final (bytes, _) =
          await DriveApi.downloadItem(_authId, item['id'], _folderId);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
    } catch (_) {}
  }

  // ============ 三点菜单 ============

  Future<void> _onItemMenu(Map<String, dynamic> item) async {
    final isDir = item['isDir'] == true;
    final actions =
        isDir ? ['打开', '传输到', '重命名', '删除'] : ['传输到', '重命名', '删除'];
    final idx = await showActionSheet(context, actions: actions);
    if (idx == null) return;
    final action = isDir
        ? ['open', 'transfer', 'rename', 'delete'][idx]
        : ['transfer', 'rename', 'delete'][idx];
    if (action == 'open') {
      _enterFolder(item);
    } else if (action == 'transfer') {
      _transferItem(item);
    } else if (action == 'rename') {
      _renameItemDialog(item);
    } else if (action == 'delete') {
      _deleteItemDialog(item);
    }
  }

  /// 传输到：携带源信息直达传输创建页（跳过选源直接选目标）
  void _transferItem(Map<String, dynamic> item) {
    if (_driveType == 'thunder') {
      Toast.show('迅雷云盘暂不支持作为传输源');
      return;
    }
    Navigator.pushNamed(context, '/transfer/create', arguments: {
      'preset': true,
      'driveId': _authId,
      'driveType': _driveType,
      'driveName': _driveName,
      'item': {
        'id': item['id'],
        'name': item['name'],
        'isDir': item['isDir'] == true,
        'size': item['size'] ?? 0,
      },
      'nodeList': _routeList.map((r) => Map<String, dynamic>.from(r)).toList(),
    });
  }

  Future<void> _renameItemDialog(Map<String, dynamic> item) async {
    final name = await showInputDialog(
      context,
      title: '重命名',
      placeholder: '请输入名称',
      initialValue: item['name']?.toString() ?? '',
    );
    if (name == null) return;
    final n = name.trim();
    if (n.isEmpty || n == item['name']) return;
    try {
      await DriveApi.rename(_authId, item['id'], n);
      Toast.show('已重命名');
      _loadFiles(forceRefresh: true);
    } catch (_) {}
  }

  Future<void> _deleteItemDialog(Map<String, dynamic> item) async {
    final ok = await showConfirm(
      context,
      title: '删除文件',
      content: '确定要删除「${item['name']}」到回收站吗？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    // 二次确认防误触（与 MP 一致）
    final ok2 = await showConfirm(
      context,
      title: '再次确认',
      content: '删除后将移入网盘回收站，是否继续？',
      confirmText: '继续删除',
      danger: true,
    );
    if (!ok2) return;
    try {
      await DriveApi.delete(_authId, item['id']);
      Toast.show('已删除');
      _loadFiles(forceRefresh: true);
    } catch (_) {}
  }

  // ============ 视图 ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(_driveName, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 22),
            tooltip: '新建文件夹',
            onPressed: _toggleMkdir,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: '刷新',
            onPressed: _refreshFiles,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBreadcrumb(),
            Divider(height: 1, color: AppColors.border.withValues(alpha:0.6)),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary))
                  : _isEmpty || _items.isEmpty
                      ? const EmptyView(text: '文件夹为空')
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () => _loadFiles(forceRefresh: true),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: AppColors.border.withValues(alpha:0.5)),
                            itemBuilder: (_, i) => _buildItemRow(_items[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// 面包屑（横向滚动）
  Widget _buildBreadcrumb() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 22,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _routeList.length,
          itemBuilder: (_, i) {
            final node = _routeList[i];
            final isLast = i == _routeList.length - 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: isLast ? null : () => _openRoute(node),
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
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final isDir = item['isDir'] == true;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: isDir ? () => _enterFolder(item) : () => _openFile(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              FileTypeBadge(type: item['_fileType']?.toString() ?? 'file'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: AppColors.textMain),
                    ),
                    if ((item['_fileSize'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item['_fileSize'].toString(),
                          style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _onItemMenu(item),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.more_horiz, size: 18, color: AppColors.textWeak),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
