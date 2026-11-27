import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';
import 'tactile_button.dart';

class FlowTabBarShell extends StatefulWidget {
  final TabId activeTab;
  final List<TabMeta> orderedTabs;
  final TabId? startupTab;
  final ValueChanged<TabId> onSelectTab;
  final ValueChanged<int>? onStepTab;
  final void Function(List<TabId> nextOrder, {TabId? nextStartupTab})? onReorderTabs;
  final RgbAccent activeAccent;
  final LangCode lang;
  final bool isLandscape;
  final PerformanceMode performanceMode;
  final ThemePaletteSpec palette;
  final VoidCallback onOpenVoice;
  final bool voiceOpen;
  final Widget child;

  const FlowTabBarShell({
    super.key,
    required this.activeTab,
    required this.orderedTabs,
    this.startupTab,
    required this.onSelectTab,
    this.onStepTab,
    this.onReorderTabs,
    required this.activeAccent,
    required this.lang,
    required this.isLandscape,
    required this.performanceMode,
    required this.palette,
    required this.onOpenVoice,
    required this.voiceOpen,
    required this.child,
  });

  @override
  State<FlowTabBarShell> createState() => _FlowTabBarShellState();
}

class _FlowTabBarShellState extends State<FlowTabBarShell> with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final Ticker _ticker;
  double _elapsedSec = 0.0;
  int _lastTickMs = 0;
  int _curIndex = 0;
  FlowMove? _activeMove;
  RgbAccent _smoothAccent = const RgbAccent(1.0, 0.48, 0.14);
  DateTime? _lastDockWheelAt;
  int? _hoveredTab;
  int? _pressedTab;
  Offset? _pressOrigin;

  TabId? _draggingTabId;
  double? _dragStartGlobalX;
  int _dragStartIndex = 0;
  bool _promotedStartupDuringDrag = false;
  String? _reorderToastText;
  int _reorderToastSeq = 0;

  void _handleDockWheel(PointerSignalEvent event) {
    if (_pressedTab != null) {
      setState(() {
        _pressedTab = null;
        _pressOrigin = null;
      });
    }
    if (event is! PointerScrollEvent || widget.orderedTabs.isEmpty) return;
    final now = DateTime.now();
    if (_lastDockWheelAt != null && now.difference(_lastDockWheelAt!).inMilliseconds < 170) {
      return;
    }
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final primary = dx.abs() > dy.abs() ? dx : dy;
    if (primary.abs() < 4.0) return;
    _lastDockWheelAt = now;
    final dir = primary > 0 ? 1 : -1;
    if (widget.onStepTab != null) {
      widget.onStepTab!(dir);
    } else {
      final len = widget.orderedTabs.length;
      final nextIdx = ((_curIndex + dir) % len + len) % len;
      _handleTapTab(nextIdx, widget.orderedTabs[nextIdx]);
    }
  }

  int _indexOfTab(TabId id) {
    final idx = widget.orderedTabs.indexWhere((t) => t.id == id);
    return idx < 0 ? 0 : idx.clamp(0, widget.orderedTabs.length - 1);
  }

  @override
  void initState() {
    super.initState();
    _curIndex = _indexOfTab(widget.activeTab);
    _smoothAccent = widget.activeAccent;
    _loadShader();
    _ticker = createTicker((elapsed) {
      final ms = elapsed.inMilliseconds;
      // Eco Battery throttles background shader updates to ~20 FPS (~50 ms interval)
      if (widget.performanceMode == PerformanceMode.ecoBattery && ms - _lastTickMs < 50) {
        return;
      }
      _lastTickMs = ms;
      setState(() {
        _elapsedSec = elapsed.inMicroseconds / 1000000.0;
        _smoothAccent = RgbAccent(
          ThermostatMath.lerp(_smoothAccent.r, widget.activeAccent.r, 0.14),
          ThermostatMath.lerp(_smoothAccent.g, widget.activeAccent.g, 0.14),
          ThermostatMath.lerp(_smoothAccent.b, widget.activeAccent.b, 0.14),
        );
      });
    })..start();
  }

  Future<void> _loadShader() async {
    try {
      final prog = await ui.FragmentProgram.fromAsset('shaders/flow_tab_bar.frag');
      if (mounted) {
        setState(() => _program = prog);
      }
    } catch (_) {
      // Fallback gradient renders automatically if shader asset fails
    }
  }

  @override
  void didUpdateWidget(covariant FlowTabBarShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIdx = _indexOfTab(widget.activeTab);
    if (nextIdx != _curIndex) {
      _activeMove = FlowMove(
        ts: _elapsedSec,
        a: _curIndex,
        b: nextIdx,
        d: ThermostatMath.moveLength(nextIdx - _curIndex),
        fromAcc: _smoothAccent,
        toAcc: widget.activeAccent,
      );
      _curIndex = nextIdx;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _handleTapTab(int idx, TabMeta meta) {
    if (_draggingTabId != null) return;
    if (idx != _curIndex) {
      _activeMove = FlowMove(
        ts: _elapsedSec,
        a: _curIndex,
        b: idx,
        d: ThermostatMath.moveLength(idx - _curIndex),
        fromAcc: _smoothAccent,
        toAcc: widget.palette.themeOverrideAccent ?? meta.accent,
      );
      _curIndex = idx;
    }
    widget.onSelectTab(meta.id);
  }

  void _beginLongPressDrag(int slotIdx, LongPressStartDetails details) {
    if (widget.onReorderTabs == null || slotIdx >= widget.orderedTabs.length) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _draggingTabId = widget.orderedTabs[slotIdx].id;
      _dragStartGlobalX = details.globalPosition.dx;
      _dragStartIndex = slotIdx;
      _promotedStartupDuringDrag = false;
      _pressedTab = null;
      _pressOrigin = null;
    });
  }

  void _updateLongPressDrag(LongPressMoveUpdateDetails details, double scale) {
    final dragged = _draggingTabId;
    final startX = _dragStartGlobalX;
    final callback = widget.onReorderTabs;
    if (dragged == null || startX == null || callback == null) return;

    final currentIdx = widget.orderedTabs.indexWhere((t) => t.id == dragged);
    if (currentIdx < 0) return;

    final safeScale = math.max(0.2, scale);
    final virtualDeltaX = (details.globalPosition.dx - startX) / safeScale;
    final startCenterX = ThermostatMath.tabXs[_dragStartIndex.clamp(0, ThermostatMath.tabXs.length - 1)];
    final targetVirtualX = startCenterX + virtualDeltaX;

    var nearestIdx = currentIdx;
    var bestDist = double.infinity;
    final limit = math.min(widget.orderedTabs.length, ThermostatMath.tabXs.length);
    for (int i = 0; i < limit; i++) {
      final d = (ThermostatMath.tabXs[i] - targetVirtualX).abs();
      if (d < bestDist) {
        bestDist = d;
        nearestIdx = i;
      }
    }

    if (nearestIdx != currentIdx) {
      HapticFeedback.selectionClick();
      final nextOrder = [for (final t in widget.orderedTabs) t.id];
      final moved = nextOrder.removeAt(currentIdx);
      nextOrder.insert(nearestIdx, moved);
      final promoteStartup = nearestIdx == 0;
      if (promoteStartup) {
        _promotedStartupDuringDrag = true;
      }
      callback(
        nextOrder,
        nextStartupTab: promoteStartup ? dragged : null,
      );
    }
  }

  void _endLongPressDrag() {
    final dragged = _draggingTabId;
    if (dragged == null) return;
    final tr = widget.lang == LangCode.tr;
    final meta = widget.orderedTabs.firstWhere(
      (t) => t.id == dragged,
      orElse: () => widget.orderedTabs.first,
    );
    final idx = widget.orderedTabs.indexWhere((t) => t.id == dragged);
    final label = tr ? meta.labelTr : meta.labelEn;
    final toast = _promotedStartupDuringDrag || idx == 0
        ? (tr
            ? '★ $label ana başlangıç ekranı & 1. sıra oldu'
            : '★ $label set as startup & slot #1')
        : (tr
            ? '✓ $label yeni sıraya taşındı (${idx + 1}/${widget.orderedTabs.length})'
            : '✓ $label moved to slot ${idx + 1}/${widget.orderedTabs.length}');
    final seq = ++_reorderToastSeq;
    setState(() {
      _draggingTabId = null;
      _dragStartGlobalX = null;
      _promotedStartupDuringDrag = false;
      _reorderToastText = toast;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && seq == _reorderToastSeq) {
        setState(() => _reorderToastText = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final vw = media.size.width;
    final vh = media.size.height;
    final bottomSafe = media.padding.bottom;
    final landscape = vw > vh;
    final compactLandscape = landscape && vh < 480;

    final voiceSize = compactLandscape ? 42.0 : 50.0;
    final gap = landscape ? 12.0 : 10.0;
    final maxDockWidth = compactLandscape
        ? math.min(vw - 32, 410.0)
        : landscape
            ? math.min(vw - 32, 460.0)
            : math.min(vw - 18, 456.0);
    final barPixelWidth = math.max(238.0, maxDockWidth - voiceSize - gap);
    final scale = barPixelWidth / 808.0;
    final barPixelHeight = 124.0 * scale;
    final bottomPad = (compactLandscape ? 6.0 : 14.0) + bottomSafe;

    final dockStartX = (vw - (barPixelWidth + gap + voiceSize)) / 2.0;
    final barCenterX = dockStartX + barPixelWidth / 2.0;
    final barCenterY = vh - bottomPad - barPixelHeight / 2.0;
    final viewX = barCenterX;
    final viewY = barCenterY - 60.0 * scale;

    final flow = ThermostatMath.computeFlowState(
      _elapsedSec,
      _activeMove,
      _curIndex,
      _smoothAccent,
    );

    final fgColor = widget.palette.isLight ? const Color(0xFF0F172A) : Colors.white;
    final tr = widget.lang == LangCode.tr;

    String? dragBannerText = _reorderToastText;
    if (_draggingTabId != null) {
      final dIdx = widget.orderedTabs.indexWhere((t) => t.id == _draggingTabId);
      final meta = widget.orderedTabs.firstWhere(
        (t) => t.id == _draggingTabId,
        orElse: () => widget.orderedTabs.first,
      );
      final label = tr ? meta.labelTr : meta.labelEn;
      dragBannerText = dIdx == 0
          ? (tr
              ? '★ $label · Sıra 1 (Ana Başlangıç Ekranı)'
              : '★ $label · Slot 1 (Startup Screen)')
          : (tr
              ? '⇄ $label · Sıra ${dIdx + 1}/${widget.orderedTabs.length} (Başlangıç için en sola sürükle)'
              : '⇄ $label · Slot ${dIdx + 1}/${widget.orderedTabs.length} (Drag leftmost for startup)');
    }

    return Stack(
      children: [
        // 1. Fullscreen GLSL atmospheric background + liquid glass Flow Tab Bar
        Positioned.fill(
          child: CustomPaint(
            painter: _FlowShaderPainter(
              program: _program,
              elapsedSec: _elapsedSec,
              viewX: viewX,
              viewY: viewY,
              scale: scale,
              flow: flow,
              isLandscape: landscape,
              palette: widget.palette,
            ),
          ),
        ),

        // 2. App pages rendered above background
        Positioned.fill(child: widget.child),

        // 3. Synchronized virtual 1080x1080 Flow Tab Bar icons, labels & tap/drag targets
        Positioned(
          left: viewX - 540.0,
          top: viewY - 540.0,
          width: 1080.0,
          height: 1080.0,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Stack(
              children: [
                for (int i = 0; i < widget.orderedTabs.length; i++)
                  _buildVirtualTabVisuals(i, widget.orderedTabs[i], flow, fgColor),
                for (int i = 0; i < widget.orderedTabs.length; i++)
                  Positioned(
                    left: ThermostatMath.tabXs[i] - 76.0,
                    top: 538.0,
                    width: 152.0,
                    height: 124.0,
                    child: MouseRegion(
                      onEnter: (_) {
                        if (_hoveredTab != i) setState(() => _hoveredTab = i);
                      },
                      onExit: (_) {
                        if (_hoveredTab == i || _pressedTab == i) {
                          setState(() {
                            if (_hoveredTab == i) _hoveredTab = null;
                            if (_pressedTab == i) {
                              _pressedTab = null;
                              _pressOrigin = null;
                            }
                          });
                        }
                      },
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerSignal: _handleDockWheel,
                        onPointerDown: (ev) {
                          setState(() {
                            _pressedTab = i;
                            _pressOrigin = ev.position;
                          });
                        },
                        onPointerMove: (ev) {
                          if (_draggingTabId == null &&
                              _pressedTab == i &&
                              _pressOrigin != null &&
                              (ev.position - _pressOrigin!).distance > 14.0) {
                            setState(() {
                              _pressedTab = null;
                              _pressOrigin = null;
                            });
                          }
                        },
                        onPointerUp: (_) {
                          if (_pressedTab == i) {
                            setState(() {
                              _pressedTab = null;
                              _pressOrigin = null;
                            });
                          }
                        },
                        onPointerCancel: (_) {
                          if (_pressedTab == i) {
                            setState(() {
                              _pressedTab = null;
                              _pressOrigin = null;
                            });
                          }
                        },
                        child: Semantics(
                          button: true,
                          selected: i == _curIndex,
                          label: widget.lang == LangCode.tr
                              ? widget.orderedTabs[i].labelTr
                              : widget.orderedTabs[i].labelEn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _handleTapTab(i, widget.orderedTabs[i]),
                            onLongPressStart: (details) => _beginLongPressDrag(i, details),
                            onLongPressMoveUpdate: (details) => _updateLongPressDrag(details, scale),
                            onLongPressEnd: (_) => _endLongPressDrag(),
                            onLongPressCancel: _endLongPressDrag,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Floating priority / drag-reorder guide chip right above Flow Tab Bar
        if (dragBannerText != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + barPixelHeight + 10,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.palette.isLight
                        ? Colors.white.withValues(alpha: 0.94)
                        : const Color(0xFF10131E).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: widget.activeAccent.toColor(0.55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    dragBannerText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.palette.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // 4. Circular Voice Assistant button next to Flow Tab Bar
        Positioned(
          left: dockStartX + barPixelWidth + gap,
          top: barCenterY - voiceSize / 2.0,
          width: voiceSize,
          height: voiceSize,
          child: TactilePress(
            focusCircle: true,
            child: Semantics(
              button: true,
              label: widget.lang == LangCode.tr ? 'Sesli Komut Asistanı' : 'Voice Command Assistant',
              child: GestureDetector(
                onTap: widget.onOpenVoice,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.palette.isLight
                        ? Colors.white.withValues(alpha: widget.voiceOpen ? 0.85 : 0.65)
                        : Colors.white.withValues(alpha: widget.voiceOpen ? 0.14 : 0.07),
                    border: Border.all(
                      color: widget.palette.isLight
                          ? const Color(0xFF0F172A).withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.voiceOpen
                            ? widget.activeAccent.toColor(0.45)
                            : Colors.black.withValues(alpha: widget.palette.isLight ? 0.16 : 0.45),
                        blurRadius: widget.voiceOpen ? 20 : 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(Icons.mic_none_rounded, color: fgColor, size: 21),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVirtualTabVisuals(int i, TabMeta tab, FlowTabState flow, Color fgColor) {
    const by = 600.0;
    final tx = ThermostatMath.tabXs[i.clamp(0, ThermostatMath.tabXs.length - 1)];
    final w = math.pow(
      ThermostatMath.clamp01(1.0 - (flow.x - tx).abs() / 86.0),
      1.5,
    ).toDouble();
    final a = w * ThermostatMath.clamp01(flow.rise);
    final iconOpacity = ThermostatMath.lerp(0.56, 1.0, ThermostatMath.clamp01(a * 1.3));
    final drawProgress = i == flow.cur ? flow.draw : 1.0;

    final la = math.pow(ThermostatMath.clamp01((a - 0.5) / 0.5), 1.4).toDouble();
    final labelOpacity = ThermostatMath.lerp(0.62, 1.0, la);
    final labelY = by + 14.0 - 16.0 * la;

    final tactileActive = TactileMotionScope.isEnabled(context);
    final isDraggingThis = _draggingTabId == tab.id;
    final isHovered = tactileActive && _hoveredTab == i;
    final isPressed = tactileActive && _pressedTab == i;
    final tactileScale = isDraggingThis
        ? 1.18
        : (isPressed ? 0.90 : (isHovered ? 1.055 : 1.0));
    final isStartup = widget.startupTab == tab.id;

    return IgnorePointer(
      child: Stack(
        children: [
          if (isDraggingThis || (_draggingTabId != null && isStartup))
            Positioned(
              left: tx - 66.0,
              top: by - 48.0 - 54.0 * a,
              width: 132.0,
              height: 112.0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28.0),
                  color: (isDraggingThis ? widget.activeAccent.toColor() : const Color(0xFFFBBF24))
                      .withValues(alpha: isDraggingThis ? 0.24 : 0.14),
                  border: Border.all(
                    color: (isDraggingThis ? widget.activeAccent.toColor() : const Color(0xFFFBBF24))
                        .withValues(alpha: 0.72),
                    width: 2.2,
                  ),
                ),
              ),
            ),
          Positioned(
            left: tx - 26.0,
            top: by - 42.0 - 54.0 * a,
            width: 52.0,
            height: 52.0,
            child: AnimatedScale(
              scale: tactileScale,
              duration: Duration(milliseconds: isPressed ? 75 : 170),
              curve: isPressed ? Curves.easeOutQuad : Curves.easeOutBack,
              child: Transform.scale(
                scale: 1.0 + 0.12 * a,
                child: Opacity(
                  opacity: iconOpacity,
                  child: CustomPaint(
                    painter: _FlowTabIconPainter(
                      tabId: tab.id,
                      drawProgress: drawProgress,
                      color: isDraggingThis ? widget.activeAccent.toColor() : fgColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isStartup && _draggingTabId != null)
            Positioned(
              left: tx + 18.0,
              top: by - 48.0 - 54.0 * a,
              child: const Icon(
                Icons.star_rounded,
                size: 22.0,
                color: Color(0xFFFBBF24),
              ),
            ),
          Positioned(
            left: tx - 74.0,
            top: labelY,
            width: 148.0,
            child: AnimatedScale(
              scale: tactileScale,
              duration: Duration(milliseconds: isPressed ? 75 : 170),
              curve: isPressed ? Curves.easeOutQuad : Curves.easeOutBack,
              child: Opacity(
                opacity: labelOpacity,
                child: Text(
                  widget.lang == LangCode.tr ? tab.labelTr : tab.labelEn,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDraggingThis ? widget.activeAccent.toColor() : fgColor,
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowShaderPainter extends CustomPainter {
  final ui.FragmentProgram? program;
  final double elapsedSec;
  final double viewX;
  final double viewY;
  final double scale;
  final FlowTabState flow;
  final bool isLandscape;
  final ThemePaletteSpec palette;

  const _FlowShaderPainter({
    required this.program,
    required this.elapsedSec,
    required this.viewX,
    required this.viewY,
    required this.scale,
    required this.flow,
    required this.isLandscape,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final prog = program;
    if (prog == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = palette.scaffoldBg);
      final focalAlign = isLandscape ? const Alignment(-0.42, -0.08) : const Alignment(0.0, -0.14);
      final fallbackPaint = Paint()
        ..shader = RadialGradient(
          center: focalAlign,
          radius: 0.95,
          colors: [
            flow.acc.toColor(palette.isLight ? 0.20 : 0.32),
            flow.acc.toColor(palette.isLight ? 0.08 : 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, fallbackPaint);
      return;
    }

    final shader = prog.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, elapsedSec);
    shader.setFloat(3, viewX);
    shader.setFloat(4, viewY);
    shader.setFloat(5, scale);
    shader.setFloat(6, flow.x);
    shader.setFloat(7, flow.rise);
    shader.setFloat(8, flow.sx);
    shader.setFloat(9, flow.acc.r);
    shader.setFloat(10, flow.acc.g);
    shader.setFloat(11, flow.acc.b);
    shader.setFloat(12, flow.tapX);
    shader.setFloat(13, flow.tapAge);
    shader.setFloat(14, 0.0);
    shader.setFloat(15, flow.sw);
    shader.setFloat(16, isLandscape ? 0.27 : 0.50);
    shader.setFloat(17, isLandscape ? 0.46 : 0.44);
    shader.setFloat(18, palette.daylightMix);
    shader.setFloat(19, palette.tactileWarmth);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _FlowShaderPainter oldDelegate) => true;
}

class _FlowTabIconPainter extends CustomPainter {
  final TabId tabId;
  final double drawProgress;
  final Color color;

  const _FlowTabIconPainter({
    required this.tabId,
    required this.drawProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 44.0;
    final sy = size.height / 44.0;
    canvas.save();
    canvas.scale(sx, sy);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final paths = <Path>[];

    switch (tabId) {
      case TabId.ev:
        paths.add(
          Path()
            ..moveTo(8, 21)
            ..lineTo(22, 10)
            ..lineTo(36, 21),
        );
        paths.add(
          Path()
            ..moveTo(12, 19)
            ..lineTo(12, 34)
            ..lineTo(32, 34)
            ..lineTo(32, 19),
        );
        paths.add(
          Path()
            ..moveTo(19, 34)
            ..lineTo(19, 25)
            ..lineTo(25, 25)
            ..lineTo(25, 34),
        );
        break;
      case TabId.termo:
        paths.add(
          Path()
            ..moveTo(10, 34)
            ..lineTo(10, 20)
            ..arcToPoint(const Offset(34, 20), radius: const Radius.circular(12), clockwise: true)
            ..lineTo(34, 34),
        );
        paths.add(
          Path()
            ..moveTo(22, 34)
            ..lineTo(22, 26),
        );
        break;
      case TabId.hava:
        paths.add(
          Path()
            ..moveTo(15, 28)
            ..arcToPoint(const Offset(14.6, 14.02), radius: const Radius.circular(7), clockwise: true)
            ..arcToPoint(const Offset(31.8, 16), radius: const Radius.circular(9), clockwise: true)
            ..arcToPoint(const Offset(32, 27), radius: const Radius.circular(5.5), clockwise: true)
            ..lineTo(15, 27),
        );
        paths.add(
          Path()
            ..moveTo(14, 34)
            ..lineTo(30, 34),
        );
        break;
      case TabId.rapor:
        paths.add(
          Path()
            ..addArc(Rect.fromCircle(center: const Offset(22, 22), radius: 12), -math.pi / 2, math.pi * 1.5),
        );
        paths.add(
          Path()
            ..moveTo(26, 8)
            ..arcToPoint(const Offset(36, 18), radius: const Radius.circular(10), clockwise: true)
            ..lineTo(26, 18)
            ..close(),
        );
        break;
      case TabId.prog:
        paths.add(
          Path()
            ..addArc(Rect.fromCircle(center: const Offset(22, 22), radius: 12), math.pi, math.pi * 1.5),
        );
        paths.add(
          Path()
            ..moveTo(22, 15)
            ..lineTo(22, 22)
            ..lineTo(27, 26),
        );
        canvas.drawCircle(const Offset(12, 32), 2.0, fillPaint);
        break;
    }

    final clamped = drawProgress.clamp(0.0, 1.0);
    for (final p in paths) {
      for (final metric in p.computeMetrics()) {
        final extracted = metric.extractPath(0.0, metric.length * clamped);
        canvas.drawPath(extracted, strokePaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlowTabIconPainter oldDelegate) =>
      oldDelegate.tabId != tabId ||
      oldDelegate.drawProgress != drawProgress ||
      oldDelegate.color != color;
}
