import 'dart:math';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'register.dart';
import 'forgot_password.dart';
import 'admin_dashboard.dart';
import 'user_dashboard.dart';

// ─────────────────────────────────────────────
//  Colour Palette — white / light luxury theme
// ─────────────────────────────────────────────
class AppColors {
  static const white    = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F5F0);
  static const cream    = Color(0xFFF0EBE0);
  static const gold     = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const goldLt   = Color(0xFFE8D08A);
  static const green    = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright   = Color(0xFF2CA86E);
  static const border   = Color(0x55C9A551);
  static const glass    = Color(0xFFFFFFFF);
  static const shadow   = Color(0x14000000);
  static const textMain = Color(0xFF1A1A1A);
  static const textSub  = Color(0xFF888880);

  // keep these so existing references don't break
  static const deep     = Color(0xFFF7F5F0);
  static const forest   = Color(0xFFEDF7F1);
  static const emerald  = Color(0xFF134D33);
}

// ─────────────────────────────────────────────
//  Particle model
// ─────────────────────────────────────────────
class _Particle {
  double x, y, speed, size, opacity;
  _Particle({
    required this.x, required this.y,
    required this.speed, required this.size, required this.opacity,
  });
}

// ─────────────────────────────────────────────
//  Login Page
// ─────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin {

  // ── your original controllers & logic ──
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final AuthService _authService = AuthService();
  bool _rememberMe  = false;
  bool _obscurePass = true;
  bool _isLoading   = false;

  // ── animation controllers ──
  late AnimationController _brandAnim;
  late AnimationController _cardAnim;
  late Animation<Offset>   _brandSlide;
  late Animation<double>   _brandFade;
  late Animation<Offset>   _cardSlide;
  late Animation<double>   _cardFade;
  late AnimationController _particleAnim;
  final List<_Particle>    _particles = [];
  final Random             _rng       = Random();

//handling for login
Future<void> _handleLogin() async {
  final email = _emailCtrl.text.trim();
  final password = _passCtrl.text.trim();

  if (email.isEmpty || password.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please enter your Gmail and password.')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    final result = await _authService.signIn(
      email: email,
      password: password,
      location: 'Oroquieta City',
      deviceId: 'APP-LOGIN',
    );

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );

      if (result.role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UserDashboardPage()),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}// end of _handleLogin

  void _openRegisterPage() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const RegisterPage()));
  }

  void _openForgotPasswordPage() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ForgotPasswordPage()));
  }

  @override
  void initState() {
    super.initState();

    _brandAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _brandSlide = Tween<Offset>(
            begin: const Offset(-0.08, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _brandAnim, curve: Curves.easeOutCubic));
    _brandFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _brandAnim, curve: Curves.easeOut));

    _cardAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _cardSlide = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _cardAnim, curve: Curves.easeOutCubic));
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _cardAnim, curve: Curves.easeOut));

    _particleAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 16))
      ..addListener(_tickParticles)
      ..repeat();

    for (int i = 0; i < 15; i++) {
      _particles.add(_Particle(
        x:       _rng.nextDouble(),
        y:       _rng.nextDouble(),
        speed:   0.0003 + _rng.nextDouble() * 0.0006,
        size:    1.0 + _rng.nextDouble() * 2.0,
        opacity: 0.06 + _rng.nextDouble() * 0.15,
      ));
    }

    Future.delayed(
        const Duration(milliseconds: 80), () => _brandAnim.forward());
    Future.delayed(
        const Duration(milliseconds: 220), () => _cardAnim.forward());
  }

  void _tickParticles() {
    setState(() {
      for (final p in _particles) {
        p.y -= p.speed;
        if (p.y < -0.02) { p.y = 1.02; p.x = _rng.nextDouble(); }
      }
    });
  }

  @override
  void dispose() {
    _brandAnim.dispose();
    _cardAnim.dispose();
    _particleAnim.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.of(context).size;
    final isWide = size.width > 820;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          // ── soft white gradient background ──
          _GradientBackground(),

          // ── top green + gold accent bar ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.green, AppColors.bright, AppColors.gold],
                ),
              ),
            ),
          ),

          // ── subtle gold particles ──
          _ParticlesLayer(particles: _particles, size: size),

          // ── botanical vines ──
          const _VinesLayer(),

          // ── art-deco corners ──
          const _ArtDecoCorners(),

          // ── content ──
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 40),
              child: isWide
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _BrandPanel(
                            slideAnim: _brandSlide,
                            fadeAnim: _brandFade),
                        const SizedBox(width: 56),
                        _VerticalSeparator(),
                        const SizedBox(width: 56),
                        _LoginCard(
                          slideAnim: _cardSlide,
                          fadeAnim: _cardFade,
                          emailCtrl: _emailCtrl,
                          passCtrl: _passCtrl,
                          rememberMe: _rememberMe,
                          obscurePass: _obscurePass,
                          isLoading: _isLoading,
                          onRemember: (v) =>
                              setState(() => _rememberMe = v ?? false),
                          onTogglePass: () => setState(
                              () => _obscurePass = !_obscurePass),
                          onLogin: _handleLogin,
                          onRegister: _openRegisterPage,
                          onForgotPassword: _openForgotPasswordPage,
                        ),
                      ],
                    )
                  : _LoginCard(
                      slideAnim: _cardSlide,
                      fadeAnim: _cardFade,
                      emailCtrl: _emailCtrl,
                      passCtrl: _passCtrl,
                      rememberMe: _rememberMe,
                      obscurePass: _obscurePass,
                      isLoading: _isLoading,
                      onRemember: (v) =>
                          setState(() => _rememberMe = v ?? false),
                      onTogglePass: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      onLogin: _handleLogin,
                      onRegister: _openRegisterPage,
                      onForgotPassword: _openForgotPasswordPage,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Gradient Background  (white → soft green)
// ─────────────────────────────────────────────
class _GradientBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.5, -0.7),
          radius: 1.6,
          colors: [Color(0xFFEDF7F1), AppColors.offWhite],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Particles Layer
// ─────────────────────────────────────────────
class _ParticlesLayer extends StatelessWidget {
  final List<_Particle> particles;
  final Size size;
  const _ParticlesLayer(
      {required this.particles, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ParticlePainter(particles: particles),
      size: size,
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  const _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      paint.color = AppColors.gold.withOpacity(p.opacity);
      canvas.drawCircle(
          Offset(p.x * size.width, p.y * size.height), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

// ─────────────────────────────────────────────
//  Vines Layer  (subtle, light opacity)
// ─────────────────────────────────────────────
class _VinesLayer extends StatelessWidget {
  const _VinesLayer();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.1,
      child: CustomPaint(
        painter: _VinesPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _VinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final vinePaint = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final leafPaint = Paint()
      ..color = AppColors.bright.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final leftVine = Path()
      ..moveTo(w * 0.04, h)
      ..cubicTo(w * 0.04, h * 0.83, w * 0.025, h * 0.75,
          w * 0.055, h * 0.64)
      ..cubicTo(w * 0.085, h * 0.53, w * 0.02, h * 0.46,
          w * 0.05, h * 0.33)
      ..cubicTo(w * 0.08, h * 0.2, w * 0.035, h * 0.13,
          w * 0.065, h * 0.02);
    canvas.drawPath(leftVine, vinePaint);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.01, h * 0.71), -20, 12, 8);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.09, h * 0.63), 15, 10, 7);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.01, h * 0.50), -10, 13, 9);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.095, h * 0.39), 25, 11, 7);

    final rightVine = Path()
      ..moveTo(w * 0.96, h)
      ..cubicTo(w * 0.96, h * 0.83, w * 0.975, h * 0.75,
          w * 0.945, h * 0.62)
      ..cubicTo(w * 0.915, h * 0.49, w * 0.98, h * 0.41,
          w * 0.95, h * 0.28)
      ..cubicTo(w * 0.92, h * 0.14, w * 0.965, h * 0.08,
          w * 0.935, h * 0.0);
    canvas.drawPath(rightVine, vinePaint);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.99, h * 0.73), 20, 12, 8);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.905, h * 0.59), -15, 10, 7);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.99, h * 0.46), 10, 13, 9);
    _drawLeaf(canvas, leafPaint, vinePaint,
        Offset(w * 0.9, h * 0.32), -25, 11, 7);
  }

  void _drawLeaf(Canvas canvas, Paint fill, Paint stroke,
      Offset center, double angleDeg, double rx, double ry) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleDeg * pi / 180);
    final rect = Rect.fromCenter(
        center: Offset.zero, width: rx * 2, height: ry * 2);
    canvas.drawOval(rect, fill);
    canvas.drawOval(rect, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VinesPainter old) => false;
}

// ─────────────────────────────────────────────
//  Art-Deco Corners
// ─────────────────────────────────────────────
class _ArtDecoCorners extends StatelessWidget {
  const _ArtDecoCorners();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CornerPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const d = 100.0, s = 20.0;
    canvas.drawLine(Offset.zero, const Offset(d, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, d), paint);
    canvas.drawLine(const Offset(s, 0), const Offset(s, s), paint);
    canvas.drawLine(const Offset(0, s), const Offset(s, s), paint);

    final br = Offset(size.width, size.height);
    canvas.drawLine(br, Offset(br.dx - d, br.dy), paint);
    canvas.drawLine(br, Offset(br.dx, br.dy - d), paint);
    canvas.drawLine(
        Offset(br.dx - s, br.dy), Offset(br.dx - s, br.dy - s), paint);
    canvas.drawLine(
        Offset(br.dx, br.dy - s), Offset(br.dx - s, br.dy - s), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ─────────────────────────────────────────────
//  Brand Panel
// ─────────────────────────────────────────────
class _BrandPanel extends StatelessWidget {
  final Animation<Offset> slideAnim;
  final Animation<double>  fadeAnim;
  const _BrandPanel(
      {required this.slideAnim, required this.fadeAnim});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // monogram
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.green,
                  border: Border.all(color: AppColors.gold, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.green.withOpacity(0.2),
                      blurRadius: 20, spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('SW',
                    style: TextStyle(
                      fontFamily: 'CormorantGaramond',
                      fontSize: 18, fontWeight: FontWeight.w300,
                      color: AppColors.gold, letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // brand name
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 52, fontWeight: FontWeight.w300,
                    height: 1.05, letterSpacing: 1,
                    color: AppColors.green,
                  ),
                  children: [
                    TextSpan(text: 'Safe\n'),
                    TextSpan(
                      text: 'Walk',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppColors.goldDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('WALK WITH CONFIDENCE',
                style: TextStyle(
                  fontSize: 9, letterSpacing: 5,
                  color: AppColors.gold.withOpacity(0.9),
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 36),
              // gold divider
              Container(
                width: 48, height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.gold, Colors.transparent],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'YOUR SAFETY COMPANION\nFOR EVERY STEP OF\nTHE JOURNEY',
                style: TextStyle(
                  fontSize: 11, letterSpacing: 2, height: 2,
                  color: AppColors.textSub,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Vertical Separator
// ─────────────────────────────────────────────
class _VerticalSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 320,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.border,
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Login Card
// ─────────────────────────────────────────────
class _LoginCard extends StatelessWidget {
  final Animation<Offset>     slideAnim;
  final Animation<double>     fadeAnim;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool   rememberMe;
  final bool   obscurePass;
  final bool   isLoading;
  final ValueChanged<bool?>   onRemember;
  final VoidCallback          onTogglePass;
  final VoidCallback          onLogin;
  final VoidCallback          onRegister;
  final VoidCallback          onForgotPassword;

  const _LoginCard({
    required this.slideAnim,
    required this.fadeAnim,
    required this.emailCtrl,
    required this.passCtrl,
    required this.rememberMe,
    required this.obscurePass,
    required this.isLoading,
    required this.onRemember,
    required this.onTogglePass,
    required this.onLogin,
    required this.onRegister,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: Container(
          width: 400,
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.border, width: 1),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 40, spreadRadius: 0,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // top gold shimmer line
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      AppColors.gold,
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(52),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // eyebrow
                    Text('SECURE ACCESS',
                      style: TextStyle(
                        fontSize: 9, letterSpacing: 5,
                        color: AppColors.gold.withOpacity(0.9),
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // heading
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontFamily: 'CormorantGaramond',
                          fontSize: 34, fontWeight: FontWeight.w300,
                          height: 1.1, color: AppColors.green,
                        ),
                        children: [
                          TextSpan(text: 'Welcome\n'),
                          TextSpan(
                            text: 'back',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.goldDark,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // email
                    _LuxuryField(
                      label: 'EMAIL ADDRESS',
                      hint: 'your@gmail.com',
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 28),

                    // password
                    _LuxuryField(
                      label: 'PASSWORD',
                      hint: '••••••••••••',
                      controller: passCtrl,
                      obscure: obscurePass,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.green.withOpacity(0.4),
                          size: 18,
                        ),
                        onPressed: onTogglePass,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // remember + forgot row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [
                          SizedBox(
                            width: 18, height: 18,
                            child: Checkbox(
                              value: rememberMe,
                              onChanged: onRemember,
                              activeColor: AppColors.green,
                              checkColor: AppColors.gold,
                              side: const BorderSide(
                                  color: AppColors.border, width: 1),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('REMEMBER ME',
                            style: TextStyle(
                              fontSize: 9, letterSpacing: 3,
                              color: AppColors.textSub,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ]),
                        GestureDetector(
                          onTap: onForgotPassword,
                          child: Text('FORGOT PASSWORD?',
                            style: TextStyle(
                              fontSize: 9, letterSpacing: 3,
                              color: AppColors.textSub,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // sign in button
                    _SignInButton(
                        onTap: onLogin, isLoading: isLoading),

                    const SizedBox(height: 24),

                    // create account link
                    Center(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 9, letterSpacing: 3,
                            color: AppColors.textSub,
                            fontWeight: FontWeight.w300,
                          ),
                          children: [
                            const TextSpan(text: 'NEW HERE?  '),
                            WidgetSpan(
                              child: GestureDetector(
                                onTap: onRegister,
                                child: const Text('CREATE AN ACCOUNT',
                                  style: TextStyle(
                                    fontSize: 9, letterSpacing: 3,
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Luxury Input Field  (light theme)
// ─────────────────────────────────────────────
class _LuxuryField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool obscure;
  final Widget? suffixIcon;

  const _LuxuryField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.suffixIcon,
  });

  @override
  State<_LuxuryField> createState() => _LuxuryFieldState();
}

class _LuxuryFieldState extends State<_LuxuryField>
    with SingleTickerProviderStateMixin {
  late AnimationController _lineAnim;
  late Animation<double>   _lineWidth;

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _lineWidth = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
            parent: _lineAnim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() { _lineAnim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) =>
          hasFocus ? _lineAnim.forward() : _lineAnim.reverse(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
            style: TextStyle(
              fontSize: 9, letterSpacing: 4,
              color: AppColors.gold.withOpacity(0.9),
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 10),
          Stack(children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                    color: AppColors.border.withOpacity(0.5), width: 1),
              ),
              child: TextField(
                controller: widget.controller,
                keyboardType: widget.keyboardType,
                obscureText: widget.obscure,
                style: const TextStyle(
                  fontSize: 14, letterSpacing: 2,
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w300,
                ),
                cursorColor: AppColors.gold,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: AppColors.textSub.withOpacity(0.5),
                    fontSize: 14, letterSpacing: 2,
                  ),
                  suffixIcon: widget.suffixIcon,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  isDense: true,
                ),
              ),
            ),
            // animated gold sweep line
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedBuilder(
                animation: _lineWidth,
                builder: (_, __) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _lineWidth.value,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.gold, AppColors.bright],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sign In Button  (shimmer + loading)
// ─────────────────────────────────────────────
class _SignInButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLoading;
  const _SignInButton(
      {required this.onTap, required this.isLoading});

  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmer;
  late Animation<double>   _shimmerAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _shimmerAnim = Tween<double>(begin: -1, end: 2).animate(
        CurvedAnimation(parent: _shimmer, curve: Curves.linear));
  }

  @override
  void dispose() { _shimmer.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) { if (!widget.isLoading) setState(() => _pressed = true); },
      onTapUp:     (_) { if (!widget.isLoading) setState(() => _pressed = false); },
      onTapCancel: ()  { if (!widget.isLoading) setState(() => _pressed = false); },
      onTap: widget.isLoading ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, _pressed ? 0 : -1, 0),
        child: Container(
          width: double.infinity, height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.green, AppColors.greenMid],
            ),
            border: Border.all(color: AppColors.gold, width: 1),
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withOpacity(0.25),
                blurRadius: 20, offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!widget.isLoading)
                  AnimatedBuilder(
                    animation: _shimmerAnim,
                    builder: (_, __) => Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment(_shimmerAnim.value, 0),
                        widthFactor: 0.35,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.transparent,
                              Colors.white.withOpacity(0.1),
                              Colors.transparent,
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                widget.isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.goldLt),
                        ),
                      )
                    : const Text('ENTER  —  SIGN IN',
                        style: TextStyle(
                          fontSize: 10, letterSpacing: 6,
                          color: AppColors.goldLt,
                          fontWeight: FontWeight.w400,
                        )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}