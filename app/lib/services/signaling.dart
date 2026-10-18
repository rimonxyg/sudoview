import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingClient {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription? _subscription;

  Future<void> connect(String url) async {
    close();
    String normalized = url.trim();
    if (normalized.startsWith('https://')) {
      normalized = 'wss://${normalized.substring(8)}';
    } else if (normalized.startsWith('http://')) {
      normalized = 'ws://${normalized.substring(7)}';
    } else if (!normalized.startsWith('ws://') && !normalized.startsWith('wss://')) {
      normalized = 'wss://$normalized';
    }
    final uri = Uri.parse(normalized);
    final channel = WebSocketChannel.connect(uri);
    await channel.ready.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        channel.sink.close();
        throw TimeoutException(
          'Could not connect to server within 10 seconds. '
          'Check that the server URL is correct and reachable.',
        );
      },
    );
    _channel = channel;

    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _subscription = channel.stream.listen(
      (data) {
        try {
          if (data is String) {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              _controller?.add(decoded);
            }
          }
        } catch (_) {
          // Ignore malformed payloads
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _controller?.addError(error, stackTrace);
      },
      onDone: () {
        _controller?.close();
      },
    );
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  Stream<Map<String, dynamic>> get messages {
    if (_controller == null) {
      return const Stream.empty();
    }
    return _controller!.stream;
  }

  void close() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _controller?.close();
    _controller = null;
  }
}
