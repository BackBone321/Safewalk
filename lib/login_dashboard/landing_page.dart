import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'login_page.dart';
import 'register.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  late final AnimationController _introController;
  late final AnimationController _blobController;
  late final AnimationController _pulseController;

  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // Floating nav — ValueNotifier so ONLY the floating widget rebuilds on scroll
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showFloatingNav = ValueNotifier(false);
  static const double _floatThreshold = 110.0;

  void _onScroll() {
    final shouldShow = _scrollController.offset > _floatThreshold;
    if (_showFloatingNav.value != shouldShow) {
      _showFloatingNav.value = shouldShow;
    }
  }

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _introController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic));

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _introController.dispose();
    _blobController.dispose();
    _pulseController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showFloatingNav.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Widget _stagger({
    required Widget child,
    required double start,
    required double end,
    double y = 28,
  }) {
    final anim = CurvedAnimation(
      parent: _introController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, builtChild) {
        final t = anim.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * y),
            child: builtChild,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 1020;

    return Scaffold(
      backgroundColor: _LC.page,
      body: Stack(
        children: [
          _BackgroundArt(blobAnim: _blobController),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1300),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTopBar(isCompact: isCompact),
                          _stagger(
                            start: 0.00,
                            end: 0.40,
                            child: _HeroSection(
                              isCompact: isCompact,
                              pulseAnim: _pulseController,
                            ),
                          ),
                          _stagger(
                            start: 0.12,
                            end: 0.52,
                            child: const _StatsStrip(),
                          ),
                          _stagger(
                            start: 0.24,
                            end: 0.72,
                            child: _FeaturesSection(key: _featuresKey),
                          ),
                          _stagger(
                            start: 0.38,
                            end: 0.86,
                            child: const _HowItWorksSection(),
                          ),
                          _stagger(
                            start: 0.50,
                            end: 0.95,
                            child: _InfoPanel(
                              key: _aboutKey,
                              title: 'About SafeWalk',
                              tag: 'MISSION',
                              body:
                                  'SafeWalk helps protect students through live location intelligence, emergency routing, and guardian visibility. It is designed for schools that need fast response, accountable records, and clear communication.',
                              icon: Icons.shield_outlined,
                            ),
                          ),
                          _stagger(
                            start: 0.58,
                            end: 1.00,
                            child: _InfoPanel(
                              key: _contactKey,
                              title: 'Contact',
                              tag: 'SUPPORT',
                              body:
                                  'Email: support@safewalk.local\nPhone: +63 900 000 0000\nHours: Monday to Friday, 8:00 AM to 6:00 PM',
                              icon: Icons.mail_outline_rounded,
                            ),
                          ),
                          _buildFooter(isCompact: isCompact),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── Floating nav overlay (only this widget rebuilds on scroll) ──
          _FloatingNav(
            showNotifier: _showFloatingNav,
            isCompact: isCompact,
            onFeatures: () => _scrollTo(_featuresKey),
            onAbout: () => _scrollTo(_aboutKey),
            onContact: () => _scrollTo(_contactKey),
            onScrollTop: () => _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar({required bool isCompact}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 16, 22, 6),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _LC.stroke),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const _BrandMark(compact: true),
          const Spacer(),
          if (!isCompact) ...[
            _TopNavButton(label: 'Features', onTap: () => _scrollTo(_featuresKey)),
            _TopNavButton(label: 'About', onTap: () => _scrollTo(_aboutKey)),
            _TopNavButton(label: 'Contact', onTap: () => _scrollTo(_contactKey)),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter({required bool isCompact}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.85),
            const Color(0xFFF5F9F6).withOpacity(0.90),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _LC.stroke),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandMark(compact: true),
                const SizedBox(height: 12),
                Container(height: 1, color: _LC.stroke),
                const SizedBox(height: 12),
                Text(
                  '© 2026 SafeWalk — Safety Monitoring System',
                  style: TextStyle(
                    fontFamily: _LC.sans,
                    color: _LC.sub.withOpacity(0.75),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                const _BrandMark(compact: true),
                const SizedBox(width: 24),
                Container(width: 1, height: 30, color: _LC.stroke),
                const SizedBox(width: 24),
                Text(
                  'Keeping students safe, every step of the way.',
                  style: TextStyle(
                    fontFamily: _LC.serif,
                    color: _LC.ink.withOpacity(0.55),
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                Text(
                  '© 2026 SafeWalk — Safety Monitoring System',
                  style: TextStyle(
                    fontFamily: _LC.sans,
                    color: _LC.sub.withOpacity(0.70),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Floating Nav (scroll-triggered, high-performance) ────────────────────────
//
// Performance notes:
//  • ValueListenableBuilder rebuilds ONLY this subtree, not the page.
//  • AnimatedOpacity + AnimatedSlide are composited on the GPU — no layout pass.
//  • No setState, no stream, no Timer. Zero overhead when not animating.

class _FloatingNav extends StatelessWidget {
  final ValueNotifier<bool> showNotifier;
  final bool isCompact;
  final VoidCallback onFeatures;
  final VoidCallback onAbout;
  final VoidCallback onContact;
  final VoidCallback onScrollTop;

  const _FloatingNav({
    required this.showNotifier,
    required this.isCompact,
    required this.onFeatures,
    required this.onAbout,
    required this.onContact,
    required this.onScrollTop,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showNotifier,
      builder: (context, show, _) {
        return AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, -1.6),
          duration: const Duration(milliseconds: 340),
          curve: show ? Curves.easeOutCubic : Curves.easeInCubic,
          child: AnimatedOpacity(
            opacity: show ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            // IgnorePointer when hidden so taps pass through
            child: IgnorePointer(
              ignoring: !show,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _FloatingPill(
                      isCompact: isCompact,
                      onFeatures: onFeatures,
                      onAbout: onAbout,
                      onContact: onContact,
                      onScrollTop: onScrollTop,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FloatingPill extends StatelessWidget {
  final bool isCompact;
  final VoidCallback onFeatures;
  final VoidCallback onAbout;
  final VoidCallback onContact;
  final VoidCallback onScrollTop;

  const _FloatingPill({
    required this.isCompact,
    required this.onFeatures,
    required this.onAbout,
    required this.onContact,
    required this.onScrollTop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: isCompact
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : const EdgeInsets.fromLTRB(16, 8, 10, 8),
      decoration: BoxDecoration(
        // Frosted-glass dark pill
        color: _LC.ink.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.30),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _LC.accent.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini brand dot + wordmark
          GestureDetector(
            onTap: onScrollTop,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A6B4A), Color(0xFF0A2D1D)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'SW',
                      style: TextStyle(
                        fontFamily: _LC.sans,
                        color: _LC.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'SafeWalk',
                    style: TextStyle(
                      fontFamily: _LC.serif,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Divider
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.white.withOpacity(0.18),
          ),
          // Nav items
          if (!isCompact) ...[
            _PillNavBtn(label: 'Features', onTap: onFeatures),
            _PillNavBtn(label: 'About', onTap: onAbout),
            _PillNavBtn(label: 'Contact', onTap: onContact),
            const SizedBox(width: 6),
          ] else ...[
            _PillIconBtn(icon: Icons.grid_view_rounded, onTap: onFeatures, tooltip: 'Features'),
            _PillIconBtn(icon: Icons.info_outline_rounded, onTap: onAbout, tooltip: 'About'),
            _PillIconBtn(icon: Icons.mail_outline_rounded, onTap: onContact, tooltip: 'Contact'),
          ],
          // Back-to-top CTA
          GestureDetector(
            onTap: onScrollTop,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E9160), Color(0xFF156B48)],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    isCompact ? 'Top' : 'Back to top',
                    style: const TextStyle(
                      fontFamily: _LC.sans,
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillNavBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillNavBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withOpacity(0.80),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontFamily: _LC.sans,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
      child: Text(label),
    );
  }
}

class _PillIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _PillIconBtn({required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white.withOpacity(0.80), size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

class _BackgroundArt extends StatelessWidget {
  final Animation<double> blobAnim;
  const _BackgroundArt({required this.blobAnim});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFEBF5EF),
                Color(0xFFF8F4EC),
                Color(0xFFF1F7F3),
                Color(0xFFFAF6EE),
              ],
              stops: [0.0, 0.38, 0.70, 1.0],
            ),
          ),
        ),
        // Animated blob top-left
        AnimatedBuilder(
          animation: blobAnim,
          builder: (_, __) {
            final t = blobAnim.value;
            return Positioned(
              top: -180 + t * 40,
              left: -90 + t * 20,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _LC.accent.withOpacity(0.22 + t * 0.08),
                      _LC.accent.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // Animated blob right
        AnimatedBuilder(
          animation: blobAnim,
          builder: (_, __) {
            final t = blobAnim.value;
            return Positioned(
              right: -130 + t * 30,
              top: 190 + t * 60,
              child: Container(
                width: 460,
                height: 460,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _LC.gold.withOpacity(0.18 + t * 0.07),
                      _LC.gold.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // Decorative bottom blob
        AnimatedBuilder(
          animation: blobAnim,
          builder: (_, __) {
            final t = blobAnim.value;
            return Positioned(
              bottom: -200 + t * 50,
              left: 100 + t * 40,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _LC.ink.withOpacity(0.04 + t * 0.02),
                      _LC.ink.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // Top accent bar (tri-color gradient)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            height: 5,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A3222), Color(0xFF1E7E52), Color(0xFF289A69), Color(0xFFCBA95A)],
                stops: [0.0, 0.35, 0.65, 1.0],
              ),
            ),
          ),
        ),
        // Subtle noise texture overlay via dot pattern
        Positioned.fill(
          child: CustomPaint(painter: _DotPatternPainter()),
        ),
      ],
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0E3425).withOpacity(0.025)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─── Brand Mark ───────────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  final bool compact;
  const _BrandMark({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 40.0 : 72.0;
    final titleSize = compact ? 22.0 : 52.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A6B4A), Color(0xFF0A2D1D)],
            ),
            boxShadow: [
              BoxShadow(
                color: _LC.ink.withOpacity(0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: _LC.sans,
                color: _LC.gold,
                fontSize: compact ? 15 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 10 : 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SafeWalk',
              style: TextStyle(
                fontFamily: _LC.serif,
                fontSize: titleSize,
                height: 1.0,
                color: _LC.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!compact)
              Text(
                'Safety Monitoring System',
                style: TextStyle(
                  fontFamily: _LC.sans,
                  fontSize: 11,
                  color: _LC.sub,
                  letterSpacing: 1.4,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final bool isCompact;
  final Animation<double> pulseAnim;
  const _HeroSection({required this.isCompact, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final left = _HeroLeft(isCompact: isCompact);
    final right = _HeroRight(pulseAnim: pulseAnim);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: 14),
                right,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: left),
                const SizedBox(width: 16),
                Expanded(flex: 9, child: right),
              ],
            ),
    );
  }
}

class _HeroLeft extends StatelessWidget {
  final bool isCompact;
  const _HeroLeft({required this.isCompact});

  @override
  Widget build(BuildContext context) {
    final headline = isCompact ? 54.0 : 82.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.88),
            const Color(0xFFF4FAF7).withOpacity(0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _LC.stroke.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: _LC.accent.withOpacity(0.08),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: _LC.ink.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _LC.accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _LC.accent.withOpacity(0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _LC.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'LIVE SAFETY NETWORK',
                  style: TextStyle(
                    fontFamily: _LC.sans,
                    color: _LC.accent,
                    fontSize: 11,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _BrandMark(compact: false),
          const SizedBox(height: 20),
          // Headline
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: _LC.serif,
                fontSize: headline,
                height: 0.88,
                color: _LC.ink,
              ),
              children: const [
                TextSpan(text: 'Fast Alerts.\n'),
                TextSpan(
                  text: 'Calm Response.',
                  style: TextStyle(
                    color: _LC.goldDeep,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Decorative rule
          Container(
            width: 64,
            height: 3,
            margin: const EdgeInsets.only(top: 14, bottom: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_LC.accent, _LC.gold],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Text(
            'Track student locations, receive SOS events instantly, and coordinate guardians and staff from one connected dashboard.',
            style: TextStyle(
              fontFamily: _LC.sans,
              fontSize: isCompact ? 16 : 18,
              color: _LC.sub,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 26),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _GooeyButton(
                label: 'Create Account',
                icon: Icons.person_add_alt_1_rounded,
                isPrimary: true,
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 200),
                    reverseTransitionDuration: const Duration(milliseconds: 160),
                    pageBuilder: (_, __, ___) => const RegisterPage(),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(
                        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
              _GooeyButton(
                label: 'Sign In',
                icon: Icons.login_rounded,
                isPrimary: false,
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 200),
                    reverseTransitionDuration: const Duration(milliseconds: 160),
                    pageBuilder: (_, __, ___) => const LoginPage(),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(
                        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _Tag(text: 'Admin + Parent Portal'),
              _Tag(text: 'Instant SOS Routing'),
              _Tag(text: 'Real-Time GPS Updates'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroRight extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _HeroRight({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    const events = [
      _LiveEvent('SOS alert received', 'Science Building', 'Now', Icons.warning_amber_rounded, Color(0xFFFFE9E9)),
      _LiveEvent('Guardian notified', 'Parent App', '12s ago', Icons.notifications_active_outlined, Color(0xFFFFF3DC)),
      _LiveEvent('Device secured', 'Gate 2 Exit', '48s ago', Icons.shield_outlined, Color(0xFFE8F5EE)),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7FDFB), Color(0xFFF0F6F2), Color(0xFFFAF6EE)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: _LC.stroke.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.07),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: _LC.gold.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(4, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              AnimatedBuilder(
                animation: pulseAnim,
                builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 18 + pulseAnim.value * 8,
                      height: 18 + pulseAnim.value * 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _LC.accent.withOpacity((1 - pulseAnim.value) * 0.25),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: _LC.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'MONITORING ACTIVE',
                style: TextStyle(
                  fontFamily: _LC.sans,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  color: _LC.sub,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0E3425), Color(0xFF1A5C3A)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: _LC.ink.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: _LC.sans,
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Map preview
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE2F0E9), Color(0xFFEDF5EF), Color(0xFFF2EDE0)],
              ),
              border: Border.all(color: _LC.stroke.withOpacity(0.8)),
              boxShadow: [
                BoxShadow(
                  color: _LC.ink.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CustomPaint(painter: _MapGridPainter()),
                )),
                // Zone circle
                Align(
                  alignment: const Alignment(-0.1, 0.1),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _LC.accent.withOpacity(0.10),
                      border: Border.all(
                        color: _LC.accent.withOpacity(0.30),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                // Location pin
                Align(
                  alignment: const Alignment(-0.1, 0.1),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: _LC.ink.withOpacity(0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 28,
                      color: _LC.ink,
                    ),
                  ),
                ),
                // Mini markers
                Positioned(
                  right: 38,
                  top: 48,
                  child: _MapDot(color: _LC.goldDeep.withOpacity(0.8)),
                ),
                Positioned(
                  left: 28,
                  bottom: 40,
                  child: _MapDot(color: _LC.accent.withOpacity(0.7)),
                ),
                Positioned(
                  right: 70,
                  bottom: 28,
                  child: _MapDot(color: _LC.ink.withOpacity(0.4)),
                ),
                // Stats overlay
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _LC.ink.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_alt_outlined, color: Colors.white, size: 13),
                        SizedBox(width: 5),
                        Text(
                          '24 tracked',
                          style: TextStyle(
                            fontFamily: _LC.sans,
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Events
          ...events.map((event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LiveEventTile(event: event),
              )),
        ],
      ),
    );
  }
}

class _MapDot extends StatelessWidget {
  final Color color;
  const _MapDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 5)],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = _LC.stroke.withOpacity(0.35)
      ..strokeWidth = 0.8;

    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Safe zone circles
    final zonePaint = Paint()
      ..color = _LC.accent.withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.30), 34, zonePaint);

    // Route path
    final route = Paint()
      ..color = _LC.goldDeep.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.72)
      ..quadraticBezierTo(size.width * 0.30, size.height * 0.20, size.width * 0.54, size.height * 0.50)
      ..quadraticBezierTo(size.width * 0.72, size.height * 0.68, size.width * 0.92, size.height * 0.38);

    canvas.drawPath(path, route);

    // Dashed accent path
    final dash = Paint()
      ..color = _LC.accent.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final dashPath = Path()
      ..moveTo(size.width * 0.65, size.height * 0.30)
      ..lineTo(size.width * 0.80, size.height * 0.56);

    canvas.drawPath(dashPath, dash);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _LiveEvent {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final Color tint;

  const _LiveEvent(this.title, this.subtitle, this.time, this.icon, this.tint);
}

class _LiveEventTile extends StatelessWidget {
  final _LiveEvent event;
  const _LiveEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _LC.stroke.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: event.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(event.icon, size: 18, color: _LC.ink.withOpacity(0.80)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontFamily: _LC.sans,
                    fontWeight: FontWeight.w700,
                    color: _LC.ink,
                    fontSize: 13,
                  ),
                ),
                Text(
                  event.subtitle,
                  style: TextStyle(
                    fontFamily: _LC.sans,
                    fontSize: 11,
                    color: _LC.sub.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _LC.ink.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              event.time,
              style: const TextStyle(
                fontFamily: _LC.sans,
                color: _LC.sub,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats Strip ──────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    const stats = [
      _StatData('99.4%', 'Alert delivery reliability', Icons.verified_outlined),
      _StatData('2.3 sec', 'Average guardian notification', Icons.speed_outlined),
      _StatData('24 / 7', 'Monitoring availability', Icons.access_time_outlined),
      _StatData('1 panel', 'Unified admin + parent oversight', Icons.dashboard_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1060
              ? 4
              : constraints.maxWidth >= 700
                  ? 2
                  : 1;
          const gap = 12.0;
          final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: stats
                .map((s) => SizedBox(width: cardWidth, child: _StatCard(data: s)))
                .toList(),
          );
        },
      ),
    );
  }
}

class _StatData {
  final String value;
  final String caption;
  final IconData icon;

  const _StatData(this.value, this.caption, this.icon);
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.90),
            const Color(0xFFF5FAF7).withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _LC.stroke),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _LC.accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: _LC.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_LC.ink, Color(0xFF1E6B48)],
                  ).createShader(bounds),
                  child: Text(
                    data.value,
                    style: const TextStyle(
                      fontFamily: _LC.serif,
                      fontSize: 32,
                      height: 0.95,
                      color: Colors.white, // masked
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.caption,
                  style: const TextStyle(
                    fontFamily: _LC.sans,
                    color: _LC.sub,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Features ─────────────────────────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required super.key});

  @override
  Widget build(BuildContext context) {
    final titleSize = MediaQuery.of(context).size.width < 640 ? 36.0 : 48.0;

    const features = [
      _FeatureData('Live Tracking', 'Follow registered devices in real time across safety zones.', Icons.location_searching_rounded, Color(0xFFE5F5EE)),
      _FeatureData('Smart SOS', 'Route emergencies to guardians and staff in seconds.', Icons.sos_rounded, Color(0xFFFFECEC)),
      _FeatureData('Geofencing', 'Get notified when students enter or exit assigned areas.', Icons.map_outlined, Color(0xFFFFF3DC)),
      _FeatureData('Role Access', 'Separate secure dashboards for admins, parents, and staff.', Icons.admin_panel_settings_outlined, Color(0xFFEEF3FF)),
      _FeatureData('Audit Trail', 'Keep incident history and timeline logs for accountability.', Icons.history_edu_outlined, Color(0xFFF5EEF8)),
      _FeatureData('Device Finder', 'Quickly locate lost or inactive registered devices.', Icons.phonelink_ring_outlined, Color(0xFFEDF7F4)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.88),
              const Color(0xFFF7FAF8).withOpacity(0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _LC.stroke),
          boxShadow: [
            BoxShadow(
              color: _LC.ink.withOpacity(0.04),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _LC.gold.withOpacity(0.28),
                    _LC.gold.withOpacity(0.14),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _LC.gold.withOpacity(0.50)),
              ),
              child: const Text(
                'FEATURE SET',
                style: TextStyle(
                  fontFamily: _LC.sans,
                  color: _LC.goldDeep,
                  letterSpacing: 1.8,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Everything Needed For\nFast, Informed Response',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _LC.serif,
                fontSize: titleSize,
                height: 0.92,
                color: _LC.ink,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Built to minimize uncertainty during incidents and keep everyone coordinated\nfrom the first alert to final update.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: _LC.sans,
                fontSize: 16,
                color: _LC.sub,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1080 ? 3 : width >= 700 ? 2 : 1;
                const gap = 12.0;
                final cardWidth = (width - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: features
                      .map((f) => SizedBox(width: cardWidth, child: _FeatureCard(data: f)))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureData {
  final String title;
  final String description;
  final IconData icon;
  final Color tint;

  const _FeatureData(this.title, this.description, this.icon, this.tint);
}

class _FeatureCard extends StatelessWidget {
  final _FeatureData data;
  const _FeatureCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _LC.stroke.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: _LC.ink.withOpacity(0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: data.tint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, color: _LC.ink.withOpacity(0.75), size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            data.title,
            style: const TextStyle(
              fontFamily: _LC.serif,
              fontSize: 28,
              height: 0.95,
              color: _LC.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 30,
            height: 2,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_LC.accent, _LC.gold]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.description,
            style: const TextStyle(
              fontFamily: _LC.sans,
              fontSize: 13,
              color: _LC.sub,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── How It Works ─────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    final titleSize = MediaQuery.of(context).size.width < 640 ? 40.0 : 52.0;

    const steps = [
      _StepData('Register Users', 'Assign student and guardian accounts with secure role access.', Icons.person_add_alt_rounded),
      _StepData('Connect Devices', 'Bind approved devices and set safety location zones.', Icons.devices_other_rounded),
      _StepData('Monitor + Respond', 'Receive incidents live and coordinate response from one panel.', Icons.health_and_safety_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C3122), Color(0xFF144E38), Color(0xFF0F3C2C)],
            stops: [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A2A1E).withOpacity(0.22),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.20)),
              ),
              child: const Text(
                'PROCESS',
                style: TextStyle(
                  fontFamily: _LC.sans,
                  color: Color(0xFFD4F0E2),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'How It Works',
              style: TextStyle(
                fontFamily: _LC.serif,
                fontSize: titleSize,
                color: const Color(0xFFFFF8F0),
                height: 0.92,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Launch-ready flow for schools and families.',
              style: TextStyle(
                fontFamily: _LC.sans,
                color: Color(0xFFB8E8CE),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                const gap = 14.0;
                final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: List.generate(
                    steps.length,
                    (i) => SizedBox(
                      width: cardWidth,
                      child: _StepCard(step: steps[i], index: i + 1),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StepData {
  final String title;
  final String body;
  final IconData icon;

  const _StepData(this.title, this.body, this.icon);
}

class _StepCard extends StatelessWidget {
  final _StepData step;
  final int index;
  const _StepCard({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.12),
            Colors.white.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8B66D).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD8B66D).withOpacity(0.35)),
                ),
                child: Icon(step.icon, color: const Color(0xFFEDD28A), size: 20),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '0$index',
                  style: const TextStyle(
                    fontFamily: _LC.sans,
                    color: Color(0xFFEDD28A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            step.title,
            style: const TextStyle(
              fontFamily: _LC.serif,
              fontSize: 30,
              height: 0.95,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 24,
            height: 2,
            decoration: BoxDecoration(
              color: const Color(0xFFD8B66D).withOpacity(0.60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: const TextStyle(
              fontFamily: _LC.sans,
              color: Color(0xFFCEEAD8),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Panel ───────────────────────────────────────────────────────────────

class _InfoPanel extends StatelessWidget {
  final String title;
  final String tag;
  final String body;
  final IconData icon;

  const _InfoPanel({
    required super.key,
    required this.title,
    required this.tag,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final titleSize = MediaQuery.of(context).size.width < 640 ? 32.0 : 40.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.88),
              const Color(0xFFF6FAF7).withOpacity(0.84),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _LC.stroke),
          boxShadow: [
            BoxShadow(
              color: _LC.ink.withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _LC.gold.withOpacity(0.26),
                          _LC.gold.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _LC.gold.withOpacity(0.45)),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontFamily: _LC.sans,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        color: _LC.goldDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: _LC.serif,
                      color: _LC.ink,
                      fontSize: titleSize,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 36,
                    height: 2,
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_LC.accent, _LC.gold]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    body,
                    style: const TextStyle(
                      fontFamily: _LC.sans,
                      fontSize: 15,
                      color: _LC.sub,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _LC.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _LC.accent.withOpacity(0.20)),
              ),
              child: Icon(icon, color: _LC.accent, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _LC.ink.withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _LC.stroke.withOpacity(1.0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: _LC.sans,
          fontSize: 12,
          color: _LC.ink,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _TopNavButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TopNavButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _LC.ink,
        textStyle: const TextStyle(
          fontFamily: _LC.sans,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

// ─── Gooey Hover Buttons ──────────────────────────────────────────────────────
//
// Performance notes:
//  • Each button owns ONE AnimationController — no shared state, no setState cascade.
//  • MouseRegion.onEnter/onExit only call _ctrl.forward/reverse — O(1) cost.
//  • AnimatedBuilder rebuilds ONLY the button subtree (not the page).
//  • _GooeyFillPainter.shouldRepaint guards against unnecessary repaints.
//  • ClipRRect (borderRadius) is the only layout-affecting property; it doesn't
//    change on hover, so Flutter never triggers a relayout pass.

class _GooeyButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _GooeyButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_GooeyButton> createState() => _GooeyButtonState();
}

class _GooeyButtonState extends State<_GooeyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.isPrimary;

    // Primary: dark-green base, lighter-green goo fills in
    // Secondary: transparent base with gold border, dark-green goo fills in
    final blobColor =
        isPrimary ? const Color(0xFF1E9160) : const Color(0xFF0C3322);
    final idleTextColor = isPrimary ? Colors.white : _LC.goldDeep;
    final hoverTextColor = Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _ctrl.forward(),
      onExit: (_) => _ctrl.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = _anim.value;
            final labelColor = Color.lerp(idleTextColor, hoverTextColor, t)!;

            return Container(
              decoration: BoxDecoration(
                // Primary keeps its gradient base; secondary stays transparent
                gradient: isPrimary
                    ? const LinearGradient(
                        colors: [Color(0xFF0E3425), Color(0xFF1A5C3A)],
                      )
                    : null,
                borderRadius: BorderRadius.circular(13),
                border: isPrimary
                    ? null
                    : Border.all(
                        color: Color.lerp(
                          _LC.goldDeep,
                          const Color(0xFF0C3322),
                          t,
                        )!,
                        width: 1.5,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: (isPrimary ? _LC.ink : _LC.goldDeep)
                        .withOpacity(isPrimary ? 0.28 + t * 0.12 : t * 0.22),
                    blurRadius: 14 + t * 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // ── Gooey wave fill (GPU path, no layout) ──
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GooeyFillPainter(
                          progress: t,
                          color: blobColor,
                        ),
                      ),
                    ),
                    // ── Label row ──
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, size: 17, color: labelColor),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: TextStyle(
                              fontFamily: _LC.sans,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: 0.3,
                              color: labelColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints a liquid wave that rises from the bottom of the button.
///
/// The wave amplitude peaks at 50% fill (most gooey-looking moment) and
/// flattens to zero at both ends — so the button looks clean at idle and
/// fully filled on complete hover.
///
/// Only [progress] and [color] drive repaints — no timers or extra state.
class _GooeyFillPainter extends CustomPainter {
  final double progress; // 0.0 = empty  →  1.0 = full
  final Color color;

  const _GooeyFillPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Wave amplitude: sine envelope so it's 0 at 0% and 100%, max at 50%
    final amplitude = h * 0.30 * math.sin(progress * math.pi);
    final blobTop = h * (1.0 - progress);

    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, blobTop);

    // 32-segment smooth wave across the top edge of the rising blob
    const steps = 32;
    for (int i = 0; i <= steps; i++) {
      final x = w * i / steps;
      // Two sine frequencies combined for an organic, non-repeating shape
      final wave = amplitude *
          (0.65 * math.sin(i / steps * math.pi * 3.0 + progress * math.pi * 2) +
           0.35 * math.sin(i / steps * math.pi * 5.5 - progress * math.pi));
      path.lineTo(x, blobTop + wave);
    }

    path
      ..lineTo(w, h)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GooeyFillPainter old) =>
      old.progress != progress || old.color != color;
}



// ─── Design Tokens ────────────────────────────────────────────────────────────

class _LC {
  static const String serif = 'CormorantGaramond';
  static const String sans = 'JosefinSans';

  static const page = Color(0xFFF3F7F4);
  static const ink = Color(0xFF0C3322);
  static const sub = Color(0xFF3D5F52);
  static const accent = Color(0xFF1E9160);
  static const gold = Color(0xFFD8B66D);
  static const goldDeep = Color(0xFF9A6F22);
  static const stroke = Color(0x60B5A57E);
}