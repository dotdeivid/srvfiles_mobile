import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0a0a0f),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SrvFilesApp());
}

class SrvFilesApp extends StatelessWidget {
  const SrvFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SrvFiles',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0f),
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'SrvFiles',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFFe2e8f0),
            ),
          ),
        ),
      ),
    );
  }
}
