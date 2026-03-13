import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../config/emailjs_config.dart';

class LoginResult {
  final bool success;
  final String role;
  final String message;

  LoginResult({
    required this.success,
    required this.role,
    required this.message,
  });
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, _PendingEmailOtp> _pendingEmailOtps = {};

  String _normalizePhoneForLookup(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+|-'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    return cleaned;
  }

  String _generateOtp() {
    final value = Random.secure().nextInt(900000) + 100000;
    return value.toString();
  }

  Future<void> _sendOtpViaEmailJs({
    required String toEmail,
    required String toName,
    required String otpCode,
  }) async {
    if (EmailJsConfig.serviceId.isEmpty ||
        EmailJsConfig.templateId.isEmpty ||
        EmailJsConfig.publicKey.isEmpty) {
      throw FirebaseAuthException(
        code: 'emailjs-not-configured',
        message: 'Email OTP is not configured. Check EmailJsConfig constants.',
      );
    }

    final otpMessage =
        'Your SafeWalk OTP code is $otpCode. This code expires in 5 minutes.';

    final payload = <String, dynamic>{
      'service_id': EmailJsConfig.serviceId,
      'template_id': EmailJsConfig.templateId,
      'user_id': EmailJsConfig.publicKey,
      'template_params': <String, dynamic>{
        'to_email': toEmail,
        'to_name': toName,
        'otp_code': otpCode,
        'app_name': 'Safewalk',
        'email': toEmail,
        'user_email': toEmail,
        'recipient': toEmail,
        'recipient_email': toEmail,
        'name': toName,
        'user_name': toName,
        'otp': otpCode,
        'code': otpCode,
        'verification_code': otpCode,
        'message': otpMessage,
        'reply_to': toEmail,
      },
    };

    final response = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 403 &&
        response.body.contains('non-browser environments')) {
      throw FirebaseAuthException(
        code: 'emailjs-non-browser-blocked',
        message:
            'EmailJS blocked this environment. Enable non-browser API access in EmailJS security settings.',
      );
    }

    if (response.statusCode == 412) {
      throw FirebaseAuthException(
        code: 'emailjs-precondition-failed',
        message: 'EmailJS rejected the request (412): ${response.body}',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseAuthException(
        code: 'emailjs-send-failed',
        message:
            'Failed to send OTP email (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<void> sendEmailOtp({
    required String email,
    required String fullName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final otpCode = _generateOtp();

    await _sendOtpViaEmailJs(
      toEmail: normalizedEmail,
      toName: fullName.trim(),
      otpCode: otpCode,
    );

    _pendingEmailOtps[normalizedEmail] = _PendingEmailOtp(
      code: otpCode,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      attempts: 0,
    );
  }

  Future<void> registerWithEmailOtp({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required String role,
    required String otpCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final pendingOtp = _pendingEmailOtps[normalizedEmail];

    if (pendingOtp == null) {
      throw FirebaseAuthException(
        code: 'otp-not-requested',
        message: 'Request OTP first.',
      );
    }

    if (DateTime.now().isAfter(pendingOtp.expiresAt)) {
      _pendingEmailOtps.remove(normalizedEmail);
      throw FirebaseAuthException(
        code: 'otp-expired',
        message: 'OTP expired. Please request a new OTP.',
      );
    }

    pendingOtp.attempts += 1;
    if (pendingOtp.attempts > 5) {
      _pendingEmailOtps.remove(normalizedEmail);
      throw FirebaseAuthException(
        code: 'too-many-requests',
        message: 'Too many OTP attempts. Please request a new OTP.',
      );
    }

    if (pendingOtp.code != otpCode.trim()) {
      throw FirebaseAuthException(
        code: 'invalid-verification-code',
        message: 'Invalid OTP code.',
      );
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password.trim(),
    );
    final user = credential.user!;

    await user.updateDisplayName(fullName.trim());
    await user.sendEmailVerification();

    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'fullName': fullName.trim(),
      'email': normalizedEmail,
      'phoneNumber': phoneNumber.trim(),
      'role': role.trim().toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    _pendingEmailOtps.remove(normalizedEmail);
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required String role,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    await _firestore.collection('users').doc(credential.user!.uid).set({
      'uid': credential.user!.uid,
      'fullName': fullName.trim(),
      'email': email.trim(),
      'phoneNumber': phoneNumber.trim(),
      'role': role.trim().toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<LoginResult> signIn({
    required String loginInput,
    required String password,
    String location = 'Unknown',
    String deviceId = 'APP-LOGIN',
  }) async {
    try {
      String emailToUse = loginInput.trim();

      final input = loginInput.trim();
      final isPhone = RegExp(r'^[0-9+\-\s]+$').hasMatch(input);
      final normalizedInput = isPhone ? _normalizePhoneForLookup(input) : input;

      if (isPhone) {
        final query = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: normalizedInput)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          await _firestore.collection('login_logs').add({
            'loginInput': input,
            'status': 'failed',
            'reason': 'Phone number not found',
            'location': location,
            'deviceId': deviceId,
            'timestamp': FieldValue.serverTimestamp(),
          });

          return LoginResult(
            success: false,
            role: 'user',
            message: 'Phone number not found.',
          );
        }

        emailToUse = (query.docs.first.data()['email'] ?? '').toString();

        if (emailToUse.isEmpty) {
          await _firestore.collection('login_logs').add({
            'loginInput': input,
            'status': 'failed',
            'reason': 'No email linked to this phone number',
            'location': location,
            'deviceId': deviceId,
            'timestamp': FieldValue.serverTimestamp(),
          });

          return LoginResult(
            success: false,
            role: 'user',
            message: 'No email linked to this phone number.',
          );
        }
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: emailToUse,
        password: password.trim(),
      );

      final uid = credential.user!.uid;
      final userDoc = await _firestore.collection('users').doc(uid).get();

      String role = 'user';
      if (userDoc.exists) {
        role = (userDoc.data()?['role'] ?? 'user').toString().toLowerCase();
      }

      await _firestore.collection('login_logs').add({
        'uid': uid,
        'loginInput': normalizedInput,
        'email': emailToUse,
        'status': 'success',
        'role': role,
        'location': location,
        'deviceId': deviceId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return LoginResult(
        success: true,
        role: role,
        message: 'Login successful.',
      );
    } catch (e) {
      await _firestore.collection('login_logs').add({
        'loginInput': loginInput.trim(),
        'status': 'failed',
        'reason': getMessageFromError(e),
        'location': location,
        'deviceId': deviceId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return LoginResult(
        success: false,
        role: 'user',
        message: getMessageFromError(e),
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  String getMessageFromError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Invalid email address.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
          return 'No user found for this account.';
        case 'wrong-password':
          return 'Incorrect password.';
        case 'email-already-in-use':
          return 'This email is already in use.';
        case 'weak-password':
          return 'Password is too weak.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'invalid-credential':
          return 'Invalid login credentials.';
        case 'invalid-verification-code':
          return 'Invalid OTP code.';
        case 'invalid-verification-id':
          return 'OTP session expired. Please request a new OTP.';
        case 'otp-expired':
          return 'OTP expired. Please request a new OTP.';
        case 'otp-not-requested':
          return 'Request OTP first.';
        case 'emailjs-not-configured':
          return e.message ?? 'Email OTP is not configured yet.';
        case 'emailjs-send-failed':
          return e.message ?? 'Failed to send OTP email. Try again.';
        case 'emailjs-precondition-failed':
          return e.message ??
              'EmailJS 412: add localhost origin and verify template/IDs.';
        case 'emailjs-non-browser-blocked':
          return e.message ??
              'EmailJS blocked non-browser requests in security settings.';
        case 'too-many-requests':
          return 'Too many OTP requests. Please try again later.';
        default:
          return e.message ?? 'Authentication error.';
      }
    }

    return e.toString();
  }
}

class _PendingEmailOtp {
  final String code;
  final DateTime expiresAt;
  int attempts;

  _PendingEmailOtp({
    required this.code,
    required this.expiresAt,
    required this.attempts,
  });
}
