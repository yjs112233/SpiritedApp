/// 订单与支付 API（对应 MP api/order.js）
///
/// 支付留桩说明：小程序虚拟支付（mpCreateOrder/mpPayParams + wx.requestVirtualPayment）
/// 与 App 端微信支付（需微信开放平台 AppID + 商户号 App 支付权限）链路不同，
/// 待用户提供开放平台资质后接入；订单创建/查询/列表接口可正常使用。
library;

import '../core/http_client.dart';

class OrderApi {
  OrderApi._();
  static final ApiClient _req = ApiClient.instance;

  /// 创建订单（Web 同款）
  static Future<dynamic> createOrder(dynamic giftId, String giftName, int giftNumber,
      {int multiNum = 0, int multiPrice = 0}) async {
    final result = await _req.postForm('/user/order/create', {
      'giftId': giftId,
      'giftNumber': giftNumber,
      'giftName': giftName,
      'multiNum': multiNum,
      'multiPrice': multiPrice,
    });
    return result.data;
  }

  /// 检查订单支付状态
  static Future<dynamic> checkOrder(String orderId) async {
    final result = await _req.postForm('/user/order/check', {'orderId': orderId});
    return result.data;
  }

  /// 获取订单列表
  static Future<List<dynamic>> getOrderList() async {
    final result = await _req.get('/user/order/list');
    return (result.data as List?)?.toList() ?? [];
  }

  // ==================== 套餐 ====================

  /// 套餐列表（按用户身份计算新客价）
  static Future<ApiResult> mpGiftList() {
    return _req.get('/user/mp/gift/list');
  }

  /// 下单（按分列价格建单）
  static Future<ApiResult> mpCreateOrder(dynamic giftId) {
    return _req.postForm('/user/mp/order/create', {'giftId': giftId});
  }

  /// 升级订阅（已有 VIP 按差价建单，复用 Web 同款接口）
  static Future<ApiResult> mpUpgradeOrder(dynamic giftId) {
    return _req.postForm('/user/order/upgrade', {'giftId': giftId});
  }

  /// 升级抵扣预览（只读不建单）：ids=逗号分隔 giftId
  static Future<ApiResult> upgradeCredit(String ids) {
    return _req.get('/user/order/upgrade/credit?ids=$ids');
  }

  /// 支付结果核查（已支付则补发权益）
  static Future<ApiResult> mpCheckOrder(String orderId) {
    return _req.postForm('/user/mp/order/check', {'orderId': orderId});
  }

  // ==================== 支付（留桩） ====================
  //
  // App 端微信支付需要：
  //  1. 微信开放平台（open.weixin.qq.com）移动应用审核通过，拿到 AppID
  //  2. 微信支付商户号开通 APP 支付权限
  //  3. 后端 /user/order/wechat 返回 App 支付签名参数（partnerId/prepayId/nonceStr/sign）
  //  4. fluwx SDK 唤起支付
  // 待用户提供上述资质后接入，当前 UI 侧按钮点击提示"支付渠道接入中"。
}
