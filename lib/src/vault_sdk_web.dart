// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// custom_code/vault_sdk.dart
//
// Local Library SDK (web-only) for Veilgrid/ShechetAI Vault.
// - Single vault root (user picked) OR OPFS fallback.
// - User-scoped vault via setUserContext(userKey).
// - User-set namespace via setLibraryNamespace(namespace).
// - Agent sandbox by default: agents/<agentId>/...
// - User override via capability tokens (grantAccess).
// - v1: status (incl persistenceGranted + lastBackupAt), delete, move (to folder),
//       downloadable backup + restore, per-file export.
//
// NOTE: This file injects a JS module (not minified) into the page and calls window.VaultSDK.*.
//
// Locking/encryption:
// - This SDK preserves your "unlock is dashboard UX" idea.
// - It does NOT implement real encryption; it provides a gating flag and routes
//   through VaultSSO for operations you choose to protect.
// - In production, the broker iframe should enforce encryption and permissions.
//   This SDK keeps you moving in FlutterFlow while you harden the broker later.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

// Web-only imports (safe to ignore in analyzer)
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as jsu;

/// ----------------------
/// Core JS-injected SDK
/// ----------------------
class VaultSDK {
  static bool _installed = false;
  static Completer<void>? _readyC;

  /// Injects JS bundle into the page and waits until `window.VaultSDK` exists.
  /// Idempotent.
  static Future<void> install() async {
    if (!kIsWeb) return;
    if (_installed) {
      if (_readyC != null && !(_readyC!.isCompleted)) {
        await _readyC!.future;
      }
      return;
    }

    _installed = true;
    _readyC = Completer<void>();

    final script = html.ScriptElement()
      ..type = 'module'
      ..text = _jsSource;
    (html.document.head ?? html.document.body)?.append(script);

    for (int i = 0; i < 200; i++) {
      final win = js.context['window'];
      final has = win != null && jsu.getProperty(win, 'VaultSDK') != null;
      if (has) {
        _readyC?.complete();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!(_readyC?.isCompleted ?? true)) {
      _readyC?.completeError(StateError('VaultSDK JS did not initialize.'));
    }
  }

  static Future<void> _ready() async {
    if (!kIsWeb) throw Exception('VaultSDK is web-only.');
    if (!_installed) {
      await install();
    } else if (_readyC != null && !(_readyC!.isCompleted)) {
      await _readyC!.future;
    }
  }

  /// Dashboard-only: user picks the vault base folder. (FSA)
  static Future<Map<String, dynamic>> setDefaultRoot() async {
    await _ready();
    final res = await _call('window.VaultSDK.setDefaultRoot');
    return _toMap(res);
  }

  /// Sets who the vault is currently scoped to (userKey).
  /// Required before list/open/save/delete/move/backup/restore.
  static Future<void> setUserContext({
    required String userKey,
  }) async {
    await _ready();
    await _callVoid('window.VaultSDK.setUserContext', [userKey]);
  }

  /// Sets the user-chosen namespace/prefix under the selected root/OPFS.
  /// Required before list/open/save/delete/move/backup/restore.
  static Future<void> setLibraryNamespace({
    required String namespace,
  }) async {
    await _ready();
    await _callVoid('window.VaultSDK.setLibraryNamespace', [namespace]);
  }

  /// Dashboard-only (recommended): request persistent storage on supported browsers.
  /// Returns { persisted: bool }.
  static Future<Map<String, dynamic>> requestPersistence() async {
    await _ready();
    final res = await _call('window.VaultSDK.requestPersistence');
    return _toMap(res);
  }

  /// Returns status info used by UI wiring:
  /// {
  ///   mode: "folder"|"browser",
  ///   label: string,
  ///   userContextSet: bool,
  ///   namespaceSet: bool,
  ///   namespace: string,
  ///   persistenceGranted: bool,
  ///   lastBackupAtMs: number|null,
  /// }
  static Future<Map<String, dynamic>> status() async {
    await _ready();
    final res = await _call('window.VaultSDK.status');
    return _toMap(res);
  }

  /// Grants an agent temporary access to a folder (or file path prefix) outside its sandbox.
  /// Returns { token: string, expiresAtMs: number }.
  static Future<Map<String, dynamic>> grantAccess({
    required String agentId,
    required String pathPrefix,
    int ttlSeconds = 300,
  }) async {
    await _ready();
    final res = await _call(
        'window.VaultSDK.grantAccess', [agentId, pathPrefix, ttlSeconds]);
    return _toMap(res);
  }

  /// Lists files under a folder.
  ///
  /// Agents: if basePath is null/empty and no token, defaults to agents/<agentId>/.
  /// Dashboard: can pass agentId="" and a basePath within the vault (full access).
  ///
  /// Returns list of:
  /// { path, name, size, modifiedMs, isDir }
  static Future<List<Map<String, dynamic>>> list({
    required String agentId,
    String basePath = '',
    String capabilityToken = '',
  }) async {
    await _ready();
    final res = await _call(
        'window.VaultSDK.list', [agentId, basePath, capabilityToken]);
    return _toListOfMap(res);
  }

  /// Opens file bytes (Uint8List).
  static Future<Uint8List> open({
    required String agentId,
    required String path,
    String capabilityToken = '',
  }) async {
    await _ready();
    final res =
        await _call('window.VaultSDK.open', [agentId, path, capabilityToken]);
    return _toUint8List(res);
  }

  /// Saves bytes to a path (creates directories as needed).
  static Future<void> save({
    required String agentId,
    required String path,
    required Uint8List bytes,
    String capabilityToken = '',
  }) async {
    await _ready();
    final b64 = base64Encode(bytes);
    await _callVoid(
        'window.VaultSDK.save', [agentId, path, b64, capabilityToken]);
  }

  /// Deletes a file (or empty folder).
  static Future<void> delete({
    required String agentId,
    required String path,
    String capabilityToken = '',
  }) async {
    await _ready();
    await _callVoid('window.VaultSDK.delete', [agentId, path, capabilityToken]);
  }

  /// Moves a file to a new folder (destination folder path).
  /// Example: moveFileToFolder(agentId, "agents/a1/inbox/x.pdf", "ClientA/Discovery/")
  /// Resulting path becomes: "ClientA/Discovery/x.pdf"
  static Future<Map<String, dynamic>> moveFileToFolder({
    required String agentId,
    required String fromPath,
    required String toFolderPath,
    String capabilityToken = '',
  }) async {
    await _ready();
    final res = await _call('window.VaultSDK.moveFileToFolder',
        [agentId, fromPath, toFolderPath, capabilityToken]);
    return _toMap(res);
  }

  /// Downloads a single file as-is (bytes) to the user's machine.
  /// This is distinct from backup (whole vault).
  static Future<void> exportFileDownload({
    required String agentId,
    required String path,
    String downloadName = '',
    String capabilityToken = '',
  }) async {
    await _ready();
    await _callVoid('window.VaultSDK.exportFileDownload',
        [agentId, path, downloadName, capabilityToken]);
  }

  /// Creates a downloadable backup file for the entire vault (for this user).
  /// Returns { ok: true, lastBackupAtMs: number, filename: string }
  static Future<Map<String, dynamic>> backupCreateDownload() async {
    await _ready();
    final res = await _call('window.VaultSDK.backupCreateDownload');
    return _toMap(res);
  }

  /// Restores from a previously created backup file (bytes).
  /// Returns { ok: true, restoredCount: number }
  static Future<Map<String, dynamic>> restoreFromBackupBytes({
    required Uint8List backupBytes,
  }) async {
    await _ready();
    final b64 = base64Encode(backupBytes);
    final res = await _call('window.VaultSDK.restoreFromBackupB64', [b64]);
    return _toMap(res);
  }

  // ---------- internals ----------
  static Future<dynamic> _call(String path, [List<dynamic>? args]) async {
    final parts = path.split('.');
    dynamic target = js.context;
    for (final p in parts) {
      if (p == 'window') continue;
      target = jsu.getProperty(target, p);
      if (target == null) {
        throw StateError('Missing JS path: $path');
      }
    }
    final hasCall = jsu.getProperty(target, 'call') != null;
    if (!hasCall) throw StateError('JS target is not a function: $path');

    final res =
        jsu.callMethod(target, 'call', [js.context['window'], ...(args ?? [])]);
    return await jsu.promiseToFuture(res);
  }

  static Future<void> _callVoid(String path, [List<dynamic>? args]) async {
    await _call(path, args);
  }

  static Map<String, dynamic> _toMap(dynamic jsObj) {
    final jsonStr =
        js.context['JSON'].callMethod('stringify', [jsObj]) as String;
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  static List<Map<String, dynamic>> _toListOfMap(dynamic jsArr) {
    final jsonStr =
        js.context['JSON'].callMethod('stringify', [jsArr]) as String;
    final data = jsonDecode(jsonStr) as List;
    return List<Map<String, dynamic>>.from(data);
  }

  static Uint8List _toUint8List(dynamic jsRes) {
    if (jsRes == null) throw Exception('vault_open_failed');
    final length = jsu.getProperty(jsRes, 'length');
    if (length is int) {
      final out = Uint8List(length);
      for (var i = 0; i < length; i++) {
        out[i] = (jsu.getProperty(jsRes, i) as num).toInt();
      }
      return out;
    }
    final arr = js.context['Array'].callMethod('from', [jsRes]);
    final jsonStr = js.context['JSON'].callMethod('stringify', [arr]) as String;
    final list = (jsonDecode(jsonStr) as List).cast<int>();
    return Uint8List.fromList(list);
  }
}

/// ----------------------
/// SSO/Broker shims (UI-layer gating)
/// ----------------------
///
/// Your product decision is: "Unlock UI is dashboard-only in v1".
/// This class provides a simple gating flag for actions.
/// Replace with worker/broker-enforced encryption later.
class VaultBroker {
  static bool _started = false;
  static void start() {
    if (!kIsWeb) return;
    if (_started) return;
    _started = true;
  }
}

class VaultSSO {
  static bool _unlocked = false;

  static Future<void> unlockWithPassphrase(String passphrase) async {
    VaultBroker.start();
    await VaultSDK.install();
    _unlocked = passphrase.isNotEmpty;
    if (!_unlocked) throw Exception('vault_unlock_failed');
  }

  static Future<void> lock() async {
    _unlocked = false;
  }

  static Future<Map<String, dynamic>> status() async {
    return {'unlocked': _unlocked};
  }

  static void requireUnlocked() {
    if (!_unlocked) throw Exception('vault_locked');
  }

  /// You can decide which operations must require unlock.
  /// Typically, anything that reads/writes file bytes should require it.
  static Future<List<Map<String, dynamic>>> list({
    required String agentId,
    String basePath = '',
    String capabilityToken = '',
    bool requireUnlock = false,
  }) async {
    if (requireUnlock) requireUnlocked();
    return VaultSDK.list(
        agentId: agentId, basePath: basePath, capabilityToken: capabilityToken);
  }

  static Future<Uint8List> open({
    required String agentId,
    required String path,
    String capabilityToken = '',
  }) async {
    requireUnlocked();
    return VaultSDK.open(
        agentId: agentId, path: path, capabilityToken: capabilityToken);
  }

  static Future<void> save({
    required String agentId,
    required String path,
    required Uint8List bytes,
    String capabilityToken = '',
  }) async {
    requireUnlocked();
    await VaultSDK.save(
        agentId: agentId,
        path: path,
        bytes: bytes,
        capabilityToken: capabilityToken);
  }
}

/// --------------------------------------------------------
/// Injected JS (module) — FSA + OPFS fallback + capabilities
/// --------------------------------------------------------
const String _jsSource = r"""
// VaultSDK JS module (injected)
// Storage layout (physical directories):
//   <root>/<namespace>/v1/user-<userKey>/files/... (user-chosen namespace)
// Agent sandbox default folder:
//   <...>/files/agents/<agentId>/...
//
// Capability tokens allow temporary access to an arbitrary prefix path.

const VAULT_DB = 'vault-db';
const HANDLE_STORE = 'handles';

function nowMs(){ return Date.now(); }

function lsGet(k){ try{ return localStorage.getItem(k); }catch(e){ return null; } }
function lsSet(k,v){ try{ localStorage.setItem(k,v); }catch(e){} }

function keyUser(){ return 'vault:userKey'; }
function keyNs(){ return 'vault:namespace'; }
function keyLastBackup(){ return 'vault:lastBackupAtMs'; }

function normalizePath(p){
  if(!p) return '';
  p = String(p).replace(/\\/g,'/').trim();
  // strip leading "./" and leading "/"
  while(p.startsWith('./')) p = p.slice(2);
  while(p.startsWith('/')) p = p.slice(1);
  // collapse multiple slashes
  p = p.replace(/\/+/g,'/');
  // disallow traversal
  if(p.includes('..')) throw new Error('invalid_path');
  return p;
}
function ensureFolderPath(p){
  p = normalizePath(p);
  if(p && !p.endsWith('/')) p += '/';
  return p;
}
function baseName(p){
  p = normalizePath(p);
  const parts = p.split('/').filter(Boolean);
  return parts.length ? parts[parts.length-1] : '';
}

async function idbOpen(){
  return new Promise((resolve,reject)=>{
    const req = indexedDB.open(VAULT_DB, 1);
    req.onupgradeneeded = ()=> req.result.createObjectStore(HANDLE_STORE);
    req.onsuccess = ()=> resolve(req.result);
    req.onerror = ()=> reject(req.error);
  });
}
async function idbPut(key,val){
  const db = await idbOpen();
  return new Promise((resolve,reject)=>{
    const tx = db.transaction(HANDLE_STORE,'readwrite');
    tx.objectStore(HANDLE_STORE).put(val,key);
    tx.oncomplete = ()=> resolve(true);
    tx.onerror = ()=> reject(tx.error);
  });
}
async function idbGet(key){
  const db = await idbOpen();
  return new Promise((resolve,reject)=>{
    const tx = db.transaction(HANDLE_STORE,'readonly');
    const req = tx.objectStore(HANDLE_STORE).get(key);
    req.onsuccess = ()=> resolve(req.result || null);
    req.onerror = ()=> reject(req.error);
  });
}

async function opfsRoot(){
  if(!navigator.storage?.getDirectory) throw new Error('opfs_unsupported');
  return await navigator.storage.getDirectory();
}

async function getRootHandle(){
  // Prefer FSA selected folder if present and available.
  const hasPicker = !!window.showDirectoryPicker;
  if(hasPicker){
    const h = await idbGet('root');
    if(h) return { mode:'folder', label:(h.name||'Selected folder'), root:h };
  }
  // OPFS fallback
  try{
    const r = await opfsRoot();
    return { mode:'browser', label:'Browser storage', root:r };
  }catch(e){
    return { mode:'browser', label:'Unavailable on this browser', root:null };
  }
}

async function ensureDir(parent, rel, create){
  rel = normalizePath(rel);
  if(!rel) return parent;
  const parts = rel.split('/').filter(Boolean);
  let cur = parent;
  for(const part of parts){
    cur = await cur.getDirectoryHandle(part, { create: !!create });
  }
  return cur;
}

async function ensureFileHandle(parentDir, name, create){
  name = normalizePath(name);
  if(name.includes('/')) throw new Error('invalid_filename');
  return await parentDir.getFileHandle(name, { create: !!create });
}

function requireInit(){
  const userKey = lsGet(keyUser());
  const ns = lsGet(keyNs());
  if(!userKey) throw new Error('vault_user_context_missing');
  if(!ns) throw new Error('vault_namespace_missing');
  return { userKey, namespace: ns };
}

function agentSandboxPrefix(agentId){
  agentId = String(agentId||'').trim();
  if(!agentId) return ''; // dashboard-level calls can pass empty agentId
  return ensureFolderPath(`agents/${agentId}/`);
}

// Capabilities: token -> { agentId, prefix, expMs }
const _caps = new Map();

function randToken(){
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  return Array.from(b).map(x=>x.toString(16).padStart(2,'0')).join('');
}

function capLookup(token){
  if(!token) return null;
  const c = _caps.get(token);
  if(!c) return null;
  if(nowMs() > c.expMs){
    _caps.delete(token);
    return null;
  }
  return c;
}

function isAllowedPath(agentId, path, token){
  path = normalizePath(path);
  // Dashboard (agentId empty) = full access
  if(!agentId) return true;

  const agentPrefix = agentSandboxPrefix(agentId); // e.g. agents/a1/
  if(path.startsWith(agentPrefix)) return true;

  const cap = capLookup(token);
  if(cap && cap.agentId === agentId){
    const pref = ensureFolderPath(cap.prefix);
    if(path.startsWith(pref)) return true;
  }
  return false;
}

function assertAllowed(agentId, path, token){
  if(!isAllowedPath(agentId, path, token)) throw new Error('vault_access_denied');
}

async function userBaseDir(create){
  const { userKey, namespace } = requireInit();
  const rootInfo = await getRootHandle();
  if(!rootInfo.root) throw new Error('vault_storage_unavailable');

  // <root>/<namespace>/v1/user-<userKey>/
  const baseRel = `${normalizePath(namespace)}/v1/user-${normalizePath(userKey)}`;
  const dir = await ensureDir(rootInfo.root, baseRel, !!create);
  return { rootInfo, dir };
}

async function filesDir(create){
  const ub = await userBaseDir(create);
  const d = await ensureDir(ub.dir, 'files', !!create);
  return { ...ub, dir:d };
}

async function walk(dirHandle, prefix){
  const out = [];
  for await (const entry of dirHandle.values()){
    if(entry.kind === 'file'){
      const f = await entry.getFile();
      out.push({
        path: (prefix ? (prefix + entry.name) : entry.name),
        name: entry.name,
        size: f.size,
        modifiedMs: f.lastModified,
        isDir: false
      });
    }else if(entry.kind === 'directory'){
      out.push({
        path: ensureFolderPath(prefix ? (prefix + entry.name) : entry.name),
        name: entry.name,
        size: 0,
        modifiedMs: 0,
        isDir: true
      });
    }
  }
  // keep stable order
  out.sort((a,b)=> a.path.localeCompare(b.path));
  return out;
}

async function readFileBytes(fileHandle){
  const f = await fileHandle.getFile();
  const buf = await f.arrayBuffer();
  return new Uint8Array(buf);
}
function b64ToBytes(b64){
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++) out[i]=bin.charCodeAt(i);
  return out;
}
function bytesToB64(bytes){
  let bin = '';
  for(let i=0;i<bytes.length;i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function downloadBlob(bytes, filename, mime){
  const blob = new Blob([bytes], { type: mime||'application/octet-stream' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(()=> URL.revokeObjectURL(url), 1000);
}

window.VaultSDK = {
  async setDefaultRoot(){
    if(!window.showDirectoryPicker) throw new Error('fsa_unsupported');
    const h = await window.showDirectoryPicker({ mode:'readwrite' });
    await idbPut('root', h);
    return { ok:true, label:(h.name||'Selected folder') };
  },

  async setUserContext(userKey){
    userKey = String(userKey||'').trim();
    if(!userKey) throw new Error('invalid_user_key');
    lsSet(keyUser(), userKey);
    return { ok:true };
  },

  async setLibraryNamespace(ns){
    ns = normalizePath(ns);
    if(!ns) throw new Error('invalid_namespace');
    lsSet(keyNs(), ns);
    return { ok:true };
  },

  async requestPersistence(){
    if(!navigator.storage?.persist) return { persisted:false };
    const persisted = await navigator.storage.persist();
    return { persisted: !!persisted };
  },

  async status(){
    const rootInfo = await getRootHandle();
    const userKey = lsGet(keyUser());
    const ns = lsGet(keyNs());
    const lastBackupAtMsStr = lsGet(keyLastBackup());
    const lastBackupAtMs = lastBackupAtMsStr ? Number(lastBackupAtMsStr) : null;

    let persistenceGranted = false;
    if(navigator.storage?.persisted){
      try{ persistenceGranted = await navigator.storage.persisted(); }catch(e){}
    }

    return {
      mode: rootInfo.mode,
      label: rootInfo.label,
      userContextSet: !!userKey,
      namespaceSet: !!ns,
      namespace: ns || '',
      persistenceGranted: !!persistenceGranted,
      lastBackupAtMs: (typeof lastBackupAtMs === 'number' && !Number.isNaN(lastBackupAtMs)) ? lastBackupAtMs : null
    };
  },

  async grantAccess(agentId, pathPrefix, ttlSeconds){
    agentId = String(agentId||'').trim();
    if(!agentId) throw new Error('invalid_agent');
    pathPrefix = ensureFolderPath(pathPrefix);
    if(!pathPrefix) throw new Error('invalid_path');

    const tok = randToken();
    const expMs = nowMs() + (Math.max(10, Number(ttlSeconds||300)) * 1000);
    _caps.set(tok, { agentId, prefix: pathPrefix, expMs });
    return { token: tok, expiresAtMs: expMs };
  },

  async list(agentId, basePath, token){
    const fd = await filesDir(true);
    agentId = String(agentId||'').trim();
    basePath = normalizePath(basePath||'');
    token = String(token||'');

    // Agent default: list its sandbox root
    if(agentId && !basePath){
      basePath = agentSandboxPrefix(agentId);
    }

    // Ensure folder path for directory listing
    const dirPath = ensureFolderPath(basePath);

    // Enforce access (for agent)
    if(agentId){
      // listing a folder: check folder prefix
      assertAllowed(agentId, dirPath, token);
    }

    const targetDir = await ensureDir(fd.dir, dirPath, true);
    return await walk(targetDir, dirPath);
  },

  async open(agentId, path, token){
    const fd = await filesDir(true);
    agentId = String(agentId||'').trim();
    path = normalizePath(path||'');
    token = String(token||'');

    if(!path) throw new Error('invalid_path');
    if(agentId){
      assertAllowed(agentId, path, token);
    }

    const parts = path.split('/').filter(Boolean);
    const name = parts.pop();
    const parentRel = parts.join('/');
    const parentDir = await ensureDir(fd.dir, parentRel, false);
    const fh = await parentDir.getFileHandle(name, { create:false });
    return await readFileBytes(fh);
  },

  async save(agentId, path, b64, token){
    const fd = await filesDir(true);
    agentId = String(agentId||'').trim();
    path = normalizePath(path||'');
    token = String(token||'');

    if(!path) throw new Error('invalid_path');
    if(agentId){
      // If caller passed a bare filename, force into sandbox
      if(!path.includes('/')) path = agentSandboxPrefix(agentId) + path;
      assertAllowed(agentId, path, token);
    }

    const parts = path.split('/').filter(Boolean);
    const name = parts.pop();
    const parentRel = parts.join('/');
    const parentDir = await ensureDir(fd.dir, parentRel, true);
    const fh = await parentDir.getFileHandle(name, { create:true });

    const w = await fh.createWritable();
    const bytes = b64ToBytes(String(b64||''));
    await w.write(bytes);
    await w.close();
    return { ok:true };
  },

  async delete(agentId, path, token){
    const fd = await filesDir(true);
    agentId = String(agentId||'').trim();
    path = normalizePath(path||'');
    token = String(token||'');

    if(!path) throw new Error('invalid_path');
    if(agentId){
      assertAllowed(agentId, path, token);
    }

    // If path ends with '/', try delete directory (must be empty)
    if(path.endsWith('/')){
      const dirPath = path.replace(/\/+$/,'');
      const parts = dirPath.split('/').filter(Boolean);
      const name = parts.pop();
      const parentRel = parts.join('/');
      const parentDir = await ensureDir(fd.dir, parentRel, false);
      await parentDir.removeEntry(name, { recursive:false });
      return { ok:true };
    }

    // Delete file
    const parts = path.split('/').filter(Boolean);
    const name = parts.pop();
    const parentRel = parts.join('/');
    const parentDir = await ensureDir(fd.dir, parentRel, false);
    await parentDir.removeEntry(name, { recursive:false });
    return { ok:true };
  },

  async moveFileToFolder(agentId, fromPath, toFolderPath, token){
    const fd = await filesDir(true);
    agentId = String(agentId||'').trim();
    fromPath = normalizePath(fromPath||'');
    toFolderPath = ensureFolderPath(toFolderPath||'');
    token = String(token||'');

    if(!fromPath || !toFolderPath) throw new Error('invalid_path');
    const fname = baseName(fromPath);
    if(!fname) throw new Error('invalid_filename');

    const destPath = normalizePath(toFolderPath + fname);

    if(agentId){
      // must be allowed for BOTH source and destination
      assertAllowed(agentId, fromPath, token);
      assertAllowed(agentId, destPath, token);
    }

    // Read bytes, write dest, delete src (portable move)
    const srcBytes = await this.open(agentId, fromPath, token);
    await this.save(agentId, destPath, bytesToB64(srcBytes), token);
    await this.delete(agentId, fromPath, token);

    return { ok:true, fromPath, toPath: destPath };
  },

  async exportFileDownload(agentId, path, downloadName, token){
    agentId = String(agentId||'').trim();
    path = normalizePath(path||'');
    token = String(token||'');
    if(!path) throw new Error('invalid_path');

    if(agentId){
      assertAllowed(agentId, path, token);
    }

    const bytes = await this.open(agentId, path, token);
    const name = (downloadName && String(downloadName).trim()) ? String(downloadName).trim() : baseName(path);
    downloadBlob(bytes, name || 'export.bin', 'application/octet-stream');
    return { ok:true };
  },

  async backupCreateDownload(){
    // Backup: downloadable JSON file containing all files under /files (for this user).
    // NOTE: For large vaults, this is memory-heavy; v1 tradeoff.
    const fd = await filesDir(true);
    const { userKey, namespace } = requireInit();
    const createdAtMs = nowMs();

    // Walk recursively under files/
    async function walkFiles(dirHandle, prefix){
      const out = [];
      for await (const entry of dirHandle.values()){
        if(entry.kind === 'file'){
          const f = await entry.getFile();
          const buf = await f.arrayBuffer();
          out.push({
            path: prefix + entry.name,
            b64: bytesToB64(new Uint8Array(buf)),
            modifiedMs: f.lastModified
          });
        } else if(entry.kind === 'directory'){
          const subPrefix = prefix + entry.name + '/';
          const sub = await walkFiles(entry, subPrefix);
          out.push(...sub);
        }
      }
      return out;
    }

    const files = await walkFiles(fd.dir, '');
    const payload = {
      format: 'veilgrid-vault-backup',
      version: 1,
      createdAtMs,
      namespace,
      userKeyHint: userKey ? ('user-' + String(userKey).slice(0, 8)) : '',
      files
    };

    const json = JSON.stringify(payload);
    const bytes = new TextEncoder().encode(json);

    const filename = `vault-backup-${createdAtMs}.json`;
    downloadBlob(bytes, filename, 'application/json');

    lsSet(keyLastBackup(), String(createdAtMs));
    return { ok:true, lastBackupAtMs: createdAtMs, filename };
  },

  async restoreFromBackupB64(b64){
    const { userKey, namespace } = requireInit();
    const fd = await filesDir(true);

    const bytes = b64ToBytes(String(b64||''));
    const json = new TextDecoder().decode(bytes);
    let payload;
    try{ payload = JSON.parse(json); }catch(e){ throw new Error('backup_parse_failed'); }

    if(!payload || payload.format !== 'veilgrid-vault-backup') throw new Error('backup_format_invalid');
    if(payload.version !== 1) throw new Error('backup_version_unsupported');

    const files = Array.isArray(payload.files) ? payload.files : [];
    let restored = 0;

    for(const item of files){
      const path = normalizePath(item.path||'');
      const fb64 = String(item.b64||'');
      if(!path || !fb64) continue;

      // Write file under files/<path>
      const parts = path.split('/').filter(Boolean);
      const name = parts.pop();
      const parentRel = parts.join('/');

      const parentDir = await ensureDir(fd.dir, parentRel, true);
      const fh = await parentDir.getFileHandle(name, { create:true });
      const w = await fh.createWritable();
      await w.write(b64ToBytes(fb64));
      await w.close();
      restored++;
    }

    // Mark last backup time as "now" because restore just happened.
    const restoredAtMs = nowMs();
    lsSet(keyLastBackup(), String(restoredAtMs));
    return { ok:true, restoredCount: restored };
  }
};
""";