import 'dart:math' as math;
import 'package:flutter/material.dart';

/// App-wide inherited scope controlling whether buttons display the subtle
/// hover-swell and press-in / spring-out tactile feedback animation.
class TactileMotionScope extends InheritedNotifier<ValueNotifier<bool>> {
  static final ValueNotifier<bool> globalEnabled = ValueNotifier<bool>(true);

  const TactileMotionScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static bool isEnabled(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<TactileMotionScope>();
    return inherited?.notifier?.value ?? globalEnabled.value;
  }
}

/// Non-intrusive wrapper (uses [MouseRegion] + [Listener] so it never competes
/// in the GestureArena) that adds:
/// - Subtle swell/lift on hover
/// - Instant crisp press-in depression on pointer down
/// - Mechanical spring bounce-out on release
class TactilePress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressScale;
  final double hoverLiftY;
  final double pressSinkY;
  final MouseCursor? cursor;

  const TactilePress({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.032,
    this.pressScale = 0.935,
    this.hoverLiftY = -1.2,
    this.pressSinkY = 1.6,
    this.cursor,
  });

  const TactilePress.card({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.015,
    this.pressScale = 0.974,
    this.hoverLiftY = -0.9,
    this.pressSinkY = 1.1,
    this.cursor,
  });

  @override
  State<TactilePress> createState() => _TactilePressState();
}

class _TactilePressState extends State<TactilePress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _hovered = false;
  bool _pressed = false;
  Offset? _pointerDownPos;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController.unbounded(vsync: this, value: 1.0);
  }

  @override
  void didUpdateWidget(covariant TactilePress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && (_hovered || _pressed || _ctrl.value != 1.0)) {
      _hovered = false;
      _pressed = false;
      _pointerDownPos = null;
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _animateToTarget({required bool isRelease}) {
    if (!mounted) return;
    final scopeOn = TactileMotionScope.isEnabled(context);
    if (!scopeOn || !widget.enabled) {
      _ctrl.value = 1.0;
      return;
    }

    final target = _pressed
        ? widget.pressScale
        : (_hovered ? widget.hoverScale : 1.0);

    if (_pressed) {
      _ctrl.animateTo(
        target,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOutQuad,
      );
    } else if (isRelease) {
      _ctrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
      );
    } else {
      _ctrl.animateTo(
        target,
        duration: const Duration(milliseconds: 145),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && TactileMotionScope.isEnabled(context);
    if (!active) {
      if (_ctrl.value != 1.0) {
        _ctrl.value = 1.0;
      }
      _hovered = false;
      _pressed = false;
      return widget.child;
    }

    return MouseRegion(
      cursor: widget.cursor ?? SystemMouseCursors.click,
      onEnter: (_) {
        _hovered = true;
        if (!_pressed) _animateToTarget(isRelease: false);
      },
      onExit: (_) {
        final wasPressed = _pressed;
        _hovered = false;
        _pressed = false;
        _pointerDownPos = null;
        _animateToTarget(isRelease: wasPressed);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pointerDownPos = event.position;
          _pressed = true;
          _animateToTarget(isRelease: false);
        },
        onPointerMove: (event) {
          if (_pressed && _pointerDownPos != null) {
            if ((event.position - _pointerDownPos!).distance > 14.0) {
              _pressed = false;
              _pointerDownPos = null;
              _animateToTarget(isRelease: false);
            }
          }
        },
        onPointerUp: (_) {
          if (_pressed) {
            _pressed = false;
            _pointerDownPos = null;
            _animateToTarget(isRelease: true);
          }
        },
        onPointerCancel: (_) {
          if (_pressed) {
            _pressed = false;
            _pointerDownPos = null;
            _animateToTarget(isRelease: false);
          }
        },
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final s = _ctrl.value;
            final double dy;
            if (s < 1.0) {
              final denom = math.max(0.001, 1.0 - widget.pressScale);
              final t = ((1.0 - s) / denom).clamp(0.0, 1.4);
              dy = widget.pressSinkY * t;
            } else {
              final denom = math.max(0.001, widget.hoverScale - 1.0);
              final t = ((s - 1.0) / denom).clamp(0.0, 1.2);
              dy = widget.hoverLiftY * t;
            }
            return Transform.translate(
              offset: Offset(0.0, dy),
              child: Transform.scale(
                scale: s,
                alignment: Alignment.center,
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
