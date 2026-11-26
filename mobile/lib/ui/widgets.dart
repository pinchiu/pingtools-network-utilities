import 'dart:ui';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../core/util/format.dart';
import 'localization.dart';

/// iOS-style page with a real frosted-glass navigation bar.
class FrostedPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final List<Widget> actions;
  final Widget child;
  final bool scrollable;

  const FrostedPage({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.actions = const [],
    required this.child,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top;
    final barHeight = 56.0 + top;
    final overlay =
        (p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: const Color(0x00000000),
              systemNavigationBarColor: p.bg,
              systemNavigationBarIconBrightness: p.isDark
                  ? Brightness.light
                  : Brightness.dark,
            );

    final body = scrollable
        ? SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              barHeight + 14,
              16,
              36 + MediaQuery.paddingOf(context).bottom,
            ),
            child: child,
          )
        : Padding(
            padding: EdgeInsets.only(top: barHeight),
            child: child,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CupertinoPageScaffold(
        backgroundColor: p.bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: body,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _FrostedBar(
                title: title,
                subtitle: subtitle,
                showBack: showBack,
                actions: actions,
                height: barHeight,
                topPadding: top,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrostedBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final List<Widget> actions;
  final double height;
  final double topPadding;

  const _FrostedBar({
    required this.title,
    required this.subtitle,
    required this.showBack,
    required this.actions,
    required this.height,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          height: height,
          padding: EdgeInsets.only(top: topPadding, left: 6, right: 6),
          decoration: BoxDecoration(
            color: p.bg.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: p.border.withValues(alpha: 0.65),
                width: 0.5,
              ),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showBack)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: context.tr('Back', '返回'),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      pressedOpacity: 0.4,
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Icon(CupertinoIcons.back, color: p.text, size: 27),
                    ),
                  ),
                ),
              if (showBack)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 52),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 10,
                            letterSpacing: 0.1,
                          ),
                        ),
                    ],
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ),
              if (actions.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border.withValues(alpha: 0.8), width: 0.8),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return SpringyTap(onTap: onTap, child: card);
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: p.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: DividerLine(color: p.border.withValues(alpha: 0.7))),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class DividerLine extends StatelessWidget {
  final Color? color;
  const DividerLine({super.key, this.color});

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.6, color: color ?? context.palette.border);
}

class AppField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool monospace;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final Widget? prefix;

  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder = '',
    this.onChanged,
    this.enabled = true,
    this.monospace = false,
    this.keyboardType,
    this.maxLines = 1,
    this.textInputAction,
    this.suffix,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: p.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          enabled: enabled,
          placeholder: placeholder,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          textInputAction: textInputAction ?? TextInputAction.done,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          style: TextStyle(
            color: p.text,
            fontSize: 15,
            fontFamily: monospace ? 'monospace' : null,
          ),
          placeholderStyle: TextStyle(color: p.muted, fontSize: 15),
          cursorColor: p.primary,
          prefix: prefix,
          suffix: suffix,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border, width: 0.8),
          ),
        ),
      ],
    );
  }
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool secondary;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.secondary = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !loading;
    final foreground = (secondary ? p.text : p.onPrimary).withValues(
      alpha: enabled ? 1 : 0.45,
    );
    return SpringyTap(
      onTap: enabled ? onPressed : null,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: secondary
              ? p.card
              : p.primary.withValues(alpha: enabled ? 1 : 0.35),
          borderRadius: BorderRadius.circular(14),
          border: secondary
              ? Border.all(
                  color: p.border.withValues(alpha: enabled ? 1 : 0.5),
                  width: 0.8,
                )
              : null,
        ),
        child: loading
            ? const CupertinoActivityIndicator(radius: 9)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Physical spring scale used by cards and buttons.
class SpringyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const SpringyTap({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.965,
  });

  @override
  State<SpringyTap> createState() => _SpringyTapState();
}

class _SpringyTapState extends State<SpringyTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 30,
  );

  void _animateTo(double target, double velocity) {
    _controller.animateWith(
      SpringSimulation(_spring, _controller.value, target, velocity),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    return Semantics(
      button: tappable,
      enabled: tappable,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: tappable
            ? (_) => _animateTo(widget.pressedScale, -2.0)
            : null,
        onTapUp: tappable
            ? (_) {
                _animateTo(1.0, 2.5);
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        onTapCancel: tappable ? () => _animateTo(1.0, 2.5) : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.scale(
            scale: _controller.value.clamp(0.9, 1.05),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MonoText extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  final int maxLines;
  final TextOverflow overflow;

  const MonoText(
    this.text, {
    super.key,
    this.size = 13,
    this.color,
    this.weight = FontWeight.w400,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        color: color ?? context.palette.text,
        fontSize: size,
        fontFamily: 'monospace',
        fontWeight: weight,
        height: 1.35,
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  final String? unit;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.elevated.withValues(alpha: p.isDark ? 0.75 : 0.6),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: MonoText(
                  value,
                  size: 19,
                  weight: FontWeight.w600,
                  color: accent ?? p.text,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit!,
                    style: TextStyle(color: p.muted, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const CopyRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: p.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 2),
              MonoText(value, color: valueColor ?? p.text, size: 13),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: context.tr('Copy', '複製'),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              HapticFeedback.selectionClick();
            },
            child: Icon(CupertinoIcons.doc_on_doc, size: 17, color: p.muted),
          ),
        ),
      ],
    );
  }
}

class DataRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const DataRow(this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? p.text,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.elevated.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 26, color: p.muted),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.danger.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 16,
            color: p.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: p.danger, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressTrack extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;
  const ProgressTrack(this.value, {super.key, this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: p.border,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(color: color ?? p.primary),
        ),
      ),
    );
  }
}

class FrostedSheet extends StatelessWidget {
  final Widget child;
  const FrostedSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          color: p.bg.withValues(alpha: 0.92),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: child,
        ),
      ),
    );
  }
}

Future<T?> showFrostedSheet<T>(BuildContext context, Widget child) {
  return showCupertinoModalPopup<T>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (context) => FrostedSheet(child: child),
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'OK',
  String cancel = 'Cancel',
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

String latencyText(double ms) => fmtLatency(ms);
