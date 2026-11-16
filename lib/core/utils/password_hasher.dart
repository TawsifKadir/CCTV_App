import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// DEMONSTRATION-ONLY password hashing for the mock authentication backend.
///
/// Implements PBKDF2-HMAC-SHA256 with a random per-user salt so that
/// passwords are never stored in plaintext on the device. A production
/// system must perform authentication on a real server (with a vetted
/// password hashing scheme such as Argon2id or bcrypt) and never ship
/// credential verification inside the client.
class PasswordHasher {
  PasswordHasher._();

  static const iterations = 10000;
  static const _keyLength = 32;

  static String generateSalt([Random? random]) {
    final rnd = random ?? Random.secure();
    final bytes = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    return base64Url.encode(bytes);
  }

  /// Returns an encoded hash string: `pbkdf2$<iterations>$<salt>$<hash>`.
  static String hash(String password, {String? salt, int rounds = iterations}) {
    final s = salt ?? generateSalt();
    final derived = _pbkdf2(utf8.encode(password), utf8.encode(s), rounds);
    return 'pbkdf2\$$rounds\$$s\$${base64Url.encode(derived)}';
  }

  static bool verify(String password, String encoded) {
    final parts = encoded.split('\$');
    if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null) return false;
    final expected = hash(password, salt: parts[2], rounds: rounds);
    return _constantTimeEquals(expected, encoded);
  }

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int rounds) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder();
    var block = 1;
    while (out.length < _keyLength) {
      final blockBytes = [
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert([...salt, ...blockBytes]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
      block++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, _keyLength));
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
