import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Region of the Firestore database and every Cloud Function.
const firebaseRegion = 'asia-southeast2';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: firebaseRegion),
);

/// Points every Firebase SDK at the local Emulator Suite. Enabled with
/// `--dart-define=USE_FIREBASE_EMULATOR=true`; 10.0.2.2 is the host machine
/// as seen from the Android emulator.
Future<void> connectToEmulatorsIfRequested() async {
  const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
  if (!useEmulator) return;
  const host = '10.0.2.2';
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instanceFor(region: firebaseRegion)
      .useFunctionsEmulator(host, 5001);
}

/// Waits briefly for a Firestore write, then moves on.
///
/// A write future completes only when the server acknowledges it, so awaiting
/// one hangs while offline even though the write is already applied to the
/// local cache and queued for sync. Waiting a moment still surfaces a rule
/// rejection when the device is online.
Future<void> settleWrite(
  Future<void> write, {
  Duration wait = const Duration(seconds: 2),
}) async {
  try {
    await write.timeout(wait);
  } on TimeoutException {
    // Still queued; Firestore sends it when the connection returns.
  }
}
