/// 主题与设计令牌（对应 MP app.wxss）
///
/// 主色 #4C7DFF；页面背景 #F5F6FA；卡片白、圆角 12；
/// 文字三级：#333333 / #666666 / #999999
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF4C7DFF);
  static const Color primaryLight = Color(0xFFEEF2FF); // 进度条底/主色浅底
  static const Color pageBg = Color(0xFFF5F6FA);
  static const Color cardBg = Colors.white;
  static const Color border = Color(0xFFF0F0F0);

  static const Color textMain = Color(0xFF333333);
  static const Color textSub = Color(0xFF666666);
  static const Color textWeak = Color(0xFF999999);

  static const Color success = Color(0xFF00C48F);
  static const Color warning = Color(0xFFFF9500);
  static const Color danger = Color(0xFFFF4D4F);
  static const Color mostSuccess = Color(0xFF9EB34D);
  static const Color wechat = Color(0xFF07C160);

  static const Color btnDisabled = Color(0xFFC6CFE3);

  static const Color tabUnselected = Color(0xFF999999);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.pageBg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.primary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textMain,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
      ),
    );
  }
}

/// 通用卡片容器
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.onLongPress});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

/// 主按钮（高 44，圆角 22）
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    this.onTap,
    this.enabled = true,
    this.height = 44,
    this.color,
  });

  final String text;
  final GestureTapCallback? onTap;
  final bool enabled;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return SizedBox(
      height: height,
      child: Material(
        color: enabled ? c : AppColors.btnDisabled,
        borderRadius: BorderRadius.circular(height / 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
