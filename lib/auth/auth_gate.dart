import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../User/parent_dashboard.dart';
import '../User/user_dashboard.dart';
import '../admin/admin_dashboard.dart';
import '../login_dashboard/login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        return _RoleRouter(user: user);
      },
    );
  }
}

class _RoleRouter extends StatelessWidget {
  const _RoleRouter({required this.user});

  final User user;

  Future<String> _resolveRole() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final role = (doc.data()?['role'] ?? '').toString().trim().toLowerCase();
      if (role.isNotEmpty) return role;
    } catch (_) {}

    final email = user.email?.trim().toLowerCase() ?? '';
    if (email == 'admin@gmail.com') return 'admin';
    return 'user';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolveRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        final role = snapshot.data ?? 'user';
        switch (role) {
          case 'admin':
            return const AdminDashboardPage();
          case 'parent':
            return const ParentDashboardPage();
          case 'student':
          case 'user':
          default:
            return const UserDashboardPage();
        }
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
