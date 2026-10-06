import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class WarmadApp extends ConsumerStatefulWidget {
  const WarmadApp({super.key});

  @override
  ConsumerState<WarmadApp> createState() => _WarmadAppState();
}

class _WarmadAppState extends ConsumerState<WarmadApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<RemoteMessage>? _pushes;

  @override
  void initState() {
    super.initState();
    // Android shows a push by itself only while the app is in the
    // background. With the app open, show it as a message instead.
    _pushes = FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title;
      if (title == null) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(title), duration: const Duration(seconds: 5)),
      );
    });
  }

  @override
  void dispose() {
    _pushes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Warmad',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
