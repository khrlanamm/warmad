import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/data/auth_service.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref.watch(firestoreProvider));
  ref.watch(authServiceProvider).beforeSignOut = service.unregister;
  ref.onDispose(service.dispose);
  return service;
});

/// Registers this phone for push notifications and keeps its token in
/// `users/{uid}/devices`, where Cloud Functions find it.
class PushService {
  PushService(this._db);

  final FirebaseFirestore _db;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _refresh;
  String? _uid;
  String? _token;

  DocumentReference<Map<String, dynamic>> _device(String uid, String token) =>
      _db.doc('users/$uid/devices/$token');

  /// Asks for permission (Android 13 and up shows a prompt) and saves the
  /// token. Does nothing when already registered for [uid]. Failing here must
  /// never get in the way of using the app, so errors are swallowed.
  Future<void> register(String uid) async {
    if (_uid == uid) return;
    _uid = uid;
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await _messaging.getToken();
      if (token != null) await _save(uid, token);
      _refresh ??= _messaging.onTokenRefresh.listen((token) {
        final current = _uid;
        if (current != null) _save(current, token);
      });
    } catch (_) {
      // No Play services, no connection, or permission flow interrupted.
    }
  }

  Future<void> _save(String uid, String token) async {
    _token = token;
    await _device(uid, token).set({
      'token': token,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stops pushes to this phone for the signed in account. Call before
  /// signing out, while the account can still delete its own token.
  Future<void> unregister() async {
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    if (uid == null || token == null) return;
    try {
      await _device(uid, token).delete().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Offline. The server drops the token once a push to it fails.
    }
  }

  void dispose() => _refresh?.cancel();
}
