import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pouch_coin.dart';

class PouchMotion extends StatefulWidget {
  const PouchMotion({required this.child, super.key});

  final Widget child;

  static void celebrate(BuildContext context, {GlobalKey? anchor}) {
    context.findAncestorStateOfType<_PouchMotionState>()?._celebrate(anchor);
  }

  @override
  State<PouchMotion> createState() => _PouchMotionState();
}

class _PouchMotionState extends State<PouchMotion>
    with SingleTickerProviderStateMixin {
  final _stage = GlobalKey();
  late final _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..addStatusListener(_onStatus);
  Offset? _origin;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _origin = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _progress.stop();
      _origin = null;
    }
  }

  void _celebrate(GlobalKey? anchor) {
    if (!mounted ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    final stage = _stage.currentContext?.findRenderObject();
    if (stage is! RenderBox || !stage.hasSize || !stage.attached) return;
    final size = stage.size;
    if (size.width < 80 || size.height < 80) return;
    var origin = Offset(size.width / 2, size.height * 0.62);
    final button = anchor?.currentContext?.findRenderObject();
    if (button is RenderBox && button.attached && button.hasSize) {
      final center = stage.globalToLocal(
        button.localToGlobal(button.size.center(Offset.zero)),
      );
      if ((Offset.zero & size).contains(center)) origin = center;
    }
    origin = Offset(
      origin.dx.clamp(40.0, size.width - 40.0).toDouble(),
      origin.dy.clamp(40.0, size.height - 40.0).toDouble(),
    );
    setState(() => _origin = origin);
    _progress.forward(from: 0);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: _stage,
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_origin != null)
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('pouch-coin-burst'),
                  painter: _CoinBurstPainter(_progress, _origin!),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _CoinBurstPainter extends CustomPainter {
  _CoinBurstPainter(this.progress, this.origin) : super(repaint: progress);

  final Animation<double> progress;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final opacity =
        (t / 0.08).clamp(0.0, 1.0).toDouble() *
        ((1 - t) / 0.35).clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < 12; i++) {
      final spread = (i - 5.5) / 5.5;
      final lift = 115.0 + (i % 4) * 19.0;
      final position =
          origin +
          Offset(spread * (76 + (i % 3) * 13) * t, -lift * t + 155 * t * t);
      final radius = 4.5 + i % 3;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(spread * t * 2);
      PouchCoinPainter.draw(
        canvas,
        radius: radius,
        angle: t * math.pi * 2 + i * 0.7,
        opacity: opacity,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CoinBurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.origin != origin;
}
