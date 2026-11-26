/// 基础组件库（「纸与墨」设计语言）
///
/// 页头 [PageHeader] / 圆角图标按钮 [RoundIconButton] / 小节标题 [SectionLabel]
/// 状态胶囊 [StatusPill] / 进度条 [AppProgressBar] / 线路图 [RouteView]
/// 小操作按钮 [PillButton] / 步骤条 [StepHeader] / 底部操作栏 [BottomActionBar]
/// 空态 [EmptyView] / 骨架屏 [SkeletonList] / 云盘图标 [DriveIcon] [DriveTile]
/// 文件图标 [FileTypeBadge] / 弹窗与底部面板 showConfirm / showInputDialog /
/// showActionSheet / showAppSheet
library;

import 'package:flutter/material.dart';

import '../theme.dart';

// ============================================================================
// 页头
// ============================================================================

/// Tab 页大标题头
///
/// 左侧眉标（可选）+ 大标题，右侧一组 [RoundIconButton]。
/// 兼容旧用法：传 [onRefresh] 自动追加一个刷新按钮。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.refreshText = '刷新',
    this.onRefresh,
    this.trailing,
    this.actions = const [],
  });

  final String title;

  /// 标题上方的小字（如问候语、任务统计）
  final String? eyebrow;
  final String refreshText;
  final VoidCallback? onRefresh;
  final Widget? trailing;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (trailing != null) trailing!,
      if (onRefresh != null)
        RoundIconButton(
          icon: Icons.refresh_rounded,
          tooltip: refreshText,
          onTap: onRefresh!,
        ),
      ...actions,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDims.pagePad, 14, AppDims.pagePad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null && eyebrow!.isNotEmpty) ...[
                  Text(
                    eyebrow!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textWeak),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(title, style: AppText.display),
              ],
            ),
          ),
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            buttons[i],
          ],
        ],
      ),
    );
  }
}

/// 44px 圆角方形图标按钮：白底描边（默认）或墨色实心（[filled]）
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.filled = false,
    this.size = 44,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool filled;
  final double size;

  /// 自定义内容（如旋转中的刷新图标），优先于 [icon]
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.ink;
    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: filled ? AppColors.ink : Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size * 0.32),
          side: filled ? BorderSide.none : const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Center(child: child ?? Icon(icon, size: size * 0.5, color: fg)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 小节标题：标题 + 计数 + 右侧附加
class SectionLabel extends StatelessWidget {
  const SectionLabel({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(2, 24, 2, 12),
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: AppText.num(15, color: AppColors.textWeak)),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ============================================================================
// 状态 / 进度
// ============================================================================

/// 状态胶囊：圆点 + 文案，浅色底
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.dot = true,
    this.solid = false,
  });

  final String label;
  final Color color;
  final bool dot;

  /// 实心样式（底色为 [color]，白字）
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆角进度条；[value] 为 null 时显示不确定态
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color = AppColors.primary,
    this.trackColor = AppColors.fill,
  });

  /// 0.0 ~ 1.0
  final double? value;
  final double height;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    if (value == null) {
      return ClipRRect(
        borderRadius: radius,
        child: LinearProgressIndicator(
          minHeight: height,
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );
    }
    final v = value!.isNaN ? 0.0 : value!.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: v),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Container(
        height: height,
        decoration: BoxDecoration(color: trackColor, borderRadius: radius),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: t,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: radius),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 线路图（传输 / 同步的统一视觉）
// ============================================================================

/// 源盘 → 目标盘 线路图
///
/// 两端是云盘图标底座，中间一条线路：静止时为虚线；有进度时实线推进到
/// 对应位置；[active] 时有光点沿线路流动。下方左右分别是源/目标路径。
class RouteView extends StatelessWidget {
  const RouteView({
    super.key,
    required this.sourceType,
    required this.destType,
    this.sourcePath,
    this.destPath,
    this.progress,
    this.active = false,
    this.label,
    this.color = AppColors.primary,
    this.tileSize = 40,
  });

  final String? sourceType;
  final String? destType;
  final String? sourcePath;
  final String? destPath;

  /// 0.0 ~ 1.0；null 表示不画进度
  final double? progress;
  final bool active;

  /// 线路中间的小标签（如「单向同步」）
  final String? label;
  final Color color;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    final hasPaths = sourcePath != null || destPath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DriveTile(driveType: sourceType, size: tileSize),
            Expanded(
              child: SizedBox(
                height: tileSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: _RouteTrack(progress: progress, active: active, color: color),
                    ),
                    if (label != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          label!,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: active ? color : AppColors.textWeak,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            DriveTile(driveType: destType, size: tileSize),
          ],
        ),
        if (hasPaths) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _path(sourcePath, TextAlign.left)),
              const SizedBox(width: 20),
              Expanded(child: _path(destPath, TextAlign.right)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _path(String? path, TextAlign align) {
    return Text(
      (path ?? '').isEmpty ? '/' : path!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSub),
    );
  }
}

class _RouteTrack extends StatefulWidget {
  const _RouteTrack({required this.progress, required this.active, required this.color});

  final double? progress;
  final bool active;
  final Color color;

  @override
  State<_RouteTrack> createState() => _RouteTrackState();
}

class _RouteTrackState extends State<_RouteTrack> with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _flow.repeat();
  }

  @override
  void didUpdateWidget(covariant _RouteTrack old) {
    super.didUpdateWidget(old);
    if (widget.active && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!widget.active && _flow.isAnimating) {
      _flow
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _flow,
        builder: (_, __) => CustomPaint(
          painter: _RoutePainter(
            progress: widget.progress,
            active: widget.active,
            color: widget.color,
            phase: _flow.value,
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.progress,
    required this.active,
    required this.color,
    required this.phase,
  });

  final double? progress;
  final bool active;
  final Color color;
  final double phase;

  static const Color _idle = Color(0xFFCFCDC3);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 10.0;
    final y = size.height / 2;
    final x0 = pad;
    final x1 = size.width - pad;
    final len = x1 - x0;
    if (len <= 0) return;

    final lit = active || (progress != null && progress! > 0);

    // 底线：虚线
    final dash = Paint()
      ..color = _idle
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var x = x0; x < x1 - 4; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(x + 3, y), dash);
    }

    // 进度：实线 + 端点
    final p = progress?.clamp(0.0, 1.0).toDouble();
    if (p != null && p > 0) {
      final px = x0 + len * p;
      final solid = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x0, y), Offset(px, y), solid);
      canvas.drawCircle(Offset(px, y), 6, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(Offset(px, y), 3.5, Paint()..color = color);
    }

    // 流动光点
    if (active) {
      for (var i = 0; i < 3; i++) {
        final t = (phase + i / 3) % 1.0;
        // 两端淡入淡出
        final fade = t < 0.15 ? t / 0.15 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
        canvas.drawCircle(
          Offset(x0 + len * t, y),
          2.2,
          Paint()..color = color.withValues(alpha: 0.75 * fade),
        );
      }
    }

    // 终点箭头
    final arrow = Paint()
      ..color = lit ? color : _idle
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(x1 - 5, y - 4.5)
      ..lineTo(x1, y)
      ..lineTo(x1 - 5, y + 4.5);
    canvas.drawPath(path, arrow);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.progress != progress ||
      old.active != active ||
      old.color != color ||
      old.phase != phase;
}

// ============================================================================
// 按钮 / 步骤 / 底栏
// ============================================================================

/// 卡片内的小操作按钮（高 34）：浅底 + 图标 + 文案
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = AppColors.ink,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// 文字/图标色；非实心时底色为浅灰
  final Color color;

  /// 实心：底色为 [color]，白字
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Material(
      color: filled ? color : AppColors.fill,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: EdgeInsets.fromLTRB(icon == null ? 14 : 10, 0, 14, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 多步骤流程的步骤条：`01 选择源 ── 02 选择目标 ── 03 确认`
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.steps, required this.current});

  final List<String> steps;

  /// 当前步骤下标（0 起）
  final int current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDims.pagePad, 6, AppDims.pagePad, 14),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: i <= current ? AppColors.ink : AppColors.border,
                ),
              ),
            _step(i),
          ],
        ],
      ),
    );
  }

  Widget _step(int i) {
    final done = i < current;
    final now = i == current;
    final Color bg = now ? AppColors.ink : (done ? AppColors.primary : Colors.white);
    final Color fg = now || done ? Colors.white : AppColors.textWeak;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: now || done ? null : Border.all(color: AppColors.border),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text('${i + 1}', style: AppText.num(14, color: fg, weight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Text(
          steps[i],
          style: TextStyle(
            fontSize: 13,
            fontWeight: now ? FontWeight.w700 : FontWeight.w500,
            color: now ? AppColors.ink : (done ? AppColors.textSub : AppColors.textWeak),
          ),
        ),
      ],
    );
  }
}

/// 页面底部操作栏：白底 + 顶部细线 + 安全区
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppDims.pagePad, 12, AppDims.pagePad, 12),
          child: child,
        ),
      ),
    );
  }
}

// ============================================================================
// 空态 / 骨架
// ============================================================================

/// 空态视图：图标底座 + 标题 + 说明 + 操作按钮
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.text = '暂无数据',
    this.desc,
    this.icon = Icons.inbox_outlined,
    this.actionText,
    this.onAction,
  });

  final String text;
  final String? desc;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 88,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 后层：错位的浅色纸片
                  Positioned(
                    left: 22,
                    top: 0,
                    child: Transform.rotate(
                      angle: 0.14,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 14,
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(icon, size: 32, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            if (desc != null) ...[
              const SizedBox(height: 8),
              Text(desc!, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.textWeak)),
            ],
            if (actionText != null) ...[
              const SizedBox(height: 24),
              PrimaryButton(
                text: actionText!,
                icon: Icons.add_rounded,
                onTap: onAction,
                height: 48,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 骨架块（配合 [SkeletonPulse] 使用）
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8, this.color});

  final double? width;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppColors.fill,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 呼吸动画包装
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

/// 列表页首屏骨架：若干张任务卡片轮廓
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppDims.pagePad, 4, AppDims.pagePad, 24),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppDims.radiusCard),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 140, height: 16),
                  Spacer(),
                  SkeletonBox(width: 52, height: 22, radius: 11),
                ],
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  SkeletonBox(width: 40, height: 40, radius: 13),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SkeletonBox(height: 3, radius: 2),
                    ),
                  ),
                  SkeletonBox(width: 40, height: 40, radius: 13),
                ],
              ),
              SizedBox(height: 18),
              SkeletonBox(width: 180, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 图标
// ============================================================================

/// 云盘图标（assets/images/{driveType}.png，缺图回退 folder_icon）
class DriveIcon extends StatelessWidget {
  const DriveIcon({super.key, this.driveType, this.size = 24});

  final String? driveType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final type = (driveType ?? '').isEmpty ? null : driveType;
    return Image.asset(
      'assets/images/${type ?? 'folder_icon'}.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/folder_icon.png',
        width: size,
        height: size,
      ),
    );
  }
}

/// 云盘图标底座：浅灰圆角方块 + 居中云盘图标
class DriveTile extends StatelessWidget {
  const DriveTile({super.key, this.driveType, this.size = 48, this.color});

  final String? driveType;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? AppColors.fill,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: DriveIcon(driveType: driveType, size: size * 0.6),
    );
  }
}

/// 文件图标（按类型着色的浅底方块 + 短标签，对应 MP getFileLabel/getFileColor）
class FileTypeBadge extends StatelessWidget {
  const FileTypeBadge({super.key, required this.type, this.size = 40});

  final String type;
  final double size;

  static const Map<String, int> _colors = {
    'folder': 0xFFE9A100,
    'image': 0xFFE5484D,
    'video': 0xFF7A4DE0,
    'audio': 0xFFD6409F,
    'doc': 0xFF2E5BFF,
    'pdf': 0xFFE5484D,
    'excel': 0xFF14995F,
    'ppt': 0xFFE8590C,
    'html': 0xFF0A93B8,
    'archive': 0xFF7A6A3A,
    'code': 0xFF5B5BD6,
    'file': 0xFF8A8D96,
  };

  static const Map<String, String> _labels = {
    'image': 'IMG',
    'video': 'MP4',
    'audio': 'MP3',
    'doc': 'DOC',
    'pdf': 'PDF',
    'excel': 'XLS',
    'ppt': 'PPT',
    'html': 'WEB',
    'archive': 'ZIP',
    'code': '{ }',
    'file': 'FILE',
  };

  @override
  Widget build(BuildContext context) {
    final c = Color(_colors[type] ?? 0xFF8A8D96);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: type == 'folder' ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: type == 'folder'
          ? Icon(Icons.folder_rounded, size: size * 0.58, color: c)
          : Text(
              _labels[type] ?? 'FILE',
              style: AppText.num(size * 0.3, color: c, weight: FontWeight.w700, letterSpacing: 0.3),
            ),
    );
  }
}

// ============================================================================
// 弹窗 / 底部面板
// ============================================================================

/// 弹窗底部的双按钮行
Widget _dialogButtons(
  BuildContext ctx, {
  required String confirmText,
  required VoidCallback onConfirm,
  Color confirmColor = AppColors.primary,
}) {
  return Row(
    children: [
      Expanded(
        child: PrimaryButton(
          text: '取消',
          outlined: true,
          height: 46,
          onTap: () => Navigator.pop(ctx),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: PrimaryButton(
          text: confirmText,
          height: 46,
          color: confirmColor,
          onTap: onConfirm,
        ),
      ),
    ],
  );
}

/// 确认弹窗（对应 wx.showModal）
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? content,
  String confirmText = '确定',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (danger) ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 24, color: AppColors.danger),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            if (content != null) ...[
              const SizedBox(height: 8),
              Text(content, style: AppText.body),
            ],
            const SizedBox(height: 24),
            _dialogButtons(
              ctx,
              confirmText: confirmText,
              confirmColor: danger ? AppColors.danger : AppColors.primary,
              onConfirm: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// 输入弹窗（对应 wx.showModal editable）
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String placeholder = '',
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
              decoration: InputDecoration(hintText: placeholder),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 24),
            _dialogButtons(
              ctx,
              confirmText: '确定',
              onConfirm: () => Navigator.pop(ctx, controller.text),
            ),
          ],
        ),
      ),
    ),
  );
  return result;
}

/// 底部面板顶部的拖动条
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

IconData _actionIcon(String action) {
  if (action.contains('删除')) return Icons.delete_outline_rounded;
  if (action.contains('刷新')) return Icons.refresh_rounded;
  if (action.contains('名称') || action.contains('重命名') || action.contains('修改')) {
    return Icons.edit_outlined;
  }
  if (action.contains('详情')) return Icons.article_outlined;
  if (action.contains('续传') || action.contains('恢复') || action.contains('同步')) {
    return Icons.play_arrow_rounded;
  }
  if (action.contains('定时')) return Icons.schedule_rounded;
  if (action.contains('停止')) return Icons.stop_rounded;
  if (action.contains('暂停')) return Icons.pause_rounded;
  if (action.contains('下载')) return Icons.download_rounded;
  if (action.contains('复制')) return Icons.copy_rounded;
  return Icons.chevron_right_rounded;
}

/// 底部操作面板（对应 wx.showActionSheet），返回所选下标
///
/// 每项自动按文案匹配图标；含「删除」的项为危险色。
Future<int?> showActionSheet(
  BuildContext context, {
  required List<String> actions,
  String? title,
}) async {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.overline,
                ),
              ),
            const SizedBox(height: 4),
            for (var i = 0; i < actions.length; i++)
              _sheetRow(ctx, actions[i], () => Navigator.pop(ctx, i)),
          ],
        ),
      ),
    ),
  );
}

Widget _sheetRow(BuildContext ctx, String action, VoidCallback onTap) {
  final danger = action.contains('删除');
  final color = danger ? AppColors.danger : AppColors.ink;
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: danger ? AppColors.dangerSoft : AppColors.fill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_actionIcon(action), size: 19, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                action,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 通用底部面板：拖动条 + 标题行（带关闭）+ 自定义内容；随键盘上移
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textWeak),
                  ),
                ],
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Text(subtitle, style: AppText.caption.copyWith(fontSize: 13)),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: builder(ctx),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
