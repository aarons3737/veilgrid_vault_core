import 'dart:typed_data';

/// Non-web stub. This package is intended to be web-only, but we provide stubs
/// so non-web builds can still compile (and throw if called).
class VaultSDK {
  static Future<void> install() =>
      Future.error(UnsupportedError('VaultSDK is web-only.'));

  static Future<Map<String, dynamic>> setDefaultRoot() =>
      Future.error(UnsupportedError('VaultSDK.setDefaultRoot is web-only.'));

  static Future<void> setUserContext({required String userKey}) =>
      Future.error(UnsupportedError('VaultSDK.setUserContext is web-only.'));

  static Future<void> setLibraryNamespace({required String namespace}) =>
      Future.error(UnsupportedError('VaultSDK.setLibraryNamespace is web-only.'));

  static Future<Map<String, dynamic>> requestPersistence() =>
      Future.error(UnsupportedError('VaultSDK.requestPersistence is web-only.'));

  static Future<Map<String, dynamic>> status() =>
      Future.error(UnsupportedError('VaultSDK.status is web-only.'));

  static Future<Map<String, dynamic>> grantAccess({
    required String agentId,
    required String pathPrefix,
    int ttlSeconds = 300,
  }) =>
      Future.error(UnsupportedError('VaultSDK.grantAccess is web-only.'));

  static Future<List<Map<String, dynamic>>> list({
    required String agentId,
    String basePath = '',
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSDK.list is web-only.'));

  static Future<Uint8List> open({
    required String agentId,
    required String path,
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSDK.open is web-only.'));

  static Future<void> save({
    required String agentId,
    required String path,
    required Uint8List bytes,
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSDK.save is web-only.'));

  static Future<void> delete({
    required String agentId,
    required String path,
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSDK.delete is web-only.'));

  static Future<Map<String, dynamic>> moveFileToFolder({
    required String agentId,
    required String fromPath,
    required String toFolderPath,
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSDK.moveFileToFolder is web-only.'));

  static Future<void> exportFileDownload({
    required String agentId,
    required String path,
    String downloadName = '',
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSDK.exportFileDownload is web-only.'));

  static Future<Map<String, dynamic>> backupCreateDownload() =>
      Future.error(UnsupportedError('VaultSDK.backupCreateDownload is web-only.'));

  static Future<Map<String, dynamic>> restoreFromBackupBytes({
    required Uint8List backupBytes,
  }) =>
      Future.error(UnsupportedError('VaultSDK.restoreFromBackupBytes is web-only.'));
}

class VaultBroker {
  static void start() =>
      throw UnsupportedError('VaultBroker is web-only.');
}

class VaultSSO {
  static Future<void> unlockWithPassphrase(String passphrase) =>
      Future.error(UnsupportedError('VaultSSO.unlockWithPassphrase is web-only.'));

  static Future<void> lock() =>
      Future.error(UnsupportedError('VaultSSO.lock is web-only.'));

  static Future<Map<String, dynamic>> status() =>
      Future.error(UnsupportedError('VaultSSO.status is web-only.'));

  static void requireUnlocked() =>
      throw UnsupportedError('VaultSSO.requireUnlocked is web-only.');

  static Future<List<Map<String, dynamic>>> list({
    required String agentId,
    String basePath = '',
    String capabilityToken = '',
    bool requireUnlock = false,
  }) =>
      Future.error(UnsupportedError('VaultSSO.list is web-only.'));

  static Future<Uint8List> open({
    required String agentId,
    required String path,
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSSO.open is web-only.'));

  static Future<void> save({
    required String agentId,
    required String path,
    required Uint8List bytes,
    String capabilityToken = '',
  }) =>
      Future.error(UnsupportedError('VaultSSO.save is web-only.'));
}
