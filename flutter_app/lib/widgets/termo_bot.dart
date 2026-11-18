import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

class TermoBotOverlay extends StatefulWidget {
  final bool enabled;
  final bool isSleeping;
  final LangCode lang;
  final Color accentColor;
  final double bottomOffset;
  final VoidCallback onWake;

  const TermoBotOverlay({
    super.key,
    required this.enabled,
    required this.isSleeping,
    required this.lang,
    required this.accentColor,
    required this.bottomOffset,
    required this.onWake,
  });

  @override
  State<TermoBotOverlay> createState() => _TermoBotOverlayState();
}

class _TermoBotOverlayState extends State<TermoBotOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _walkCtrl;
  int _walkCycles = 0;
  bool _napping = false;
  Timer? _bubbleTimer;
  String? _speech;

  @override
  void initState() {
    super.initState();
    _walkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _walkCycles++;
          if (_walkCycles >= 3) {
            if (mounted) setState(() => _napping = true);
          } else {
            _walkCtrl.reverse();
          }
        } else if (status == AnimationStatus.dismissed) {
          _walkCycles++;
          if (_walkCycles >= 3) {
            if (mounted) setState(() => _napping = true);
          } else {
            _walkCtrl.forward();
          }
        }
      });
  }

  @override
  void didUpdateWidget(covariant TermoBotOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && widget.isSleeping && !_walkCtrl.isAnimating && !_napping) {
      _walkCycles = 0;
      _walkCtrl.forward();
    } else if ((!widget.enabled || !widget.isSleeping) && (_walkCtrl.isAnimating || _napping)) {
      _walkCtrl.stop();
      _napping = false;
      _walkCycles = 0;
    }
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _walkCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() {
      _napping = false;
      _walkCycles = 0;
      _speech = widget.lang == LangCode.tr ? 'Sistem dengede, enerji tasarrufu aktif!' : 'System balanced, saving energy!';
    });
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _speech = null);
    });
    widget.onWake();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !widget.isSleeping) return const SizedBox.shrink();

    final width = MediaQuery.of(context).size.width;
    final maxWalk = math.max(80.0, width - 130.0);

    return AnimatedBuilder(
      animation: _walkCtrl,
      builder: (context, child) {
        final x = 18.0 + (_napping ? 0.15 : _walkCtrl.value) * (maxWalk * 0.45);
        final bob = _napping ? 0.0 : math.sin(_walkCtrl.value * math.pi * 10).abs() * 3.0;
        return Positioned(
          left: x,
          bottom: widget.bottomOffset + bob,
          child: GestureDetector(
            onTap: _handleTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_speech != null || _napping)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141620).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.accentColor.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      _speech ?? 'zZz · TermoBot',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF151822).withValues(alpha: 0.90),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.65), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: widget.accentColor.withValues(alpha: 0.35), blurRadius: 14),
                    ],
                  ),
                  child: Icon(
                    _napping ? Icons.bedtime_outlined : Icons.smart_toy_rounded,
                    size: 20,
                    color: widget.accentColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
