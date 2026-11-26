/// 应用壳：底部 4 Tab（云存储/传输/同步/我的）+ IndexedStack 保活
///
/// 对应 MP custom-tab-bar（CSS+SVG 图标，选中 #4C7DFF）
library;

import 'package:flutter/material.dart';

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
    (Icons.cloud_outlined, Icons.cloud, '云存储'),
    (Icons.swap_horiz_outlined, Icons.swap_horiz, '传输'),
    (Icons.sync_outlined, Icons.sync, '同步'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  /// 外部跳转到指定 tab（如登录页跳"我的"）
  void switchTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.tabUnselected,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          for (var i = 0; i < _items.length; i++)
            BottomNavigationBarItem(
              icon: Icon(_items[i].$1, size: 24),
              activeIcon: Icon(_items[i].$2, size: 24),
              label: _items[i].$3,
            ),
        ],
      ),
    );
  }
}
