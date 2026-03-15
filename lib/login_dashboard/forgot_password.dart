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
//  Forgot Password Page
// ─────────────────────────────────────────────
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailCtrl = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;

  late final AnimationController _introController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  Future<void> _handleResetPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.sendPasswordResetEmail(email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Check your inbox.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authService.getMessageFromError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
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
    _emailCtrl.dispose();
    super.dispose();
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
                  padding: EdgeInsets.fromLTRB(24, 32, 24, 32 + viewInsets),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  foregroundColor: _C.green.withOpacity(0.75),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 36),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 14,
                                ),
                                label: const Text(
                                  'BACK',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),
                            const _BrandMark(),
                            const SizedBox(height: 28),

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
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _C.green.withOpacity(0.07),
                                        border: Border.all(
                                          color: _C.border,
                                          width: 1,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.lock_reset_outlined,
                                        color: _C.green.withOpacity(0.75),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 18),

                                    Text(
                                      'ACCOUNT RECOVERY',
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
                                          TextSpan(text: 'Forgot your\n'),
                                          TextSpan(
                                            text: 'password?',
                                            style: TextStyle(
                                              color: _C.goldDark,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    const Text(
                                      'Enter your email address and Firebase will send you a password reset email.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.7,
                                        color: _C.textSub,
                                      ),
                                    ),
                                    const SizedBox(height: 28),

                                    Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 1,
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                _C.gold,
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'YOUR EMAIL',
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
                                    ),
                                    const SizedBox(height: 22),

                                    _LightField(
                                      label: 'REGISTERED EMAIL',
                                      hint: 'your@email.com',
                                      controller: _emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      prefixIcon: Icons.mail_outline,
                                    ),

                                    const SizedBox(height: 28),

                                    _PrimaryButton(
                                      text: 'SEND RESET EMAIL',
                                      isLoading: _isLoading,
                                      onTap: _handleResetPassword,
                                    ),

                                    const SizedBox(height: 18),

                                    Center(
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        children: [
                                          const Text(
                                            'Remembered it?',
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

class _LightField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final IconData? prefixIcon;

  const _LightField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
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
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(
                fontSize: 14,
                color: _C.textMain,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _C.goldDark,
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