import 'dart:math' as math;

import 'package:flutter/material.dart';

class PouchCoin extends StatefulWidget {
  const PouchCoin({this.size = 28, super.key}) : assert(size > 0);

  final double size;

  @override
  State<PouchCoin> createState() => _PouchCoinState();
}

class _PouchCoinState extends State<PouchCoin>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
    value: 0.08,
  );
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRotation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateRotation();
  }

  void _updateRotation() {
    if (!mounted) return;
    if (_foreground &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      if (MediaQuery.disableAnimationsOf(context)) _rotation.value = 0.08;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: PouchCoinPainter(rotation: _rotation)),
        ),
      ),
    ),
  );
}

class PouchCoinPainter extends CustomPainter {
  PouchCoinPainter({required this.rotation}) : super(repaint: rotation);

  final Animation<double> rotation;

  static final _edgeShader = const LinearGradient(
    colors: [Color(0xFF77501A), Color(0xFFD6A347), Color(0xFF946119)],
  ).createShader(const Rect.fromLTRB(-1, -1, 1, 1));
  static final _faceShader = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE7A2), Color(0xFFE3B758), Color(0xFFB67B27)],
    stops: [0, 0.45, 1],
  ).createShader(const Rect.fromLTRB(-1, -1, 1, 1));
  static final _emblem = Path()
    ..moveTo(-0.24, 0.42)
    ..lineTo(-0.24, -0.42)
    ..lineTo(0.10, -0.42)
    ..cubicTo(0.52, -0.42, 0.52, 0.08, 0.10, 0.08)
    ..lineTo(-0.24, 0.08);

  static void draw(
    Canvas canvas, {
    required double radius,
    required double angle,
    double opacity = 1,
  }) {
    final faceWidth = math.cos(angle).abs().clamp(0.025, 1.0).toDouble();
    final depth = math.sin(angle).abs() * 0.19;
    final faceOffset = -math.sin(angle).sign * depth / 2;
    final edge = Paint()
      ..shader = _edgeShader
      ..color = Colors.white.withValues(alpha: opacity);
    final face = Paint()
      ..shader = _faceShader
      ..color = Colors.white.withValues(alpha: opacity);
    final rim = Paint()
      ..color = const Color(0xFF98651D).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07;
    final highlight = Paint()
      ..color = const Color(0xFFFFF0BF).withValues(alpha: opacity * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.045
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.scale(radius, radius);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 2 * faceWidth + depth,
        height: 2,
      ),
      edge,
    );
    canvas.translate(faceOffset, 0);
    canvas.scale(faceWidth, 1);
    const faceBounds = Rect.fromLTRB(-1, -1, 1, 1);
    canvas.drawOval(faceBounds, face);
    canvas.drawOval(faceBounds.deflate(0.045), rim);
    canvas.drawOval(faceBounds.deflate(0.20), highlight);
    canvas.drawArc(faceBounds.deflate(0.11), -2.8, 1.9, false, highlight);
    if (faceWidth > 0.12) {
      canvas.save();
      if (math.cos(angle) < 0) canvas.scale(-1, 1);
      canvas.translate(0.015, 0.025);
      rim
        ..strokeWidth = 0.14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(_emblem, rim);
      canvas.translate(-0.025, -0.045);
      highlight.strokeWidth = 0.06;
      canvas.drawPath(_emblem, highlight);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    draw(
      canvas,
      radius: math.min(size.width, size.height) * 0.44,
      angle: rotation.value * math.pi * 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PouchCoinPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
