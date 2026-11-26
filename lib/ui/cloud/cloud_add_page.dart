/// 添加云存储（对应 MP pages/cloud/add/add）
///
/// 授权方式分发：oauth（WebView 打开授权链接）/ pkce（二维码轮询）/
/// webdav/ftp/secret/cookie（表单弹窗）。
/// drive139 移动云盘仅 vipLevel>10 展示（与 Web showDrive139 一致）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/drive_api.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class CloudAddPage extends StatefulWidget {
  const CloudAddPage({super.key});

  @override
  State<CloudAddPage> createState() => _CloudAddPageState();
}

class _CloudAddEntry {
  const _CloudAddEntry(this.type, this.name, this.authType, {this.vipOnly = false});
  final String type;
  final String name;
  final String authType; // oauth | pkce | webdav | ftp | secret | cookie
  final bool vipOnly;
}

const List<_CloudAddEntry> _allDrives = [
  _CloudAddEntry('alicloud', '阿里云盘', 'oauth'),
  _CloudAddEntry('baidu', '百度网盘', 'oauth'),
  _CloudAddEntry('drive115', '115网盘', 'pkce'),
  _CloudAddEntry('thunder', '迅雷云盘', 'oauth'),
  _CloudAddEntry('quark', '夸克网盘', 'pkce'),
  _CloudAddEntry('guangya', '光鸭云盘', 'pkce'),
  _CloudAddEntry('drive189', '天翼云盘', 'pkce'),
  _CloudAddEntry('uc', 'UC网盘', 'pkce'),
  _CloudAddEntry('drive123', '123云盘', 'secret'),
  _CloudAddEntry('drive139', '移动云盘', 'cookie', vipOnly: true),
  _CloudAddEntry('onedrive', '微软云盘', 'oauth'),
  _CloudAddEntry('google', '谷歌云盘', 'oauth'),
  _CloudAddEntry('wps', 'WPS云盘', 'oauth'),
  _CloudAddEntry('webdav', 'WebDAV', 'webdav'),
  _CloudAddEntry('ftp', 'FTP/SFTP', 'ftp'),
];

class _CloudAddPageState extends State<CloudAddPage> with WidgetsBindingObserver {
  List<_CloudAddEntry> _drives = [];

  // PKCE 扫码弹窗
  bool _showPkce = false;
  Uint8List? _pkceQrBytes;
  String _pkceState = '';
  String _pkceDriveType = '';
  String _pkceDriveName = '';
  Timer? _pkceTimer;
  String _pkceStatus = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyDriveList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPkcePolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台（去其他设备扫码）停止轮询，切回恢复（对应 MP onHide/onShow）
    if (state == AppLifecycleState.paused) {
      _stopPkcePolling();
    } else if (state == AppLifecycleState.resumed && _showPkce && _pkceState.isNotEmpty) {
      _startPkcePolling();
    }
  }

  void _applyDriveList() {
    final info = Store.getUserInfo();
    final mainGift = (info?['mainGift'] as Map?) ?? const {};
    final vipOk = mainGift['isVip'] == true && ((mainGift['vipLevel'] ?? 0) as num) > 10;
    setState(() {
      _drives = _allDrives.where((d) => !d.vipOnly || vipOk).toList();
    });
  }

  Future<void> _selectDrive(_CloudAddEntry drive) async {
    // 授权需要账户体系，游客态直接跳登录页
    if (Store.getToken().isEmpty) {
      Toast.show('请先登录');
      Navigator.pushNamed(context, '/login');
      return;
    }

    // 谷歌授权前置提示：授权页需本地网络可达谷歌
    if (drive.type == 'google') {
      final ok = await showConfirm(
        context,
        title: '谷歌云盘授权提示',
        content: '为了确保授权过程畅通，请先确保您的本地网络能够访问谷歌网址，以便我们向谷歌云盘请求您的授权，授权完成后即可不再依赖本地网络。',
        confirmText: '继续',
      );
      if (!ok) return;
      await _startOAuth(drive);
      return;
    }

    switch (drive.authType) {
      case 'oauth':
        await _startOAuth(drive);
        break;
      case 'pkce':
        await _startPkce(drive);
        break;
      case 'webdav':
      case 'ftp':
      case 'secret':
      case 'cookie':
        _openForm(drive.authType, drive);
        break;
    }
  }

  // ============ OAuth 授权（App 内 WebView 直接打开授权链接） ============

  Future<void> _startOAuth(_CloudAddEntry drive) async {
    try {
      final result = await DriveApi.authNewDrive(drive.type);
      final url = result.data;
      if (!result.ok || url is! String || url.isEmpty) {
        // 业务拒绝（如 229 达到添加上限）时提示语在 data
        Toast.show(url is String && url.isNotEmpty ? url : '获取授权链接失败');
        return;
      }
      if (!mounted) return;
      // 进入本页即代表授权流程已发起，清空列表缓存，返回时自动拉新
      Store.clearDrives();
      Navigator.pushNamed(context, '/oauth', arguments: {
        'type': drive.type,
        'name': drive.name,
        'url': url,
      });
    } catch (_) {}
  }

  // ============ PKCE 扫码授权 ============

  Future<void> _startPkce(_CloudAddEntry drive) async {
    _stopPkcePolling();
    LoadingManager.show('生成二维码...');
    try {
      final result = await DriveApi.getPkceQrcode(drive.type);
      LoadingManager.hide();
      if (!result.ok) {
        final tip = result.data;
        Toast.show(tip is String && tip.isNotEmpty ? tip : '生成二维码失败');
        return;
      }
      final data = result.data;
      final map = data is Map ? data : const {};
      final qrcodeUrl = (map['qrcodeUrl'] ?? map['url'] ?? map['qrcode'] ?? data)?.toString() ?? '';
      final state = (map['state'] ?? map['qrcodeKey'] ?? '')?.toString() ?? '';
      if (qrcodeUrl.isEmpty) {
        Toast.show('生成二维码失败');
        return;
      }
      setState(() {
        _showPkce = true;
        _pkceQrBytes = _dataUriBytes(qrcodeUrl);
        _pkceState = state;
        _pkceDriveType = drive.type;
        _pkceDriveName = drive.name;
        _pkceStatus = '';
      });
      _startPkcePolling();
    } catch (e) {
      LoadingManager.hide();
      Toast.show('生成二维码失败');
    }
  }

  void _startPkcePolling() {
    _stopPkcePolling();
    _pkceTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final result =
            await DriveApi.getPkceQrcodeStatus(_pkceDriveType, _pkceState);
        final data = result.data;
        // 后端 PkceStatusEnum：keep_wait / scan_success / auth_success / invalid_qrcode
        final status = data is String ? data : ((data as Map?)?['status'] ?? '')?.toString() ?? '';
        if (status == 'keep_wait') {
          // 继续等待
        } else if (status == 'scan_success') {
          _setPkceStatus('已扫码，请在手机上确认');
        } else if (status == 'auth_success') {
          _setPkceStatus('授权成功，正在回调...');
          _stopPkcePolling();
          await _pkceCallback();
        } else if (status == 'invalid_qrcode') {
          _setPkceStatus('二维码已失效，请关闭后重新发起');
          _stopPkcePolling();
        }
      } catch (_) {
        // 静默处理轮询错误（含切后台网络中断）
      }
    });
  }

  void _setPkceStatus(String s) {
    if (mounted) setState(() => _pkceStatus = s);
  }

  void _stopPkcePolling() {
    _pkceTimer?.cancel();
    _pkceTimer = null;
  }

  Future<void> _pkceCallback() async {
    try {
      await DriveApi.pkceCallback(_pkceDriveType, _pkceState);
      Store.clearDrives();
      Toast.show('授权成功');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _showPkce = false);
      Navigator.pop(context);
    } catch (e) {
      _setPkceStatus('授权回调失败：${e is ApiException ? e.message : '未知错误'}');
    }
  }

  void _closePkce() {
    _stopPkcePolling();
    setState(() => _showPkce = false);
  }

  /// 我已完成授权：静默查一次状态，已确认则立即回调落库，未确认直接返回
  Future<void> _finishPkce() async {
    _stopPkcePolling();
    try {
      final result = await DriveApi.getPkceQrcodeStatus(_pkceDriveType, _pkceState);
      final data = result.data;
      final status = data is String ? data : ((data as Map?)?['status'] ?? '')?.toString() ?? '';
      if (status == 'auth_success') {
        _setPkceStatus('授权成功，正在回调...');
        await _pkceCallback();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _showPkce = false);
    Navigator.pop(context);
  }

  static Uint8List? _dataUriBytes(String dataUri) {
    if (dataUri.isEmpty) return null;
    final idx = dataUri.indexOf('base64,');
    if (idx < 0) return null;
    try {
      return base64.decode(dataUri.substring(idx + 7).replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return null;
    }
  }

  // ============ 表单类授权 ============

  Future<void> _openForm(String formType, _CloudAddEntry drive) async {
    final Map<String, String> initial = switch (formType) {
      'webdav' => {'username': '', 'password': '', 'weburl': ''},
      'ftp' => {'host': '', 'port': '21', 'username': '', 'password': '', 'path': '/'},
      'secret' => {'appKey': '', 'appSecret': ''},
      _ => {'cookie': ''},
    };

    final fields = {...initial};
    final labels = {
      'weburl': '服务器地址（http(s)://开头）',
      'username': '用户名',
      'password': '密码',
      'host': '主机地址',
      'port': '端口',
      'path': '初始路径',
      'appKey': 'client_id',
      'appSecret': 'client_secret',
      'cookie': 'Authorization Token',
    };
    final obscure = {'password'};

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加${drive.name}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textMain)),
            const SizedBox(height: 16),
            for (final entry in initial.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  obscureText: obscure.contains(entry.key),
                  keyboardType: entry.key == 'port' ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(
                    hintText: labels[entry.key] ?? entry.key,
                    filled: true,
                    fillColor: AppColors.pageBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => fields[entry.key] = v,
                ),
              ),
            if (formType == 'secret')
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'https://www.qianclouds.com/docs/ots'));
                    Toast.show('教程链接已复制');
                  },
                  child: const Text('查看获取教程（复制链接到浏览器打开）',
                      style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              text: '授权',
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _submitForm(formType, drive, fields);
  }

  String? _validateForm(String formType, Map<String, String> f) {
    if (formType == 'webdav') {
      if ((f['weburl'] ?? '').trim().isEmpty) return '请输入服务器地址';
      final url = f['weburl']!.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return '地址需以 http:// 或 https:// 开头';
      }
      if ((f['username'] ?? '').trim().isEmpty) return '请输入用户名';
      if ((f['password'] ?? '').isEmpty) return '请输入密码';
    } else if (formType == 'ftp') {
      if ((f['host'] ?? '').trim().isEmpty) return '请输入主机地址';
      final port = int.tryParse((f['port'] ?? '').trim());
      if ((f['port'] ?? '').trim().isNotEmpty && (port == null || port < 1 || port > 65535)) {
        return '端口范围为 1 - 65535';
      }
      if ((f['username'] ?? '').trim().isEmpty) return '请输入用户名';
      if ((f['password'] ?? '').isEmpty) return '请输入密码';
    } else if (formType == 'secret') {
      if ((f['appKey'] ?? '').trim().isEmpty) return '请输入client_id';
      if ((f['appSecret'] ?? '').trim().isEmpty) return '请输入client_secret';
    } else if (formType == 'cookie') {
      if ((f['cookie'] ?? '').trim().isEmpty) return '请填入Authorization Token';
    }
    return null;
  }

  Future<void> _submitForm(String formType, _CloudAddEntry drive, Map<String, String> f) async {
    final tip = _validateForm(formType, f);
    if (tip != null) {
      Toast.show(tip);
      return;
    }
    LoadingManager.show('授权中...');
    try {
      if (formType == 'webdav') {
        await DriveApi.authWebdav(drive.type, f['username']!.trim(), f['password']!, f['weburl']!.trim());
      } else if (formType == 'ftp') {
        await DriveApi.authFtpDrive({
          'type': drive.type,
          'host': f['host']!.trim(),
          'port': f['port']!.trim().isEmpty ? '21' : f['port']!.trim(),
          'username': f['username']!.trim(),
          'password': f['password']!,
          'path': (f['path'] ?? '').trim().isEmpty ? '/' : f['path']!.trim(),
        });
      } else if (formType == 'secret') {
        await DriveApi.authSecretDrive(drive.type, f['appKey']!.trim(), f['appSecret']!.trim());
      } else if (formType == 'cookie') {
        await DriveApi.authCookieDrive(drive.type, f['cookie']!.trim());
      }
      LoadingManager.hide();
      Toast.show('授权成功');
      Store.clearDrives();
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      LoadingManager.hide();
      Toast.show(e is ApiException ? e.message : '授权失败');
    }
  }

  // ============ 视图 ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('添加云存储')),
      body: SafeArea(
        child: Stack(
          children: [
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              itemCount: _drives.length,
              itemBuilder: (_, i) {
                final d = _drives[i];
                return AppCard(
                  padding: EdgeInsets.zero,
                  onTap: () => _selectDrive(d),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DriveIcon(driveType: d.type, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (_showPkce) _buildPkceMask(),
          ],
        ),
      ),
    );
  }

  /// PKCE 扫码全屏遮罩
  Widget _buildPkceMask() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$_pkceDriveName 授权',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                const SizedBox(height: 6),
                const Text('请使用云盘官方 App 扫码',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _pkceQrBytes == null
                      ? const SizedBox(width: 200, height: 200, child: Center(child: CircularProgressIndicator()))
                      : Image.memory(_pkceQrBytes!, width: 200, height: 200),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 20,
                  child: Text(
                    _pkceStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(text: '我已完成授权', onTap: _finishPkce),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _closePkce,
                  child: const Text('关闭', style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
