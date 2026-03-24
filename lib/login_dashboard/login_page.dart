import 'dart:math';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import 'register.dart';
import 'forgot_password.dart';
import '../admin/admin_dashboard.dart';
import '../User/user_dashboard.dart';
import '../User/parent_dashboard.dart';

// ─────────────────────────────────────────────
//  Colour Palette — white / light luxury theme
// ─────────────────────────────────────────────
class AppColors {
  static const white = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F5F0);
  static const cream = Color(0xFFF0EBE0);
  static const gold = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const goldLt = Color(0xFFE8D08A);
  static const green = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright = Color(0xFF2CA86E);
  static const border = Color(0x55C9A551);
  static const glass = Color(0xFFFFFFFF);
  static const shadow = Color(0x14000000);
  static const textMain = Color(0xFF1A1A1A);
  static const textSub = Color(0xFF888880);

  static const deep = Color(0xFFF7F5F0);
  static const forest = Color(0xFFEDF7F1);
  static const emerald = Color(0xFF134D33);
}

// ─────────────────────────────────────────────
//  Particle model
// ─────────────────────────────────────────────
class _Particle {
  double x, y, speed, size, opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
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

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final AuthService _authService = AuthService();

  bool _rememberMe = false;
  bool _obscurePass = true;
  bool _isLoading = false;

  late AnimationController _brandAnim;
  late AnimationController _cardAnim;
  late Animation<Offset> _brandSlide;
  late Animation<double> _brandFade;
  late Animation<Offset> _cardSlide;
  late Animation<double> _cardFade;
  late AnimationController _particleAnim;

  final List<_Particle> _particles = [];
  final Random _rng = Random();

  Future<void> _handleLogin() async {
    final loginInput = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (loginInput.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email/phone number and password.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signIn(
        loginInput: loginInput,
        password: password,
        location: 'Mobile App',
        deviceId: 'APP-LOGIN',
      );

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }

      final role = result.role.toLowerCase().trim();

      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
      } else if (role == 'student' || role == 'user') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UserDashboardPage()),
        );
      } else if (role == 'parent') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardPage()),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unknown role: $role')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authService.getMessageFromError(e))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();

    _brandAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _cardAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );

    _brandSlide = Tween<Offset>(
      begin: const Offset(-0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _brandAnim, curve: Curves.easeOutCubic));

    _brandFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _brandAnim, curve: Curves.easeOut));

    _cardSlide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOutCubic));

    _cardFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOut));

    _particleAnim =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: 1),
          )
          ..addListener(_tickParticles)
          ..repeat();

    for (int i = 0; i < 10; i++) {
      _particles.add(
        _Particle(
          x: _rng.nextDouble(),
          y: _rng.nextDouble(),
          speed: 0.0003 + _rng.nextDouble() * 0.0006,
          size: 1.0 + _rng.nextDouble() * 2.0,
          opacity: 0.06 + _rng.nextDouble() * 0.12,
        ),
      );
    }

    _brandAnim.forward();
    _cardAnim.forward();
  }

  void _tickParticles() {
    for (final p in _particles) {
      p.y -= p.speed;
      if (p.y < -0.02) {
        p.y = 1.02;
        p.x = _rng.nextDouble();
      }
    }
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
    final size = MediaQuery.of(context).size;
    final isCompactLayout = size.width < 980;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.45, -0.75),
                radius: 1.7,
                colors: [Color(0xFFEDF7F1), AppColors.offWhite],
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
                  colors: [AppColors.green, AppColors.bright, AppColors.gold],
                ),
              ),
            ),
          ),

          RepaintBoundary(
            child: CustomPaint(
              size: size,
              isComplex: false,
              willChange: true,
              painter: _ParticlePainter(
                particles: _particles,
                repaint: _particleAnim,
              ),
            ),
          ),

          const _CornerDecorations(),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompactLayout ? 14 : 24,
                  vertical: isCompactLayout ? 20 : 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isCompactLayout ? 640 : 1140,
                  ),
                  child: isCompactLayout
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FadeTransition(
                              opacity: _brandFade,
                              child: SlideTransition(
                                position: _brandSlide,
                                child: const _BrandPanel(isCompact: true),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LoginCard(
                              slideAnim: _cardSlide,
                              fadeAnim: _cardFade,
                              emailCtrl: _emailCtrl,
                              passCtrl: _passCtrl,
                              rememberMe: _rememberMe,
                              obscurePass: _obscurePass,
                              isLoading: _isLoading,
                              isCompact: true,
                              onRemember: (v) {
                                setState(() => _rememberMe = v ?? false);
                              },
                              onTogglePass: () {
                                setState(() => _obscurePass = !_obscurePass);
                              },
                              onLogin: _handleLogin,
                              onRegister: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterPage(),
                                  ),
                                );
                              },
                              onForgotPassword: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: FadeTransition(
                                opacity: _brandFade,
                                child: SlideTransition(
                                  position: _brandSlide,
                                  child: const _BrandPanel(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 34),
                            _VerticalSeparator(),
                            const SizedBox(width: 34),
                            _LoginCard(
                              slideAnim: _cardSlide,
                              fadeAnim: _cardFade,
                              emailCtrl: _emailCtrl,
                              passCtrl: _passCtrl,
                              rememberMe: _rememberMe,
                              obscurePass: _obscurePass,
                              isLoading: _isLoading,
                              isCompact: false,
                              onRemember: (v) {
                                setState(() => _rememberMe = v ?? false);
                              },
                              onTogglePass: () {
                                setState(() => _obscurePass = !_obscurePass);
                              },
                              onLogin: _handleLogin,
                              onRegister: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterPage(),
                                  ),
                                );
                              },
                              onForgotPassword: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordPage(),
                                  ),
                                );
                              },
                            ),
                          ],
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

// ─────────────────────────────────────────────
//  Brand Panel
// ─────────────────────────────────────────────
class _BrandPanel extends StatelessWidget {
  final bool isCompact;

  const _BrandPanel({this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: isCompact ? 640 : 420),
      padding: EdgeInsets.all(isCompact ? 24 : 34),
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.88),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isCompact ? 62 : 76,
            height: isCompact ? 62 : 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green,
              border: Border.all(color: AppColors.gold, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.green.withOpacity(0.18),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                'SW',
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: isCompact ? 20 : 24,
                  fontWeight: FontWeight.w300,
                  color: AppColors.gold,
                ),
              ),
            ),
          ),
          SizedBox(height: isCompact ? 18 : 24),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: isCompact ? 44 : 54,
                fontWeight: FontWeight.w300,
                height: 1.03,
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
          SizedBox(height: isCompact ? 8 : 10),
          Text(
            'SECURE ACCESS PORTAL',
            style: TextStyle(
              fontSize: isCompact ? 8 : 9,
              letterSpacing: isCompact ? 3.2 : 6,
              color: AppColors.green.withOpacity(0.8),
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: isCompact ? 22 : 30),
          Container(
            width: 56,
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold, Colors.transparent],
              ),
            ),
          ),
          SizedBox(height: isCompact ? 18 : 28),
          Text(
            'LOGIN AS ADMIN, STUDENT,\nOR PARENT/GUARDIAN USING\nYOUR REGISTERED ACCOUNT.',
            style: TextStyle(
              fontSize: isCompact ? 10 : 11,
              letterSpacing: isCompact ? 1.2 : 2,
              height: isCompact ? 1.65 : 2,
              color: AppColors.textSub,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
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
      width: 1,
      height: 320,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, AppColors.border, Colors.transparent],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Login Card
// ─────────────────────────────────────────────
class _LoginCard extends StatelessWidget {
  final Animation<Offset> slideAnim;
  final Animation<double> fadeAnim;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool rememberMe;
  final bool obscurePass;
  final bool isLoading;
  final bool isCompact;
  final ValueChanged<bool?> onRemember;
  final VoidCallback onTogglePass;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onForgotPassword;

  const _LoginCard({
    required this.slideAnim,
    required this.fadeAnim,
    required this.emailCtrl,
    required this.passCtrl,
    required this.rememberMe,
    required this.obscurePass,
    required this.isLoading,
    required this.isCompact,
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
          width: isCompact ? double.infinity : 400,
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.border, width: 1),
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 40,
                spreadRadius: 0,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.gold,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isCompact ? 26 : 52),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SECURE ACCESS',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: isCompact ? 3.2 : 5,
                        color: AppColors.gold.withOpacity(0.9),
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    SizedBox(height: isCompact ? 8 : 10),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: 'CormorantGaramond',
                          fontSize: isCompact ? 30 : 34,
                          fontWeight: FontWeight.w300,
                          height: 1.1,
                          color: AppColors.green,
                        ),
                        children: const [
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
                    SizedBox(height: isCompact ? 24 : 36),
                    _LuxuryField(
                      label: 'EMAIL',
                      hint: 'Enter your email',
                      controller: emailCtrl,
                      keyboardType: TextInputType.text,
                    ),
                    SizedBox(height: isCompact ? 18 : 28),
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
                    SizedBox(height: isCompact ? 16 : 28),
                    if (isCompact) ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: rememberMe,
                              onChanged: onRemember,
                              activeColor: AppColors.green,
                              checkColor: AppColors.gold,
                              side: const BorderSide(
                                color: AppColors.border,
                                width: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'REMEMBER ME',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 2,
                              color: AppColors.textSub,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: onForgotPassword,
                        child: Text(
                          'FORGOT PASSWORD?',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 2,
                            color: AppColors.textSub,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ] else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: Checkbox(
                                  value: rememberMe,
                                  onChanged: onRemember,
                                  activeColor: AppColors.green,
                                  checkColor: AppColors.gold,
                                  side: const BorderSide(
                                    color: AppColors.border,
                                    width: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'REMEMBER ME',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 3,
                                  color: AppColors.textSub,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: onForgotPassword,
                            child: Text(
                              'FORGOT PASSWORD?',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 3,
                                color: AppColors.textSub,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: isCompact ? 22 : 32),
                    _SignInButton(onTap: onLogin, isLoading: isLoading),
                    SizedBox(height: isCompact ? 16 : 24),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            'NEW HERE?',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: isCompact ? 2 : 3,
                              color: AppColors.textSub,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          GestureDetector(
                            onTap: onRegister,
                            child: Text(
                              'CREATE AN ACCOUNT',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: isCompact ? 2 : 3,
                                color: AppColors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
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
//  Luxury Input Field
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
  late Animation<double> _lineWidth;

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _lineWidth = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _lineAnim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _lineAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _lineAnim.forward();
        } else {
          _lineAnim.reverse();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 4,
              color: AppColors.gold.withOpacity(0.9),
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 10),
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.border.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  keyboardType: widget.keyboardType,
                  obscureText: widget.obscure,
                  style: const TextStyle(
                    fontSize: 14,
                    letterSpacing: 2,
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w300,
                  ),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      color: AppColors.textSub.withOpacity(0.5),
                      fontSize: 14,
                      letterSpacing: 2,
                    ),
                    suffixIcon: widget.suffixIcon,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _lineWidth,
                  builder: (_, __) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _lineWidth.value,
                      child: Container(height: 1.2, color: AppColors.gold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sign In Button
// ─────────────────────────────────────────────
class _SignInButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLoading;

  const _SignInButton({required this.onTap, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.green,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.gold.withOpacity(0.65)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.gold,
                    ),
                  )
                : const Text(
                    'LOGIN',
                    style: TextStyle(
                      color: AppColors.white,
                      letterSpacing: 4,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Background particles painter
// ─────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  _ParticlePainter({required this.particles, required Listenable repaint})
    : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = AppColors.gold.withOpacity(p.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => false;
}

// ─────────────────────────────────────────────
//  Corner decorations
// ─────────────────────────────────────────────
class _CornerDecorations extends StatelessWidget {
  const _CornerDecorations();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: const [
          Positioned(top: 20, left: 20, child: _CornerPiece()),
          Positioned(top: 20, right: 20, child: _CornerPiece(isRight: true)),
          Positioned(bottom: 20, left: 20, child: _CornerPiece(isBottom: true)),
          Positioned(
            bottom: 20,
            right: 20,
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
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationZ(
        isRight && isBottom
            ? pi
            : isRight
            ? pi / 2
            : isBottom
            ? -pi / 2
            : 0,
      ),
      child: SizedBox(
        width: 42,
        height: 42,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withOpacity(0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);

    canvas.drawLine(const Offset(10, 0), const Offset(10, 10), paint);
    canvas.drawLine(const Offset(0, 10), const Offset(10, 10), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
