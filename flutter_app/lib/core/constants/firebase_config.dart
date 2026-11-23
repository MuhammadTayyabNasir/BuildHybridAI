import '../../firebase_options.dart';

/// Firebase settings shared by the SDK and the REST fallback (Windows).
///
/// PMA uses the #BuildHybridAI Firebase project. The API key is the public
/// client key from [DefaultFirebaseOptions]; access is restricted by App Check
/// and Firestore security rules, not by keeping it secret.
class FirebaseConfig {
  FirebaseConfig._();

  static const projectId = 'buildhybridai-e2cc2';

  /// PMA stores its data in the project's default Firestore database.
  static const databaseId = '(default)';

  static String get apiKey => DefaultFirebaseOptions.web.apiKey;

  static String get firestoreBase =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/$databaseId/documents';

  static String get authBase =>
      'https://identitytoolkit.googleapis.com/v1/accounts';

  static String get tokenBase =>
      'https://securetoken.googleapis.com/v1/token';
}
