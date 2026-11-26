/// 我的（对应 MP pages/mine/mine，Tab4）
///
/// 蓝底用户卡（头像/昵称/VIP 皇冠/账号/配额条）+ 功能菜单
/// （套餐订阅/我的订单/意见反馈或工单/账户设置）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/user_api.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../utils/formatters.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> with WidgetsBindingObserver {
  Map<String, dynamic>? _userInfo;
  bool _isLoggedIn = false;
  bool _isVip = false;
  int _trafficPercent = 0;
  String _usedTraffic = '';
  String _totalTraffic = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 对应 MP onShow：切回前台刷新（登录/退出可能在别处完成）
    if (state == AppLifecycleState.resumed) {
      _loadUserInfo();
    }
  }

  Future<void> _loadUserInfo() async {
    final cached = Store.getUserInfo();
    if (cached != null) {
      _applyUserInfo(cached);
    }
    if (Store.getToken().isEmpty) {
      if (mounted) {
        setState(() => _isLoggedIn = false);
      }
      return;
    }
    try {
      final info = await UserApi.getUserInfo();
      if (info != null && mounted) {
        _applyUserInfo(info);
      }
    } catch (_) {}
  }

  /// 应用用户信息（并写缓存，编辑资料页等同源）
  void _applyUserInfo(Map<String, dynamic> info) {
    Store.saveUserInfo(info);
    final isUnlimited = info['totalTraffic'] == -1;
    final percent = Formatters.computeTrafficPercent(
      info['usedTraffic'] ?? 0,
      info['totalTraffic'] ?? 0,
    );
    // 与 Web MineHome 一致：isVip 嵌套在 mainGift
    final mainGift = info['mainGift'];
    final gift = mainGift is Map ? mainGift : <String, dynamic>{};
    final isLifetime = Formatters.isLifetimeEndTime(gift['giftEndTime']?.toString());

    setState(() {
      _userInfo = info;
      _isLoggedIn = true;
      _isVip = gift['isVip'] == true;
      _trafficPercent = percent;
      _usedTraffic = Formatters.formatFileSize(info['usedTraffic'], 1);
      _totalTraffic = isUnlimited
          ? (isLifetime ? '终身无限' : '无限')
          : Formatters.formatFileSize(info['totalTraffic'], 1);
    });
  }

  /// 头像地址解析：http 链接直显；base64（可带 data: 前缀）解码为内存图；
  /// 解析失败返回 null 回退默认头像
  ImageProvider? _avatarProvider(String? headImage) {
    final s = headImage?.trim() ?? '';
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return NetworkImage(s);
    var b64 = s;
    if (s.startsWith('data:')) {
      final comma = s.indexOf(',');
      if (comma != -1) b64 = s.substring(comma + 1);
    }
    try {
      return MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  // ==================== 交互 ====================

  Future<void> _goLogin() async {
    await Navigator.pushNamed(context, '/login');
    _loadUserInfo();
  }

  Future<void> _openEditProfile() async {
    if (!_isLoggedIn) return;
    await Navigator.pushNamed(context, '/mine/edit');
    _loadUserInfo();
  }

  Future<void> _goGifts() async {
    await Navigator.pushNamed(context, '/gift/list');
    _loadUserInfo();
  }

  Future<void> _goOrders() async {
    await Navigator.pushNamed(context, '/order/list');
  }

  Future<void> _goAccount() async {
    await Navigator.pushNamed(context, '/mine/account');
    _loadUserInfo();
  }

  /// 意见反馈（免费用户）/ 提交工单（VIP，接口与 Web HelpDialog 一致）
  Future<void> _handleFeedback() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isVip ? '提交工单' : '意见反馈',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: _isVip ? 500 : null,
          decoration: InputDecoration(
            hintText: _isVip ? '请描述您遇到的问题...' : '请输入您的反馈...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textWeak)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final content = controller.text.trim();
    if (content.isEmpty) return;
    try {
      if (_isVip) {
        // 工单 contact 必填：绑定手机号 → 账号 → App 用户
        final info = _userInfo ?? <String, dynamic>{};
        final contact = (info['phone'] ?? info['account'] ?? 'App用户').toString();
        await UserApi.submitTicket(content, contact);
      } else {
        await UserApi.saveMessage(content);
      }
      if (mounted) Toast.show('提交成功');
    } catch (e) {
      if (mounted) Toast.show(e is ApiException ? e.message : '提交失败');
    }
  }

  // ==================== 视图 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUserCard(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildMenuSection([
                    _MenuItem(Icons.card_giftcard, AppColors.primary, '套餐订阅', _goGifts),
                    if (_isLoggedIn)
                      _MenuItem(Icons.receipt_long, AppColors.success, '我的订单', _goOrders),
                    _MenuItem(Icons.feedback, AppColors.warning,
                        _isVip ? '提交工单' : '意见反馈', _handleFeedback),
                  ]),
                  if (_isLoggedIn) ...[
                    const SizedBox(height: 12),
                    _buildMenuSection([
                      _MenuItem(Icons.manage_accounts, const Color(0xFF7C4DFF),
                          '账户设置', _goAccount),
                    ]),
                  ],
                  const SizedBox(height: 24),
                  const Center(
                    child: Text('QianClouds v1.0.0',
                        style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 蓝底渐变用户卡片
  Widget _buildUserCard() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C7DFF), Color(0xFF3563E0)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: _isLoggedIn && _userInfo != null
          ? Row(
              children: [
                GestureDetector(
                  onTap: _openEditProfile,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white24,
                        backgroundImage: _avatarProvider(_userInfo?['headImage']?.toString()),
                        onBackgroundImageError: (_, __) {},
                        child: const Icon(Icons.person, size: 36, color: Colors.white70),
                      ),
                      // 相机角标（编辑头像）
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 1),
                          ),
                          child: const Icon(Icons.photo_camera,
                              size: 12, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _openEditProfile,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isVip) ...[
                              const Icon(Icons.workspace_premium,
                                  size: 18, color: Color(0xFFFFD700)),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                (_userInfo?['nickname']?.toString() ?? '').isNotEmpty
                                    ? _userInfo!['nickname'].toString()
                                    : '未设置昵称',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((_userInfo?['account']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _userInfo!['account'].toString(),
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // 配额进度条
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: LinearProgressIndicator(
                            value: (_trafficPercent / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$_usedTraffic / $_totalTraffic',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : GestureDetector(
              onTap: _goLogin,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, size: 36, color: Colors.white70),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('点击登录',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      SizedBox(height: 6),
                      Text('登录后可管理云存储',
                          style: TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMenuSection(List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 60, color: AppColors.border.withValues(alpha:0.6)),
            _buildMenuRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuRow(_MenuItem item) {
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, size: 16, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.title,
                  style: const TextStyle(fontSize: 15, color: AppColors.textMain)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textWeak),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.color, this.title, this.onTap);

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
}
