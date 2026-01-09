// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Web-only crypto helpers for Veilgrid Vault Core.
// NOTE: This does NOT encrypt anything. It only derives a stable, non-PII user key.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

// Web-only imports (safe to ignore in analyzer via conditional export)
import 'dart:js' as js;
import 'dart:js_util' as jsu;

class VaultCrypto {
  /// Derive a stable, non-PII vault namespace key for this user.
  ///
  /// Recommended formula: hex(sha256(issuer + "|" + subject))
  /// NOTE: This is NOT encryption and does NOT unlock anything.
  static Future<String> deriveUserKey({
    required String issuer,
    required String subject,
  }) async {
    if (!kIsWeb) {
      throw UnsupportedError('VaultCrypto.deriveUserKey is web-only.');
    }

    final cryptoObj = js.context['crypto'];
    if (cryptoObj == null) {
      throw StateError('Web Crypto API not available (window.crypto missing).');
    }
    final subtle = jsu.getProperty(cryptoObj, 'subtle');
    if (subtle == null) {
      throw StateError('Web Crypto API not available (crypto.subtle missing).');
    }

    final input = _utf8('$issuer|$subject');

    final hashBuf = await jsu.promiseToFuture(jsu.callMethod(
      subtle,
      'digest',
      ['SHA-256', input],
    ));

    final bytes = Uint8List.view(hashBuf as ByteBuffer);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString(); // 64 hex chars
  }

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
}
