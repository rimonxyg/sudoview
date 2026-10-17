import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
  final Future<RTCPeerConnection> Function(Map<String, dynamic> configuration)? peerConnectionFactory;
  final Future<RTCVideoRenderer> Function()? rendererFactory;

  const ViewerScreen({
    super.key,
    this.signalingClient,
    this.peerConnectionFactory,
    this.rendererFactory,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final TextEditingController _codeController = TextEditingController();
  late final SignalingClient _signaling;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  RTCPeerConnection? _peerConnection;
  RTCVideoRenderer? _videoRenderer;
  bool _hasRemoteTrack = false;

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
    _cleanupWebRTC();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _cleanupWebRTC() async {
    try {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
    } catch (_) {}

    try {
      _videoRenderer?.srcObject = null;
      await _videoRenderer?.dispose();
      _videoRenderer = null;
    } catch (_) {}
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

      await _initWebRTC();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = ViewerState.error;
        _errorMessage = 'Could not connect to server:\n$e';
      });
    }
  }

  Future<void> _initWebRTC() async {
    try {
      final renderer = widget.rendererFactory != null
          ? await widget.rendererFactory!()
          : RTCVideoRenderer();
      await renderer.initialize();
      _videoRenderer = renderer;

      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };

      final pc = widget.peerConnectionFactory != null
          ? await widget.peerConnectionFactory!(configuration)
          : await createPeerConnection(configuration);

      _peerConnection = pc;

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          _signaling.send({
            'type': 'ice',
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          });
        }
      };

      pc.onTrack = (RTCTrackEvent event) {
        debugPrint('remote track received');
        if (event.streams.isNotEmpty) {
          _videoRenderer?.srcObject = event.streams[0];
        }
        if (mounted) {
          setState(() {
            _state = ViewerState.accepted;
            _hasRemoteTrack = true;
            _statusText = 'Streaming screen';
          });
        }
      };
    } catch (e) {
      debugPrint('Error initializing Viewer WebRTC: $e');
    }
  }

  Future<void> _handleMessage(Map<String, dynamic> message) async {
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
      _cleanupWebRTC();
    } else if (type == 'offer') {
      debugPrint('offer received');
      final sdp = message['sdp']?.toString() ?? '';
      await _handleOffer(sdp);
    } else if (type == 'ice') {
      final candidateMap = message['candidate'];
      if (candidateMap is Map && _peerConnection != null) {
        try {
          final candidate = RTCIceCandidate(
            candidateMap['candidate']?.toString(),
            candidateMap['sdpMid']?.toString(),
            candidateMap['sdpMLineIndex'] is int ? candidateMap['sdpMLineIndex'] as int : null,
          );
          await _peerConnection!.addCandidate(candidate);
        } catch (e) {
          debugPrint('Error adding ICE candidate: $e');
        }
      }
    } else if (type == 'error') {
      final serverMsg = message['message']?.toString() ?? 'unknown';
      setState(() {
        _state = ViewerState.error;
        _errorMessage = _formatErrorMessage(serverMsg);
      });
      if (serverMsg == 'too_many_attempts') {
        _signaling.close();
        _cleanupWebRTC();
      }
    } else if (type == 'ended' || type == 'peer-left') {
      setState(() {
        _state = ViewerState.error;
        _errorMessage = type == 'peer-left' ? 'Host disconnected' : 'Session ended';
      });
      _signaling.close();
      _cleanupWebRTC();
    }
  }

  Future<void> _handleOffer(String sdp) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdp, 'offer');
      await _peerConnection!.setRemoteDescription(description);

      final answerConstraints = <String, dynamic>{
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      };

      final answer = await _peerConnection!.createAnswer(answerConstraints);
      await _peerConnection!.setLocalDescription(answer);

      _signaling.send({
        'type': 'answer',
        'sdp': answer.sdp,
      });
      debugPrint('answer sent');
    } catch (e) {
      debugPrint('Error handling offer: $e');
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
    _cleanupWebRTC();
    setState(() {
      _state = ViewerState.idle;
      _errorMessage = null;
      _statusText = null;
      _hasRemoteTrack = false;
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
          Icon(
            _hasRemoteTrack ? Icons.tv : Icons.check_circle_outline,
            color: Colors.green,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            _hasRemoteTrack ? 'Connected!' : 'Host accepted!',
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
