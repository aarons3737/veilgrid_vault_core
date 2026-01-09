import 'dart:typed_data';

/// Non-web stub. This package is intended to be web-only, but we provide stubs
/// so non-web builds can still compile.
class VaultCrypto {
  static Future<String> deriveUserKey({
    required String issuer,
    required String subject,
  }) {
    throw UnsupportedError('VaultCrypto.deriveUserKey is web-only.');
  }
}
