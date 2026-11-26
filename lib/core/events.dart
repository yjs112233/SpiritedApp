/// 轻量 UI 事件（模拟 MP 的 onShow 自动刷新机制）
///
/// MP 里授权完成回到列表页靠页面 onShow 重新拉数据；Flutter 的
/// IndexedStack 保活页面没有 onShow，改用版本号广播：
/// 授权/删除后 bump 版本，列表页监听到即强制刷新。
library;

import 'package:flutter/foundation.dart';

class UiEvents {
  UiEvents._();

  /// 云盘列表数据版本（授权成功/删除云盘后 +1）
  static final ValueNotifier<int> driveListVersion = ValueNotifier(0);

  /// 传输/同步任务列表数据版本（创建任务后 +1）
  static final ValueNotifier<int> taskListVersion = ValueNotifier(0);

  /// 壳 Tab 切换（0云存储/1传输/2同步/3我的），创建任务成功后跳对应列表
  static final ValueNotifier<int> shellTab = ValueNotifier(0);

  static void bumpDrives() => driveListVersion.value++;

  static void bumpTasks() => taskListVersion.value++;

  static void switchTab(int i) => shellTab.value = i;
}
