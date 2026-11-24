import 'dart:async'; // NEW: Required for TimeoutException
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final FirestoreService? _firestoreService;
  final LocalStorageService? _localStorageService;

  AuthProvider(
      this._authService, {
        FirestoreService? firestoreService,
        LocalStorageService? localStorageService,
      })  : _firestoreService = firestoreService,
        _localStorageService = localStorageService;

  AuthState _state = AuthState.initial;
  UserModel? _user;
  String? _errorMessage;
  bool _isOfflineMode = false;

  AuthState get state => _state;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isViewer => _user?.isViewer ?? false;
  bool get isQC => _user?.isQC ?? false;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isOfflineMode => _isOfflineMode;

  bool _isDemo = false;

  /// Local demo session (no Firebase sign-in, synthetic data).
  bool get isDemo => _isDemo;

  /// Opens the app as a local demo admin. [seed] fills the phone with
  /// made-up data first; it runs before the home screen appears.
  Future<void> startDemo(UserModel demoUser, Future<void> Function() seed) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      await seed();
      _user = demoUser;
      _isDemo = true;
      _isOfflineMode = true;
      _state = AuthState.authenticated;
    } catch (e) {
      _errorMessage = 'Could not open the demo: $e';
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> checkAuth() async {
    _state = AuthState.loading;
    notifyListeners();

    final user = await _authService.currentUserProfile();
    if (user != null) {
      _user = user;
      _state = AuthState.authenticated;
      // Detect if restored from cache (no live token)
      final local = _localStorageService;
      if (local != null && local.isAuthCacheValid()) {
        _isOfflineMode = false;
      }
    } else {
      _state = AuthState.unauthenticated;
      _isOfflineMode = false;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    username = AuthService.normalizeUsername(username);
    _state = AuthState.loading;
    _errorMessage = null;
    _isOfflineMode = false;
    notifyListeners();

    try {
      // A cold start has to fetch an App Check token, sign in and read the
      // profile; on slow factory Wi-Fi 5 s was not enough and fell through to
      // the offline path. 30 s still stops an endless spinner.
      final user = await _authService
          .login(username, password)
          .timeout(const Duration(seconds: 30));

      _user = user;
      _state = AuthState.authenticated;

      final signedInOnline = _authService.isLoggedIn;
      _isOfflineMode = !signedInOnline;

      // NEW: Save the successful online session to Local Storage for future offline use!
      if (signedInOnline && _localStorageService != null) {
        await _localStorageService.saveOfflineSession(user, password);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
      notifyListeners();

      // Seeds default products and machines only when the database is empty,
      // so the first phone to sign in to a fresh project gets a usable app.
      if (!_isOfflineMode) {
        _firestoreService?.seedInitialData();
      }
      return true;

    } on TimeoutException {
      return await _handleOfflineFallback(username, password);
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('network') || errorStr.contains('permission-denied') || errorStr.contains('unavailable')) {
        return await _handleOfflineFallback(username, password);
      }

      _state = AuthState.unauthenticated;
      _isOfflineMode = false;
      _errorMessage = errorStr.replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> _handleOfflineFallback(String username, String password) async {
    if (_localStorageService == null) {
      _errorMessage = 'No internet connection and no local database found.';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }

    try {
      final isLocalValid = await _localStorageService.validateOfflineLogin(username, password);

      if (isLocalValid) {
        // NEW: Added the 'await' keyword here since getCachedUser is a Future
        final cachedUser = await _localStorageService.getCachedUser();

        if (cachedUser != null) {
          if (cachedUser.isAdmin) {
            _errorMessage = 'Admins must have an active internet connection to log in.';
            _state = AuthState.unauthenticated;
            notifyListeners();
            return false;
          }

          _user = cachedUser;
          _state = AuthState.authenticated;
          _isOfflineMode = true;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);

          notifyListeners();
          return true;
        }
      }

      _errorMessage = 'No internet connection, and invalid offline credentials.';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;

    } catch (e) {
      _errorMessage = 'Offline login error: $e';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }
  // 4. Custom Local DB Login handler

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _state = AuthState.unauthenticated;
    _isOfflineMode = false;
    _isDemo = false;
    notifyListeners();
  }

  Future<String?> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    return _authService.createUser(username: username, password: password, role: role);
  }

  Future<List<UserModel>> listUsers() => _authService.listUsers();

  Future<String?> deleteUser(String uid) => _authService.deleteUser(uid);
}