import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const TeachViewApp());
}

class TeachViewApp extends StatelessWidget {
  const TeachViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeachView',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
