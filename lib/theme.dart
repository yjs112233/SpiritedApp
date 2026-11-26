/// 主题与设计令牌 —— 「纸与墨」设计语言（v2）
///
/// - 纸：暖白页面底 #F4F3EE，白色卡片 + 1px 细描边（不靠投影堆层次）
/// - 墨：近黑 #16181D 承担标题与重点卡片（首页容量卡、底部导航选中态）
/// - 钴蓝：品牌色 #2E5BFF，只用在可操作元素与进度上
/// - 荧光绿 #C8F250：仅用于墨色表面上的「进行中」信号
/// - 数字：Barlow Semi Condensed（[AppText.num]），容量/百分比/速度统一用它
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  // ---- 品牌 ----
  static const Color primary = Color(0xFF2E5BFF);
  static const Color primaryDeep = Color(0xFF1F45D8);
  static const Color primaryLight = Color(0xFFE8EDFF); // 主色浅底/进度轨道
  static const Color lime = Color(0xFFC8F250); // 墨色表面上的进行中信号

  // ---- 纸与墨 ----
  static const Color ink = Color(0xFF16181D);
  static const Color inkSoft = Color(0xFF23262E); // 墨色表面上的次级块
  static const Color pageBg = Color(0xFFF4F3EE);
  static const Color cardBg = Colors.white;
  static const Color fill = Color(0xFFF1F0EA); // 输入框/图标底座/浅灰块
  static const Color border = Color(0xFFE6E4DC); // 卡片描边/分隔线

  // ---- 文字三级 ----
  static const Color textMain = ink;
  static const Color textSub = Color(0xFF5A5E69);
  static const Color textWeak = Color(0xFF9A9CA5);

  // ---- 语义色（Soft 为对应浅底）----
  static const Color success = Color(0xFF14995F);
  static const Color successSoft = Color(0xFFE3F5EC);
  static const Color warning = Color(0xFFDD8500);
  static const Color warningSoft = Color(0xFFFCF0DA);
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerSoft = Color(0xFFFDEBEC);
  static const Color mostSuccess = Color(0xFF7E9A2B);
  static const Color wechat = Color(0xFF07C160);

  static const Color btnDisabled = Color(0xFFD5D4CD);
  static const Color tabUnselected = textWeak;

  /// 多云盘占比配色（墨色卡片上的分段条/图例，按云盘顺序循环取用）
  static const List<Color> series = [
    Color(0xFF7C9BFF),
    lime,
    Color(0xFFFF9B73),
    Color(0xFF63D9E8),
    Color(0xFFC0A6FF),
    Color(0xFFFFD166),
  ];
}

/// 尺寸令牌
class AppDims {
  AppDims._();

  static const double pagePad = 20; // 页面左右边距
  static const double radiusCard = 20;
  static const double radiusTile = 14; // 图标底座/输入框/小块
  static const double radiusBtn = 16;
  static const double btnHeight = 52;

  /// Tab 页列表底部留白（让最后一张卡片不贴导航栏）
  static const double listBottom = 32;
}

/// 文字样式
class AppText {
  AppText._();

  static const String numFamily = 'BarlowSemiCondensed';

  /// 数字/拉丁字样式（容量、百分比、速度、计数、字标）
  static TextStyle num(
    double size, {
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w600,
    double? height,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: numFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Tab 页大标题
  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: 0.5,
  );

  /// 卡片标题
  static const TextStyle title = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppColors.textSub,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AppColors.textWeak,
  );

  /// 小节眉标（全大写感的小字，字距拉开）
  static const TextStyle overline = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.textWeak,
    letterSpacing: 1.2,
  );
}

class AppTheme {
  AppTheme._();

  /// 浅色页面的状态栏样式（深色图标）
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      surface: Colors.white,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      outline: AppColors.border,
      surfaceTint: Colors.transparent,
    );

    OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusTile),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.pageBg,
      splashColor: AppColors.ink.withValues(alpha: 0.04),
      highlightColor: AppColors.ink.withValues(alpha: 0.03),
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.pageBg,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: overlay,
        iconTheme: IconThemeData(color: AppColors.ink, size: 22),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primaryLight,
        circularTrackColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: AppText.body,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fill,
        hintStyle: const TextStyle(fontSize: 15, color: AppColors.textWeak),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(AppColors.ink, 1.5),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger, 1.5),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.2),
        selectionHandleColor: AppColors.primary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.btnDisabled,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: AppColors.btnDisabled, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.btnDisabled,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: AppColors.ink.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }
}

/// 通用卡片容器：白底 + 细描边，圆角 20
///
/// [tone] 可换底色（如墨色重点卡）；[selected] 为 true 时描边变主色。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.color,
    this.selected = false,
    this.radius = AppDims.radiusCard,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final Color? color;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.cardBg;
    final borderColor = selected
        ? AppColors.primary
        : (color == null ? AppColors.border : Colors.transparent);
    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(18),
          child: child,
        ),
      ),
    );
  }
}

/// 主按钮（高 52，圆角 16）
///
/// 默认钴蓝实心；[color] 传 [AppColors.ink] 得到墨色按钮；
/// [outlined] 为描边次按钮；[loading] 显示转圈并禁用点击。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    this.onTap,
    this.enabled = true,
    this.height = AppDims.btnHeight,
    this.color,
    this.icon,
    this.outlined = false,
    this.loading = false,
  });

  final String text;
  final GestureTapCallback? onTap;
  final bool enabled;
  final double height;
  final Color? color;
  final IconData? icon;
  final bool outlined;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final active = enabled && !loading;
    final Color bg;
    final Color fg;
    if (outlined) {
      bg = Colors.white;
      fg = enabled ? AppColors.ink : AppColors.textWeak;
    } else {
      bg = enabled ? c : AppColors.btnDisabled;
      fg = Colors.white;
    }
    final radius = BorderRadius.circular(height >= 48 ? AppDims.radiusBtn : height / 2.6);
    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: outlined ? const BorderSide(color: AppColors.border) : BorderSide.none,
        ),
        child: InkWell(
          onTap: active ? onTap : null,
          splashColor: Colors.white.withValues(alpha: outlined ? 0 : 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: height >= 48 ? 16 : 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
