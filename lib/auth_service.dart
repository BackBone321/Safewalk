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

  Future<LoginResult> signIn({
    required String email,
    required String password,
    String location = 'Unknown',
    String deviceId = 'APP-LOGIN',
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final uid = credential.user!.uid;
      final userDoc = await _firestore.collection('users').doc(uid).get();

      String role = 'user';
      if (userDoc.exists) {
        role = (userDoc.data()?['role'] ?? 'user').toString();
      }

      await _firestore.collection('login_logs').add({
        'email': email.trim(),
        'status': 'success',
        'role': role,
        'timestamp': FieldValue.serverTimestamp(),
        'location': location,
        'deviceId': deviceId,
      });

      return LoginResult(
        success: true,
        role: role,
        message: 'Login successful!',
      );
    } on FirebaseAuthException catch (e) {
      await _firestore.collection('login_logs').add({
        'email': email.trim(),
        'status': 'failed',
        'role': 'unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'location': location,
        'deviceId': deviceId,
        'error': e.code,
      });

      return LoginResult(
        success: false,
        role: 'unknown',
        message: getMessageFromError(e),
      );
    } catch (e) {
      await _firestore.collection('login_logs').add({
        'email': email.trim(),
        'status': 'failed',
        'role': 'unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'location': location,
        'deviceId': deviceId,
        'error': e.toString(),
      });

      return LoginResult(
        success: false,
        role: 'unknown',
        message: 'Something went wrong.',
      );
    }
  }

  Future<UserCredential> register({
    required String email,
    required String password,
    String role = 'user',
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    await _firestore.collection('users').doc(credential.user!.uid).set({
      'email': email.trim(),
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  Future<void> resetPassword({
    required String email,
  }) async {
    await _auth.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  String getMessageFromError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Invalid email address.';
        case 'user-not-found':
          return 'No user found for that email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'This email is already registered.';
        case 'weak-password':
          return 'Password is too weak.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'missing-email':
          return 'Please enter your email address.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }
    return 'Something went wrong.';
  }
}