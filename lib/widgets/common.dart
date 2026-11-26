/// 基础组件：页头（大标题+刷新）、空态、云盘/文件图标、确认弹窗
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 页面大标题头（对应 MP 自定义导航 + 页面大标题风格）
///
/// 左侧大标题，右侧圆形刷新按钮（可选）
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.refreshText = '刷新',
    this.onRefresh,
    this.trailing,
  });

  final String title;
  final String refreshText;
  final VoidCallback? onRefresh;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain,
              ),
            ),
          ),
          if (trailing != null) trailing!,
          if (onRefresh != null)
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      refreshText,
                      style: const TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 空态视图（对应 MP components/empty）
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, this.text = '暂无数据', this.actionText, this.onAction});

  final String text;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_queue, size: 64, color: AppColors.border),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textWeak)),
          if (actionText != null) ...[
            const SizedBox(height: 16),
            PrimaryButton(
              text: actionText!,
              onTap: onAction,
              height: 38,
            ),
          ],
        ],
      ),
    );
  }
}

/// 云盘图标（assets/images/{driveType}.png，缺图回退 folder_icon）
class DriveIcon extends StatelessWidget {
  const DriveIcon({super.key, this.driveType, this.size = 24});

  final String? driveType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final type = (driveType ?? '').isEmpty ? null : driveType;
    return Image.asset(
      'assets/images/${type ?? 'folder_icon'}.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/folder_icon.png',
        width: size,
        height: size,
      ),
    );
  }
}

/// 文件图标（按类型彩色短标签方块，对应 MP getFileLabel/getFileColor）
class FileTypeBadge extends StatelessWidget {
  const FileTypeBadge({super.key, required this.type, this.size = 36});

  final String type;
  final double size;

  static const Map<String, int> _colors = {
    'folder': 0xFFFFB300,
    'image': 0xFFEA5455,
    'video': 0xFF424242,
    'audio': 0xFFEA5455,
    'doc': 0xFF495C83,
    'pdf': 0xFFEA5455,
    'excel': 0xFF159895,
    'ppt': 0xFFEA5455,
    'html': 0xFF2196F3,
    'archive': 0xFF245953,
    'code': 0xFF7C4DFF,
    'file': 0xFF999999,
  };

  static const Map<String, String> _labels = {
    'image': 'IMG',
    'video': 'MP4',
    'audio': 'MP3',
    'doc': 'DOC',
    'pdf': 'PDF',
    'excel': 'XLS',
    'ppt': 'PPT',
    'html': 'WEB',
    'archive': 'ZIP',
    'code': '{}',
    'file': 'FILE',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(_colors[type] ?? 0xFF999999),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: type == 'folder'
          ? Icon(Icons.folder, size: size * 0.7, color: Colors.white)
          : Text(
              _labels[type] ?? 'FILE',
              style: TextStyle(
                fontSize: size * 0.26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
    );
  }
}

/// wx.showModal 风格确认弹窗
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? content,
  String confirmText = '确定',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: content == null
          ? null
          : Text(content, style: const TextStyle(fontSize: 14, color: AppColors.textSub)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消', style: TextStyle(color: AppColors.textWeak)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText,
              style: TextStyle(color: danger ? AppColors.danger : AppColors.primary)),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// wx.showModal editable 风格输入弹窗
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String placeholder = '',
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: placeholder),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消', style: TextStyle(color: AppColors.textWeak)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('确定', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    ),
  );
  return result;
}

/// wx.showActionSheet 风格底部操作面板
Future<int?> showActionSheet(
  BuildContext context, {
  required List<String> actions,
}) async {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++)
            ListTile(
              title: Center(
                child: Text(
                  actions[i],
                  style: TextStyle(
                    fontSize: 16,
                    color: actions[i].contains('删除') ? AppColors.danger : AppColors.textMain,
                  ),
                ),
              ),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ],
      ),
    ),
  );
}
