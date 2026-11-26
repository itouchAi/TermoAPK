import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class BlurredDepthSubTabSwitcher extends StatelessWidget {
  final Widget child;
  final bool disableBlur;

  const BlurredDepthSubTabSwitcher({
    required this.child,
    this.disableBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (childWidget, anim) {
        final isIncoming = childWidget.key == child.key;
        final scale = Tween<double>(
          begin: isIncoming ? 0.97 : 0.91,
          end: 1.0,
        ).animate(anim);
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        Widget content = FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: childWidget,
          ),
        );
        if (!disableBlur) {
          content = AnimatedBuilder(
            animation: anim,
            builder: (_, built) {
              final sigma = ((1.0 - anim.value) * (isIncoming ? 2.4 : 6.5)).clamp(0.0, 7.5);
              if (sigma < 0.25) return built!;
              return ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: built,
              );
            },
            child: content,
          );
        }
        return content;
      },
      child: child,
    );
  }
}
