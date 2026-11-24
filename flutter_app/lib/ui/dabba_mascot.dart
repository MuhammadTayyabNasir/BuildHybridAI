import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pma_ui.dart';

/// What Dabba is doing; drives its face and motion.
enum DabbaMood { idle, listening, thinking, speaking, happy, worried, sleeping }

/// Dabba ("box" in Urdu): PMA's assistant, a friendly cardboard-box robot
/// that matches the logo. Drawn entirely in code so it scales crisply and
/// animates without asset files.
///
/// * idle      – gentle bob, blinks now and then
/// * listening – antenna light pulses, lid flaps lift like ears
/// * thinking  – eyes look up, three dots orbit the antenna
/// * speaking  – mouth opens and closes, sound waves on the side
/// * happy     – a hop with closed happy eyes (after a save)
/// * worried   – eyebrows tilt, tint turns red (a red value)
/// * sleeping  – eyes closed, slow breathing (offline / no session)
class Dabba extends StatefulWidget {
  const Dabba({super.key, this.mood = DabbaMood.idle, this.size = 96});

  final DabbaMood mood;
  final double size;

  @override
  State<Dabba> createState() => _DabbaState();
}

class _DabbaState extends State<Dabba> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    Future<void>.delayed(Duration(milliseconds: 1800 + _rand.nextInt(2600)), () async {
      if (!mounted) return;
      await _blink.forward();
      if (!mounted) return;
      await _blink.reverse();
      _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Dabba, the PMA assistant, ${widget.mood.name}',
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _blink]),
              builder: (_, _) => CustomPaint(
                painter: _DabbaPainter(
                  t: _loop.value,
                  blink: _blink.value,
                  mood: widget.mood,
                ),
              ),
            ),
          ),
        ),
      );
}

class _DabbaPainter extends CustomPainter {
  _DabbaPainter({required this.t, required this.blink, required this.mood});

  final double t; // 0..1 loop
  final double blink; // 0 open .. 1 closed
  final DabbaMood mood;

  static const _dark = Color(0xFF2B2A30);
  static const _boxTop = Color(0xFFFFB45C);
  static const _boxFront = Color(0xFFFF8A3D);
  static const _boxSide = Color(0xFFE2632A);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100; // design in a 100x100 box
    canvas.save();
    canvas.scale(s);

    final wave = math.sin(t * 2 * math.pi);
    final double bob = switch (mood) {
      DabbaMood.happy => -6 * math.max(0.0, math.sin(t * 4 * math.pi)),
      DabbaMood.sleeping => 1.2 * wave,
      DabbaMood.speaking => 1.5 * math.sin(t * 6 * math.pi),
      _ => 2.2 * wave,
    };

    // Shadow
    final shadowW = 46 - bob.abs() * 1.5;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 93), width: shadowW, height: 6),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    canvas.translate(0, bob);

    final worried = mood == DabbaMood.worried;
    final front = worried ? const Color(0xFFE8574A) : _boxFront;
    final top = worried ? const Color(0xFFF58A7C) : _boxTop;
    final side = worried ? const Color(0xFFC63C33) : _boxSide;

    // Arms (behind body)
    final armSwing = mood == DabbaMood.speaking
        ? 8 * math.sin(t * 6 * math.pi)
        : mood == DabbaMood.happy
            ? -18.0
            : 3 * wave;
    final arm = Paint()
      ..color = _dark
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(24, 62), Offset(14, 70 + armSwing), arm);
    canvas.drawLine(const Offset(76, 62), Offset(86, 70 - armSwing), arm);
    canvas.drawCircle(Offset(14, 70 + armSwing), 3.4, Paint()..color = Pma.sun);
    canvas.drawCircle(Offset(86, 70 - armSwing), 3.4, Paint()..color = Pma.sun);

    // Feet
    final foot = Paint()..color = _dark;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(33, 82, 12, 6), const Radius.circular(3)), foot);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(55, 82, 12, 6), const Radius.circular(3)), foot);

    // Body: front face + right side + top
    final outline = Paint()
      ..color = _dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round;
    final sidePath = Path()
      ..moveTo(72, 40)
      ..lineTo(80, 34)
      ..lineTo(80, 76)
      ..lineTo(72, 84)
      ..close();
    canvas.drawPath(sidePath, Paint()..color = side);
    canvas.drawPath(sidePath, outline);

    final frontRect = RRect.fromRectAndRadius(const Rect.fromLTWH(24, 40, 48, 44), const Radius.circular(5));
    canvas.drawRRect(
      frontRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [front, Color.lerp(front, side, 0.45)!],
        ).createShader(frontRect.outerRect),
    );
    canvas.drawRRect(frontRect, outline);

    // Circuit lines on the side, like the logo
    final circuit = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..moveTo(75, 48)..lineTo(75, 58)..lineTo(78, 61), circuit);
    canvas.drawCircle(const Offset(78, 61), 1.3, Paint()..color = Colors.white70);

    // Lid flaps: lift when listening / happy
    final lift = switch (mood) {
      DabbaMood.listening => 10 + 4 * math.sin(t * 4 * math.pi),
      DabbaMood.happy => 14.0,
      DabbaMood.sleeping => 0.0,
      _ => 4 + 1.5 * wave,
    };
    _flap(canvas, const Offset(24, 40), const Offset(48, 40), -lift, top, outline);
    _flap(canvas, const Offset(48, 40), const Offset(72, 40), lift, top, outline);
    // back lid edge to the side
    canvas.drawPath(
      Path()
        ..moveTo(72, 40)
        ..lineTo(80, 34)
        ..lineTo(56, 34)
        ..lineTo(48, 40),
      Paint()..color = top.withValues(alpha: 0.85),
    );

    // Antenna
    final antennaTop = Offset(48 + 2 * wave, 18);
    canvas.drawLine(const Offset(48, 36), antennaTop, arm..strokeWidth = 2.4);
    final glow = switch (mood) {
      DabbaMood.listening => 0.55 + 0.45 * math.sin(t * 8 * math.pi).abs(),
      DabbaMood.speaking => 0.8,
      DabbaMood.sleeping => 0.15,
      _ => 0.5,
    };
    canvas.drawCircle(antennaTop, 7 * glow + 2,
        Paint()..color = (worried ? Pma.bad : Pma.sun).withValues(alpha: 0.25 * glow));
    canvas.drawCircle(antennaTop, 4, Paint()..color = worried ? Pma.bad : Pma.flame);
    canvas.drawCircle(antennaTop.translate(-1.2, -1.2), 1.2, Paint()..color = Colors.white);

    // Face plate
    final face = RRect.fromRectAndRadius(const Rect.fromLTWH(31, 50, 34, 24), const Radius.circular(8));
    canvas.drawRRect(face, Paint()..color = _dark);

    // Eyes
    final look = mood == DabbaMood.thinking ? const Offset(1.5, -2.5) : Offset(1.2 * wave, 0);
    final closed = mood == DabbaMood.sleeping ? 1.0 : blink;
    final eyePaint = Paint()..color = const Color(0xFF7CF5D6);
    for (final cx in [41.0, 55.0]) {
      final c = Offset(cx, 59) + look;
      if (mood == DabbaMood.happy) {
        canvas.drawArc(Rect.fromCenter(center: c.translate(0, 1.5), width: 7, height: 6), math.pi, math.pi, false,
            Paint()
              ..color = eyePaint.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round);
      } else {
        final h = 6.5 * (1 - closed) + 0.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 5.5, height: h), const Radius.circular(3)),
          eyePaint,
        );
      }
    }
    if (worried) {
      final brow = Paint()
        ..color = eyePaint.color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(37, 53.5), const Offset(44, 55.5), brow);
      canvas.drawLine(const Offset(59, 53.5), const Offset(52, 55.5), brow);
    }

    // Mouth
    final mouth = Paint()
      ..color = eyePaint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case DabbaMood.speaking:
        final open = 1 + 3.5 * math.sin(t * 10 * math.pi).abs();
        canvas.drawOval(Rect.fromCenter(center: const Offset(48, 68.5), width: 7, height: open),
            Paint()..color = eyePaint.color);
      case DabbaMood.worried:
        canvas.drawArc(Rect.fromCenter(center: const Offset(48, 71), width: 8, height: 4), math.pi, math.pi, false, mouth);
      case DabbaMood.thinking:
        canvas.drawLine(const Offset(45, 68.5), const Offset(51, 68.5), mouth);
      case DabbaMood.sleeping:
        canvas.drawLine(const Offset(46, 68.5), const Offset(50, 68.5), mouth);
      default:
        canvas.drawArc(Rect.fromCenter(center: const Offset(48, 66.5), width: 9, height: 5), 0.15, math.pi - 0.3, false, mouth);
    }

    // Mood extras
    if (mood == DabbaMood.thinking) {
      for (var i = 0; i < 3; i++) {
        final a = t * 2 * math.pi + i * 2 * math.pi / 3;
        canvas.drawCircle(antennaTop + Offset(9 * math.cos(a), 5 * math.sin(a)), 1.8,
            Paint()..color = Pma.flame.withValues(alpha: 0.4 + 0.2 * i));
      }
    }
    if (mood == DabbaMood.speaking || mood == DabbaMood.listening) {
      final w = Paint()
        ..color = Pma.flame.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 2; i++) {
        final p = (t * 2 + i * 0.5) % 1;
        final r = 6 + 8 * p;
        w.color = Pma.flame.withValues(alpha: 0.7 * (1 - p));
        final c = mood == DabbaMood.speaking ? const Offset(88, 50) : const Offset(10, 50);
        final start = mood == DabbaMood.speaking ? -0.6 : math.pi - 0.6;
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, 1.2, false, w);
      }
    }
    if (mood == DabbaMood.sleeping) {
      final z = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(fontSize: 9 + 3 * t, color: Pma.inkSoft.withValues(alpha: 1 - t), fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      z.paint(canvas, Offset(70 + 6 * t, 20 - 10 * t));
    }
    if (mood == DabbaMood.happy) {
      final sp = Paint()..color = Pma.sun;
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + t * math.pi;
        canvas.drawCircle(const Offset(48, 30) + Offset(30 * math.cos(a), 14 * math.sin(a)), 1.6, sp);
      }
    }
    canvas.restore();
  }

  void _flap(Canvas c, Offset a, Offset b, double lift, Color color, Paint outline) {
    final mid = Offset((a.dx + b.dx) / 2, a.dy);
    final tip = mid.translate(lift * 0.35, -8 - lift.abs() * 0.6);
    final p = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(b.dx + (lift > 0 ? 4 : -2), tip.dy)
      ..lineTo(a.dx + (lift > 0 ? 2 : -4), tip.dy)
      ..close();
    c.drawPath(p, Paint()..color = color);
    c.drawPath(p, outline);
  }

  @override
  bool shouldRepaint(_DabbaPainter old) =>
      old.t != t || old.blink != blink || old.mood != mood;
}

/// Dabba with a speech bubble, for empty states and greetings.
class DabbaSays extends StatelessWidget {
  const DabbaSays({
    super.key,
    required this.message,
    this.mood = DabbaMood.idle,
    this.size = 88,
  });

  final String message;
  final DabbaMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Dabba(mood: mood, size: size),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              margin: EdgeInsets.only(bottom: size * 0.45),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Text(message, style: const TextStyle(color: Pma.ink, height: 1.3)),
            ),
          ),
        ],
      );
}
