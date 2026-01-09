/// Derive a stable, non-PII vault namespace key for this user.
  /// Recommended formula: hex(sha256(issuer + "|" + subject))
  /// NOTE: This is NOT encryption and does NOT unlock anything.
  static Future<String> deriveUserKey({
    required String issuer,
    required String subject,
  }) async {
    if (!kIsWeb) {
      throw Exception('deriveUserKey is web-only in this implementation.');
    }

    final subtle = jsu.getProperty(js.context['crypto'], 'subtle');
    final input = _utf8('$issuer|$subject');

    final hashBuf = await jsu.promiseToFuture(jsu.callMethod(
      subtle,
      'digest',
      ['SHA-256', input],
    ));

    final bytes = Uint8List.view((hashBuf as ByteBuffer));
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString(); // 64 hex chars
  }
