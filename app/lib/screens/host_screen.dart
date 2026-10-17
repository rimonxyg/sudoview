import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/settings.dart';
import '../services/signaling.dart';

typedef ScreenCaptureFunction = Future<MediaStream> Function(Map<String, dynamic> constraints);

class HostScreen extends StatefulWidget {
  final SignalingClient? signalingClient;
  final ScreenCaptureFunction? screenCapture;

  const HostScreen({
    super.key,
    this.signalingClient,
    this.screenCapture,
  });

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  late final SignalingClient _signaling;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  MediaStream? _localStream;

  bool _isLoading = true;
  String? _errorMessage;
  String? _code;
  String _statusText = 'Waiting for viewer...';
  bool _isSharingStarted = false;

  static const MethodChannel _projectionChannel =
      MethodChannel('com.teachview.teachview/media_projection');

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
      _isSharingStarted = false;
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
    } else if (type == 'join-request') {
      _showConsentDialog();
    } else if (type == 'ended' || type == 'peer-left') {
      setState(() {
        _isSharingStarted = false;
        _statusText = type == 'peer-left' ? 'Waiting for viewer...' : 'Session ended';
      });
    } else if (type == 'error') {
      setState(() {
        _errorMessage = 'Server error: ${message['message']}';
        _isLoading = false;
      });
    }
  }

  Future<void> _showConsentDialog() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Viewer Request'),
            content: const Text('Someone wants to view your screen.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                  _signaling.send({'type': 'decline'});
                  if (mounted) {
                    setState(() {
                      _statusText = 'Waiting for viewer...';
                    });
                  }
                },
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                  _signaling.send({'type': 'accept'});
                  if (mounted) {
                    setState(() {
                      _isSharingStarted = true;
                      _statusText = 'Starting...';
                    });
                  }
                  _startCapture();
                },
                child: const Text('Accept'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startCapture() async {
    try {
      if (widget.screenCapture == null && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _projectionChannel.invokeMethod('startService');
        } catch (_) {}
      }

      final constraints = <String, dynamic>{
        'audio': false,
        'video': true,
      };

      if (widget.screenCapture != null) {
        _localStream = await widget.screenCapture!(constraints);
      } else {
        _localStream = await navigator.mediaDevices.getDisplayMedia(constraints);
      }
      debugPrint('capture started');
    } catch (e) {
      debugPrint('Capture failed or cancelled: $e');
      _stopSession();
    }
  }

  void _stopSession({bool shouldPop = true}) {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        _projectionChannel.invokeMethod('stopService').catchError((_) {});
      }
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _localStream = null;
    } catch (_) {}

    try {
      _signaling.send({'type': 'end'});
    } catch (_) {}
    _signaling.close();

    if (shouldPop && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stopSession(shouldPop: false);
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

    if (_isSharingStarted) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Starting...',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
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
