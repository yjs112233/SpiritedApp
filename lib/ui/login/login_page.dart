/// 登录页 v3.1（2026-11-24 三次优化）
///
/// 布局：品牌区（缩小+略偏上）占据渐变背景层；表单起为白色悬浮卡片
/// （四角圆角+柔光投影、四周留白）浮于背景之上，形成前后两层层次，
/// 底部留白与品牌区间隙均衡。卡内顺序：表单→协议→其他登录方式（最底）。
/// 小屏/键盘弹起时品牌区 FittedBox 等比缩小、整页可滚动，不溢出不遮挡。
/// 视觉：顶部柔光渐变+气泡背景、渐变字标、渐变主按钮、立体圆形入口图标。
///
/// - 默认手机号验证码登录（新号自动创建账户），底部「其他登录方式」切换 密码/微信
/// - 人机验证为图形验证码：点「获取验证码」弹底部「安全验证」面板，输对 4 位即发码
/// - 密码登录：连续失败达阈值后内嵌图形验证码行（reason=maxAuthenticatedFail）
/// - 微信登录留桩（需微信开放平台 AppID + fluwx，待用户提供资质后接入）
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/user_api.dart';
import '../../core/app_state.dart';
import '../../core/crypto_util.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';

enum _LoginMode { sms, password }

// ---- 设计令牌（本页专用） ----
const Color _inkBorder = Color(0xFFE4E9F4); // 输入框描边
const Color _inkBorderSoft = Color(0xFFEEF1F7); // 白底圆形入口描边
const Color _gradStart = Color(0xFF3D6BF0); // 品牌渐变起点（深）
const Color _gradEnd = Color(0xFF6D9AFF); // 品牌渐变终点（浅）
const Color _bgTint = Color(0xFFE9F0FF); // 顶部背景色

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  _LoginMode _mode = _LoginMode.sms;

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _kaptchaCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  bool _pwdVisible = false;
  bool _loging = false;
  int _countdown = 0;
  bool _agreed = false;

  // 密码模式连续失败达阈值后的图形验证码
  bool _kaptchaShow = false;
  String _kaptchaImg = '';
  String _kaptchaKey = '';

  @override
  void initState() {
    super.initState();
    // 清除可能残留的过期 token，确保每次都从登录页手动进入
    Store.clearToken();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _kaptchaCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  // ============ 协议 ============

  void _toggleAgree() => setState(() => _agreed = !_agreed);

  /// 登录提交的协议检查：未勾选时首次点击自动勾选（本次不提交），再次点击才真正提交
  bool _ensureAgreed() {
    if (_agreed) return true;
    setState(() => _agreed = true);
    Toast.show('已同意协议，请再次点击登录');
    return false;
  }

  Future<void> _viewAgreement() async {
    // 协议页点「同意」回传 true，回写本页勾选状态
    final agreed = await Navigator.pushNamed(context, '/agreement',
        arguments: {'showAgree': true});
    if (agreed == true && mounted) {
      setState(() => _agreed = true);
    }
  }

  // ============ 模式切换 ============

  void _switchMode(_LoginMode mode) {
    if (_mode == mode) return;
    _phoneFocus.unfocus();
    setState(() {
      _mode = mode;
      _kaptchaShow = false;
      _kaptchaImg = '';
      _kaptchaCtrl.clear();
    });
  }

  // ============ 验证码登录 ============

  /// 点「获取验证码」：先校验手机号，再弹图形验证码面板，验证通过即发码
  Future<void> _sendLoginCode() async {
    if (_countdown > 0) return;
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      Toast.show('请输入正确的手机号');
      return;
    }
    FocusScope.of(context).unfocus();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _KaptchaSheet(phone: phone),
    );
    if (ok == true && mounted) {
      Toast.show('验证码已发送');
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown -= 1);
      return _countdown > 0;
    });
  }

  Future<void> _confirmSmsLogin() async {
    if (_loging) return;
    if (!_ensureAgreed()) return;
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      Toast.show('请输入正确的手机号');
      return;
    }
    if (code.isEmpty) {
      Toast.show('请输入验证码');
      return;
    }

    setState(() => _loging = true);
    try {
      await UserApi.smsLogin(phone, code);
      await _loginDone();
    } catch (_) {
      if (mounted) setState(() => _loging = false);
    }
  }

  // ============ 密码登录 ============

  Future<void> _confirmAccountLogin() async {
    if (_loging) return;
    if (!_ensureAgreed()) return;
    final account = _accountCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (account.isEmpty) {
      Toast.show('请输入手机号或邮箱');
      return;
    }
    if (password.length < 8) {
      Toast.show('密码至少 8 位');
      return;
    }
    if (_kaptchaShow && _kaptchaCtrl.text.trim().length != 4) {
      Toast.show('请输入 4 位图形验证码');
      return;
    }

    setState(() => _loging = true);
    try {
      await UserApi.signIn(
        account,
        CryptoUtil.md5Hash(password),
        kaptchaKey: _kaptchaShow ? _kaptchaKey : '',
        kaptchaValue: _kaptchaCtrl.text.trim(),
      );
      setState(() {
        _kaptchaShow = false;
        _kaptchaImg = '';
        _kaptchaCtrl.clear();
      });
      await _loginDone();
    } on ApiException catch (err) {
      if (err.reason == 'maxAuthenticatedFail') {
        _loadKaptcha();
      }
      if (mounted) setState(() => _loging = false);
    } catch (_) {
      if (mounted) setState(() => _loging = false);
    }
  }

  /// 拉取图形验证码并展示输入行（点图片可换一张）
  Future<void> _loadKaptcha() async {
    final key = UserApi.newCaptchaKey();
    try {
      final result = await UserApi.getKaptcha(key);
      final data = result.data;
      final img = data is Map ? (data['img'] ?? '') : '';
      _kaptchaKey = data is Map ? (data['key'] ?? key) : key;
      if (!mounted) return;
      setState(() {
        _kaptchaShow = true;
        _kaptchaImg = img;
        _kaptchaCtrl.clear();
      });
    } catch (_) {}
  }

  // ============ 微信登录（留桩） ============

  void _handleWxLogin() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('微信登录接入中（需微信开放平台资质），请先使用短信验证码或账号密码登录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ============ 登录成功 ============

  Future<void> _loginDone() async {
    try {
      await context.read<AppState>().onLoginSuccess();
    } catch (_) {}
    if (!mounted) return;
    Toast.show('登录成功');
    Navigator.of(context).pop(true);
  }

  // ============ 布局：品牌区弹性居中，表单区沉底 ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          SafeArea(
            // 官方推荐模式：Scroll + ConstrainedBox(minHeight) + IntrinsicHeight + Expanded，
            // 表单整体贴底、空间不足时可滚动（docs: Expanding content to fit the viewport）
            child: LayoutBuilder(
              builder: (ctx, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopBar(),
                        Expanded(child: _buildBrandZone()),
                        _buildBottomZone(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部背景装饰：柔光渐变 + 低透明度圆形气泡（固定不随滚动）
  Widget _buildBackground() {
    Widget blob(double size, Color color) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_bgTint, Color(0x00E9F0FF)],
                  ),
                ),
                child: SizedBox.expand(),
              ),
              Positioned(top: -46, right: -42, child: blob(150, const Color(0xFF4C7DFF).withValues(alpha: 0.07))),
              Positioned(top: 96, left: -56, child: blob(190, const Color(0xFF6D9AFF).withValues(alpha: 0.08))),
              Positioned(top: 30, left: 90, child: blob(26, const Color(0xFF4C7DFF).withValues(alpha: 0.10))),
              Positioned(top: 170, right: 70, child: blob(18, const Color(0xFF3D6BF0).withValues(alpha: 0.10))),
            ],
          ),
        ),
        const Expanded(flex: 6, child: SizedBox()),
      ],
    );
  }

  Widget _buildTopBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _inkBorder),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4C7DFF).withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 15, color: AppColors.textSub),
          ),
        ),
      ),
    );
  }

  /// 品牌区：logo + 渐变字标 + slogan（略偏上；空间不足时等比缩小防重叠）
  Widget _buildBrandZone() {
    return Align(
      alignment: const Alignment(0, -0.45),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/logo0.png', width: 88),
              const SizedBox(height: 14),
              // 渐变字标：ShaderMask 用品牌渐变填充笔画
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_gradStart, _gradEnd],
                ).createShader(bounds),
                child: const Text(
                  'QianClouds',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.white, // 被 shader 替换，仅占位
                    fontFeatures: [],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '让多云数据更安全、更自由',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textWeak,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部区：白色悬浮卡片（四角圆角+柔光投影、左右与底部留白）承载
  /// 表单→协议→其他方式，与渐变背景形成前后两层层次；
  /// 不贴底，底部留白与品牌区/卡片间隙均衡
  Widget _buildBottomZone() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4C7DFF).withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mode == _LoginMode.sms) _buildSmsForm() else _buildPasswordForm(),
              const SizedBox(height: 14),
              _buildAgreement(),
              const SizedBox(height: 24),
              _buildOtherMethods(),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 手机验证码表单（默认） ============

  Widget _buildSmsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _textField(
          controller: _phoneCtrl,
          focusNode: _phoneFocus,
          hint: '请输入手机号',
          icon: Icons.phone_iphone_outlined,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _textField(
                controller: _codeCtrl,
                hint: '请输入验证码',
                icon: Icons.sms_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
                formatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 12),
            _sendCodeButton(),
          ],
        ),
        const SizedBox(height: 30),
        _GradientButton(
          text: '登录 / 注册',
          enabled: !_loging,
          onTap: _confirmSmsLogin,
        ),
      ],
    );
  }

  Widget _sendCodeButton() {
    final busy = _countdown > 0;
    return GestureDetector(
      onTap: busy ? null : _sendLoginCode,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: busy ? const Color(0xFFF0F2F8) : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            _countdown > 0 ? '${_countdown}s后重发' : '获取验证码',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: busy ? AppColors.textWeak : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  // ============ 密码表单 ============

  Widget _buildPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _textField(
          controller: _accountCtrl,
          hint: '手机号或邮箱',
          icon: Icons.person_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _passwordCtrl,
          hint: '密码（至少 8 位）',
          icon: Icons.lock_outline,
          obscure: !_pwdVisible,
          suffix: IconButton(
            icon: Icon(
              _pwdVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18,
              color: AppColors.textWeak,
            ),
            onPressed: () => setState(() => _pwdVisible = !_pwdVisible),
          ),
        ),
        if (_kaptchaShow) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _kaptchaCtrl,
                  hint: '图形验证码',
                  icon: Icons.image_outlined,
                  maxLength: 4,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loadKaptcha,
                child: _kaptchaImg.isEmpty
                    ? Container(
                        width: 96,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.pageBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _inkBorder),
                        ),
                        alignment: Alignment.center,
                        child: const Text('点击获取',
                            style: TextStyle(fontSize: 11, color: AppColors.textWeak)),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _decodeBase64Img(_kaptchaImg),
                          width: 96,
                          height: 48,
                          fit: BoxFit.fill,
                          errorBuilder: (_, __, ___) => Container(
                            width: 96,
                            height: 48,
                            color: AppColors.pageBg,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 30),
        _GradientButton(
          text: '登 录',
          enabled: !_loging,
          onTap: _confirmAccountLogin,
        ),
      ],
    );
  }

  // ============ 其他登录方式 ============

  Widget _buildOtherMethods() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('其他登录方式',
                  style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
            ),
            const Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_mode != _LoginMode.sms) ...[
              _methodEntry(
                icon: Icons.sms_outlined,
                label: '短信登录',
                onTap: () => _switchMode(_LoginMode.sms),
              ),
              const SizedBox(width: 44),
            ],
            if (_mode != _LoginMode.password) ...[
              _methodEntry(
                icon: Icons.lock_outline,
                label: '密码登录',
                onTap: () => _switchMode(_LoginMode.password),
              ),
              const SizedBox(width: 44),
            ],
            _methodEntry(
              asset: 'assets/images/wechatLogo.png',
              label: '微信登录',
              onTap: _handleWxLogin,
            ),
          ],
        ),
      ],
    );
  }

  /// 入口图标：品牌渐变立体圆 + 白色图标；微信为白色圆 + 原色 logo（品牌绿自带辨识度）
  Widget _methodEntry({
    IconData? icon,
    String? asset,
    required String label,
    required VoidCallback onTap,
  }) {
    final isWechat = asset != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isWechat ? Colors.white : null,
              gradient: isWechat
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_gradEnd, _gradStart],
                    ),
              border: isWechat ? Border.all(color: _inkBorderSoft) : null,
              boxShadow: [
                BoxShadow(
                  color: (isWechat ? const Color(0xFF07C160) : _gradStart)
                      .withValues(alpha: 0.24),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isWechat
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.asset(asset, fit: BoxFit.contain),
                  )
                : Icon(icon, size: 22, color: Colors.white),
          ),
          const SizedBox(height: 7),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        ],
      ),
    );
  }

  // ============ 协议 ============

  Widget _buildAgreement() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        children: [
          GestureDetector(
            onTap: _toggleAgree,
            child: Icon(
              _agreed ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: _agreed ? AppColors.primary : AppColors.textWeak,
            ),
          ),
          const SizedBox(width: 5),
          const Text('未注册的手机号验证后将自动创建账户',
              style: TextStyle(fontSize: 11, color: AppColors.textWeak)),
          const Text('，登录即代表同意',
              style: TextStyle(fontSize: 11, color: AppColors.textWeak)),
          GestureDetector(
            onTap: _viewAgreement,
            child: const Text(
              '《用户协议》',
              style: TextStyle(fontSize: 11, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ============ 通用输入 ============

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    Widget? suffix,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    FocusNode? focusNode,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: formatters,
      style: const TextStyle(fontSize: 15, color: AppColors.textMain),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textWeak),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: AppColors.textWeak),
        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 20),
        suffixIcon: suffix,
        counterText: '',
        enabledBorder: border(_inkBorder),
        focusedBorder: border(AppColors.primary, 1.2),
      ),
    );
  }

  static Uint8List _decodeBase64Img(String img) {
    final idx = img.indexOf('base64,');
    final b64 = idx >= 0 ? img.substring(idx + 7) : img;
    return base64.decode(b64.replaceAll(RegExp(r'\s'), ''));
  }
}

/// 发码前「安全验证」底部面板：图形验证码 + 4 位输入，验证通过即发送短信
class _KaptchaSheet extends StatefulWidget {
  const _KaptchaSheet({required this.phone});

  final String phone;

  @override
  State<_KaptchaSheet> createState() => _KaptchaSheetState();
}

class _KaptchaSheetState extends State<_KaptchaSheet> {
  final _inputCtrl = TextEditingController();

  String _key = '';
  String _img = '';
  bool _loading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    final key = UserApi.newCaptchaKey();
    try {
      final result = await UserApi.getKaptcha(key);
      final data = result.data;
      if (!mounted) return;
      setState(() {
        _key = data is Map ? (data['key'] ?? key) : key;
        _img = data is Map ? (data['img'] ?? '') : '';
        _loading = false;
        _inputCtrl.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final value = _inputCtrl.text.trim();
    if (value.length != 4 || _sending || _key.isEmpty) return;
    setState(() => _sending = true);
    try {
      await UserApi.sendSmsLoginCode(widget.phone, _key, value);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      // 验证码错误/过期（http_client 已 toast 错误信息）：自动换一张
      if (!mounted) return;
      setState(() => _sending = false);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canSend = !_sending && _inputCtrl.text.trim().length == 4;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 160),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '安全验证',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: const Icon(Icons.close, size: 20, color: AppColors.textWeak),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '输入图形验证码，验证通过后发送短信验证码',
                  style: TextStyle(fontSize: 12, color: AppColors.textWeak),
                ),
                const SizedBox(height: 16),
                // 验证码图片（点击换一张）
                GestureDetector(
                  onTap: _refresh,
                  child: Container(
                    height: 132,
                    decoration: BoxDecoration(
                      color: AppColors.pageBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _inkBorder),
                    ),
                    alignment: Alignment.center,
                    child: _img.isNotEmpty
                        ? Image.memory(
                            _decode(_img),
                            height: 112,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('图片加载失败，点击重试',
                                    style: TextStyle(
                                        fontSize: 12, color: AppColors.textWeak)),
                          )
                        : Text(
                            _loading ? '加载中…' : '点击获取验证码',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textWeak),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('看不清？点击图片换一张',
                      style: TextStyle(fontSize: 11, color: AppColors.textWeak)),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.pageBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _inputCtrl.text.trim().length == 4
                          ? AppColors.primary
                          : _inkBorder,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _inputCtrl,
                    autofocus: true,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      letterSpacing: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '请输入 4 位字符',
                      hintStyle: TextStyle(
                          fontSize: 14, color: AppColors.textWeak, letterSpacing: 0),
                      border: InputBorder.none,
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (v) {
                      // 输满 4 位自动提交
                      if (v.trim().length == 4) _submit();
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _GradientButton(
                  text: _sending ? '发送中…' : '发送验证码',
                  enabled: canSend,
                  onTap: _submit,
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 8 : 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Uint8List _decode(String img) {
    final idx = img.indexOf('base64,');
    final b64 = idx >= 0 ? img.substring(idx + 7) : img;
    return base64.decode(b64.replaceAll(RegExp(r'\s'), ''));
  }
}

/// 品牌渐变主按钮（带柔光投影）
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.text,
    required this.onTap,
    this.enabled = true,
  });

  final String text;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: enabled ? const LinearGradient(colors: [_gradStart, _gradEnd]) : null,
        color: enabled ? null : AppColors.btnDisabled,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _gradStart.withValues(alpha: 0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
