import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _initialization;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // On Android the web client ID comes from google-services.json
  // (default_web_client_id), so no serverClientId is passed here.
  Future<void> _ensureInitialized() =>
      _initialization ??= _googleSignIn.initialize();

  /// Returns null when the user dismisses the Google account picker.
  Future<UserCredential?> signInWithGoogle() async {
    await _ensureInitialized();

    final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
