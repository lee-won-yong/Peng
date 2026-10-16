import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shown while local learning data is loaded. Drawn locally without image assets.
class BookSplash extends StatefulWidget {
  const BookSplash({super.key});

  @override
  State<BookSplash> createState() => _BookSplashState();
}

class _BookSplashState extends State<BookSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Semantics(
            label: 'Peng, 학습 자료를 불러오는 중',
            liveRegion: true,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size(240, 180),
                    painter: _BookPainter(_controller, colors.primary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Peng',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '오늘도 한 장씩, 영어와 친해져요',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '학습 자료를 불러오고 있어요…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookPainter extends CustomPainter {
  _BookPainter(this.animation, this.color) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + 4);
    canvas.drawOval(
      const Rect.fromLTWH(-104, 61, 208, 18),
      Paint()..color = color.withValues(alpha: 0.09),
    );
    final cover = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-105, -62, 210, 124),
      const Radius.circular(10),
    );
    canvas.drawRRect(cover, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(62, 35, 13, 37),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xfff2b66d),
    );
    _page(canvas, false);
    _page(canvas, true);

    // The page rotates about the spine, revealing its reverse halfway through.
    final progress = Curves.easeInOut.transform(animation.value);
    final turn = math.cos(progress * math.pi);
    canvas.save();
    canvas.scale(turn, 1);
    final lift = math.sin(progress * math.pi) * 19;
    final page = Path()
      ..moveTo(0, -53)
      ..cubicTo(30, -64 - lift, 71, -63 - lift, 98, -54 - lift)
      ..lineTo(98, 51 - lift)
      ..cubicTo(65, 43 - lift, 30, 44, 0, 56)
      ..close();
    canvas.drawPath(
      page,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xffe1e9e8), Colors.white],
        ).createShader(const Rect.fromLTWH(0, -70, 98, 130)),
    );
    _lines(canvas, lift);
    canvas.restore();
    canvas.drawLine(
      const Offset(0, -53),
      const Offset(0, 56),
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  void _page(Canvas canvas, bool right) {
    canvas.save();
    if (!right) canvas.scale(-1, 1);
    final page = Path()
      ..moveTo(0, -53)
      ..cubicTo(30, -64, 71, -63, 98, -54)
      ..lineTo(98, 51)
      ..cubicTo(65, 43, 30, 44, 0, 56)
      ..close();
    canvas.drawPath(page, Paint()..color = const Color(0xfff8faf7));
    _lines(canvas, 0);
    canvas.restore();
  }

  void _lines(Canvas canvas, double lift) {
    final ink = Paint()
      ..color = color.withValues(alpha: 0.17)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final y = -30.0 + i * 14;
      canvas.drawLine(
        Offset(17, y - lift * 0.2),
        Offset(i == 4 ? 61 : 81, y - 3 - lift * 0.8),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BookPainter oldDelegate) =>
      color != oldDelegate.color || animation != oldDelegate.animation;
}
