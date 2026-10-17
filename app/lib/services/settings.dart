import 'package:shared_preferences/shared_preferences.dart';

const String defaultServerUrl = 'ws://192.168.0.100:8082';
const String serverUrlKey = 'server_url';

Future<String> getServerUrl() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(serverUrlKey) ?? defaultServerUrl;
}

Future<void> setServerUrl(String url) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(serverUrlKey, url);
}

