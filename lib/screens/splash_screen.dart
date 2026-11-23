// ============================================================
// splash_screen.dart — Animated IntelliGuard opening screen
// Shown briefly before routing to Login or MainShell.
// ============================================================
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5, curve: Curves.elasticOut)));

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.8, curve: Curves.easeIn)));

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.8, curve: Curves.easeOut)));

    _ctrl.forward();

    // Navigate after animation + short pause
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted && !_navigating) {
        _navigating = true;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.next,
            transitionDuration: const Duration(milliseconds: 500),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Background gradient radial glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 1.1,
                  colors: [
                    AppColors.accentPrimary.withValues(alpha: 0.08),
                    AppColors.bgPrimary,
                  ],
                ),
              ),
            ),
          ),

          // Bottom subtle grid lines
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),

          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Shield + camera logo
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => Transform.scale(
                    scale: _logoScale.value,
                    child: Opacity(
                      opacity: _logoFade.value.clamp(0.0, 1.0),
                      child: _ShieldLogo(),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Brand name + tagline
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => SlideTransition(
                    position: _textSlide,
                    child: Opacity(
                      opacity: _textFade.value.clamp(0.0, 1.0),
                      child: Column(
                        children: [
                          RichText(
                            text: const TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Intelli',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 36,
                                    fontWeight: FontWeight.w300,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Guard',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.accentPrimary,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'AI Surveillance & Alert System',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'Smarter Security.\nSafer Tomorrow.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                              height: 1.55,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 60),

                // Loading indicator
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => Opacity(
                    opacity: _textFade.value.clamp(0.0, 1.0),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentPrimary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Version watermark at bottom
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Opacity(
                  opacity: (_textFade.value * 0.5).clamp(0.0, 1.0),
                  child: const Text(
                    'IntelliGuard Security System',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted, letterSpacing: 1),
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

// ── Shield logo widget ────────────────────────────────────────────────────────
class _ShieldLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow ring
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.accentPrimary.withValues(alpha: 0.2),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Shield icon
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgCard,
            border: Border.all(color: AppColors.accentPrimary.withValues(alpha: 0.4), width: 2),
          ),
          child: const Icon(Icons.shield_rounded, color: AppColors.accentPrimary, size: 50),
        ),
        // Camera icon overlay
        Positioned(
          bottom: 18,
          right: 18,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.bgPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentPrimary, width: 1.5),
            ),
            child: const Icon(Icons.videocam_rounded, color: AppColors.accentPrimary, size: 14),
          ),
        ),
      ],
    );
  }
}

// ── Subtle background grid ────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
