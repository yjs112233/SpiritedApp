/// 定时计划编辑器（对应 MP components/timer-plans）
///
/// 计划模型与后端 TimerPlanModel 对齐：{planType: 'day'|'week'|'month', num?, time: 'HH:mm'}
/// - day 每天：仅需时间；week 每周：num=1~7；month 每月：num=1~28；分钟级精度
/// - 自带一栏头部（左「定时计划」右「+添加」），新增默认 每周一 08:00
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/formatters.dart';

class TimerPlans extends StatefulWidget {
  const TimerPlans({
    super.key,
    this.initialPlans = const [],
    this.max = 2,
    this.onChanged,
  });

  /// 回填计划：[{type, num?, time}]（页面模型）或后端模型 [{planType, num?, time}]
  final List<Map<String, dynamic>> initialPlans;

  /// 最多计划条数（同步 timerMaxPlans=2）
  final int max;

  /// 计划变化回调：detail = {plans: [{planType, num?, time}]}（后端模型）
  final ValueChanged<List<Map<String, dynamic>>>? onChanged;

  @override
  State<TimerPlans> createState() => TimerPlansState();
}

class TimerPlansState extends State<TimerPlans> {
  static const _typeNames = ['每天', '每周', '每月'];
  static const _typeValues = ['day', 'week', 'month'];
  static const _weekNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static final _monthNames =
      List.generate(28, (d) => '${d + 1}日');

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _rows = widget.initialPlans.map(_toRow).toList();
  }

  Map<String, dynamic> _toRow(Map<dynamic, dynamic> p) {
    final type = _typeValues.contains(p['type'] ?? p['planType'])
        ? (p['type'] ?? p['planType']).toString()
        : 'day';
    var num = int.tryParse((p['num'] ?? 1).toString()) ?? 1;
    num = num.clamp(1, 28);
    return {
      'type': type,
      'typeIndex': _typeValues.indexOf(type),
      'num': num,
      'time': (p['time'] ?? '08:00').toString(),
    };
  }

  /// 输出后端模型（day 不带 num）
  List<Map<String, dynamic>> toPlans() {
    return _rows.map((r) {
      final plan = <String, dynamic>{
        'planType': r['type'],
        'time': r['time'],
      };
      if (r['type'] == 'week' || r['type'] == 'month') {
        plan['num'] = r['num'];
      }
      return plan;
    }).toList();
  }

  void _emit() => widget.onChanged?.call(toPlans());

  void _addPlan() {
    if (_rows.length >= widget.max) return;
    setState(() => _rows.add(_toRow({'type': 'week', 'num': 1, 'time': '08:00'})));
    _emit();
  }

  void _removePlan(int idx) {
    setState(() => _rows.removeAt(idx));
    _emit();
  }

  void _onTypeChange(int idx, int typeIndex) {
    setState(() {
      _rows[idx] = _toRow({
        'type': _typeValues[typeIndex],
        'num': _rows[idx]['num'],
        'time': _rows[idx]['time'],
      });
    });
    _emit();
  }

  void _onNumChange(int idx, int num) {
    setState(() {
      _rows[idx] = _toRow({
        'type': _rows[idx]['type'],
        'num': num,
        'time': _rows[idx]['time'],
      });
    });
    _emit();
  }

  Future<void> _onTimeChange(int idx) async {
    final old = _rows[idx]['time'].toString().split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.tryParse(old[0]) ?? 8, minute: int.tryParse(old[1]) ?? 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _rows[idx] = _toRow({
        'type': _rows[idx]['type'],
        'num': _rows[idx]['num'],
        'time': time,
      });
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 一栏头部：左标题 右添加按钮
        Row(
          children: [
            const Expanded(
              child: Text('定时计划',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
            ),
            GestureDetector(
              onTap: _addPlan,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 13, color: AppColors.primary),
                    Text('添加', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('最多 ${widget.max} 个', style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
        ],
        // 编辑行
        for (var i = 0; i < _rows.length; i++) _buildRow(i),
      ],
    );
  }

  Widget _buildRow(int i) {
    final row = _rows[i];
    final type = row['type'] as String;
    final num = row['num'] as int;
    final numName = type == 'week' ? _weekNames[num - 1] : _monthNames[num - 1];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          // 类型选择
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _pickType(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_typeNames[row['typeIndex'] as int],
                          style: const TextStyle(fontSize: 13, color: AppColors.textMain)),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textWeak),
                  ],
                ),
              ),
            ),
          ),
          // 周几/几号
          if (type != 'day') ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => _pickNum(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.pageBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(numName,
                            style: const TextStyle(fontSize: 13, color: AppColors.textMain)),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textWeak),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // 时间
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _onTimeChange(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(row['time'].toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textMain)),
                    ),
                    const Icon(Icons.access_time, size: 14, color: AppColors.textWeak),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _removePlan(i),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickType(int i) async {
    final idx = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var t = 0; t < _typeNames.length; t++)
              ListTile(
                dense: true,
                title: Center(child: Text(_typeNames[t])),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (idx != null) _onTypeChange(i, idx);
  }

  Future<void> _pickNum(int i) async {
    final type = _rows[i]['type'] as String;
    final names = type == 'week' ? _weekNames : _monthNames;
    final idx = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SizedBox(
        height: 320,
        child: ListView.builder(
          itemCount: names.length,
          itemBuilder: (_, n) => ListTile(
            dense: true,
            title: Center(child: Text(names[n])),
            onTap: () => Navigator.pop(ctx, n + 1),
          ),
        ),
      ),
    );
    if (idx != null) _onNumChange(i, idx);
  }
}

/// 重复计划校验（与 Web TimerDialog isPlanDuplicate 同口径）
bool hasDuplicatePlans(List<Map<String, dynamic>> plans) {
  final keys =
      plans.map((p) => '${p['planType']}-${p['num'] ?? ''}-${p['time']}').toList();
  return keys.asMap().entries.any((e) => keys.indexOf(e.value) != e.key);
}

/// 获取时区（TimerPlans 保存时构建 timerModel 用）
String currentTimezone() => Formatters.getTimezone();
