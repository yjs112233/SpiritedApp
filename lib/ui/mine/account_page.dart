/// 账户设置（对应 MP pages/mine/account）
///
/// 昵称/手机号展示 + 注销账户（需填原因）+ 退出登录。
/// 退出/注销成功后清缓存返回，「我的」页刷新即切未登录视图。
library;

import 'package:flutter/material.dart';

import '../../api/user_api.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  String _nickname = '';
  String _phone = '';

  @override
  void initState() {
    super.initState();
    final info = Store.getUserInfo();
    if (info != null) {
      _nickname = info['nickname']?.toString() ?? '';
      _phone = info['phone']?.toString() ?? '';
    } else if (Store.getToken().isNotEmpty) {
      // 缓存缺失时兜底拉取
      UserApi.getUserInfo().then((fresh) {
        if (!mounted || fresh == null) return;
        setState(() {
          _nickname = fresh['nickname']?.toString() ?? '';
          _phone = fresh['phone']?.toString() ?? '';
        });
      }).catchError((_) {});
    }
  }

  Future<void> _handleLogout() async {
    final ok = await showConfirm(
      context,
      title: '退出登录',
      content: '确定要退出登录吗？',
      confirmText: '退出',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await UserApi.signOut();
    } catch (_) {
      // 忽略退出接口错误（signOut 内部已清缓存）
    }
    if (!mounted) return;
    Navigator.pop(context);
    Toast.show('已退出');
  }

  Future<void> _openDelUserDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注销账户', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '注销后账户数据将被删除且无法恢复，请谨慎操作',
              style: TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '请填写注销原因',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textWeak)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认注销', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final reason = controller.text.trim();
    if (reason.isEmpty) {
      Toast.show('请填写注销原因');
      return;
    }
    try {
      await UserApi.delUser(reason);
      if (!mounted) return;
      Toast.show('感谢支持！Bye');
      Navigator.pop(context);
    } catch (_) {
      if (mounted) Toast.show('注销失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('账户设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildInfoRow('昵称', _nickname),
                Divider(height: 1, indent: 16, color: AppColors.border.withValues(alpha:0.6)),
                _buildInfoRow('电话', _phone.isNotEmpty ? _phone : '未绑定'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 注销账户
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openDelUserDialog,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('注销账户',
                          style: TextStyle(fontSize: 15, color: AppColors.danger)),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: AppColors.textWeak),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 退出登录
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _handleLogout,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Center(
                  child: Text('退出登录',
                      style: TextStyle(fontSize: 15, color: AppColors.textMain)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 15, color: AppColors.textMain)),
          const Spacer(),
          Text(
            value.isNotEmpty ? value : '-',
            style: const TextStyle(fontSize: 14, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }
}
