import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/settings.dart';
import '../services/signaling.dart';

typedef ScreenCaptureFunction = Future<MediaStream> Function(Map<String, dynamic> constraints);
typedef PeerConnectionFactory = Future<RTCPeerConnection> Function(Map<String, dynamic> configuration);

class HostScreen extends StatefulWidget {
  final SignalingClient? signalingClient;
  final ScreenCaptureFunction? screenCapture;
  final PeerConnectionFactory? peerConnectionFactory;
  final int maxSessionSeconds;

  const HostScreen({
    super.key,
    this.signalingClient,
    this.screenCapture,
    this.peerConnectionFactory,
    this.maxSessionSeconds = 1800,
  });

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  late final SignalingClient _signaling;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  Timer? _sessionTimer;
  int _sessionSeconds = 0;

  bool _isLoading = true;
  String? _errorMessage;
  String? _code;
  String _statusText = 'Waiting for viewer...';
  bool _isSharingStarted = false;
  String? _connectionStatus;
  String _serverUrl = defaultServerUrl;

  String get _formattedSessionDuration {
    final minutes = (_sessionSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_sessionSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionSeconds = 0;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _sessionSeconds++;
      });
      if (_sessionSeconds >= widget.maxSessionSeconds) {
        timer.cancel();
        _stopSession(
          message: 'Session ended: ${widget.maxSessionSeconds ~/ 60}-minute limit reached',
        );
      }
    });
  }

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
      _connectionStatus = null;
    });

    try {
      final url = await getServerUrl();
      _serverUrl = url;
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

  Future<void> _handleMessage(Map<String, dynamic> message) async {
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
    } else if (type == 'answer') {
      final sdp = message['sdp']?.toString() ?? '';
      final description = RTCSessionDescription(sdp, 'answer');
      try {
        await _peerConnection?.setRemoteDescription(description);
        debugPrint('answer received');
      } catch (e) {
        debugPrint('Error setting remote description: $e');
      }
    } else if (type == 'ice') {
      final candidateMap = message['candidate'];
      if (candidateMap is Map) {
        try {
          final candidate = RTCIceCandidate(
            candidateMap['candidate']?.toString(),
            candidateMap['sdpMid']?.toString(),
            candidateMap['sdpMLineIndex'] is int ? candidateMap['sdpMLineIndex'] as int : null,
          );
          await _peerConnection?.addCandidate(candidate);
        } catch (e) {
          debugPrint('Error adding ICE candidate: $e');
        }
      }
    } else if (type == 'ended' || type == 'peer-left') {
      final message = type == 'peer-left' ? 'Viewer disconnected' : 'Session ended';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      _stopSession(sendEnd: false);
    } else if (type == 'error') {
      setState(() {
        _errorMessage = 'Server error: ${message['message']}';
        _isLoading = false;
      });
    }
  }

  BuildContext? _consentDialogContext;

  Future<void> _showConsentDialog() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _consentDialogContext = dialogContext;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Viewer Request'),
            content: const Text('Someone wants to view your screen.'),
            actions: [
              TextButton(
                onPressed: () {
                  _consentDialogContext = null;
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
                  _consentDialogContext = null;
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
    _consentDialogContext = null;
  }

  void _sendTelemetry(String msg) {
    debugPrint('[Telemetry] $msg');
    try {
      final base = _serverUrl.replaceFirst('wss://', 'https://').replaceFirst('ws://', 'http://');
      final client = HttpClient();
      client.postUrl(Uri.parse('$base/log')).then((req) async {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'event': msg, 'timestamp': DateTime.now().toIso8601String()}));
        await req.close();
      }).catchError((_) {});
    } catch (_) {}
  }

  Future<void> _startCapture() async {
    try {
      if (widget.screenCapture == null && defaultTargetPlatform == TargetPlatform.android) {
        _sendTelemetry('Requesting capture permission via Helper');
        final isGranted = await Helper.requestCapturePermission();
        _sendTelemetry('Helper.requestCapturePermission result: $isGranted');
        if (!isGranted) {
          debugPrint('User cancelled screen capture permission');
          _stopSession();
          return;
        }

        try {
          _sendTelemetry('Starting MediaProjection foreground service');
          final serviceStarted = await _projectionChannel.invokeMethod<bool>('startService');
          _sendTelemetry('MediaProjection foreground service started: $serviceStarted');
          // Allow Android system_server / MediaProjectionManagerService sufficient time to register the active foreground service
          await Future.delayed(const Duration(milliseconds: 600));
        } catch (e) {
          _sendTelemetry('Foreground service error: $e');
        }
      }

      final constraints = <String, dynamic>{
        'audio': false,
        'video': true,
      };

      _sendTelemetry('Calling getDisplayMedia');
      if (widget.screenCapture != null) {
        _localStream = await widget.screenCapture!(constraints);
      } else {
        _localStream = await navigator.mediaDevices.getDisplayMedia(constraints);
      }
      _sendTelemetry('getDisplayMedia succeeded');
      debugPrint('capture started');
      _startSessionTimer();

      await _initWebRTC();
    } catch (e, stack) {
      _sendTelemetry('CRASH or ERROR in _startCapture: $e\n$stack');
      debugPrint('Capture failed or cancelled: $e');
      _stopSession();
    }
  }

  Future<void> _initWebRTC() async {
    try {
      _sendTelemetry('Initializing WebRTC PeerConnection');
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
      _sendTelemetry('PeerConnection created');

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          _sendTelemetry('Adding track to PeerConnection: ${track.kind}');
          await pc.addTrack(track, _localStream!);
        }
      }

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          _sendTelemetry('Sending ICE candidate');
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

      if (mounted) {
        setState(() {
          _connectionStatus = 'Connecting';
        });
      }

      pc.onConnectionState = (RTCPeerConnectionState state) {
        _sendTelemetry('Peer connection state changed: $state');
        debugPrint('Peer connection state: $state');
        if (!mounted) return;
        setState(() {
          switch (state) {
            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              _connectionStatus = 'Connected';
              _statusText = 'Screen sharing active';
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            case RTCPeerConnectionState.RTCPeerConnectionStateNew:
              _connectionStatus = 'Connecting';
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
              _connectionStatus = 'Disconnected';
              break;
          }
        });
      };

      pc.onIceConnectionState = (RTCIceConnectionState state) {
        _sendTelemetry('ICE connection state changed: $state');
        debugPrint('ICE connection state: $state');
        if (!mounted) return;
        setState(() {
          if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
              state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
            _connectionStatus = 'Connected';
            _statusText = 'Screen sharing active';
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking ||
              state == RTCIceConnectionState.RTCIceConnectionStateNew) {
            if (_connectionStatus != 'Connected') {
              _connectionStatus = 'Connecting';
            }
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
              state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
              state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
            _connectionStatus = 'Disconnected';
          }
        });
      };

      final offerConstraints = <String, dynamic>{
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      };

      _sendTelemetry('Creating WebRTC offer');
      final description = await pc.createOffer(offerConstraints);
      _sendTelemetry('Setting local description');
      await pc.setLocalDescription(description);

      _sendTelemetry('Sending offer to signaling server');
      _signaling.send({
        'type': 'offer',
        'sdp': description.sdp,
      });
      debugPrint('offer sent');
      _sendTelemetry('WebRTC offer sent');
    } catch (e, stack) {
      _sendTelemetry('CRASH or ERROR in _initWebRTC: $e\n$stack');
      debugPrint('WebRTC initialization error: $e');
      _stopSession();
    }
  }

  bool _isCleaningUp = false;
  bool _canPop = false;

  void _stopSession({bool shouldPop = true, bool sendEnd = true, String? message}) {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    _sessionTimer?.cancel();
    _sessionTimer = null;

    if (sendEnd) {
      try {
        _signaling.send({'type': 'end'});
      } catch (_) {}
    }
    _signaling.close();

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        _projectionChannel.invokeMethod('stopService').catchError((_) {});
      } catch (_) {}
    }

    try {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _localStream = null;
    } catch (_) {}

    try {
      _peerConnection?.close();
      _peerConnection?.dispose();
      _peerConnection = null;
    } catch (_) {}

    if (_consentDialogContext != null) {
      try {
        Navigator.of(_consentDialogContext!).pop();
      } catch (_) {}
      _consentDialogContext = null;
    }

    _connectionStatus = 'Disconnected';

    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }

    if (shouldPop && mounted) {
      setState(() {
        _canPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _subscription?.cancel();
    _stopSession(shouldPop: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _stopSession();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Share my screen'),
          actions: [
            if (_connectionStatus != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: Container(
                    key: const Key('host_connection_status'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: _connectionStatus == 'Connected'
                              ? Colors.green
                              : (_connectionStatus == 'Connecting' ? Colors.orange : Colors.red),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _connectionStatus!,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
            'Sharing your screen',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  _formattedSessionDuration,
                  key: const Key('host_session_timer'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_connectionStatus != null)
            Text(
              _connectionStatus!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _connectionStatus == 'Connected'
                    ? Colors.green
                    : (_connectionStatus == 'Connecting' ? Colors.orange : Colors.red),
              ),
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
