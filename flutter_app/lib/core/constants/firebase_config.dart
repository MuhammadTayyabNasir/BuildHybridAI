class FirebaseConfig {
  FirebaseConfig._();

  static const projectId = 'remoxinenterprise-e0611';
  static const databaseId = 'remoxindatabase';

  // Web/Windows key used for REST API calls on all platforms
  static const apiKey = 'REDACTED_API_KEY';

  static String get firestoreBase =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/$databaseId/documents';

  static String get authBase =>
      'https://identitytoolkit.googleapis.com/v1/accounts';

  static String get tokenBase =>
      'https://securetoken.googleapis.com/v1/token';
}
