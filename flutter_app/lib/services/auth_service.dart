import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'local_storage_service.dart';

class AuthService {
  final LocalStorageService _local;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'remoxindatabase');

  static const _emailDomain = '@4u.remoxin.com';

  AuthService(this._local);

  String _emailOf(String username) => '$username$_emailDomain';

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static bool _isNetworkError(dynamic e) {
    if (e is FirebaseAuthException && e.code == 'network-request-failed') {
      return true;
    }
    final msg = e.toString().toLowerCase();
    return e is SocketException ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection timed out') ||
        msg.contains('no route to host') ||
        msg.contains('handshake') ||
        msg.contains('errno = ');
  }

  static String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'invalid-email':
        return 'Username not found. Check spelling.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong username or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again later.';
      default:
        return 'Login failed: $code';
    }
  }

  /// Returns the logged-in [UserModel] or throws with a human-readable message.
  Future<UserModel> login(String username, String password) async {
    final usernameClean = username.trim().toLowerCase();
    final email = _emailOf(usernameClean);

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;

      // Try to fetch the Firestore profile
      UserModel? profile = await _fetchUserProfile(uid, usernameClean);

      // If profile is missing (new setup or doc doesn't exist yet), create it
      if (profile == null) {
        debugPrint('[AuthService] No profile found for $uid — creating one now');
        final role = usernameClean == 'admin' ? 'admin' : 'operator';
        final data = {
          'username': usernameClean,
          'role': role,
          'createdAt': FieldValue.serverTimestamp(),
        };
        try {
          await _db.collection('users').doc(uid).set(data);
          debugPrint('[AuthService] Profile created in Firestore at users/$uid');
        } catch (e) {
          debugPrint('[AuthService] Could not write profile to Firestore: $e');
        }
        profile = UserModel(
          id: uid,
          username: usernameClean,
          role: role,
          createdAt: DateTime.now(),
        );
      }

      // Save auth cache for offline login
      await _local.saveAuthCache(
        uid,
        usernameClean,
        profile.role,
        _hashPassword(password),
      );

      return profile;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        debugPrint('[AuthService] Network error during login, checking offline cache.');
        return _tryOfflineLogin(usernameClean, password);
      }
      throw Exception(_authErrorMessage(e.code));
    } catch (e) {
      if (_isNetworkError(e)) {
        return _tryOfflineLogin(usernameClean, password);
      }
      rethrow;
    }
  }

  Future<UserModel> _tryOfflineLogin(String username, String password) async {
    if (!_local.isAuthCacheValid()) {
      throw Exception('No internet connection and no valid offline session. Please connect and log in online first.');
    }
    final cache = _local.getAuthCache();
    if (cache == null) {
      throw Exception('No offline session available. Please connect and log in online first.');
    }
    final cachedUsername = cache['username'] as String? ?? '';
    final cachedHash = cache['passwordHash'] as String? ?? '';
    if (cachedUsername != username) {
      throw Exception('No offline session for this username. Please connect and log in online first.');
    }
    if (_hashPassword(password) != cachedHash) {
      throw Exception('Wrong password.');
    }
    debugPrint('[AuthService] Offline login successful for $username');
    return UserModel(
      id: cache['uid'] as String? ?? '',
      username: cachedUsername,
      role: cache['role'] as String? ?? 'operator',
      createdAt: DateTime.now(),
    );
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('[AuthService] SDK signOut failed: $e');
    }
  }

  Future<UserModel?> currentUserProfile() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return _tryRestoreFromCache();
      }
      return _fetchUserProfile(user.uid, null);
    } catch (e) {
      if (_isNetworkError(e)) {
        return _tryRestoreFromCache();
      }
      return null;
    }
  }

  UserModel? _tryRestoreFromCache() {
    if (!_local.isAuthCacheValid()) return null;
    final cache = _local.getAuthCache();
    if (cache == null) return null;
    return UserModel(
      id: cache['uid'] as String? ?? '',
      username: cache['username'] as String? ?? '',
      role: cache['role'] as String? ?? 'operator',
      createdAt: DateTime.now(),
    );
  }

  Future<UserModel?> _fetchUserProfile(String uid, String? usernameFallback) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data()!, doc.id);
      }
      debugPrint('[AuthService] users/$uid returned null (404)');
    } catch (e) {
      debugPrint('[AuthService] getDocument users/$uid failed: $e');
    }

    if (usernameFallback != null) {
      try {
        final query = await _db
            .collection('users')
            .where('username', isEqualTo: usernameFallback)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          debugPrint('[AuthService] Found profile via username scan: ${doc.id}');
          return UserModel.fromMap(doc.data(), doc.id);
        }
        debugPrint('[AuthService] Username scan: no doc with username=$usernameFallback');
      } catch (e) {
        debugPrint('[AuthService] Username scan failed: $e');
      }
    }

    return null;
  }

  Future<String?> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final email = _emailOf(username.trim().toLowerCase());
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = result.user!.uid;

      await _db.collection('users').doc(uid).set({
        'username': username.trim().toLowerCase(),
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return 'Username already exists';
      return e.message ?? e.code;
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    }
  }

  Future<String?> deleteUser(String uid) async {
    try {
      await _db.collection('users').doc(uid).delete();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<List<UserModel>> listUsers() async {
    try {
      final snap = await _db.collection('users').get();
      return snap.docs
          .map((d) => UserModel.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) => a.username.compareTo(b.username));
    } catch (_) {
      return [];
    }
  }

  bool get isLoggedIn => _auth.currentUser != null;
}