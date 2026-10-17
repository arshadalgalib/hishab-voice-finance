import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import 'secure_store.dart';

/// App-lock PIN handling.
///
/// The PIN itself is never stored. A random 16-byte salt plus a PBKDF2-HMAC-
/// SHA256 verifier (120 000 iterations) are kept in platform secure storage.
/// Verification compares in constant time so an attacker cannot learn the
/// verifier one byte at a time.
///
/// This is a *local* convenience lock, not a replacement for device
/// encryption: it protects the app UI, while the database remains protected by
/// Android's own file-based encryption.
class PinService {
  PinService(this._store, {Random? random})
    : _random = random ?? Random.secure();

  final SecureStore _store;
  final Random _random;

  static const int _iterations = 120000;
  static const int _saltBytes = 16;
  static const int _keyBytes = 32;
  static const int minLength = 4;
  static const int maxLength = 12;

  Future<bool> hasPin() async =>
      (await _store.read(SecureKeys.pinHash)) != null;

  /// Stores a new verifier for [pin], replacing any previous one.
  Future<void> setPin(String pin) async {
    _validate(pin);
    final salt = _randomBytes(_saltBytes);
    final derived = _derive(pin, salt, _iterations);
    await _store.write(SecureKeys.pinSalt, base64Encode(salt));
    await _store.write(
      SecureKeys.pinHash,
      'pbkdf2-sha256\$$_iterations\$${base64Encode(derived)}',
    );
  }

  /// Returns true when [pin] matches the stored verifier.
  Future<bool> verify(String pin) async {
    final stored = await _store.read(SecureKeys.pinHash);
    final saltText = await _store.read(SecureKeys.pinSalt);
    if (stored == null || saltText == null) return false;

    final parts = stored.split(r'$');
    if (parts.length != 3 || parts[0] != 'pbkdf2-sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1000) return false;

    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64Decode(saltText);
      expected = base64Decode(parts[2]);
    } on FormatException {
      return false;
    }

    final actual = _derive(pin, salt, iterations);
    return _constantTimeEquals(expected, actual);
  }

  /// Changes the PIN after checking the current one. Throws when the current
  /// PIN is wrong so a thief with an unlocked phone cannot silently re-lock the
  /// owner out.
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    if (!await verify(currentPin)) {
      throw const ValidationException(
        'That PIN is not correct.',
        field: 'currentPin',
      );
    }
    await setPin(newPin);
  }

  Future<void> clearPin() async {
    await _store.delete(SecureKeys.pinHash);
    await _store.delete(SecureKeys.pinSalt);
  }

  void _validate(String pin) {
    final trimmed = pin.trim();
    if (trimmed.length < minLength || trimmed.length > maxLength) {
      throw const ValidationException(
        'Your PIN must be $minLength–$maxLength characters long.',
        field: 'pin',
      );
    }
    if (RegExp(r'^(.)\1+$').hasMatch(trimmed)) {
      throw const ValidationException(
        'Choose a PIN that is not a single repeated character.',
        field: 'pin',
      );
    }
  }

  Uint8List _derive(String pin, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyBytes));
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
