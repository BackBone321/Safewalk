import 'dart:math';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart';

// ─────────────────────────────────────────────
//  Colour Palette — white / light luxury theme
// ─────────────────────────────────────────────
class _C {
  static const white    = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F5F0);
  static const gold     = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const goldLt   = Color(0xFFE8D08A);
  static const green    = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright   = Color(0xFF2CA86E);
  static const border   = Color(0x55C9A551);
  static const shadow   = Color(0x14000000);
  static const textMain = Color(0xFF1A1A1A);
  static const textSub  = Color(0xFF888880);
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
//  Register Page
// ─────────────────────────────────────────────
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {

  // ── controllers & service ──
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final AuthService _authService = AuthService();

  String _accountType = 'Student';
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _otpRequested = false;

  // ── animation controllers ──
  late AnimationController _cardAnim;
  late Animation<Offset>   _cardSlide;
  late Animation<double>   _cardFade;
  late AnimationController _particleAnim;
  final List<_Particle>    _particles = [];
  final Random             _rng       = Random();

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateInputs() {
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final password = _passCtrl.text.trim();
    final confirmPassword = _confirmCtrl.text.trim();

    if (fullName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showMessage('Please fill in all fields.');
      return false;
    }
    if (password != confirmPassword) {
      _showMessage('Passwords do not match.');
      return false;
    }
    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return false;
    }
    return true;
  }

  Future<void> _sendOtp() async {
    if (!_validateInputs()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.sendEmailOtp(
        email: _emailCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
      );
      if (!mounted) return;

      setState(() {
        _otpRequested = true;
      });

      _showMessage('OTP sent to ${_emailCtrl.text.trim()}');
    } catch (e) {
      if (!mounted) return;
      _showMessage(_authService.getMessageFromError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtpAndRegister() async {
    if (!_validateInputs()) return;
    if (!_otpRequested) {
      _showMessage('Request OTP first.');
      return;
    }

    final otp = _otpCtrl.text.trim();
    if (otp.length < 6) {
      _showMessage('Enter the 6-digit OTP.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.registerWithEmailOtp(
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        role: _accountType.toLowerCase(),
        otpCode: otp,
      );

      if (!mounted) return;
      _showMessage('Account created successfully.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_authService.getMessageFromError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    if (_otpRequested) {
      await _verifyOtpAndRegister();
      return;
    }
    await _sendOtp();
  }

  @override
  void initState() {
    super.initState();

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
        opacity: 0.06 + _rng.nextDouble() * 0.12,
      ));
    }

    Future.delayed(
        const Duration(milliseconds: 100), () => _cardAnim.forward());
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
    _cardAnim.dispose();
    _particleAnim.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _C.offWhite,
      body: Stack(
        children: [
          // ── soft white gradient background ──
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.5, -0.7),
                radius: 1.6,
                colors: [Color(0xFFEDF7F1), _C.offWhite],
              ),
            ),
          ),

          // ── top green + gold accent bar ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_C.green, _C.bright, _C.gold],
                ),
              ),
            ),
          ),

          // ── subtle gold particles ──
          CustomPaint(
            painter: _ParticlePainter(particles: _particles),
            size: size,
          ),

          // ── botanical vines ──
          const _VinesLayer(),

          // ── art-deco corners ──
          const _CornerWidget(),

          // ── content ──
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: Column(
                  children: [

                    // brand mark
                    FadeTransition(
                      opacity: _cardFade,
                      child: Column(children: [
                        Container(
                          width: 62, height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _C.green,
                            border: Border.all(
                                color: _C.gold, width: 1.5),
                            boxShadow: [BoxShadow(
                              color: _C.green.withOpacity(0.2),
                              blurRadius: 20, spreadRadius: 2,
                            )],
                          ),
                          child: const Center(
                            child: Text('SW', style: TextStyle(
                              fontFamily: 'CormorantGaramond',
                              fontSize: 18, fontWeight: FontWeight.w300,
                              color: _C.gold, letterSpacing: 1.5,
                            )),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('SAFEWALK', style: TextStyle(
                          fontSize: 9, letterSpacing: 6,
                          color: _C.green.withOpacity(0.8),
                          fontWeight: FontWeight.w400,
                        )),
                      ]),
                    ),

                    const SizedBox(height: 28),

                    // ── white card ──
                    FadeTransition(
                      opacity: _cardFade,
                      child: SlideTransition(
                        position: _cardSlide,
                        child: Container(
                          width: 440,
                          decoration: BoxDecoration(
                            color: _C.white,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                                color: _C.border, width: 1),
                            boxShadow: [BoxShadow(
                              color: _C.shadow,
                              blurRadius: 40, spreadRadius: 0,
                              offset: const Offset(0, 12),
                            )],
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
                                      _C.gold,
                                      Colors.transparent,
                                    ]),
                                  ),
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.all(48),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [

                                    // eyebrow
                                    Text('NEW MEMBER',
                                      style: TextStyle(
                                        fontSize: 9, letterSpacing: 5,
                                        color: _C.gold.withOpacity(0.9),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // heading
                                    RichText(
                                      text: const TextSpan(
                                        style: TextStyle(
                                          fontFamily: 'CormorantGaramond',
                                          fontSize: 34,
                                          fontWeight: FontWeight.w300,
                                          height: 1.1,
                                          color: _C.green,
                                        ),
                                        children: [
                                          TextSpan(text: 'Create your\n'),
                                          TextSpan(
                                            text: 'account',
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: _C.goldDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 32),
                                    _sectionDivider('ACCOUNT DETAILS'),
                                    const SizedBox(height: 24),

                                    _LuxField(
                                      label: 'FULL NAME',
                                      hint: 'Enter your full name',
                                      controller: _fullNameCtrl,
                                      keyboardType: TextInputType.name,
                                      prefixIcon: Icons.person_outline,
                                    ),
                                    const SizedBox(height: 22),

                                    _LuxField(
                                      label: 'EMAIL ADDRESS',
                                      hint: 'your@email.com',
                                      controller: _emailCtrl,
                                      keyboardType:
                                          TextInputType.emailAddress,
                                      prefixIcon: Icons.mail_outline,
                                    ),
                                    const SizedBox(height: 22),

                                    _LuxField(
                                      label: 'PHONE NUMBER',
                                      hint: '+63 9XXXXXXXXX',
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      prefixIcon: Icons.phone_outlined,
                                    ),
                                    const SizedBox(height: 22),

                                    if (_otpRequested) ...[
                                      _LuxField(
                                        label: 'OTP CODE',
                                        hint: 'Enter 6-digit OTP',
                                        controller: _otpCtrl,
                                        keyboardType: TextInputType.number,
                                        prefixIcon: Icons.verified_user_outlined,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'OTP sent to ${_emailCtrl.text.trim()}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: _C.green.withOpacity(0.7),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _isLoading ? null : _sendOtp,
                                          child: const Text('Resend OTP'),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],

                                    Text(
                                      'ACCOUNT TYPE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        letterSpacing: 4,
                                        color: _C.gold.withOpacity(0.9),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: _C.offWhite,
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: _C.border.withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _accountType,
                                          isExpanded: true,
                                          dropdownColor: _C.white,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            letterSpacing: 1.2,
                                            color: _C.textMain,
                                            fontWeight: FontWeight.w300,
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'Student',
                                              child: Text('Student'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'Parent',
                                              child: Text('Parent'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value != null) {
                                              setState(() => _accountType = value);
                                            }
                                          },
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 32),
                                    _sectionDivider('SECURITY'),
                                    const SizedBox(height: 24),

                                    _LuxField(
                                      label: 'PASSWORD',
                                      hint: '••••••••••••',
                                      controller: _passCtrl,
                                      obscure: _obscurePass,
                                      prefixIcon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: _C.green.withOpacity(0.4),
                                          size: 18,
                                        ),
                                        onPressed: () => setState(() =>
                                            _obscurePass = !_obscurePass),
                                      ),
                                    ),
                                    const SizedBox(height: 22),

                                    _LuxField(
                                      label: 'CONFIRM PASSWORD',
                                      hint: '••••••••••••',
                                      controller: _confirmCtrl,
                                      obscure: _obscureConfirm,
                                      prefixIcon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureConfirm
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: _C.green.withOpacity(0.4),
                                          size: 18,
                                        ),
                                        onPressed: () => setState(() =>
                                            _obscureConfirm =
                                                !_obscureConfirm),
                                      ),
                                    ),

                                    const SizedBox(height: 36),

                                    // ── CREATE ACCOUNT BUTTON ──
                                    _RegisterButton(
                                      isLoading: _isLoading,
                                      label: _otpRequested ? 'VERIFY OTP' : 'SEND EMAIL OTP',
                                      onTap: _handleRegister,
                                    ),

                                    const SizedBox(height: 22),

                                    // sign in link
                                    Center(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: 9, letterSpacing: 3,
                                            color: _C.textSub,
                                          ),
                                          children: [
                                            const TextSpan(
                                                text: 'Already a member?  '),
                                            WidgetSpan(
                                              child: GestureDetector(
                                                onTap: () =>
                                                    Navigator.pop(context),
                                                child: const Text('SIGN IN',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    letterSpacing: 3,
                                                    color: _C.green,
                                                    fontWeight:
                                                        FontWeight.w600,
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
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider(String label) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 320,
        child: Row(children: [
          Container(
            width: 28,
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_C.gold, Colors.transparent]),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 4,
              color: _C.gold.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: _C.border.withOpacity(0.4),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Luxury Input Field  (light theme)
// ─────────────────────────────────────────────
class _LuxField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool obscure;
  final IconData? prefixIcon;
  final Widget? suffixIcon;

  const _LuxField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  State<_LuxField> createState() => _LuxFieldState();
}

class _LuxFieldState extends State<_LuxField>
    with SingleTickerProviderStateMixin {
  late AnimationController _line;
  late Animation<double>   _lineW;

  @override
  void initState() {
    super.initState();
    _line = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _lineW = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _line, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() { _line.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => f ? _line.forward() : _line.reverse(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: TextStyle(
            fontSize: 9, letterSpacing: 4,
            color: _C.gold.withOpacity(0.9),
            fontWeight: FontWeight.w400,
          )),
          const SizedBox(height: 8),
          Stack(children: [
            Container(
              decoration: BoxDecoration(
                color: _C.offWhite,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                    color: _C.border.withOpacity(0.5), width: 1),
              ),
              child: TextField(
                controller: widget.controller,
                keyboardType: widget.keyboardType,
                obscureText: widget.obscure,
                style: const TextStyle(
                  fontSize: 13, letterSpacing: 1.5,
                  color: _C.textMain, fontWeight: FontWeight.w300,
                ),
                cursorColor: _C.gold,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: _C.textSub.withOpacity(0.5),
                    fontSize: 13, letterSpacing: 1,
                  ),
                  prefixIcon: widget.prefixIcon != null
                      ? Icon(widget.prefixIcon,
                          color: _C.green.withOpacity(0.4), size: 18)
                      : null,
                  suffixIcon: widget.suffixIcon,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  isDense: true,
                ),
              ),
            ),
            // animated gold sweep bottom line
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedBuilder(
                animation: _lineW,
                builder: (_, __) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _lineW.value,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_C.gold, _C.bright]),
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
//  Register Button  (shimmer + loading spinner)
// ─────────────────────────────────────────────
class _RegisterButton extends StatefulWidget {
  final bool isLoading;
  final String label;
  final VoidCallback onTap;
  const _RegisterButton(
      {required this.isLoading, required this.label, required this.onTap});

  @override
  State<_RegisterButton> createState() => _RegisterButtonState();
}

class _RegisterButtonState extends State<_RegisterButton>
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
              colors: [_C.green, _C.greenMid],
            ),
            border: Border.all(color: _C.gold, width: 1),
            borderRadius: BorderRadius.circular(1),
            boxShadow: [BoxShadow(
              color: _C.green.withOpacity(0.25),
              blurRadius: 20, offset: const Offset(0, 8),
            )],
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
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              _C.goldLt),
                        ),
                      )
                    : Text(widget.label,
                        style: const TextStyle(
                          fontSize: 10, letterSpacing: 6,
                          color: _C.goldLt,
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

// ─────────────────────────────────────────────
//  Painters
// ─────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  const _ParticlePainter({required this.particles});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      paint.color = _C.gold.withOpacity(p.opacity);
      canvas.drawCircle(
          Offset(p.x * size.width, p.y * size.height), p.size, paint);
    }
  }
  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

class _VinesLayer extends StatelessWidget {
  const _VinesLayer();
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: 0.1,
    child: CustomPaint(
        painter: _VinesPainter(), child: const SizedBox.expand()),
  );
}

class _VinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final vine = Paint()
      ..color = _C.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final leaf = Paint()
      ..color = _C.bright.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    final lv = Path()
      ..moveTo(w * 0.04, h)
      ..cubicTo(w * 0.04, h * 0.83, w * 0.025, h * 0.75,
          w * 0.055, h * 0.64)
      ..cubicTo(w * 0.085, h * 0.53, w * 0.02, h * 0.46,
          w * 0.05, h * 0.33)
      ..cubicTo(w * 0.08, h * 0.2, w * 0.035, h * 0.13,
          w * 0.065, h * 0.02);
    canvas.drawPath(lv, vine);
    _leaf(canvas, leaf, vine, Offset(w * 0.01, h * 0.71), -20, 12, 8);
    _leaf(canvas, leaf, vine, Offset(w * 0.09, h * 0.63), 15, 10, 7);
    _leaf(canvas, leaf, vine, Offset(w * 0.01, h * 0.50), -10, 13, 9);
    _leaf(canvas, leaf, vine, Offset(w * 0.095, h * 0.39), 25, 11, 7);
    final rv = Path()
      ..moveTo(w * 0.96, h)
      ..cubicTo(w * 0.96, h * 0.83, w * 0.975, h * 0.75,
          w * 0.945, h * 0.62)
      ..cubicTo(w * 0.915, h * 0.49, w * 0.98, h * 0.41,
          w * 0.95, h * 0.28)
      ..cubicTo(w * 0.92, h * 0.14, w * 0.965, h * 0.08,
          w * 0.935, h * 0.0);
    canvas.drawPath(rv, vine);
    _leaf(canvas, leaf, vine, Offset(w * 0.99, h * 0.73), 20, 12, 8);
    _leaf(canvas, leaf, vine, Offset(w * 0.905, h * 0.59), -15, 10, 7);
    _leaf(canvas, leaf, vine, Offset(w * 0.99, h * 0.46), 10, 13, 9);
    _leaf(canvas, leaf, vine, Offset(w * 0.9, h * 0.32), -25, 11, 7);
  }
  void _leaf(Canvas c, Paint fill, Paint stroke,
      Offset center, double angle, double rx, double ry) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(angle * 3.14159 / 180);
    final r = Rect.fromCenter(
        center: Offset.zero, width: rx * 2, height: ry * 2);
    c.drawOval(r, fill);
    c.drawOval(r, stroke);
    c.restore();
  }
  @override
  bool shouldRepaint(_VinesPainter old) => false;
}

class _CornerWidget extends StatelessWidget {
  const _CornerWidget();
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _CornerPainter(), child: const SizedBox.expand());
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _C.gold.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const d = 100.0, s = 20.0;
    canvas.drawLine(Offset.zero, const Offset(d, 0), p);
    canvas.drawLine(Offset.zero, const Offset(0, d), p);
    canvas.drawLine(const Offset(s, 0), const Offset(s, s), p);
    canvas.drawLine(const Offset(0, s), const Offset(s, s), p);
    final br = Offset(size.width, size.height);
    canvas.drawLine(br, Offset(br.dx - d, br.dy), p);
    canvas.drawLine(br, Offset(br.dx, br.dy - d), p);
    canvas.drawLine(Offset(br.dx - s, br.dy),
        Offset(br.dx - s, br.dy - s), p);
    canvas.drawLine(Offset(br.dx, br.dy - s),
        Offset(br.dx - s, br.dy - s), p);
  }
  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
