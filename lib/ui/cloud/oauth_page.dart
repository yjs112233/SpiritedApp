/// OAuth 授权页（对应 MP pages/oauth/webview）
///
/// App 内 WebView 直接打开授权链接完成授权（比 MP 复制链接到浏览器体验更好），
/// 授权完成后落地 qianclouds 静态结果页，点击「我已完成授权」返回云存储列表。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/events.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';

class OauthPage extends StatefulWidget {
  const OauthPage({super.key});

  @override
  State<OauthPage> createState() => _OauthPageState();
}

class _OauthPageState extends State<OauthPage> {
  String _url = '';
  String _driveName = '';
  WebViewController? _controller;
  bool _pageLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_url.isEmpty) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _url = args?['url']?.toString() ?? '';
      _driveName = args?['name']?.toString() ?? '';
      if (_url.isEmpty) {
        Navigator.pop(context);
        return;
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _pageLoading = false);
            },
            onWebResourceError: (_) {
              if (mounted) setState(() => _pageLoading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(_url));
      _controller = controller;
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _url));
    Toast.show('已复制授权链接');
  }

  /// 授权完成（或放弃）：清缓存标记 + 广播刷新，返回云存储 Tab
  void _finish() {
    Store.clearDrives();
    UiEvents.bumpDrives();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('$_driveName授权', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: '复制链接',
            onPressed: _copyLink,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primaryLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              '请在上方页面完成授权，完成后点击底部按钮返回',
              style: TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_controller != null) WebViewWidget(controller: _controller!),
                if (_pageLoading && _controller != null)
                  const Positioned.fill(
                    child: Center(
                        child: CircularProgressIndicator(color: AppColors.primary)),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: PrimaryButton(text: '我已完成授权', onTap: _finish),
            ),
          ),
        ],
      ),
    );
  }
}
