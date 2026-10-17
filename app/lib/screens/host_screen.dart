import 'dart:async';
import 'package:flutter/material.dart';
import '../services/settings.dart';
import '../services/signaling.dart';

class HostScreen extends StatefulWidget {
  final SignalingClient? signalingClient;

  const HostScreen({super.key, this.signalingClient});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  late final SignalingClient _signaling;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  bool _isLoading = true;
  String? _errorMessage;
  String? _code;
  String _statusText = 'Waiting for viewer...';

  @override
  void initState() {
    super.initState();
    _signaling = widget.signalingClient ?? SignalingClient();
    _initSession();
  }

  Future<void> _initSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = await getServerUrl();
      await _signaling.connect(url);

      _subscription = _signaling.messages.listen(
        _handleMessage,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _errorMessage = 'Connection error: $error';
            _isLoading = false;
          });
        },
        onDone: () {
          if (!mounted) return;
          if (_code != null && _errorMessage == null) {
            setState(() {
              _errorMessage = 'Connection closed by server';
            });
          }
        },
      );

      _signaling.send({'type': 'create'});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not connect to signaling server:\n$e';
        _isLoading = false;
      });
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    final type = message['type'];

    if (type == 'created') {
      setState(() {
        _code = message['code']?.toString() ?? '';
        _isLoading = false;
        _statusText = 'Waiting for viewer...';
      });
    } else if (type == 'ended' || type == 'peer-left') {
      setState(() {
        _statusText = type == 'peer-left' ? 'Viewer disconnected' : 'Session ended';
      });
    } else if (type == 'error') {
      setState(() {
        _errorMessage = 'Server error: ${message['message']}';
        _isLoading = false;
      });
    }
  }

  void _stopSession() {
    try {
      _signaling.send({'type': 'end'});
    } catch (_) {}
    _signaling.close();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _signaling.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _stopSession();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Share my screen'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting to signaling server...'),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 16),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: _initSession,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Your code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Text(
          _code ?? '------',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        const SizedBox(height: 48),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          onPressed: _stopSession,
        ),
      ],
    );
  }
}
