import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/env.dart';
import '../../core/secure_storage.dart';
import '../auth/auth_controller.dart';

/// Manages a persistent WebSocket connection to `/ws/chat`.
///
/// - Connects when an authenticated user is present.
/// - Sends a PING heartbeat every 25 s.
/// - Auto-reconnects with exponential backoff on disconnect.
/// - Exposes incoming frames as [stream].
class ChatSocketService {
  ChatSocketService(this._ref) {
    // Start when created (only if user is authenticated).
    _connect();
  }

  final Ref _ref;
  WebSocketChannel? _channel;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Incoming WS frames decoded as JSON maps. Types: MESSAGE, READ, DELETED, SIGNAL.
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Future<void> _connect() async {
    if (_disposed) return;

    final user = _ref.read(authUserProvider);
    if (user == null) return;

    final token = await SecureStorage.readToken();
    if (token == null || token.isEmpty) return;

    // Build the WebSocket URL from the REST base URL.
    final baseUri = Uri.parse(Env.apiBaseUrl);
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = Uri(
      scheme: scheme,
      host: baseUri.host,
      port: baseUri.port,
      path: '/ws/chat',
      queryParameters: {'token': token},
    );

    try {
      _channel = WebSocketChannel.connect(wsUri);
      await _channel!.ready;
      _reconnectAttempt = 0;
      _startHeartbeat();

      _channel!.stream.listen(
        (raw) {
          if (_disposed) return;
          try {
            final data = jsonDecode(raw as String);
            if (data is Map<String, dynamic>) {
              _controller.add(data);
            }
          } catch (e) {
            debugPrint('[ChatSocket] Bad frame: $e');
          }
        },
        onDone: () => _scheduleReconnect(),
        onError: (_) => _scheduleReconnect(),
      );
    } catch (e) {
      debugPrint('[ChatSocket] Connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add(jsonEncode({'type': 'PING'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _heartbeat?.cancel();
    _reconnectAttempt++;
    final delay = min(30, pow(2, _reconnectAttempt).toInt());
    debugPrint('[ChatSocket] Reconnecting in ${delay}s (attempt $_reconnectAttempt)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), _connect);
  }

  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}

/// Auto-dispose provider that creates the socket when the user is logged in
/// and tears it down on logout / provider disposal.
final chatSocketProvider = Provider.autoDispose<ChatSocketService>((ref) {
  // Keep alive while the shell is mounted.
  ref.keepAlive();

  // React to auth changes — if user logs out, the provider is invalidated.
  final user = ref.watch(authUserProvider);
  if (user == null) {
    // Return a no-op service that won't connect.
    final svc = ChatSocketService(ref);
    ref.onDispose(svc.dispose);
    return svc;
  }

  final svc = ChatSocketService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});
