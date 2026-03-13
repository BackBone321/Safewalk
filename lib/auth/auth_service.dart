import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

      if (isPhone) {
        final query = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: input)
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
        'loginInput': input,
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
        default:
          return e.message ?? 'Authentication error.';
      }
    }

    return e.toString();
  }
}