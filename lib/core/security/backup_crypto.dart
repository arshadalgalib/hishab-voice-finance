import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../errors/app_exception.dart';

/// Optional password protection for a backup file.
///
/// A backup is plain, human-readable JSON by default so the user can open it,
/// diff it or hand it to another tool. When the user chooses a password the
/// same JSON is wrapped in an AES-256-GCM envelope keyed with PBKDF2-HMAC-
/// SHA256 (150 000 iterations, random 16-byte salt, random 12-byte nonce).
///
/// This is authenticated encryption: a wrong password or a tampered file fails
/// the GCM tag check and is reported as a bad file rather than being decrypted
/// into garbage.
class BackupCrypto {
  const BackupCrypto._();

  static const String envelopeFormat = 'pfm-backup-encrypted';
  static const int envelopeVersion = 1;
  static const int _iterations = 150000;
  static const int _saltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _keyBytes = 32;
  static const int _tagBits = 128;

  /// Wraps [plaintext] and returns the envelope as pretty JSON.
  static String encrypt(String plaintext, String password) {
    if (password.trim().length < 6) {
      throw const ValidationException(
        'Use a backup password of at least 6 characters.',
        field: 'password',
      );
    }
    final random = Random.secure();
    final salt = _randomBytes(random, _saltBytes);
    final nonce = _randomBytes(random, _nonceBytes);
    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);

    // GCM appends the tag to the ciphertext; split it out so the envelope is
    // explicit about what each field means.
    final tagLength = _tagBits ~/ 8;
    final cipherText = output.sublist(0, output.length - tagLength);
    final mac = output.sublist(output.length - tagLength);

    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': envelopeFormat,
      'version': envelopeVersion,
      'encrypted': true,
      'kdf': <String, Object?>{
        'algorithm': 'pbkdf2-sha256',
        'iterations': _iterations,
        'salt': base64Encode(salt),
      },
      'cipher': <String, Object?>{
        'algorithm': 'aes-256-gcm',
        'nonce': base64Encode(nonce),
        'mac': base64Encode(mac),
        'ciphertext': base64Encode(cipherText),
      },
    });
  }

  static bool looksEncrypted(Map<String, Object?> json) =>
      json['format'] == envelopeFormat;

  /// Unwraps an envelope produced by [encrypt].
  static String decrypt(Map<String, Object?> envelope, String password) {
    final kdf = envelope['kdf'];
    final cipherInfo = envelope['cipher'];
    if (kdf is! Map || cipherInfo is! Map) {
      throw const InvalidFileException('This backup file is not readable.');
    }
    final iterations = (kdf['iterations'] as num?)?.toInt() ?? _iterations;

    try {
      final salt = base64Decode(kdf['salt']! as String);
      final nonce = base64Decode(cipherInfo['nonce']! as String);
      final mac = base64Decode(cipherInfo['mac']! as String);
      final cipherText = base64Decode(cipherInfo['ciphertext']! as String);

      final key = _deriveKey(password, salt, iterations: iterations);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
        );

      final input = Uint8List(cipherText.length + mac.length)
        ..setRange(0, cipherText.length, cipherText)
        ..setRange(cipherText.length, cipherText.length + mac.length, mac);
      final plain = cipher.process(input);
      return utf8.decode(plain);
    } on InvalidCipherTextException {
      throw const InvalidFileException(
        'The password is wrong, or this backup file has been damaged.',
      );
    } on FormatException {
      throw const InvalidFileException('This backup file is not readable.');
    }
  }

  static Uint8List _deriveKey(
    String password,
    Uint8List salt, {
    int iterations = _iterations,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyBytes));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _randomBytes(Random random, int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
