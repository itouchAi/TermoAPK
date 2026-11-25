import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Describes the currently pressed tactile target whose perimeter remains crisp
/// while surrounding elements subtly blur.
class TactileFocusTarget {
  final Object token;
  final Rect globalRect;
  final bool isCircle;
  final double borderRadius;
  final double? overrideCircleRadius;

  const TactileFocusTarget({
    required this.token,
    required this.globalRect,
    this.isCircle = false,
    this.borderRadius = 18.0,
    this.overrideCircleRadius,
  });

  double get effectiveCircleRadius =>
      overrideCircleRadius ??
      (math.max(globalRect.width, globalRect.height) * 0.5 + 5.0);
}

/// App-wide inherited scope controlling whether buttons & the thermostat dial
/// display tactile hover/press animations and surrounding press-focus blur,
/// plus wheel-event coordination for the thermostat dial.
class TactileMotionScope extends InheritedNotifier<ValueNotifier<bool>> {
  static final ValueNotifier<bool> globalEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<TactileFocusTarget?> activeFocus =
      ValueNotifier<TactileFocusTarget?>(null);

  static PointerEvent? _consumedScrollRoot;
  static int? _consumedScrollPointer;
  static Duration? _consumedScrollTimeStamp;

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

  /// Marks a [PointerScrollEvent] as handled by an inner tactile widget
  /// (such as [RotaryDial]) so outer page-navigation wheel listeners ignore it.
  static void markScrollEventConsumed(PointerScrollEvent event) {
    _consumedScrollRoot = event.original ?? event;
    _consumedScrollPointer = event.pointer;
    _consumedScrollTimeStamp = event.timeStamp;
  }

  /// Returns true if [event] (or its pre-transform original) was already
  /// handled by an inner widget.
  static bool wasScrollEventConsumed(PointerScrollEvent event) {
    final root = event.original ?? event;
    if (_consumedScrollRoot != null && identical(_consumedScrollRoot, root)) {
      return true;
    }
    if (event.timeStamp != Duration.zero &&
        _consumedScrollPointer == event.pointer &&
        _consumedScrollTimeStamp == event.timeStamp) {
      return true;
    }
    return false;
  }

  /// Registers a pressed tactile target in global viewport coordinates so
  /// [TactileFocusBlurHost] subtly blurs everything outside it.
  static void beginFocus(
    BuildContext context, {
    required Object token,
    bool isCircle = false,
    double borderRadius = 18.0,
    double? overrideCircleRadius,
  }) {
    if (!globalEnabled.value) return;
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    final size = ro.size;
    if (size.isEmpty) return;
    final globalRect = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & size,
    );
    activeFocus.value = TactileFocusTarget(
      token: token,
      globalRect: globalRect,
      isCircle: isCircle,
      borderRadius: borderRadius,
      overrideCircleRadius: overrideCircleRadius,
    );
  }

  /// Clears active surrounding focus blur if [token] owns the current focus.
  static void endFocus(Object token) {
    if (activeFocus.value?.token == token) {
      activeFocus.value = null;
    }
  }
}

/// Renders an inverse-clipped subtle backdrop blur around the currently pressed
/// tactile element while keeping the element itself razor-sharp.
class TactileFocusBlurHost extends StatefulWidget {
  final Widget child;
  final double maxBlurSigma;

  const TactileFocusBlurHost({
    super.key,
    required this.child,
    this.maxBlurSigma = 2.8,
  });

  @override
  State<TactileFocusBlurHost> createState() => _TactileFocusBlurHostState();
}

class _TactileFocusBlurHostState extends State<TactileFocusBlurHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blurCtrl;
  TactileFocusTarget? _renderTarget;

  @override
  void initState() {
    super.initState();
    _blurCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 155),
    );
    TactileMotionScope.activeFocus.addListener(_syncFocus);
    TactileMotionScope.globalEnabled.addListener(_syncEnabled);
    _syncFocus();
  }

  void _syncEnabled() {
    if (!TactileMotionScope.globalEnabled.value) {
      TactileMotionScope.activeFocus.value = null;
      _renderTarget = null;
      _blurCtrl.value = 0.0;
    }
  }

  void _syncFocus() {
    if (!mounted) return;
    final next = TactileMotionScope.activeFocus.value;
    final enabled = TactileMotionScope.globalEnabled.value;
    if (!enabled) {
      _renderTarget = null;
      _blurCtrl.value = 0.0;
      return;
    }
    if (next != null) {
      setState(() {
        _renderTarget = next;
      });
      _blurCtrl.forward();
    } else {
      _blurCtrl.reverse().then((_) {
        if (mounted && TactileMotionScope.activeFocus.value == null) {
          setState(() {
            _renderTarget = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    TactileMotionScope.activeFocus.removeListener(_syncFocus);
    TactileMotionScope.globalEnabled.removeListener(_syncEnabled);
    _blurCtrl.dispose();
    super.dispose();
  }

  Rect _toLocalRect(Rect globalRect) {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      final topLeft = ro.globalToLocal(globalRect.topLeft);
      final bottomRight = ro.globalToLocal(globalRect.bottomRight);
      return Rect.fromPoints(topLeft, bottomRight);
    }
    return globalRect;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _blurCtrl,
              builder: (context, _) {
                final target = _renderTarget;
                final enabled = TactileMotionScope.globalEnabled.value;
                final t = Curves.easeOutCubic.transform(_blurCtrl.value);
                final sigma = widget.maxBlurSigma * t;
                if (!enabled || target == null || sigma < 0.06) {
                  return const SizedBox.shrink();
                }
                final localRect = _toLocalRect(target.globalRect);
                return ClipPath(
                  clipper: _InverseFocusClipper(
                    targetRect: localRect,
                    isCircle: target.isCircle,
                    borderRadius: target.borderRadius,
                    circleRadius: target.effectiveCircleRadius,
                  ),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.055 * t),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _InverseFocusClipper extends CustomClipper<Path> {
  final Rect targetRect;
  final bool isCircle;
  final double borderRadius;
  final double circleRadius;

  const _InverseFocusClipper({
    required this.targetRect,
    required this.isCircle,
    required this.borderRadius,
    required this.circleRadius,
  });

  @override
  Path getClip(Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (isCircle) {
      path.addOval(
        Rect.fromCircle(center: targetRect.center, radius: circleRadius),
      );
    } else {
      path.addRRect(
        RRect.fromRectAndRadius(
          targetRect.inflate(4.0),
          Radius.circular(borderRadius + 4.0),
        ),
      );
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _InverseFocusClipper oldClipper) =>
      oldClipper.targetRect != targetRect ||
      oldClipper.isCircle != isCircle ||
      oldClipper.borderRadius != borderRadius ||
      oldClipper.circleRadius != circleRadius;
}

/// Non-intrusive wrapper (uses [MouseRegion] + [Listener] so it never competes
/// in the GestureArena) that adds:
/// - Subtle swell/lift on hover
/// - Instant crisp press-in depression on pointer down + surrounding focus blur
/// - Mechanical spring bounce-out on release
class TactilePress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressScale;
  final double hoverLiftY;
  final double pressSinkY;
  final MouseCursor? cursor;
  final bool focusCircle;
  final double focusBorderRadius;

  const TactilePress({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.032,
    this.pressScale = 0.935,
    this.hoverLiftY = -1.2,
    this.pressSinkY = 1.6,
    this.cursor,
    this.focusCircle = false,
    this.focusBorderRadius = 16.0,
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
    this.focusCircle = false,
    this.focusBorderRadius = 20.0,
  });

  @override
  State<TactilePress> createState() => _TactilePressState();
}

class _TactilePressState extends State<TactilePress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final Object _focusToken = Object();
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
      TactileMotionScope.endFocus(_focusToken);
    }
  }

  @override
  void dispose() {
    TactileMotionScope.endFocus(_focusToken);
    _ctrl.dispose();
    super.dispose();
  }

  void _clearPressed({required bool isRelease}) {
    if (!_pressed) return;
    _pressed = false;
    _pointerDownPos = null;
    TactileMotionScope.endFocus(_focusToken);
    _animateToTarget(isRelease: isRelease);
  }

  void _animateToTarget({required bool isRelease}) {
    if (!mounted) return;
    final scopeOn = TactileMotionScope.isEnabled(context);
    if (!scopeOn || !widget.enabled) {
      _ctrl.value = 1.0;
      TactileMotionScope.endFocus(_focusToken);
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
      TactileMotionScope.endFocus(_focusToken);
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
        TactileMotionScope.endFocus(_focusToken);
        _animateToTarget(isRelease: wasPressed);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pointerDownPos = event.position;
          _pressed = true;
          TactileMotionScope.beginFocus(
            context,
            token: _focusToken,
            isCircle: widget.focusCircle,
            borderRadius: widget.focusBorderRadius,
          );
          _animateToTarget(isRelease: false);
        },
        onPointerMove: (event) {
          if (_pressed && _pointerDownPos != null) {
            if ((event.position - _pointerDownPos!).distance > 14.0) {
              _clearPressed(isRelease: false);
            }
          }
        },
        onPointerUp: (_) {
          _clearPressed(isRelease: true);
        },
        onPointerCancel: (_) {
          _clearPressed(isRelease: false);
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
