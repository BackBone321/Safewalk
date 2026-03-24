import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase/firebase_options.dart';
import 'login_dashboard/landing_page.dart';
import 'login_dashboard/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SafewalkApp());
}

class SafewalkApp extends StatelessWidget {
  const SafewalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safewalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'JosefinSans'),
      home: kIsWeb ? const LandingPage() : const LoginPage(),
    );
  }
}
