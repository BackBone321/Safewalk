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
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _introController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.03),
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

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 1000;

    return Scaffold(
      backgroundColor: _LColors.offWhite,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.45, -0.75),
                radius: 1.7,
                colors: [Color(0xFFEDF7F1), _LColors.offWhite],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_LColors.green, _LColors.bright, _LColors.gold],
                ),
              ),
            ),
          ),
          const _CornerDecorations(),
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
                        children: [
                          _buildTopBar(isCompact: isCompact),
                          _buildHero(isCompact: isCompact),
                          _buildFeaturesSection(),
                          _buildSimpleSection(
                            key: _aboutKey,
                            title: 'ABOUT SAFEWALK',
                            body:
                                'Built for schools and families to improve emergency response and real-time location awareness.',
                          ),
                          _buildSimpleSection(
                            key: _contactKey,
                            title: 'CONTACT',
                            body: 'support@safewalk.local - +63 900 000 0000',
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
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
      child: Row(
        children: [
          const _CompactBrand(),
          const Spacer(),
          if (!isCompact) ...[
            _TopNavButton(label: 'Features', onTap: () => _scrollTo(_featuresKey)),
            _TopNavButton(label: 'About', onTap: () => _scrollTo(_aboutKey)),
            _TopNavButton(label: 'Contact', onTap: () => _scrollTo(_contactKey)),
          ],
        ],
      ),
    );
  }

  Widget _buildHero({required bool isCompact}) {
    final left = const _HeroLeftPanel();
    final right = const _HeroRightPanel();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 52),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(height: 22),
                right,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: left),
                const SizedBox(width: 22),
                Expanded(flex: 9, child: right),
              ],
            ),
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      key: _featuresKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 62, 22, 74),
      child: const _FeaturesSectionBody(),
    );
  }

  Widget _buildSimpleSection({
    required Key key,
    required String title,
    required String body,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _LColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: _LColors.sans,
                fontSize: 11,
                letterSpacing: 2.7,
                color: _LColors.goldDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(
                fontFamily: _LColors.sans,
                fontSize: 16,
                height: 1.45,
                color: _LColors.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter({required bool isCompact}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _LColors.border)),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _CompactBrand(),
                SizedBox(height: 12),
                Text(
                  'Copyright 2026 SafeWalk. Campus Safety Monitoring System.',
                  style: TextStyle(
                    fontFamily: _LColors.sans,
                    color: _LColors.textSub,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          : Row(
              children: const [
                _CompactBrand(),
                Spacer(),
                Text(
                  'Copyright 2026 SafeWalk. Campus Safety Monitoring System.',
                  style: TextStyle(
                    fontFamily: _LColors.sans,
                    color: _LColors.textSub,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        CircleAvatar(
          radius: 19,
          backgroundColor: _LColors.greenMid,
          child: Text(
            'SW',
            style: TextStyle(
              fontFamily: _LColors.sans,
              color: _LColors.gold,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 10),
        Text(
          'SafeWalk',
          style: TextStyle(
            fontFamily: _LColors.serif,
            fontSize: 38,
            height: 1,
            color: _LColors.green,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: _LColors.sans,
          color: _LColors.greenMid,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _HeroLeftPanel extends StatelessWidget {
  const _HeroLeftPanel();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 720;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _LogoCard(),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _LColors.cream,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'CAMPUS SAFETY SYSTEM',
            style: TextStyle(
              fontFamily: _LColors.sans,
              color: _LColors.goldDark,
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 20),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: _LColors.serif,
              fontSize: narrow ? 56 : 84,
              height: 0.93,
              color: _LColors.green,
            ),
            children: const [
              TextSpan(text: 'Keep Your '),
              TextSpan(
                text: 'Loved Ones',
                style: TextStyle(color: _LColors.goldDark, fontStyle: FontStyle.italic),
              ),
              TextSpan(text: '\nSafe & Located'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Track your child\'s device location in real-time. View accurate position updates across campus instantly.',
          style: TextStyle(
            fontFamily: _LColors.sans,
            fontSize: 18,
            height: 1.5,
            color: _LColors.textSub.withOpacity(0.95),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _PrimaryButton(
              label: 'Create Account',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
            ),
            _SecondaryButton(
              label: 'Sign In',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Supports Admin, Student, and Parent accounts',
          style: TextStyle(
            fontFamily: _LColors.sans,
            fontSize: 14,
            color: _LColors.textSub.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
}

class _LogoCard extends StatelessWidget {
  const _LogoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        border: Border.all(color: _LColors.border),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          CircleAvatar(
            radius: 38,
            backgroundColor: _LColors.greenMid,
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: _LColors.sans,
                color: _LColors.gold,
                fontSize: 33,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Safe',
            style: TextStyle(
              fontFamily: _LColors.serif,
              fontSize: 68,
              height: 0.9,
              color: _LColors.green,
            ),
          ),
          Text(
            'Walk',
            style: TextStyle(
              fontFamily: _LColors.serif,
              fontSize: 68,
              height: 0.9,
              color: _LColors.goldDark,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'SECURE ACCESS PORTAL',
            style: TextStyle(
              fontFamily: _LColors.sans,
              fontSize: 11,
              letterSpacing: 5.2,
              color: _LColors.textSub,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRightPanel extends StatelessWidget {
  const _HeroRightPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _LColors.border),
        boxShadow: const [
          BoxShadow(
            color: _LColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _LColors.gold,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.circle, color: _LColors.bright, size: 10),
                SizedBox(width: 6),
                Text(
                  'System Active',
                  style: TextStyle(
                    fontFamily: _LColors.sans,
                    color: _LColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 210,
            decoration: BoxDecoration(
              color: _LColors.offWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _LColors.border),
            ),
            child: const Center(
              child: Icon(
                Icons.location_on_outlined,
                color: _LColors.goldDark,
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'LIVE MAP PREVIEW',
            style: TextStyle(
              fontFamily: _LColors.sans,
              fontSize: 12,
              letterSpacing: 2.2,
              color: _LColors.textSub,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _InfoChip(label: 'GPS Monitoring'),
              _InfoChip(label: 'Instant SOS'),
              _InfoChip(label: 'Guardian Alerts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _LColors.cream,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: _LColors.sans,
          color: _LColors.green,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeaturesSectionBody extends StatelessWidget {
  const _FeaturesSectionBody();

  @override
  Widget build(BuildContext context) {
    const features = [
      _FeatureData('Live Tracking', 'Real-time GPS location of registered devices', Icons.location_on_outlined),
      _FeatureData('SOS Alerts', 'Instant emergency notifications to guardians', Icons.notifications_none_rounded),
      _FeatureData('Device Finder', 'Locate any registered device on campus', Icons.smartphone_outlined),
      _FeatureData('Guardian Portal', 'Secure dashboard for parents and guardians', Icons.shield_outlined),
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _LColors.cream,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'FEATURES',
            style: TextStyle(
              fontFamily: _LColors.sans,
              color: _LColors.goldDark,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Everything You Need',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _LColors.serif,
            fontSize: 62,
            color: _LColors.green,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A comprehensive safety platform designed to give guardians peace of mind.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _LColors.sans,
            fontSize: 18,
            color: _LColors.textSub.withOpacity(0.95),
          ),
        ),
        const SizedBox(height: 30),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1120
                ? 4
                : width >= 760
                ? 2
                : 1;
            const gap = 16.0;
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
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _FeatureData data;
  const _FeatureCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _LColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _LColors.cream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: _LColors.goldDark),
          ),
          const SizedBox(height: 14),
          Text(
            data.title,
            style: const TextStyle(
              fontFamily: _LColors.serif,
              fontSize: 34,
              color: _LColors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.description,
            style: TextStyle(
              fontFamily: _LColors.sans,
              fontSize: 15,
              height: 1.45,
              color: _LColors.textSub.withOpacity(0.95),
            ),
          ),
        ],
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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _LColors.greenMid,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: _LColors.sans,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
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
      icon: const Icon(Icons.login_rounded),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _LColors.green,
        side: const BorderSide(color: _LColors.gold, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: _LColors.sans,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CornerDecorations extends StatelessWidget {
  const _CornerDecorations();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: const [
          Positioned(top: 16, left: 16, child: _CornerPiece()),
          Positioned(top: 16, right: 16, child: _CornerPiece(isRight: true)),
          Positioned(bottom: 16, left: 16, child: _CornerPiece(isBottom: true)),
          Positioned(
            bottom: 16,
            right: 16,
            child: _CornerPiece(isRight: true, isBottom: true),
          ),
        ],
      ),
    );
  }
}

class _CornerPiece extends StatelessWidget {
  final bool isRight;
  final bool isBottom;

  const _CornerPiece({this.isRight = false, this.isBottom = false});

  @override
  Widget build(BuildContext context) {
    final angle = isRight && isBottom
        ? 3.14159
        : isRight
        ? 1.5708
        : isBottom
        ? -1.5708
        : 0.0;
    return Transform.rotate(
      angle: angle,
      child: SizedBox(
        width: 34,
        height: 34,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _LColors.gold.withOpacity(0.45)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LColors {
  static const String serif = 'CormorantGaramond';
  static const String sans = 'JosefinSans';

  static const offWhite = Color(0xFFF7F5F0);
  static const cream = Color(0xFFF0EBE0);
  static const gold = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const green = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright = Color(0xFF2CA86E);
  static const border = Color(0x55C9A551);
  static const shadow = Color(0x14000000);
  static const textSub = Color(0xFF4E6E68);
}
