import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/app.dart';
import 'core/firebase/firebase_providers.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await connectToEmulatorsIfRequested();
  // Never evict cached documents. The warung works offline from this cache,
  // and the product list is synced incrementally on top of it.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  Intl.defaultLocale = 'id_ID';
  await initializeDateFormatting('id_ID');

  runApp(const ProviderScope(child: WarmadApp()));
}
