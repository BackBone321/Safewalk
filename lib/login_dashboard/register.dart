import 'package:flutter/material.dart';
import '../auth/auth_service.dart';

// ─────────────────────────────────────────────
//  Colour Palette — light luxury theme
// ─────────────────────────────────────────────
class _C {
  static const white = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F5F0);
  static const gold = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const goldLt = Color(0xFFE8D08A);
  static const green = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright = Color(0xFF2CA86E);
  static const border = Color(0x55C9A551);
  static const shadow = Color(0x14000000);
  static const textMain = Color(0xFF1A1A1A);
  static const textSub = Color(0xFF888880);
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
    with SingleTickerProviderStateMixin {
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

  late final AnimationController _introController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _fadeAnim = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutCubic,
      ),
    );

    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

      setState(() => _otpRequested = true);
      _showMessage('OTP sent to ${_emailCtrl.text.trim()}');
    } catch (e) {
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
      _showMessage(_authService.getMessageFromError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    if (_otpRequested) {
      await _verifyOtpAndRegister();
    } else {
      await _sendOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: _C.offWhite,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.45, -0.75),
            radius: 1.5,
            colors: [
              Color(0xFFEDF7F1),
              _C.offWhite,
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopAccentBar(),
            ),

            const Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _CornerPainter(),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 32 + viewInsets),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          children: [
                            const _BrandMark(),
                            const SizedBox(height: 24),

                            Container(
                              decoration: BoxDecoration(
                                color: _C.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _C.border, width: 1),
                                boxShadow: const [
                                  BoxShadow(
                                    color: _C.shadow,
                                    blurRadius: 28,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NEW MEMBER',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 4,
                                        color: _C.gold.withOpacity(0.95),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    RichText(
                                      text: const TextSpan(
                                        style: TextStyle(
                                          fontFamily: 'CormorantGaramond',
                                          fontSize: 34,
                                          height: 1.08,
                                          fontWeight: FontWeight.w500,
                                          color: _C.green,
                                        ),
                                        children: [
                                          TextSpan(text: 'Create your\n'),
                                          TextSpan(
                                            text: 'account',
                                            style: TextStyle(
                                              color: _C.goldDark,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 26),
                                    _sectionDivider('ACCOUNT DETAILS'),
                                    const SizedBox(height: 20),

                                    _LightField(
                                      label: 'FULL NAME',
                                      hint: 'Enter your full name',
                                      controller: _fullNameCtrl,
                                      keyboardType: TextInputType.name,
                                      prefixIcon: Icons.person_outline,
                                    ),
                                    const SizedBox(height: 18),

                                    _LightField(
                                      label: 'EMAIL ADDRESS',
                                      hint: 'your@email.com',
                                      controller: _emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      prefixIcon: Icons.mail_outline,
                                    ),
                                    const SizedBox(height: 18),

                                    _LightField(
                                      label: 'PHONE NUMBER',
                                      hint: '+63 9XXXXXXXXX',
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      prefixIcon: Icons.phone_outlined,
                                    ),
                                    const SizedBox(height: 18),

                                    Text(
                                      'ACCOUNT TYPE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 3,
                                        color: _C.gold.withOpacity(0.9),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _C.offWhite,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _C.border.withOpacity(0.55),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _accountType,
                                          isExpanded: true,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          dropdownColor: _C.white,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: _C.textMain,
                                            fontWeight: FontWeight.w500,
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
                                          onChanged: _isLoading
                                              ? null
                                              : (value) {
                                                  if (value != null) {
                                                    setState(() {
                                                      _accountType = value;
                                                    });
                                                  }
                                                },
                                        ),
                                      ),
                                    ),

                                    if (_otpRequested) ...[
                                      const SizedBox(height: 26),
                                      _sectionDivider('EMAIL VERIFICATION'),
                                      const SizedBox(height: 20),

                                      _LightField(
                                        label: 'OTP CODE',
                                        hint: 'Enter 6-digit OTP',
                                        controller: _otpCtrl,
                                        keyboardType: TextInputType.number,
                                        prefixIcon:
                                            Icons.verified_user_outlined,
                                      ),
                                      const SizedBox(height: 8),

                                      Text(
                                        'OTP sent to ${_emailCtrl.text.trim()}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _C.green.withOpacity(0.75),
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed:
                                              _isLoading ? null : _sendOtp,
                                          child: const Text('Resend OTP'),
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 26),
                                    _sectionDivider('SECURITY'),
                                    const SizedBox(height: 20),

                                    _LightField(
                                      label: 'PASSWORD',
                                      hint: '••••••••••••',
                                      controller: _passCtrl,
                                      obscure: _obscurePass,
                                      keyboardType:
                                          TextInputType.visiblePassword,
                                      prefixIcon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscurePass = !_obscurePass;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: _C.green.withOpacity(0.55),
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),

                                    _LightField(
                                      label: 'CONFIRM PASSWORD',
                                      hint: '••••••••••••',
                                      controller: _confirmCtrl,
                                      obscure: _obscureConfirm,
                                      keyboardType:
                                          TextInputType.visiblePassword,
                                      prefixIcon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscureConfirm =
                                                !_obscureConfirm;
                                          });
                                        },
                                        icon: Icon(
                                          _obscureConfirm
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: _C.green.withOpacity(0.55),
                                          size: 20,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 28),

                                    _PrimaryButton(
                                      text: _otpRequested
                                          ? 'VERIFY OTP'
                                          : 'SEND EMAIL OTP',
                                      isLoading: _isLoading,
                                      onTap: _handleRegister,
                                    ),

                                    const SizedBox(height: 18),

                                    Center(
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        children: [
                                          const Text(
                                            'Already a member?',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _C.textSub,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => Navigator.pop(context),
                                            child: const Text(
                                              'SIGN IN',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: _C.green,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.2,
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

                            const SizedBox(height: 20),
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
      ),
    );
  }

  Widget _sectionDivider(String label) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_C.gold, Colors.transparent],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 3,
            color: _C.gold.withOpacity(0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: _C.border.withOpacity(0.35),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Small UI Widgets
// ─────────────────────────────────────────────
class _TopAccentBar extends StatelessWidget {
  const _TopAccentBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.green, _C.bright, _C.gold],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _C.green,
            border: Border.all(color: _C.gold, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _C.green.withOpacity(0.16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: _C.gold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'SAFEWALK',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 5,
            color: _C.green.withOpacity(0.82),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LightField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool obscure;
  final IconData? prefixIcon;
  final Widget? suffixIcon;

  const _LightField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  State<_LightField> createState() => _LightFieldState();
}

class _LightFieldState extends State<_LightField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused ? _C.gold : _C.border.withOpacity(0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 3,
            color: _C.gold.withOpacity(0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (value) {
            if (_focused != value) {
              setState(() => _focused = value);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: _C.offWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: _C.gold.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: TextField(
              controller: widget.controller,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscure,
              cursorColor: _C.goldDark,
              style: const TextStyle(
                fontSize: 14,
                color: _C.textMain,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: _C.textSub.withOpacity(0.6),
                  fontSize: 14,
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color: _C.green.withOpacity(0.55),
                        size: 20,
                      )
                    : null,
                suffixIcon: widget.suffixIcon,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final bool isLoading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.text,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_C.green, _C.greenMid],
            ),
            border: Border.all(color: _C.gold, width: 1),
            boxShadow: [
              BoxShadow(
                color: _C.green.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isLoading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_C.goldLt),
                      ),
                    )
                  : Text(
                      text,
                      key: const ValueKey('text'),
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        color: _C.goldLt,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Static Corner Decoration
// ─────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _C.gold.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const d = 90.0;
    const s = 18.0;

    // top-left
    canvas.drawLine(Offset.zero, const Offset(d, 0), p);
    canvas.drawLine(Offset.zero, const Offset(0, d), p);
    canvas.drawLine(const Offset(s, 0), const Offset(s, s), p);
    canvas.drawLine(const Offset(0, s), const Offset(s, s), p);

    // bottom-right
    final br = Offset(size.width, size.height);
    canvas.drawLine(br, Offset(br.dx - d, br.dy), p);
    canvas.drawLine(br, Offset(br.dx, br.dy - d), p);
    canvas.drawLine(
      Offset(br.dx - s, br.dy),
      Offset(br.dx - s, br.dy - s),
      p,
    );
    canvas.drawLine(
      Offset(br.dx, br.dy - s),
      Offset(br.dx - s, br.dy - s),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
