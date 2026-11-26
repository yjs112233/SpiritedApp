/// 应用壳：底部 4 Tab（云存储/传输/同步/我的）+ IndexedStack 保活
///
/// 导航栏：白底 + 顶部细线；选中项图标落在墨色胶囊里，文字加粗。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/events.dart';
import '../theme.dart';
import 'cloud/cloud_list_page.dart';
import 'transfer/transfer_list_page.dart';
import 'sync/sync_list_page.dart';
import 'mine/mine_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => ShellPageState();
}

class ShellPageState extends State<ShellPage> {
  int _index = 0;

  static const _pages = [
    CloudListPage(),
    TransferListPage(),
    SyncListPage(),
    MinePage(),
  ];

  @override
  void initState() {
    super.initState();
    UiEvents.shellTab.addListener(_onSwitchTab);
  }

  @override
  void dispose() {
    UiEvents.shellTab.removeListener(_onSwitchTab);
    super.dispose();
  }

  void _onSwitchTab() {
    setState(() => _index = UiEvents.shellTab.value);
  }

  static const _items = [
    (Icons.cloud_outlined, Icons.cloud_rounded, '云存储'),
    (Icons.swap_horiz_rounded, Icons.swap_horiz_rounded, '传输'),
    (Icons.sync_rounded, Icons.sync_rounded, '同步'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
  ];

  /// 外部跳转到指定 tab（如登录页跳"我的"）
  void switchTo(int i) => setState(() => _index = i);

  void _onTap(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: _pages,
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _NavItem(
                        icon: _items[i].$1,
                        activeIcon: _items[i].$2,
                        label: _items[i].$3,
                        selected: i == _index,
                        onTap: () => _onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: selected ? 54 : 40,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.ink.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                selected ? activeIcon : icon,
                size: 21,
                color: selected ? Colors.white : AppColors.textWeak,
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.ink : AppColors.textWeak,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
