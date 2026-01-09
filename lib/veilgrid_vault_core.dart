library veilgrid_vault_core;

export 'src/vault_sdk_stub.dart'
    if (dart.library.html) 'src/vault_sdk_web.dart';

export 'src/vault_crypto_stub.dart'
    if (dart.library.html) 'src/vault_crypto_web.dart';
