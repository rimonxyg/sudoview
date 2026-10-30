import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/settings.dart';

void _reportHoneypot(String type, Object error, StackTrace? stack) {
  try {
    getServerUrl().then((serverUrl) async {
      try {
        final base = serverUrl.replaceFirst('wss://', 'https://').replaceFirst('ws://', 'http://');
        final uri = Uri.parse('$base/crash');
        final client = HttpClient();
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({
          'source': 'Dart/Flutter',
          'type': type,
          'error': error.toString(),
          'stack': stack?.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        }));
        await req.close();
      } catch (_) {}
    }).catchError((_) {});
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportHoneypot('FlutterError', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _reportHoneypot('PlatformDispatcherError', error, stack);
    return true;
  };

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
