import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Inicio de sesión con Firebase Auth.
///
/// Se inicia sesión una sola vez por tablet: Firebase guarda la sesión en el
/// dispositivo y la renueva sola cuando hay conexión, aunque pasen semanas
/// sin red. Mientras tanto [user] sigue disponible sin conexión.
///
/// Si Firebase no está disponible (tests, escritorio) [available] es false y
/// la app funciona igual, solo en local.
class AuthService extends ChangeNotifier {
  final FirebaseAuth? _auth;
  StreamSubscription<User?>? _sub;
  bool _googleReady = false;

  AuthService(FirebaseAuth auth) : _auth = auth {
    _sub = auth.authStateChanges().listen((_) => notifyListeners());
  }

  /// Sin Firebase: la app solo funciona en local.
  AuthService.disabled() : _auth = null;

  bool get available => _auth != null;
  User? get user => _auth?.currentUser;
  bool get signedIn => user != null;

  /// Lanza [AuthError] con un mensaje listo para mostrar.
  Future<void> signInWithEmail(String email, String password) => _guard(
    () => _auth!.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<void> createAccount(String email, String password) => _guard(
    () => _auth!.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth!.sendPasswordResetEmail(email: email.trim()));

  /// Devuelve false si el usuario cancela.
  Future<bool> signInWithGoogle() async {
    final auth = _auth!;
    if (kIsWeb) {
      await _guard(() => auth.signInWithPopup(GoogleAuthProvider()));
      return true;
    }
    final google = GoogleSignIn.instance;
    try {
      if (!_googleReady) {
        await google.initialize();
        _googleReady = true;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      await _guard(
        () => auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        ),
      );
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw AuthError('No se pudo entrar con Google (${e.code.name}).');
    }
  }

  Future<void> signOut() async {
    if (_googleReady) await GoogleSignIn.instance.signOut();
    await _auth?.signOut();
  }

  Future<void> _guard(Future<Object?> Function() f) async {
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      throw AuthError(authMessage(e.code));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class AuthError implements Exception {
  final String message;
  const AuthError(this.message);
  @override
  String toString() => message;
}

/// Traduce los códigos de error de Firebase Auth.
String authMessage(String code) => switch (code) {
  'invalid-email' => 'El email no es válido.',
  'user-disabled' => 'Esta cuenta está desactivada.',
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => 'Email o contraseña incorrectos.',
  'email-already-in-use' => 'Ya existe una cuenta con ese email.',
  'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
  'network-request-failed' =>
    'Sin conexión. Para iniciar sesión la primera vez hace falta internet.',
  'too-many-requests' => 'Demasiados intentos. Espera un poco.',
  'operation-not-allowed' =>
    'Este método de inicio de sesión no está activado en Firebase.',
  'account-exists-with-different-credential' =>
    'Ese email ya entra con otro método (prueba con email y contraseña).',
  _ => 'No se pudo iniciar sesión ($code).',
};
