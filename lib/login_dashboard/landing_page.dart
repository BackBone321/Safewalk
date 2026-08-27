// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'login_page.dart';
import 'register.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────

class _T {
  static const String display = 'CormorantGaramond';
  static const String body = 'JosefinSans';
  static const Color bg = Color(0xFF060D0A);
  static const Color surface = Color(0xFF0D1A14);
  static const Color surfaceHigh = Color(0xFF132218);
  static const Color panel = Color(0xFF0F1D16);
  static const Color border = Color(0x28A8C8A0);
  static const Color ink = Color(0xFFF0F8F2);
  static const Color muted = Color(0xFF8AA898);
  static const Color faint = Color(0xFF3D5A4E);
  static const Color green = Color(0xFF1FCE78);
  static const Color greenDeep = Color(0xFF0D7A46);
  static const Color gold = Color(0xFFE8C46A);
  static const Color goldMid = Color(0xFFC9A445);
  static const Color red = Color(0xFFFF5C5C);
  static const Color blue = Color(0xFF5CB8FF);
}

PageRouteBuilder<T> _fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
}

// ─── Landing Page ─────────────────────────────────────────────────────────────

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();
  final ScrollController _scrollCtrl = ScrollController();
  final ValueNotifier<bool> _showFloatingNav = ValueNotifier(false);

  late final AnimationController _introCtrl;
  late final AnimationController _meshCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
    _meshCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _scrollCtrl.addListener(() {
      final should = _scrollCtrl.offset > 120.0;
      if (_showFloatingNav.value != should) _showFloatingNav.value = should;
    });
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _meshCtrl.dispose();
    _pulseCtrl.dispose();
    _scrollCtrl.dispose();
    _showFloatingNav.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic, alignment: 0.06);
  }

  Widget _stagger({required Widget child, required double start, required double end, double y = 32}) {
    final anim = CurvedAnimation(parent: _introCtrl, curve: Interval(start, end, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, c) => Opacity(opacity: anim.value, child: Transform.translate(offset: Offset(0, (1 - anim.value) * y), child: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isCompact = w < 1050;
    return Scaffold(
      backgroundColor: _T.bg,
      body: Stack(
        children: [
          _MeshBg(anim: _meshCtrl),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stagger(start: 0.00, end: 0.25, child: _TopBar(isCompact: isCompact, onFeatures: () => _scrollTo(_featuresKey), onAbout: () => _scrollTo(_aboutKey), onContact: () => _scrollTo(_contactKey))),
                      _stagger(start: 0.05, end: 0.45, child: _HeroSection(isCompact: isCompact, pulseAnim: _pulseCtrl)),
                      _stagger(start: 0.20, end: 0.60, child: const _TrustBand()),
                      _stagger(start: 0.28, end: 0.70, child: _FeaturesSection(key: _featuresKey)),
                      _stagger(start: 0.38, end: 0.80, child: const _HowItWorksSection()),
                      _stagger(start: 0.48, end: 0.88, child: const _TestimonialsSection()),
                      _stagger(start: 0.55, end: 0.95, child: const _CTABanner()),
                      _stagger(start: 0.60, end: 1.00, child: _InfoSection(key: _aboutKey, contactKey: _contactKey)),
                      const _Footer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _FloatingNav(
            showNotifier: _showFloatingNav,
            isCompact: isCompact,
            onFeatures: () => _scrollTo(_featuresKey),
            onAbout: () => _scrollTo(_aboutKey),
            onContact: () => _scrollTo(_contactKey),
            onScrollTop: () => _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic),
          ),
        ],
      ),
    );
  }
}
// ─── Mesh Background ─────────────────────────────────────────────────────────

class _MeshBg extends StatelessWidget {
  final Animation<double> anim;
  const _MeshBg({required this.anim});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final t = anim.value;
        return Stack(
          children: [
            Container(color: _T.bg),
            Positioned(top: -250 + t * 60, left: -180 + t * 40, child: _Blob(size: 600, color: _T.green.withOpacity(0.07 + t * 0.04))),
            Positioned(top: 100 + t * 40, right: -200 + t * 50, child: _Blob(size: 500, color: _T.gold.withOpacity(0.05 + t * 0.03))),
            Positioned(top: 600 - t * 80, left: 0, right: 0, child: Center(child: _Blob(size: 800, color: _T.green.withOpacity(0.03 + t * 0.02)))),
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),
            Positioned(left: 0, right: 0, top: 0, child: Container(height: 1, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, _T.green, _T.gold, Colors.transparent], stops: [0.0, 0.35, 0.65, 1.0])))),
          ],
        );
      },
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, Colors.transparent])));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF1FCE78).withOpacity(0.03)..strokeWidth = 0.8;
    for (double x = 0; x < size.width; x += 60) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), p); }
    for (double y = 0; y < size.height; y += 60) { canvas.drawLine(Offset(0, y), Offset(size.width, y), p); }
  }
  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isCompact;
  final VoidCallback onFeatures, onAbout, onContact;
  const _TopBar({required this.isCompact, required this.onFeatures, required this.onAbout, required this.onContact});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _T.surface.withOpacity(0.70),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _T.border),
          boxShadow: [BoxShadow(color: _T.green.withOpacity(0.06), blurRadius: 30, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            const _BrandMark(compact: true),
            const Spacer(),
            if (!isCompact) ...[
              _NavBtn(label: 'Features', onTap: onFeatures),
              _NavBtn(label: 'About', onTap: onAbout),
              _NavBtn(label: 'Contact', onTap: onContact),
              const SizedBox(width: 14),
            ],
            _PillBtn(label: 'Sign In', icon: Icons.login_rounded, onTap: () => Navigator.push(context, _fadeRoute(const LoginPage()))),
          ],
        ),
      ),
    );
  }
}

// ─── Brand Mark ──────────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  final bool compact;
  final bool micro;
  const _BrandMark({this.compact = false, this.micro = false});
  @override
  Widget build(BuildContext context) {
    final logoSz = micro ? 28.0 : compact ? 40.0 : 72.0;
    final titleSz = micro ? 15.0 : compact ? 20.0 : 48.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSz, height: logoSz,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_T.green, _T.greenDeep]),
            boxShadow: [BoxShadow(color: _T.green.withOpacity(0.40), blurRadius: compact ? 10 : 20, offset: const Offset(0, 4))],
          ),
          child: Center(child: Text('SW', style: TextStyle(fontFamily: _T.body, color: Colors.white, fontSize: micro ? 9 : compact ? 13 : 24, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
        ),
        SizedBox(width: micro ? 8 : compact ? 10 : 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SafeWalk', style: TextStyle(fontFamily: _T.display, fontSize: titleSz, height: 1.0, color: _T.ink, fontWeight: FontWeight.w700)),
            if (!compact && !micro)
              const Text('SAFETY MONITORING SYSTEM', style: TextStyle(fontFamily: _T.body, fontSize: 10, color: _T.muted, letterSpacing: 2.0, height: 1.4)),
          ],
        ),
      ],
    );
  }
}

// ─── Hero Section ─────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final bool isCompact;
  final Animation<double> pulseAnim;
  const _HeroSection({required this.isCompact, required this.pulseAnim});
  @override
  Widget build(BuildContext context) {
    final left = _HeroLeft(isCompact: isCompact);
    final right = _HeroRight(pulseAnim: pulseAnim, isCompact: isCompact);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: isCompact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 20), right])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 12, child: left), const SizedBox(width: 20), Expanded(flex: 10, child: right)]),
    );
  }
}

class _HeroLeft extends StatelessWidget {
  final bool isCompact;
  const _HeroLeft({required this.isCompact});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 36),
      decoration: BoxDecoration(
        color: _T.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _T.border),
        boxShadow: [BoxShadow(color: _T.green.withOpacity(0.07), blurRadius: 60, offset: const Offset(0, 20))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(label: 'LIVE SAFETY NETWORK', color: _T.green, dot: true),
          const SizedBox(height: 28),
          RichText(
            text: TextSpan(
              style: TextStyle(fontFamily: _T.display, fontSize: isCompact ? 58.0 : 90.0, height: 0.88, fontWeight: FontWeight.w700),
              children: [
                const TextSpan(text: 'Keep Every\nStudent ', style: TextStyle(color: _T.ink)),
                TextSpan(
                  text: 'Safe.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    foreground: Paint()..shader = const LinearGradient(colors: [_T.green, _T.gold]).createShader(const Rect.fromLTWH(0, 0, 400, 100)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(width: 72, height: 3, decoration: BoxDecoration(gradient: const LinearGradient(colors: [_T.green, _T.gold]), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 22),
          Text(
            'Real-time location tracking, instant SOS alerts, and unified guardian visibility — built for schools that need fast, accountable response.',
            style: TextStyle(fontFamily: _T.body, fontSize: isCompact ? 15.0 : 17.0, color: _T.muted, height: 1.65, letterSpacing: 0.3),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 14, runSpacing: 14,
            children: [
              _GooeyBtn(label: 'Create Account', icon: Icons.person_add_alt_1_rounded, isPrimary: true, onTap: () => Navigator.push(context, _fadeRoute(const RegisterPage()))),
              _GooeyBtn(label: 'Sign In', icon: Icons.login_rounded, isPrimary: false, onTap: () => Navigator.push(context, _fadeRoute(const LoginPage()))),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: const [
              _Tag(text: 'Admin + Parent Portal'),
              _Tag(text: 'Instant SOS Routing'),
              _Tag(text: 'Real-Time GPS'),
              _Tag(text: '24/7 Monitoring'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroRight extends StatelessWidget {
  final Animation<double> pulseAnim;
  final bool isCompact;
  const _HeroRight({required this.pulseAnim, required this.isCompact});
  @override
  Widget build(BuildContext context) {
    const events = [
      _LEv('SOS Alert Received', 'Science Building - Block B', 'Now', Icons.warning_amber_rounded, _T.red),
      _LEv('Guardian Notified', 'Parent App - Maria Santos', '12s ago', Icons.notifications_active_outlined, _T.gold),
      _LEv('Device Secured', 'Gate 2 Exit - Scan verified', '48s ago', Icons.shield_outlined, _T.green),
      _LEv('Route Deviation', 'Unexpected exit detected', '2m ago', Icons.route_outlined, _T.blue),
    ];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _T.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _T.border),
            boxShadow: [BoxShadow(color: _T.green.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, 16))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (_, __) => Stack(alignment: Alignment.center, children: [
                      Container(width: 20 + pulseAnim.value * 10, height: 20 + pulseAnim.value * 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _T.green.withOpacity((1 - pulseAnim.value) * 0.22))),
                      Container(width: 10, height: 10, decoration: const BoxDecoration(color: _T.green, shape: BoxShape.circle)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  const Text('MONITORING ACTIVE', style: TextStyle(fontFamily: _T.body, fontSize: 11, letterSpacing: 2.0, color: _T.muted, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [_T.green, _T.greenDeep]), borderRadius: BorderRadius.circular(99), boxShadow: [BoxShadow(color: _T.green.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))]),
                    child: const Text('LIVE', style: TextStyle(fontFamily: _T.body, color: Colors.white, fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 190,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: _T.panel, border: Border.all(color: _T.border)),
                child: Stack(
                  children: [
                    Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: CustomPaint(painter: _DarkMapPainter()))),
                    Align(alignment: const Alignment(-0.15, 0.0), child: Container(width: 88, height: 88, decoration: BoxDecoration(shape: BoxShape.circle, color: _T.green.withOpacity(0.08), border: Border.all(color: _T.green.withOpacity(0.25), width: 1.5)))),
                    Align(
                      alignment: const Alignment(-0.15, 0.0),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: _T.surfaceHigh, shape: BoxShape.circle, border: Border.all(color: _T.green.withOpacity(0.5), width: 1.5), boxShadow: [BoxShadow(color: _T.green.withOpacity(0.3), blurRadius: 12)]),
                        child: const Icon(Icons.location_on_rounded, color: _T.green, size: 22),
                      ),
                    ),
                    Positioned(right: 44, top: 46, child: _MDot(color: _T.gold.withOpacity(0.8))),
                    Positioned(left: 26, bottom: 38, child: _MDot(color: _T.blue.withOpacity(0.8))),
                    Positioned(right: 72, bottom: 26, child: _MDot(color: _T.green.withOpacity(0.6))),
                    Positioned(
                      right: 12, bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(10), border: Border.all(color: _T.border)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.people_alt_outlined, color: _T.green, size: 13), const SizedBox(width: 5), const Text('24 tracked', style: TextStyle(fontFamily: _T.body, color: _T.ink, fontSize: 11, fontWeight: FontWeight.w700))]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ...events.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _LEvTile(event: e))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _MiniStats(),
      ],
    );
  }
}

class _MiniStats extends StatelessWidget {
  const _MiniStats();
  @override
  Widget build(BuildContext context) {
    final items = [('99.4%', 'Uptime'), ('<2s', 'Alert time'), ('24/7', 'Active')];
    return Row(
      children: items.asMap().entries.map((e) => Expanded(
        child: Container(
          margin: EdgeInsets.only(left: e.key > 0 ? 8 : 0),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: _T.surface.withOpacity(0.7), borderRadius: BorderRadius.circular(14), border: Border.all(color: _T.border)),
          child: Column(children: [
            ShaderMask(shaderCallback: (b) => const LinearGradient(colors: [_T.green, _T.gold]).createShader(b), child: Text(e.value.$1, style: const TextStyle(fontFamily: _T.display, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.0))),
            const SizedBox(height: 4),
            Text(e.value.$2, style: const TextStyle(fontFamily: _T.body, color: _T.muted, fontSize: 11, letterSpacing: 0.8)),
          ]),
        ),
      )).toList(),
    );
  }
}

// ─── Trust Band ───────────────────────────────────────────────────────────────

class _TrustBand extends StatelessWidget {
  const _TrustBand();
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.verified_rounded, '99.4% Alert Reliability'),
      (Icons.speed_rounded, 'Under 2s Notification'),
      (Icons.shield_rounded, 'End-to-End Encrypted'),
      (Icons.people_alt_rounded, 'School-Grade Access Control'),
      (Icons.access_time_filled_rounded, '24/7 System Monitoring'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(color: _T.surface.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: _T.border)),
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly, spacing: 12, runSpacing: 12,
          children: items.map((i) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(i.$1, color: _T.green, size: 16), const SizedBox(width: 8), Text(i.$2, style: const TextStyle(fontFamily: _T.body, color: _T.muted, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3))])).toList(),
        ),
      ),
    );
  }
}

// ─── Features Section ─────────────────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required super.key});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    const feats = [
      _FD('Live Tracking', 'Follow registered devices in real time across school safety zones with sub-second updates.', Icons.location_searching_rounded, _T.green, 'GPS'),
      _FD('Smart SOS', 'Route emergencies directly to the nearest guardians and on-duty staff within seconds.', Icons.sos_rounded, _T.red, 'Emergency'),
      _FD('Geofencing', 'Receive instant notifications when students enter or exit assigned safety zones.', Icons.hexagon_outlined, _T.gold, 'Zones'),
      _FD('Role Access', 'Separate encrypted dashboards for administrators, parents, and security staff.', Icons.admin_panel_settings_outlined, _T.blue, 'Auth'),
      _FD('Audit Trail', 'Full incident history with timestamped logs, evidence chains, and export tools.', Icons.history_edu_outlined, _T.goldMid, 'Logs'),
      _FD('Device Finder', 'Quickly locate lost, inactive, or unauthorized registered devices on the campus map.', Icons.phonelink_ring_outlined, _T.muted, 'Devices'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(label: 'FEATURE SET', color: _T.goldMid),
          const SizedBox(height: 16),
          Text('Everything Needed\nFor Fast Response', style: TextStyle(fontFamily: _T.display, fontSize: w < 640 ? 38.0 : 58.0, color: _T.ink, height: 0.92, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          const Text('Built to minimize uncertainty during incidents and keep every guardian, admin, and staff coordinated.', style: TextStyle(fontFamily: _T.body, fontSize: 15, color: _T.muted, height: 1.65)),
          const SizedBox(height: 36),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 700 ? 2 : 1;
            const gap = 14.0;
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: feats.map((f) => SizedBox(width: cardW, child: _FCard(data: f))).toList());
          }),
        ],
      ),
    );
  }
}

class _FD {
  final String title, description, tag;
  final IconData icon;
  final Color accent;
  const _FD(this.title, this.description, this.icon, this.accent, this.tag);
}

class _FCard extends StatefulWidget {
  final _FD data;
  const _FCard({required this.data});
  @override
  State<_FCard> createState() => _FCardState();
}

class _FCardState extends State<_FCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        decoration: BoxDecoration(
          color: _h ? _T.surfaceHigh : _T.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _h ? d.accent.withOpacity(0.35) : _T.border),
          boxShadow: _h ? [BoxShadow(color: d.accent.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10))] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: d.accent.withOpacity(0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: d.accent.withOpacity(0.25))), child: Icon(d.icon, color: d.accent, size: 22)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: d.accent.withOpacity(0.08), borderRadius: BorderRadius.circular(99), border: Border.all(color: d.accent.withOpacity(0.20))), child: Text(d.tag, style: TextStyle(fontFamily: _T.body, color: d.accent, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 18),
            Text(d.title, style: const TextStyle(fontFamily: _T.display, fontSize: 28, height: 0.95, color: _T.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            AnimatedContainer(duration: const Duration(milliseconds: 280), width: _h ? 50 : 30, height: 2, decoration: BoxDecoration(gradient: LinearGradient(colors: [d.accent, _T.gold]), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Text(d.description, style: const TextStyle(fontFamily: _T.body, fontSize: 13, color: _T.muted, height: 1.55)),
          ],
        ),
      ),
    );
  }
}

// ─── How It Works ─────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    const steps = [
      _SD('Register Users', 'Assign student and guardian accounts with encrypted role-based access in minutes.', Icons.person_add_alt_rounded, '01'),
      _SD('Connect Devices', 'Bind approved GPS devices and define safety geofence zones for each student.', Icons.devices_other_rounded, '02'),
      _SD('Monitor and Respond', 'Receive live incidents, acknowledge SOS alerts, and coordinate your team from one panel.', Icons.health_and_safety_outlined, '03'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(32, 36, 32, 36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D2518), Color(0xFF091810), Color(0xFF0B1E14)]),
          border: Border.all(color: _T.green.withOpacity(0.18)),
          boxShadow: [BoxShadow(color: _T.green.withOpacity(0.08), blurRadius: 50, offset: const Offset(0, 16))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Badge(label: 'HOW IT WORKS', color: _T.green),
            const SizedBox(height: 16),
            Text('Three Steps to\nFull Protection', style: TextStyle(fontFamily: _T.display, fontSize: w < 640 ? 40.0 : 58.0, color: _T.ink, height: 0.92, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('Launch-ready flow for schools and families. Go live in under a day.', style: TextStyle(fontFamily: _T.body, color: Color(0xFF7ABAAA), fontSize: 15, height: 1.5)),
            const SizedBox(height: 36),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 1000 ? 3 : c.maxWidth >= 680 ? 2 : 1;
              const gap = 16.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(spacing: gap, runSpacing: gap, children: steps.map((s) => SizedBox(width: cardW, child: _SCard(step: s))).toList());
            }),
          ],
        ),
      ),
    );
  }
}

class _SD {
  final String title, body, number;
  final IconData icon;
  const _SD(this.title, this.body, this.icon, this.number);
}

class _SCard extends StatefulWidget {
  final _SD step;
  const _SCard({required this.step});
  @override
  State<_SCard> createState() => _SCardState();
}

class _SCardState extends State<_SCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        decoration: BoxDecoration(
          color: _h ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _h ? _T.green.withOpacity(0.35) : Colors.white.withOpacity(0.10)),
          boxShadow: _h ? [BoxShadow(color: _T.green.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8))] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: _T.gold.withOpacity(0.10), borderRadius: BorderRadius.circular(13), border: Border.all(color: _T.gold.withOpacity(0.25))), child: Icon(s.icon, color: _T.gold, size: 20)),
              const Spacer(),
              Text(s.number, style: TextStyle(fontFamily: _T.display, fontSize: 52, height: 1.0, color: _T.gold.withOpacity(0.12), fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 18),
            Text(s.title, style: const TextStyle(fontFamily: _T.display, fontSize: 30, height: 0.95, color: _T.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(width: 28, height: 2, decoration: BoxDecoration(color: _T.gold.withOpacity(0.55), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Text(s.body, style: const TextStyle(fontFamily: _T.body, color: Color(0xFF8ABBA8), fontSize: 13, height: 1.55)),
          ],
        ),
      ),
    );
  }
}

// ─── Testimonials ─────────────────────────────────────────────────────────────

class _TestimonialsSection extends StatelessWidget {
  const _TestimonialsSection();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    const tests = [
      _TD('"SafeWalk has transformed how we handle student safety incidents. The SOS routing is phenomenal."', 'Maria Santos', 'Head of Security, Lakeview Academy', 'MS', _T.green),
      _TD('"As a parent, I finally feel at ease. I can see where my daughter is during school hours at any time."', 'Jose Reyes', 'Parent - Grade 9 Student', 'JR', _T.gold),
      _TD('"The admin dashboard is clean, fast, and incredibly well designed. Setup took less than two hours."', 'Carlo Dela Cruz', 'IT Administrator, Northfield School', 'CD', _T.blue),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Badge(label: 'TESTIMONIALS', color: _T.blue),
          const SizedBox(height: 16),
          Text('Trusted by Schools\nand Families', style: TextStyle(fontFamily: _T.display, fontSize: w < 640 ? 38.0 : 58.0, color: _T.ink, height: 0.92, fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 620 ? 2 : 1;
            const gap = 16.0;
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: tests.map((t) => SizedBox(width: cardW, child: _TCard(data: t))).toList());
          }),
        ],
      ),
    );
  }
}

class _TD {
  final String quote, name, role, initials;
  final Color accent;
  const _TD(this.quote, this.name, this.role, this.initials, this.accent);
}

class _TCard extends StatelessWidget {
  final _TD data;
  const _TCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final d = data;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(color: _T.surface.withOpacity(0.6), borderRadius: BorderRadius.circular(22), border: Border.all(color: _T.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: List.generate(5, (_) => const Icon(Icons.star_rounded, color: _T.gold, size: 14))),
          const SizedBox(height: 14),
          Text(d.quote, style: const TextStyle(fontFamily: _T.display, fontSize: 18, color: _T.ink, height: 1.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 18),
          Container(height: 1, color: _T.border),
          const SizedBox(height: 14),
          Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: d.accent.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: d.accent.withOpacity(0.30))), child: Center(child: Text(d.initials, style: TextStyle(fontFamily: _T.body, color: d.accent, fontSize: 12, fontWeight: FontWeight.w800)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: const TextStyle(fontFamily: _T.body, color: _T.ink, fontSize: 13, fontWeight: FontWeight.w700)),
              Text(d.role, style: const TextStyle(fontFamily: _T.body, color: _T.muted, fontSize: 11)),
            ])),
          ]),
        ],
      ),
    );
  }
}

// ─── CTA Banner ───────────────────────────────────────────────────────────────

class _CTABanner extends StatelessWidget {
  const _CTABanner();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 36, vertical: w < 640 ? 36 : 52),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0E3D26), Color(0xFF0A2E1C), Color(0xFF061910)]),
          border: Border.all(color: _T.green.withOpacity(0.25)),
          boxShadow: [BoxShadow(color: _T.green.withOpacity(0.12), blurRadius: 60, offset: const Offset(0, 20))],
        ),
        child: Column(
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(colors: [_T.green, _T.gold]).createShader(b),
              child: Text('Ready to Protect\nYour Students?', textAlign: TextAlign.center, style: TextStyle(fontFamily: _T.display, fontSize: w < 640 ? 46.0 : 72.0, color: Colors.white, fontWeight: FontWeight.w700, height: 0.9)),
            ),
            const SizedBox(height: 20),
            const Text('Join schools already using SafeWalk to keep every student accounted for, every minute of the school day.', textAlign: TextAlign.center, style: TextStyle(fontFamily: _T.body, color: Color(0xFF7ABAAA), fontSize: 15, height: 1.6)),
            const SizedBox(height: 36),
            Wrap(
              spacing: 14, runSpacing: 14, alignment: WrapAlignment.center,
              children: [
                _GooeyBtn(label: 'Get Started Free', icon: Icons.rocket_launch_rounded, isPrimary: true, onTap: () => Navigator.push(context, _fadeRoute(const RegisterPage()))),
                _GooeyBtn(label: 'Sign In', icon: Icons.login_rounded, isPrimary: false, onTap: () => Navigator.push(context, _fadeRoute(const LoginPage()))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Info Section ─────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final Key? contactKey;
  const _InfoSection({required super.key, this.contactKey});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final a = const _ICard(tag: 'MISSION', title: 'About SafeWalk', body: 'SafeWalk helps protect students through live location intelligence, emergency routing, and guardian visibility. Designed for schools that need fast response, accountable records, and clear communication.', icon: Icons.shield_outlined, accent: _T.green);
    final c = _ICard(key: contactKey, tag: 'SUPPORT', title: 'Contact Us', body: 'Email: support@safewalk.local\nPhone: +63 900 000 0000\nHours: Monday to Friday, 8:00 AM to 6:00 PM', icon: Icons.mail_outline_rounded, accent: _T.gold);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: w < 800 ? Column(children: [a, const SizedBox(height: 16), c]) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: c)]),
    );
  }
}

class _ICard extends StatelessWidget {
  final String tag, title, body;
  final IconData icon;
  final Color accent;
  const _ICard({super.key, required this.tag, required this.title, required this.body, required this.icon, required this.accent});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
      decoration: BoxDecoration(color: _T.surface.withOpacity(0.6), borderRadius: BorderRadius.circular(24), border: Border.all(color: _T.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Badge(label: tag, color: accent),
            const Spacer(),
            Container(width: 46, height: 46, decoration: BoxDecoration(color: accent.withOpacity(0.10), borderRadius: BorderRadius.circular(13), border: Border.all(color: accent.withOpacity(0.22))), child: Icon(icon, color: accent, size: 22)),
          ]),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontFamily: _T.display, fontSize: 36, color: _T.ink, height: 0.95, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(width: 36, height: 2, decoration: BoxDecoration(gradient: LinearGradient(colors: [accent, _T.gold]), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Text(body, style: const TextStyle(fontFamily: _T.body, fontSize: 14, color: _T.muted, height: 1.65)),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: BoxDecoration(color: _T.surface.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: _T.border)),
        child: w < 640
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _BrandMark(compact: true),
                const SizedBox(height: 14),
                Container(height: 1, color: _T.border),
                const SizedBox(height: 14),
                const Text('2026 SafeWalk - Safety Monitoring System', style: TextStyle(fontFamily: _T.body, color: _T.faint, fontSize: 12)),
              ])
            : Row(children: [
                const _BrandMark(compact: true),
                const SizedBox(width: 24),
                Container(width: 1, height: 28, color: _T.border),
                const SizedBox(width: 24),
                const Text('Keeping students safe, every step of the way.', style: TextStyle(fontFamily: _T.display, color: _T.muted, fontSize: 15, fontStyle: FontStyle.italic)),
                const Spacer(),
                const Text('2026 SafeWalk', style: TextStyle(fontFamily: _T.body, color: _T.faint, fontSize: 12)),
              ]),
      ),
    );
  }
}

// ─── Floating Nav ─────────────────────────────────────────────────────────────

class _FloatingNav extends StatelessWidget {
  final ValueNotifier<bool> showNotifier;
  final bool isCompact;
  final VoidCallback onFeatures, onAbout, onContact, onScrollTop;
  const _FloatingNav({required this.showNotifier, required this.isCompact, required this.onFeatures, required this.onAbout, required this.onContact, required this.onScrollTop});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showNotifier,
      builder: (_, show, __) => AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, -1.5),
        duration: const Duration(milliseconds: 380),
        curve: show ? Curves.easeOutCubic : Curves.easeInCubic,
        child: AnimatedOpacity(
          opacity: show ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: IgnorePointer(
            ignoring: !show,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: isCompact ? const EdgeInsets.fromLTRB(14, 8, 10, 8) : const EdgeInsets.fromLTRB(18, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: _T.surface.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _T.border),
                      boxShadow: [BoxShadow(color: _T.green.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 6)), BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(onTap: onScrollTop, child: const _BrandMark(compact: true, micro: true)),
                        Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 12), color: _T.border),
                        if (!isCompact) ...[
                          _PillNavBtn(label: 'Features', onTap: onFeatures),
                          _PillNavBtn(label: 'About', onTap: onAbout),
                          _PillNavBtn(label: 'Contact', onTap: onContact),
                          const SizedBox(width: 6),
                        ] else ...[
                          _PIBtn(icon: Icons.grid_view_rounded, onTap: onFeatures, tooltip: 'Features'),
                          _PIBtn(icon: Icons.info_outline_rounded, onTap: onAbout, tooltip: 'About'),
                          _PIBtn(icon: Icons.mail_outline_rounded, onTap: onContact, tooltip: 'Contact'),
                        ],
                        GestureDetector(
                          onTap: onScrollTop,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(gradient: const LinearGradient(colors: [_T.green, _T.greenDeep]), borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: _T.green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))]),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 15),
                              const SizedBox(width: 4),
                              Text(isCompact ? 'Top' : 'Back to top', style: const TextStyle(fontFamily: _T.body, color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;
  const _Badge({required this.label, required this.color, this.dot = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.30))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 7)],
        Text(label, style: TextStyle(fontFamily: _T.body, color: color, fontSize: 11, letterSpacing: 2.0, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(999), border: Border.all(color: _T.border)),
    child: Text(text, style: const TextStyle(fontFamily: _T.body, fontSize: 12, color: _T.muted, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
  );
}

class _NavBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NavBtn({required this.label, required this.onTap});
  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: _h ? _T.green.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(widget.label, style: TextStyle(fontFamily: _T.body, color: _h ? _T.green : _T.muted, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ),
      ),
    );
  }
}

class _PillNavBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillNavBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(foregroundColor: _T.muted, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontFamily: _T.body, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.4)),
    child: Text(label),
  );
}

class _PIBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _PIBtn({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) => Tooltip(message: tooltip, child: IconButton(onPressed: onTap, icon: Icon(icon, color: _T.muted, size: 18), padding: const EdgeInsets.symmetric(horizontal: 6), constraints: const BoxConstraints(minWidth: 32, minHeight: 32)));
}

class _PillBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PillBtn({required this.label, required this.icon, required this.onTap});
  @override
  State<_PillBtn> createState() => _PillBtnState();
}

class _PillBtnState extends State<_PillBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: _h ? const LinearGradient(colors: [_T.green, _T.greenDeep]) : null,
            color: _h ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: _h ? null : Border.all(color: _T.border),
            boxShadow: _h ? [BoxShadow(color: _T.green.withOpacity(0.30), blurRadius: 14, offset: const Offset(0, 4))] : [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 15, color: _h ? Colors.white : _T.muted),
            const SizedBox(width: 7),
            Text(widget.label, style: TextStyle(fontFamily: _T.body, fontWeight: FontWeight.w700, fontSize: 13, color: _h ? Colors.white : _T.muted, letterSpacing: 0.3)),
          ]),
        ),
      ),
    );
  }
}

// ─── Map Painter ──────────────────────────────────────────────────────────────

class _DarkMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = _T.green.withOpacity(0.08)..strokeWidth = 0.7;
    for (double x = 0; x < size.width; x += 32) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid); }
    for (double y = 0; y < size.height; y += 28) { canvas.drawLine(Offset(0, y), Offset(size.width, y), grid); }
    canvas.drawCircle(Offset(size.width * 0.62, size.height * 0.35), 36, Paint()..color = _T.green.withOpacity(0.06));
    final route = Paint()..color = _T.green.withOpacity(0.55)..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..moveTo(size.width * 0.08, size.height * 0.75)..quadraticBezierTo(size.width * 0.30, size.height * 0.20, size.width * 0.54, size.height * 0.50)..quadraticBezierTo(size.width * 0.72, size.height * 0.65, size.width * 0.92, size.height * 0.35), route);
    canvas.drawPath(Path()..moveTo(size.width * 0.62, size.height * 0.35)..lineTo(size.width * 0.78, size.height * 0.60), Paint()..color = _T.gold.withOpacity(0.30)..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _MDot extends StatelessWidget {
  final Color color;
  const _MDot({required this.color});
  @override
  Widget build(BuildContext context) => Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)]));
}

// ─── Live Event ───────────────────────────────────────────────────────────────

class _LEv {
  final String title, subtitle, time;
  final IconData icon;
  final Color accent;
  const _LEv(this.title, this.subtitle, this.time, this.icon, this.accent);
}

class _LEvTile extends StatelessWidget {
  final _LEv event;
  const _LEvTile({required this.event});
  @override
  Widget build(BuildContext context) {
    final e = event;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(color: _T.panel.withOpacity(0.8), borderRadius: BorderRadius.circular(13), border: Border.all(color: _T.border)),
      child: Row(
        children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: e.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: e.accent.withOpacity(0.25))), child: Icon(e.icon, size: 16, color: e.accent)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, style: const TextStyle(fontFamily: _T.body, fontWeight: FontWeight.w700, color: _T.ink, fontSize: 12)),
            Text(e.subtitle, style: const TextStyle(fontFamily: _T.body, fontSize: 10, color: _T.muted)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _T.border.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text(e.time, style: const TextStyle(fontFamily: _T.body, color: _T.muted, fontSize: 10, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

// ─── Gooey Button ─────────────────────────────────────────────────────────────

class _GooeyBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;
  const _GooeyBtn({required this.label, required this.icon, required this.isPrimary, required this.onTap});
  @override
  State<_GooeyBtn> createState() => _GooeyBtnState();
}

class _GooeyBtnState extends State<_GooeyBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final ip = widget.isPrimary;
    final blobColor = ip ? _T.greenDeep : const Color(0xFF082010);
    final idleText = ip ? Colors.white : _T.green;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _ctrl.forward(),
      onExit: (_) => _ctrl.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            final t = _anim.value;
            final lc = Color.lerp(idleText, Colors.white, t)!;
            return Container(
              decoration: BoxDecoration(
                gradient: ip ? const LinearGradient(colors: [_T.green, _T.greenDeep]) : null,
                borderRadius: BorderRadius.circular(14),
                border: ip ? null : Border.all(color: Color.lerp(_T.green, _T.greenDeep, t)!, width: 1.5),
                boxShadow: [BoxShadow(color: _T.green.withOpacity(ip ? 0.30 + t * 0.15 : t * 0.25), blurRadius: 16 + t * 10, offset: const Offset(0, 6))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _GooeyPainter(progress: t, color: blobColor))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.icon, size: 16, color: lc),
                        const SizedBox(width: 9),
                        Text(widget.label, style: TextStyle(fontFamily: _T.body, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.4, color: lc)),
                      ]),
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

class _GooeyPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _GooeyPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final amplitude = h * 0.30 * math.sin(progress * math.pi);
    final blobTop = h * (1.0 - progress);
    final path = Path()..moveTo(0, h)..lineTo(0, blobTop);
    for (int i = 0; i <= 32; i++) {
      final x = w * i / 32;
      final wave = amplitude * (0.65 * math.sin(i / 32 * math.pi * 3.0 + progress * math.pi * 2) + 0.35 * math.sin(i / 32 * math.pi * 5.5 - progress * math.pi));
      path.lineTo(x, blobTop + wave);
    }
    path..lineTo(w, h)..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(_GooeyPainter old) => old.progress != progress || old.color != color;
}
