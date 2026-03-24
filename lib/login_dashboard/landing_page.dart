import 'package:flutter/material.dart';

import 'login_page.dart';
import 'register.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  late final AnimationController _introController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _introController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Widget _stagger({
    required Widget child,
    required double start,
    required double end,
    double y = 22,
  }) {
    final anim = CurvedAnimation(
      parent: _introController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, builtChild) {
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
      backgroundColor: _LColors.page,
      body: Stack(
        children: [
          const _BackgroundArt(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1260),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTopBar(isCompact: isCompact),
                          _stagger(
                            start: 0.00,
                            end: 0.40,
                            child: _HeroSection(isCompact: isCompact),
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
                                  'SafeWalk helps campuses protect students through live location intelligence, emergency routing, and guardian visibility. It is designed for schools that need fast response, accountable records, and clear communication.',
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
        ],
      ),
    );
  }

  Widget _buildTopBar({required bool isCompact}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Row(
        children: [
          const _BrandMark(compact: true),
          const Spacer(),
          if (!isCompact) ...[
            _TopNavButton(label: 'Features', onTap: () => _scrollTo(_featuresKey)),
            _TopNavButton(label: 'About', onTap: () => _scrollTo(_aboutKey)),
            _TopNavButton(label: 'Contact', onTap: () => _scrollTo(_contactKey)),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter({required bool isCompact}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _LColors.stroke),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _BrandMark(compact: true),
                SizedBox(height: 10),
                Text(
                  'Copyright 2026 SafeWalk. Campus Safety Monitoring System.',
                  style: TextStyle(
                    fontFamily: _LColors.sans,
                    color: _LColors.sub,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : Row(
              children: const [
                _BrandMark(compact: true),
                Spacer(),
                Text(
                  'Copyright 2026 SafeWalk. Campus Safety Monitoring System.',
                  style: TextStyle(
                    fontFamily: _LColors.sans,
                    color: _LColors.sub,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
    );
  }
}

class _BackgroundArt extends StatelessWidget {
  const _BackgroundArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEEF7F4), Color(0xFFF8F2E8), Color(0xFFF6F9F8)],
            ),
          ),
        ),
        Positioned(
          top: -140,
          left: -80,
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _LColors.accent.withOpacity(0.30),
                  _LColors.accent.withOpacity(0.02),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: -120,
          top: 210,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _LColors.gold.withOpacity(0.24),
                  _LColors.gold.withOpacity(0.01),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF114B36), Color(0xFF289A69), Color(0xFFCBA95A)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
class _BrandMark extends StatelessWidget {
  final bool compact;
  const _BrandMark({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 38.0 : 72.0;
    final titleSize = compact ? 34.0 : 72.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF145A40), Color(0xFF0A2D1D)],
            ),
          ),
          child: Center(
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: _LColors.sans,
                color: _LColors.gold,
                fontSize: compact ? 16 : 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 10 : 14),
        Text(
          'SafeWalk',
          style: TextStyle(
            fontFamily: _LColors.serif,
            fontSize: titleSize,
            height: 0.9,
            color: _LColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HeroSection extends StatelessWidget {
  final bool isCompact;
  const _HeroSection({required this.isCompact});

  @override
  Widget build(BuildContext context) {
    final left = _HeroLeft(isCompact: isCompact);
    const right = _HeroRight();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: 16),
                right,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: left),
                const SizedBox(width: 18),
                const Expanded(flex: 9, child: right),
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
    final headline = isCompact ? 52.0 : 78.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.76),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _LColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _LColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE CAMPUS SAFETY NETWORK',
                style: TextStyle(
                  fontFamily: _LColors.sans,
                  color: _LColors.sub,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _BrandMark(compact: isCompact),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: _LColors.serif,
                fontSize: headline,
                height: 0.90,
                color: _LColors.ink,
              ),
              children: const [
                TextSpan(text: 'Fast Alerts.\n'),
                TextSpan(
                  text: 'Calm Response.',
                  style: TextStyle(color: _LColors.goldDeep, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Track student locations, receive SOS events instantly, and coordinate guardians and staff from one connected dashboard.',
            style: TextStyle(
              fontFamily: _LColors.sans,
              fontSize: isCompact ? 17 : 19,
              color: _LColors.sub,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PrimaryButton(
                label: 'Create Account',
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 180),
                    reverseTransitionDuration: const Duration(milliseconds: 150),
                    pageBuilder: (_, __, ___) => const RegisterPage(),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(
                        opacity: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
              _SecondaryButton(
                label: 'Sign In',
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 180),
                    reverseTransitionDuration: const Duration(milliseconds: 150),
                    pageBuilder: (_, __, ___) => const LoginPage(),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(
                        opacity: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
  const _HeroRight();

  @override
  Widget build(BuildContext context) {
    const events = [
      _LiveEvent(
        'SOS alert received',
        'Science Building',
        'Now',
        Icons.warning_amber_rounded,
      ),
      _LiveEvent(
        'Guardian notified',
        'Parent App',
        '12s ago',
        Icons.notifications_active_outlined,
      ),
      _LiveEvent(
        'Device secured',
        'Gate 2 Exit',
        '48s ago',
        Icons.shield_outlined,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9FDFC), Color(0xFFF4F7F4)],
        ),
        border: Border.all(color: _LColors.stroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14062A1C),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: const BoxDecoration(
                  color: _LColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'MONITORING ACTIVE',
                style: TextStyle(
                  fontFamily: _LColors.sans,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  color: _LColors.sub,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _LColors.ink,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: _LColors.sans,
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 188,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE7F4EE), Color(0xFFEFF7F1), Color(0xFFF5EFE3)],
              ),
              border: Border.all(color: _LColors.stroke.withOpacity(0.9)),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _MapGridPainter()),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _LColors.accent.withOpacity(0.13),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 42,
                      color: _LColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...events
              .map((event) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _LiveEventTile(event: event),
                  ))
              .toList(),
        ],
      ),
    );
  }
}
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = _LColors.stroke.withOpacity(0.45)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final route = Paint()
      ..color = _LColors.goldDeep.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.22,
        size.width * 0.56,
        size.height * 0.47,
      )
      ..quadraticBezierTo(
        size.width * 0.71,
        size.height * 0.66,
        size.width * 0.90,
        size.height * 0.42,
      );

    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LiveEvent {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;

  const _LiveEvent(this.title, this.subtitle, this.time, this.icon);
}

class _LiveEventTile extends StatelessWidget {
  final _LiveEvent event;
  const _LiveEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _LColors.stroke.withOpacity(0.9)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _LColors.ink.withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(event.icon, size: 18, color: _LColors.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontFamily: _LColors.sans,
                    fontWeight: FontWeight.w700,
                    color: _LColors.ink,
                    fontSize: 14,
                  ),
                ),
                Text(
                  event.subtitle,
                  style: const TextStyle(
                    fontFamily: _LColors.sans,
                    fontSize: 12,
                    color: _LColors.sub,
                  ),
                ),
              ],
            ),
          ),
          Text(
            event.time,
            style: const TextStyle(
              fontFamily: _LColors.sans,
              color: _LColors.sub,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    const stats = [
      _StatData('99.4%', 'Alert delivery reliability'),
      _StatData('2.3 sec', 'Average guardian notification time'),
      _StatData('24/7', 'Monitoring availability'),
      _StatData('1 panel', 'Unified admin + parent oversight'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050
              ? 4
              : constraints.maxWidth >= 690
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

  const _StatData(this.value, this.caption);
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _LColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.value,
            style: const TextStyle(
              fontFamily: _LColors.serif,
              fontSize: 36,
              height: 0.95,
              color: _LColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            data.caption,
            style: const TextStyle(
              fontFamily: _LColors.sans,
              color: _LColors.sub,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required super.key});

  @override
  Widget build(BuildContext context) {
    final titleSize = MediaQuery.of(context).size.width < 640 ? 38.0 : 50.0;

    const features = [
      _FeatureData(
        'Live Tracking',
        'Follow registered devices in real time across campus zones.',
        Icons.location_searching_rounded,
      ),
      _FeatureData(
        'Smart SOS',
        'Route emergencies to guardians and staff in seconds.',
        Icons.sos_rounded,
      ),
      _FeatureData(
        'Geofencing',
        'Get notified when students enter or exit assigned areas.',
        Icons.map_outlined,
      ),
      _FeatureData(
        'Role Access',
        'Separate secure dashboards for admins, parents, and staff.',
        Icons.admin_panel_settings_outlined,
      ),
      _FeatureData(
        'Audit Trail',
        'Keep incident history and timeline logs for accountability.',
        Icons.history_edu_outlined,
      ),
      _FeatureData(
        'Device Finder',
        'Quickly locate lost or inactive registered devices.',
        Icons.phonelink_ring_outlined,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withOpacity(0.78),
          border: Border.all(color: _LColors.stroke),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _LColors.gold.withOpacity(0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'FEATURE SET',
                style: TextStyle(
                  fontFamily: _LColors.sans,
                  color: _LColors.ink,
                  letterSpacing: 1.7,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Everything Needed For Fast, Informed Response',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _LColors.serif,
                fontSize: titleSize,
                height: 0.95,
                color: _LColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Built to minimize uncertainty during incidents and keep everyone coordinated from the first alert to final update.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _LColors.sans,
                fontSize: 17,
                color: _LColors.sub,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1080
                    ? 3
                    : width >= 700
                        ? 2
                        : 1;
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

  const _FeatureData(this.title, this.description, this.icon);
}

class _FeatureCard extends StatelessWidget {
  final _FeatureData data;
  const _FeatureCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _LColors.stroke.withOpacity(0.95)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _LColors.ink.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: _LColors.ink),
          ),
          const SizedBox(height: 10),
          Text(
            data.title,
            style: const TextStyle(
              fontFamily: _LColors.serif,
              fontSize: 30,
              height: 0.95,
              color: _LColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.description,
            style: const TextStyle(
              fontFamily: _LColors.sans,
              fontSize: 14,
              color: _LColors.sub,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    final titleSize = MediaQuery.of(context).size.width < 640 ? 42.0 : 52.0;

    const steps = [
      _StepData(
        'Register Users',
        'Assign student and guardian accounts with secure role access.',
        Icons.person_add_alt_rounded,
      ),
      _StepData(
        'Connect Devices',
        'Bind approved devices and set campus location zones.',
        Icons.devices_other_rounded,
      ),
      _StepData(
        'Monitor + Respond',
        'Receive incidents live and coordinate response from one panel.',
        Icons.health_and_safety_outlined,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF0E3626), Color(0xFF114B36)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0A2A1E),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How It Works',
              style: TextStyle(
                fontFamily: _LColors.serif,
                fontSize: titleSize,
                color: Color(0xFFFFF6E5),
                height: 0.95,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Launch-ready flow for schools and families.',
              style: TextStyle(
                fontFamily: _LColors.sans,
                color: Color(0xFFE9F8F1),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                const gap = 12.0;
                final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: List.generate(
                    steps.length,
                    (index) => SizedBox(
                      width: cardWidth,
                      child: _StepCard(step: steps[index], index: index + 1),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E5).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(step.icon, color: const Color(0xFFFFF0D1), size: 19),
              ),
              const SizedBox(width: 9),
              Text(
                '0$index',
                style: const TextStyle(
                  fontFamily: _LColors.sans,
                  color: Color(0xFFFFF0D1),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.title,
            style: const TextStyle(
              fontFamily: _LColors.serif,
              fontSize: 30,
              height: 0.95,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.body,
            style: const TextStyle(
              fontFamily: _LColors.sans,
              color: Color(0xFFE0F5E8),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final String tag;
  final String body;

  const _InfoPanel({
    required super.key,
    required this.title,
    required this.tag,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final titleSize = MediaQuery.of(context).size.width < 640 ? 34.0 : 42.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.80),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _LColors.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _LColors.gold.withOpacity(0.20),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontFamily: _LColors.sans,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: _LColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontFamily: _LColors.serif,
                color: _LColors.ink,
                fontSize: titleSize,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              body,
              style: const TextStyle(
                fontFamily: _LColors.sans,
                fontSize: 16,
                color: _LColors.sub,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _LColors.ink.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _LColors.stroke.withOpacity(0.9)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: _LColors.sans,
          fontSize: 12,
          color: _LColors.ink,
          fontWeight: FontWeight.w600,
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
        foregroundColor: _LColors.ink,
        textStyle: const TextStyle(
          fontFamily: _LColors.sans,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      child: Text(label),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _LColors.ink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        textStyle: const TextStyle(
          fontFamily: _LColors.sans,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.login_rounded, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _LColors.ink,
        side: const BorderSide(color: _LColors.goldDeep, width: 1.3),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        textStyle: const TextStyle(
          fontFamily: _LColors.sans,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _LColors {
  static const String serif = 'CormorantGaramond';
  static const String sans = 'JosefinSans';

  static const page = Color(0xFFF5F7F5);
  static const ink = Color(0xFF0E3425);
  static const sub = Color(0xFF44635A);
  static const accent = Color(0xFF2B9D69);
  static const gold = Color(0xFFD8B66D);
  static const goldDeep = Color(0xFFA77C2F);
  static const stroke = Color(0x55AB9B79);
}
