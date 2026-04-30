import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

enum FeedbackTone { info, success, warning, error }

class AnimatedFeedbackPopupCard extends StatelessWidget {
  final String title;
  final String message;
  final FeedbackTone tone;
  final VoidCallback? onClose;

  const AnimatedFeedbackPopupCard({
    super.key,
    required this.title,
    required this.message,
    this.tone = FeedbackTone.info,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final config = _FeedbackToneConfig.fromTone(tone);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 520,
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.96),
                config.surfaceTint.withValues(alpha: 0.84),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
            boxShadow: [
              BoxShadow(
                color: config.accent.withValues(alpha: 0.14),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
              const BoxShadow(
                color: Color(0x18000000),
                blurRadius: 32,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      config.accent.withValues(alpha: 0.16),
                      config.accent.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: config.accent.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(config.icon, color: config.accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF17252C),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF40545E),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            config.accent,
                            config.accent.withValues(alpha: 0.16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.74),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: Color(0xFF526670),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfessionalProcessingCard extends StatelessWidget {
  final String title;
  final String message;
  final String badge;
  final IconData icon;
  final Color accent;
  final Color accentGlow;

  const ProfessionalProcessingCard({
    super.key,
    required this.title,
    required this.message,
    required this.badge,
    required this.icon,
    required this.accent,
    Color? accentGlow,
  }) : accentGlow = accentGlow ?? accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.94),
                const Color(0xFFF4FBFD).withValues(alpha: 0.88),
              ],
            ),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
            boxShadow: [
              BoxShadow(
                color: accentGlow.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
              const BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 34,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.14),
                        accent.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 15,
                        color: accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        badge,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              ProfessionalActivitySpinner(
                accent: accent,
                accentGlow: accentGlow,
                icon: icon,
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF16242B),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334850),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfessionalActivitySpinner extends StatefulWidget {
  final Color accent;
  final Color accentGlow;
  final IconData icon;

  const ProfessionalActivitySpinner({
    super.key,
    required this.accent,
    required this.accentGlow,
    required this.icon,
  });

  @override
  State<ProfessionalActivitySpinner> createState() =>
      _ProfessionalActivitySpinnerState();
}

class _ProfessionalActivitySpinnerState
    extends State<ProfessionalActivitySpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final pulse = 0.92 + (math.sin(t * math.pi * 2) * 0.06);

        return SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentGlow.withValues(alpha: 0.18),
                        blurRadius: 32,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              RotationTransition(
                turns: _controller,
                child: Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.accent.withValues(alpha: 0.16),
                      width: 3.6,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.accent.withValues(alpha: 0.84),
                            widget.accentGlow,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              RotationTransition(
                turns: Tween<double>(
                  begin: 0,
                  end: -1,
                ).animate(_controller),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.accent.withValues(alpha: 0.10),
                      width: 2.8,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accent.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.accent,
                      widget.accentGlow,
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentGlow.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeedbackToneConfig {
  final Color accent;
  final Color surfaceTint;
  final IconData icon;

  const _FeedbackToneConfig({
    required this.accent,
    required this.surfaceTint,
    required this.icon,
  });

  factory _FeedbackToneConfig.fromTone(FeedbackTone tone) {
    return switch (tone) {
      FeedbackTone.success => const _FeedbackToneConfig(
        accent: Color(0xFF238056),
        surfaceTint: Color(0xFFE9F7EF),
        icon: Icons.check_circle_rounded,
      ),
      FeedbackTone.warning => const _FeedbackToneConfig(
        accent: Color(0xFFB5790A),
        surfaceTint: Color(0xFFFFF4DC),
        icon: Icons.warning_amber_rounded,
      ),
      FeedbackTone.error => const _FeedbackToneConfig(
        accent: Color(0xFFC74B5A),
        surfaceTint: Color(0xFFFFEBEE),
        icon: Icons.error_rounded,
      ),
      FeedbackTone.info => const _FeedbackToneConfig(
        accent: Color(0xFF0B6D8A),
        surfaceTint: Color(0xFFE8F6FB),
        icon: Icons.info_rounded,
      ),
    };
  }
}
