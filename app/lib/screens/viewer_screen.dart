import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings.dart';
import '../services/signaling.dart';

enum ViewerState {
  idle,
  connecting,
  waitingForHost,
  declined,
  accepted,
  error,
}

class ViewerScreen extends StatefulWidget {
  final SignalingClient? signalingClient;

  const ViewerScreen({super.key, this.signalingClient});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final TextEditingController _codeController = TextEditingController();
  late final SignalingClient _signaling;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  ViewerState _state = ViewerState.idle;
  String? _errorMessage;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _signaling = widget.signalingClient ?? SignalingClient();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _signaling.close();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinSession() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Please enter a valid 6-digit code';
      });
      return;
    }

    setState(() {
      _state = ViewerState.connecting;
      _errorMessage = null;
      _statusText = 'Connecting to signaling server...';
    });

    try {
      final serverUrl = await getServerUrl();
      await _signaling.connect(serverUrl);

      _subscription?.cancel();
      _subscription = _signaling.messages.listen(
        _handleMessage,
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _state = ViewerState.error;
            _errorMessage = 'Connection error: $e';
          });
        },
        onDone: () {
          if (!mounted) return;
          if (_state != ViewerState.declined &&
              _state != ViewerState.error &&
              _state != ViewerState.idle) {
            setState(() {
              _state = ViewerState.error;
              _errorMessage = 'Disconnected from server';
            });
          }
        },
      );

      _signaling.send({
        'type': 'join',
        'code': code,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = ViewerState.error;
        _errorMessage = 'Could not connect to server:\n$e';
      });
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    final type = message['type'];

    if (type == 'waiting') {
      setState(() {
        _state = ViewerState.waitingForHost;
        _statusText = 'Waiting for host to accept...';
      });
    } else if (type == 'accepted') {
      setState(() {
        _state = ViewerState.accepted;
        _statusText = 'Connecting video stream...';
      });
    } else if (type == 'declined') {
      setState(() {
        _state = ViewerState.declined;
        _statusText = 'Host declined';
      });
      _signaling.close();
    } else if (type == 'error') {
      final serverMsg = message['message']?.toString() ?? 'unknown';
      setState(() {
        _state = ViewerState.error;
        _errorMessage = _formatErrorMessage(serverMsg);
      });
      if (serverMsg == 'too_many_attempts') {
        _signaling.close();
      }
    } else if (type == 'ended' || type == 'peer-left') {
      setState(() {
        _state = ViewerState.error;
        _errorMessage = type == 'peer-left' ? 'Host disconnected' : 'Session ended';
      });
      _signaling.close();
    }
  }

  String _formatErrorMessage(String message) {
    switch (message) {
      case 'invalid_code':
        return 'Invalid code. Please check and try again.';
      case 'room_busy':
        return 'Room is busy. Another viewer is already connected.';
      case 'too_many_attempts':
        return 'Too many failed attempts. You have been locked out.';
      case 'not_allowed':
        return 'Action not allowed by server.';
      default:
        return 'Server error: $message';
    }
  }

  void _cancelOrReset() {
    _subscription?.cancel();
    _signaling.close();
    setState(() {
      _state = ViewerState.idle;
      _errorMessage = null;
      _statusText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch a screen'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_state == ViewerState.connecting || _state == ViewerState.waitingForHost) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            _statusText ?? 'Please wait...',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _cancelOrReset,
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (_state == ViewerState.declined) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.red, size: 56),
          const SizedBox(height: 16),
          Text(
            'Host declined',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The host declined your request to view their screen.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _cancelOrReset,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Try Again'),
          ),
        ],
      );
    }

    if (_state == ViewerState.accepted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 56),
          const SizedBox(height: 16),
          Text(
            'Host accepted!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText ?? 'Connecting video stream...',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Default: ViewerState.idle or ViewerState.error
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter 6-digit Code',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the code shown on the screen of the device you want to watch.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            hintText: '000000',
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            errorText: _errorMessage,
          ),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            } else {
              setState(() {});
            }
          },
          onSubmitted: (_) {
            if (_codeController.text.trim().length == 6) {
              _joinSession();
            }
          },
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _codeController.text.trim().length == 6 ? _joinSession : null,
          icon: const Icon(Icons.login),
          label: const Text('Join'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
