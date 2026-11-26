/// 编辑资料（对应 MP pages/mine/edit）
///
/// 头像 + 昵称编辑。保存仅提交变更项：昵称变了才调 reset/nickname，
/// 换了头像才上传 reset/headimg（返回新头像 base64 回写缓存）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/user_api.dart';
import '../../core/http_client.dart';
import '../../core/store.dart';
import '../../theme.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _nameController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cached = Store.getUserInfo();
    if (cached != null) {
      _nameController.text = cached['nickname']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  ImageProvider? _currentAvatar() {
    final head = Store.getUserInfo()?['headImage']?.toString().trim() ?? '';
    if (head.isEmpty) return null;
    if (head.startsWith('http://') || head.startsWith('https://')) return NetworkImage(head);
    var b64 = head;
    if (head.startsWith('data:')) {
      final comma = head.indexOf(',');
      if (comma != -1) b64 = head.substring(comma + 1);
    }
    try {
      return MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  /// 更换头像（拍照/相册）
  ///
  /// TODO(头像上传留桩)：需接入 image_picker（相册/相机）选择图片后走
  /// UserApi.resetHeadimg(filePath) multipart 上传。当前提示即将开放。
  void _chooseAvatar() {
    Toast.show('头像修改即将开放');
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    final nickname = _nameController.text.trim();
    if (nickname.isEmpty) {
      Toast.show('请输入昵称');
      return;
    }
    setState(() => _saving = true);
    LoadingManager.show('保存中...');
    try {
      final cached = Store.getUserInfo() ?? <String, dynamic>{};
      // 1. 昵称变更 → reset/nickname
      if (nickname != cached['nickname']?.toString()) {
        await UserApi.resetNickname(nickname);
      }
      // 2. 头像变更 → reset/headimg（选图接入后补充，见 _chooseAvatar 留桩）
      // 3. 同步本地缓存（mine 页刷新用缓存先渲染）
      final merged = Map<String, dynamic>.from(cached);
      merged['nickname'] = nickname;
      Store.saveUserInfo(merged);
      LoadingManager.hide();
      Toast.show('已保存');
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      LoadingManager.hide();
      if (mounted) {
        setState(() => _saving = false);
        Toast.show(e is ApiException ? e.message : '保存失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('编辑资料')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // 头像
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: GestureDetector(
                onTap: _chooseAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: _currentAvatar(),
                      onBackgroundImageError: (_, __) {},
                      child: const Icon(Icons.person, size: 48, color: AppColors.primary),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.photo_camera, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 昵称
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('昵称', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.pageBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            text: _saving ? '保存中...' : '保存',
            onTap: _saving ? null : _saveProfile,
          ),
        ],
      ),
    );
  }
}
