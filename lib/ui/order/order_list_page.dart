/// 我的订单（对应 MP pages/order/list）
///
/// 订单卡片：套餐名 + 支付状态（已是中文）/ 天数 / 订购日期 / 金额；
/// 待支付订单提供「刷新支付状态」（虚拟支付单走 mp 专用查单）。
library;

import 'package:flutter/material.dart';

import '../../api/order_api.dart';
import '../../core/http_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class OrderListPage extends StatefulWidget {
  const OrderListPage({super.key});

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  bool _isEmpty = false;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final list = await OrderApi.getOrderList();
      if (!mounted) return;
      final orders = <Map<String, dynamic>>[];
      for (final o in list) {
        if (o is! Map) continue;
        final m = Map<String, dynamic>.from(o);
        m['_statusColor'] = _statusColor(m['payStatus']?.toString() ?? '');
        orders.add(m);
      }
      setState(() {
        _orders = orders;
        _isEmpty = orders.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isEmpty = true;
      });
    }
  }

  // payStatus 已是中文：'已成功'、'待支付'、'已取消'、'已退款'
  Color _statusColor(String payStatus) {
    switch (payStatus) {
      case '已成功':
        return AppColors.success;
      case '待支付':
        return AppColors.warning;
      case '已退款':
        return AppColors.danger;
      default:
        return AppColors.textWeak;
    }
  }

  /// 刷新待支付订单状态（小程序虚拟支付单走专用查单，其余走原接口）
  Future<void> _checkOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    if (orderId.isEmpty) return;
    LoadingManager.show('查询中...');
    try {
      final platform = order['payPlatform']?.toString() ?? '';
      final result = platform == 'WechatVirtual'
          ? await OrderApi.mpCheckOrder(orderId)
          : await OrderApi.checkOrder(orderId);
      await _loadOrders();
      LoadingManager.hide();
      // 兼容两种返回：整包 ApiResult（.data）与直接 DTO
      Map<dynamic, dynamic>? dto;
      if (result is ApiResult) {
        dto = result.data is Map ? result.data as Map : null;
      } else if (result is Map) {
        dto = result;
      }
      if (dto != null && dto['payStatus'] == '已成功') {
        Toast.show('支付成功');
      }
    } catch (_) {
      LoadingManager.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('我的订单')),
      body: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _isEmpty || _orders.isEmpty
              ? const EmptyView(text: '暂无订单记录')
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadOrders,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _buildOrderCard(_orders[i]),
                  ),
                ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final payStatus = order['payStatus']?.toString() ?? '';
    final statusColor = order['_statusColor'] as Color? ?? AppColors.textWeak;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order['giftName']?.toString().isNotEmpty == true
                      ? order['giftName'].toString()
                      : '订单',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMain),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                payStatus,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRow('天数', order['giftAddTime']?.toString() ?? '-'),
          _buildRow('订购日期', order['createTime']?.toString() ?? '-'),
          _buildRow('订单金额', '¥${order['payMoney'] ?? '0'}', valueColor: AppColors.danger),
          if (payStatus == '待支付') ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _checkOrder(order),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary.withValues(alpha:0.5)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('刷新支付状态',
                      style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? AppColors.textSub,
                fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
