import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/entries_provider.dart';
import 'providers/machines_provider.dart';
import 'providers/products_provider.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/device_service.dart';
import 'services/firestore_service.dart';
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'services/report_service.dart';
import 'services/th_threshold_service.dart';
import 'services/settings_service.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // 1. Initialize Firebase natively on all platforms
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final localStorage = LocalStorageService();
  await localStorage.init();

  final connectivityService = ConnectivityService();
  await connectivityService.init();

  final deviceService = DeviceService(localStorage);

  // 2. Initialize Services (Native Firestore, no REST)
  final firestoreService = FirestoreService();
  final authService = AuthService(localStorage);

  final thresholdService = ThThresholdService();
  thresholdService.init(); // Instantly attaches the gRPC listener

  final syncService = SyncService(firestoreService, localStorage, connectivityService);
  final settingsService = SettingsService();
  final entriesProvider = EntriesProvider(
    firestoreService,
    localStorage,
    connectivityService,
    syncService,
  );

  final productsProvider = ProductsProvider(firestoreService, localStorage);
  final machinesProvider = MachinesProvider(firestoreService, localStorage);

  // 3. Listen to auth state to trigger data fetches
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      // User logged in: Start the live gRPC listeners!
      productsProvider.startListening();
      machinesProvider.startListening(); // assuming you added it here too
      entriesProvider.startListening();
      settingsService.startListening(); // <--- ADD THIS
    } else {
      // User logged out: kill the listeners
      productsProvider.stopListening();
      machinesProvider.stopListening();
      entriesProvider.stopListening();
      settingsService.stopListening(); // <--- ADD THIS
    }
  });
  runApp(
    MultiProvider(
      providers: [
        Provider<LocalStorageService>.value(value: localStorage),
        Provider<FirestoreService>.value(value: firestoreService),
        Provider<DeviceService>.value(value: deviceService),
        Provider<ReportService>(
          create: (_) => ReportService(firestoreService, localStorage, thresholdService),
        ),
        Provider<ConnectivityService>.value(value: connectivityService),
        Provider<SyncService>.value(value: syncService),
        Provider<ThThresholdService>.value(value: thresholdService),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService, firestoreService: firestoreService, localStorageService: localStorage),
        ),
        ChangeNotifierProvider(
          create: (_) => ConnectivityProvider(connectivityService, syncService)..init(),
        ),
        ChangeNotifierProvider.value(value: productsProvider),
        ChangeNotifierProvider.value(value: machinesProvider),
        ChangeNotifierProvider.value(value: entriesProvider),
        ChangeNotifierProvider.value(value: settingsService), // <--- ADD THIS
      ],
      child: const App(),
    ),
  );
}