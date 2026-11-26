// 基础单元测试：不 pump 整个 App（启动依赖 Store.init 等平台通道），
// 只验证纯工具函数。

import 'package:flutter_test/flutter_test.dart';

import 'package:spirited_app/utils/formatters.dart';

void main() {
  test('Formatters.formatFileSize 输出人类可读字符串', () {
    expect(Formatters.formatFileSize(1024, 1), isNotEmpty);
    expect(Formatters.formatFileSize(0, 1), isNotEmpty);
  });

  test('Formatters.computeTrafficPercent 边界值', () {
    expect(Formatters.computeTrafficPercent(50, 100), 50);
    expect(Formatters.computeTrafficPercent(10, 0), 0);
    expect(Formatters.computeTrafficPercent(0, -1), 0);
  });
}
