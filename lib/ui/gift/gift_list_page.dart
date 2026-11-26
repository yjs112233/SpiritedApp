/// 套餐订阅（对应 MP pages/gift/list）
///
/// 三层结构：套餐卡片横滑单选（PageView）→ 选中套餐权益（配额/速度/有效期 + 12 条会员权益）
/// → 吸底订购按钮（当前订阅/升级订阅/立即订阅三态）+ 服务协议勾选。
///
/// 支付留桩：App 端微信支付需微信开放平台移动应用 + 商户号 APP 支付权限，
/// 待资质就绪后接入；当前订购按钮提示「支付渠道接入中」。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/order_api.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';

// 会员权益（所有付费套餐共有；容量/速度/时长/价格为动态值，来自接口）
const List<String> _kBenedits = [
  '全部云存储授权', '云盘在线管理', '绑定 10 个云盘', '任务自动排队',
  '跨云传输功能', '文件夹传输', '支持100GB单文件', '文件秒传',
  '智能多文件并行', '跨云同步功能', '天/周/月定时执行', '工单技术支持'
];

// 已下架但存量用户仍在订阅期的旧套餐（对齐 Web MineGift LEGACY_NUMBERS）：
// 保留匹配使这部分用户仍可见「升级订阅」入口，补差由后端 upgradeOrder 计算
const List<String> _kLegacyNumbers = [
  '4TB-90D-Y2608', 'Unlimit-HY-2602', 'Discount-Unlimit-Y2508',
  '5TB-M-2608', '500G-31D-Y2601', 'C-Personal-5TB-Y-2607', '3000G-30D-Y2601',
  '3TB-Q-Y26072', 'Personal-Y-2607', '500GB-M-26072', '3000G-M-Y26072',
  '100GB-D-2608', 'Lite-Unlimit-3M-2608', '6000G-90D-Y2601', '6000G-M-Y26072',
  '1TB-M-2608', '1TB-M-26082', 'Unlimit-Y-2608', '10TB-Y-2607', '50TB-Y-2607', '5TB-Y-2608',
  '50GB-D-2607', 'Unlimit-Q-Y26072', '2TB-Y-2607', '6TB-Y-Y26072',
  'Unlimit-R-Y26072', 'Unlimit-Y-Y26072', 'C-Ultra-10TB-Y-2607',
  'Fast-Unlimit/3Y'
];

// 服务说明三要点（对齐 Web MineOrderV2 notesDialog）
const List<Map<String, String>> _kNotePoints = [
  {
    'title': '合规安全通道',
    'desc': '本产品基于官方API开发，不提供任何绕过官方限速的破解服务。您的实际传输速度和单文件大小上限，取决于您在对应云盘的官方会员权益以及QianClouds的通过权益。'
  },
  {
    'title': '按量消耗配额，透明计费',
    'desc': '数据传输（上传/下载/同步/备份等）按实际流量 1:1 消耗配额（如传输 1GB 文件，扣除 1GB 配额）。配额包支持随时叠加购买。'
  },
  {
    'title': '受官方接口稳定性影响',
    'desc': '云存储服务受各平台政策及接口波动影响，偶尔可能出现连接延迟，我们会第一时间跟进适配。'
  }
];

// 各云盘传输限制对照表（对齐 Web MineOrderV2 limitRules）
const List<List<String>> _kLimitRules = [
  ['阿里云盘', '受官方第三方权益包限制', '需在阿里云盘官方开通第三方应用流量包'],
  ['123云盘', '官方会员上限 (10GB)', '受您 123云盘 官方会员等级影响'],
  ['百度网盘', '官方SVIP上限 (20GB)', '受您 百度网盘 官方SVIP等级影响'],
  ['115网盘', '受 QianClouds 订阅权益限制', '受115官方权益及本站通过权益影响'],
  ['夸克网盘', '受 QianClouds 订阅权益限制', '受夸克官方权益及本站通过权益影响'],
  ['迅雷网盘', '受 QianClouds 订阅权益限制', '受迅雷官方权益及本站通过权益影响'],
  ['OneDrive', '受 QianClouds 订阅权益限制', '受Onedrive官方权益及本站通过权益影响'],
  ['光鸭', '受 QianClouds 订阅权益限制', '受光鸭官方权益及本站通过权益影响'],
];

class GiftListPage extends StatefulWidget {
  const GiftListPage({super.key});

  @override
  State<GiftListPage> createState() => _GiftListPageState();
}

class _GiftListPageState extends State<GiftListPage> with WidgetsBindingObserver {
  bool _isLoggedIn = true;
  bool _loading = true;
  List<Map<String, dynamic>> _gifts = [];
  int _activeIndex = 0;
  bool _isVip = false;
  String _currentGiftNumber = '';
  bool _hasCurrentPlanMatch = false;
  int _currentPriceFen = 0;
  bool _agreed = false;

  // 新客优惠倒计时（注册 3 天内，新客卡展示）
  Timer? _countdownTimer;
  int? _newUserDeadline;
  String _newUserCountdown = '';

  final PageController _pageController = PageController(viewportFraction: 0.56);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initPage();
    }
  }

  void _initPage() {
    if (Store.getToken().isEmpty) {
      setState(() {
        _isLoggedIn = false;
        _loading = false;
      });
      return;
    }
    setState(() => _isLoggedIn = true);
    // VIP 态与当前订阅套餐取缓存用户信息（mainGift，与 mine 页同源）
    final mainGift = Store.getUserInfo()?['mainGift'];
    final gift = mainGift is Map ? mainGift : <String, dynamic>{};
    setState(() {
      _isVip = gift['isVip'] == true;
      _currentGiftNumber = gift['giftNumber']?.toString() ?? '';
    });
    _startNewUserCountdown();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    setState(() => _loading = true);
    try {
      final result = await OrderApi.mpGiftList();
      if (!mounted) return;
      if (!result.ok) {
        Toast.show(result.data?.toString() ?? '套餐加载失败');
        setState(() {
          _loading = false;
          _gifts = [];
        });
        return;
      }
      _applyGifts((result.data as List?)?.toList() ?? []);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 组装展示数据：动态值格式化 + 当前订阅标记（单序列按 mp_gift.sort，横滑选择）
  void _applyGifts(List<dynamic> list) {
    final gifts = <Map<String, dynamic>>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final g = Map<String, dynamic>.from(raw);
      g['priceText'] = _fenToYuan(g['priceFen']);
      g['originalText'] = g['originalPriceFen'] != null && g['originalPriceFen'] != 0
          ? _fenToYuan(g['originalPriceFen'])
          : '';
      g['sizeText'] = g['giftAddSize'] == -1
          ? '无限'
          : Formatters.formatFileSize(g['giftAddSize'], 0);
      g['speedText'] = _speedOf(g);
      g['timeText'] = _timeText(g['giftAddTime']);
      g['isCurrent'] =
          _currentGiftNumber.isNotEmpty && g['giftNumber'] == _currentGiftNumber;
      gifts.add(g);
    }
    final matchedIndex =
        gifts.indexWhere((g) => g['isCurrent'] == true);
    // 当前套餐可识别 = 在售列表命中或存量旧套餐；未识别/存量旧套餐价按 0 处理
    final hasCurrentPlanMatch =
        matchedIndex != -1 || _kLegacyNumbers.contains(_currentGiftNumber);
    final currentPriceFen = matchedIndex != -1
        ? (gifts[matchedIndex]['priceFen'] as num? ?? 0).toInt()
        : 0;
    // 列表变短时保护选中下标越界；首屏固定从第一张卡开始（不定位当前订阅）
    final activeIndex = _activeIndex.clamp(0, gifts.isEmpty ? 0 : gifts.length - 1);
    setState(() {
      _gifts = gifts;
      _activeIndex = activeIndex;
      _hasCurrentPlanMatch = hasCurrentPlanMatch;
      _currentPriceFen = currentPriceFen;
      _loading = false;
    });
  }

  /// mp_gift.speed 展示：纯数字按默认单位补 M/s（15 → 15M/s），
  /// 带单位的文案原样显示，未配置回退 bandWidth 计算
  String _speedOf(Map<String, dynamic> g) {
    final raw = (g['speed'] ?? '').toString().trim();
    if (raw.isNotEmpty) {
      return RegExp(r'^\d+(\.\d+)?$').hasMatch(raw) ? '${raw}M/s' : raw;
    }
    return '${g['bandWidth'] ?? 0}MB/s';
  }

  /// 分转元展示（去尾零：2480 → '24.8'，2500 → '25'）
  String _fenToYuan(dynamic fen) {
    if (fen == null) return '';
    final n = (fen as num).toDouble();
    return ((n / 100).toStringAsFixed(2)).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  /// 天数 → 展示文案（30 → 1个月，90 → 3个月，>3650 即终身）
  String _timeText(dynamic days) {
    if (days == null) return '';
    final d = (days as num).toInt();
    if (Formatters.isLifetimeDays(d)) return '终身';
    if (d % 30 == 0) return '${d ~/ 30}个月';
    return '$d天';
  }

  // ==================== 新客优惠倒计时 ====================

  void _startNewUserCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final createTimeTs = Store.getUserInfo()?['createTimeTs'];
    if (createTimeTs == null) return;
    final deadline = (createTimeTs as num).toInt() + 3 * 24 * 3600 * 1000;
    _newUserDeadline = deadline;
    _tickNewUserCountdown();
    if (_newUserCountdown.isNotEmpty) {
      _countdownTimer = Timer.periodic(
          const Duration(seconds: 1), (_) => _tickNewUserCountdown(fromTimer: true));
    }
  }

  void _tickNewUserCountdown({bool fromTimer = false}) {
    final deadline = _newUserDeadline;
    if (deadline == null) return;
    final remain = deadline - DateTime.now().millisecondsSinceEpoch;
    if (remain <= 0) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      final expired = fromTimer;
      if (mounted) setState(() => _newUserCountdown = '');
      // 页面停留期间过期才需重刷（initPage 流程中的初始过期随后自会 loadGifts）
      if (expired) _loadGifts();
      return;
    }
    final h = remain ~/ 3600000;
    final m = (remain % 3600000) ~/ 60000;
    final s = (remain % 60000) ~/ 1000;
    String pad2(int n) => n.toString().padLeft(2, '0');
    final text = '${pad2(h)}:${pad2(m)}:${pad2(s)}';
    if (text != _newUserCountdown && mounted) {
      setState(() => _newUserCountdown = text);
    }
  }

  // ==================== 订购三态 ====================

  /// 选中套餐的订购态：当前订阅(禁用) / VIP 且套餐可识别且价格更高 → 升级订阅 / 其余 立即订阅
  Map<String, dynamic> _orderMode(Map<String, dynamic>? gift) {
    if (gift == null) return {'text': '立即订阅', 'disabled': true, 'upgrade': false};
    if (gift['isCurrent'] == true) {
      return {'text': '当前订阅', 'disabled': true, 'upgrade': false};
    }
    final priceFen = (gift['priceFen'] as num? ?? 0).toInt();
    if (_isVip && _hasCurrentPlanMatch && priceFen > _currentPriceFen) {
      return {'text': '升级订阅', 'disabled': false, 'upgrade': true};
    }
    return {'text': '立即订阅', 'disabled': false, 'upgrade': false};
  }

  /// 协议勾选 → 下单（支付留桩：待微信开放平台资质后接入 App 支付）
  Future<void> _handlePay() async {
    if (Store.getToken().isEmpty) {
      await Navigator.pushNamed(context, '/login');
      _initPage();
      return;
    }
    if (_gifts.isEmpty) return;
    final gift = _gifts[_activeIndex];
    if (_orderMode(gift)['disabled'] == true) return;
    if (!_agreed) {
      // 未勾选协议：弹小卡片确认（同意并支付）
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认协议', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          content: GestureDetector(
            onTap: () {
              Navigator.pop(ctx, false);
              _openNotes();
            },
            child: const Text(
              '已阅读《QianClouds服务说明》',
              style: TextStyle(fontSize: 14, color: AppColors.primary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textWeak)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('同意并支付', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _agreed = true);
    }
    // TODO(支付留桩)：接入 fluwx App 支付（下单 → 拉起支付 → 核查）
    Toast.show('支付渠道接入中，敬请期待');
  }

  // ==================== 服务说明弹窗 ====================

  Future<void> _openNotes() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: const Text(
                  'QianClouds 服务协议与使用须知',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: _buildNotesBody(),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('我知道了', style: TextStyle(color: AppColors.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesBody() {
    TextSpan bold(String s) => TextSpan(
          text: s,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMain),
        );
    Widget text(String s) => Text(s,
        style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        text('请您在订阅前了解我们的服务机制。QianClouds 致力于提供合规、安全的云端数据备份与同步通道：'),
        for (final p in _kNotePoints) ...[
          const SizedBox(height: 10),
          Text(p['title']!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          const SizedBox(height: 3),
          text(p['desc']!),
        ],
        const Divider(height: 28, color: AppColors.border),
        text('感谢您选择 QianClouds。为了让您获得最佳的数据备份与同步体验，并保障您的账号安全，请仔细阅读以下服务说明：'),
        const SizedBox(height: 10),
        const Text('一、 服务定位与安全机制',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
        const SizedBox(height: 3),
        text('QianClouds 是一款纯云端的多云存储数据资产安全服务平台，通过各云盘官方授权的 API 接口为您提供文件备份、同步与传输服务。'),
        Text.rich(TextSpan(children: [
          bold('不破解、不存数据：'),
          const TextSpan(
              text: '我们绝不提供任何绕过云存储官方限制或破解会员权益的服务。QianClouds 仅作为数据传输通道，不私自存储您的任何文件内容，保障您的隐私安全。'),
        ]), style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub)),
        Text.rich(TextSpan(children: [
          bold('速度与权限规则：'),
          const TextSpan(
              text: 'QianClouds 提供传输通道和带宽配额，但具体的下载/上传速度以及单文件大小限制，需遵循您所在云盘的官方规则。若需提升传输速度或解除大文件限制，请前往对应云盘官方购买相关权益。'),
        ]), style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub)),
        const SizedBox(height: 10),
        const Text('二、 计费与配额消耗规则',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
        const SizedBox(height: 3),
        Text.rich(TextSpan(children: [
          bold('配额消耗逻辑：'),
          const TextSpan(
              text: '在您使用产品的备份、同步、上传或下载等传输功能时，系统将按文件实际大小，1:1 消耗您的数据传输配额。（例如：成功传输一个 5GB 的视频，将扣除 5GB 配额）。'),
        ]), style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub)),
        Text.rich(TextSpan(children: [
          bold('配额有效期：'),
          const TextSpan(
              text: '所有订阅许可均按年计费。配额包支持重复购买且叠加使用，配额包自购买之日起有效期为 1 年，到期未使用完的配额将自动清零。'),
        ]), style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub)),
        Text.rich(TextSpan(children: [
          bold('任务重试提示：'),
          const TextSpan(
              text: '如因网络波动或接口异常导致任务失败并自动重试，自动重试不会消耗你的配额，仅当文件传输成功后扣减配额。但为了传输可靠性，建议您在进行大批量数据同步前，先使用少量文件测试通道连通性。'),
        ]), style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSub)),
        const SizedBox(height: 10),
        const Text('三、 各大云盘传输限制对照表',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
        const SizedBox(height: 3),
        text('为避免因官方规则调整带来的误解，以下为目前各云盘在第三方工具（即本平台）调用时的常见限制参考。具体限制以云盘官方最新政策为准。'),
        const SizedBox(height: 8),
        _buildLimitTable(),
        const SizedBox(height: 8),
        text('若您遇到提示"文件过大"或"限速"，通常是由于云盘官方限制了非会员或第三方调用权限，建议检查您在该云盘的官方会员状态。'),
      ],
    );
  }

  Widget _buildLimitTable() {
    return Table(
      border: TableBorder.all(color: AppColors.border, width: 0.5),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(70),
        1: FlexColumnWidth(1.1),
        2: FlexColumnWidth(1.4),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: AppColors.primaryLight),
          children: const [
            _LimitCell('云盘平台', header: true),
            _LimitCell('单文件大小限制\n（第三方API）', header: true),
            _LimitCell('传输速度影响说明', header: true),
          ],
        ),
        for (final row in _kLimitRules)
          TableRow(
            children: [
              _LimitCell(row[0]),
              _LimitCell(row[1]),
              _LimitCell(row[2]),
            ],
          ),
      ],
    );
  }

  // ==================== 视图 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('套餐订阅')),
      body: !_isLoggedIn ? _buildLoginCard() : _buildBody(),
      bottomNavigationBar: _isLoggedIn ? _buildOrderBar() : null,
    );
  }

  Widget _buildLoginCard() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.card_membership, size: 56, color: AppColors.border),
          const SizedBox(height: 12),
          const Text('登录后即可查看套餐并订阅',
              style: TextStyle(fontSize: 14, color: AppColors.textWeak)),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            child: PrimaryButton(
              text: '去登录',
              height: 38,
              onTap: () async {
                await Navigator.pushNamed(context, '/login');
                _initPage();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _gifts.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_gifts.isEmpty) {
      return const Center(
        child: Text('暂无可订阅套餐', style: TextStyle(fontSize: 14, color: AppColors.textWeak)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildCards(),
        const SizedBox(height: 16),
        _buildBenefitCard(),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 套餐卡片横滑（选中可见窗口左侧卡）
  Widget _buildCards() {
    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _gifts.length,
            onPageChanged: (i) => setState(() => _activeIndex = i),
            itemBuilder: (_, i) {
              final gift = _gifts[i];
              final active = i == _activeIndex;
              return GestureDetector(
                onTap: () {
                  _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.ease,
                  );
                },
                child: Container(
                  margin: EdgeInsets.fromLTRB(6, active ? 4 : 10, 6, active ? 4 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: active ? AppColors.primary : Colors.transparent, width: 1.5),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha:0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    gift['sizeText']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textMain),
                                  ),
                                ),
                                if (gift['isCurrent'] == true)
                                  _buildBadge('当前订阅', AppColors.success)
                                else if (gift['groupType'] == 'new_user' &&
                                    gift['newUserPrice'] != null)
                                  _buildBadge('新客专享', AppColors.warning),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              gift['subtitle']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '最高${gift['speedText']} · ${gift['timeText']}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textWeak),
                            ),
                            const Spacer(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                const Text('¥',
                                    style: TextStyle(fontSize: 13, color: AppColors.danger)),
                                const SizedBox(width: 1),
                                Text(
                                  gift['priceText']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.danger),
                                ),
                                if ((gift['originalText'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '¥${gift['originalText']}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textWeak,
                                        decoration: TextDecoration.lineThrough),
                                  ),
                                ],
                                if (gift['groupType'] == 'new_user' &&
                                    gift['newUserPrice'] != null &&
                                    _newUserCountdown.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '限时 $_newUserCountdown',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10, color: AppColors.warning),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 选中角标
                      if (i == _activeIndex)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(13),
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // 位置指示点
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _gifts.length; i++)
              Container(
                width: i == _activeIndex ? 14 : 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _activeIndex ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  /// 选中套餐权益：三指标 + 会员权益网格（公共 12 条 + 套餐 ext 额外权益）
  Widget _buildBenefitCard() {
    final gift = _gifts[_activeIndex];
    final ext = gift['ext'] is List ? gift['ext'] as List : [];
    final benefits = [..._kBenedits, ...ext.map((e) => e.toString())];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildValueItem(gift['sizeText']?.toString() ?? '', '传输配额'),
              _buildValueItem(gift['speedText']?.toString() ?? '', '最高速度'),
              _buildValueItem(gift['timeText']?.toString() ?? '', '有效期'),
            ],
          ),
          const Divider(height: 24, color: AppColors.border),
          const Text('会员权益',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final b in benefits)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 32 - 32 - 10) / 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 13, color: AppColors.success),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          b,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValueItem(String num, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(num,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textWeak)),
        ],
      ),
    );
  }

  /// 吸底订购栏：按钮 + 协议勾选
  Widget _buildOrderBar() {
    final gift = _gifts.isNotEmpty ? _gifts[_activeIndex] : null;
    final mode = _orderMode(gift);
    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: mode['text'] as String,
                  onTap: mode['disabled'] == true ? null : _handlePay,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _agreed ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 14,
                      color: _agreed ? AppColors.primary : AppColors.textWeak,
                    ),
                    const SizedBox(width: 4),
                    const Text('阅读并同意',
                        style: TextStyle(fontSize: 11, color: AppColors.textWeak)),
                    GestureDetector(
                      onTap: _openNotes,
                      child: const Text('《QianClouds服务说明》',
                          style: TextStyle(fontSize: 11, color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 云盘限制对照表单元格
class _LimitCell extends StatelessWidget {
  const _LimitCell(this.text, {this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.4,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
          color: header ? AppColors.textMain : AppColors.textSub,
        ),
      ),
    );
  }
}
