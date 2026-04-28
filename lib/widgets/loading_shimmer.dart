import 'package:flutter/material.dart';

/// Shimmer-style loading placeholder that animates a gradient sweep
/// across placeholder shapes, giving the user a preview of content layout.
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({super.key});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final highlightColor = isDark ? Colors.white24 : Colors.grey.shade50;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stat cards row
              Row(
                children: [
                  Expanded(child: _shimmerBox(baseColor, highlightColor, height: 80, radius: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: _shimmerBox(baseColor, highlightColor, height: 80, radius: 18)),
                ],
              ),
              const SizedBox(height: 16),
              // Content cards
              _shimmerBox(baseColor, highlightColor, height: 140, radius: 18),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, height: 140, radius: 18),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, height: 100, radius: 18),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(Color base, Color highlight,
      {required double height, double radius = 12}) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-1.0 + 2.0 * _controller.value + 1, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

/// Simple slide-up page route transition.
class SlideUpRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SlideUpRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final tween = Tween(begin: const Offset(0, 0.15), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic));
            final fadeTween = Tween(begin: 0.0, end: 1.0)
                .chain(CurveTween(curve: Curves.easeOut));
            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(
                opacity: animation.drive(fadeTween),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 250),
        );
}
