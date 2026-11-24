import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/alerts_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'services/cloud_sync_service.dart';
import 'services/local_db_service.dart';
import 'services/notification_service.dart';
import 'services/secure_session_storage.dart';
import 'services/tflite_detection_service.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var setupError = SupabaseConfig.validate();
  if (setupError == null) {
    // Retry initialization once if the first attempt fails on a network blip.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey,
          authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage(), detectSessionInUri: false));
        await NotificationService.init();
        break; // success
      } catch (e) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue; // retry once
        }
        setupError = 'Could not initialize the app. Check your internet connection and try again.';
      }
    }
  }
  if (setupError != null) {
    runApp(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: SafeArea(child: Center(
      child: Padding(padding: const EdgeInsets.all(28), child: Text(setupError, textAlign: TextAlign.center)))))));
    return;
  }
  runApp(const IntelliGuardApp());
}

final RouteObserver<ModalRoute<dynamic>> appRouteObserver = RouteObserver<ModalRoute<dynamic>>();

class IntelliGuardApp extends StatelessWidget {
  const IntelliGuardApp({super.key});
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider(Supabase.instance.client)..initialize()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: Consumer<ThemeProvider>(
      builder: (_, themeProvider, __) => MaterialApp(
        title: 'IntelliGuard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeProvider.mode,
        navigatorObservers: [appRouteObserver],
        home: const SplashScreen(next: _RootRouter()),
      ),
    ),
  );
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.starting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final scope = auth.scope;
    if (!auth.isLoggedIn || scope == null) return const LoginScreen();
    return _SessionShell(key: ObjectKey(scope), scope: scope);
  }
}

class _SessionShell extends StatefulWidget {
  final LocalDbScope scope;
  const _SessionShell({super.key, required this.scope});
  @override
  State<_SessionShell> createState() => _SessionShellState();
}
class _SessionShellState extends State<_SessionShell> {
  late final AlertsProvider _alerts;
  late final CloudSyncService _sync;
  bool _ready = false;
  bool _booting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final scope = widget.scope;
    _alerts = AlertsProvider(historyKey: 'ig_known_${scope.storageKey}',
      loadEvents: () => LocalDbService.getAllEvents(scope: scope),
      updateStatus: (id, status, {bool forceSet = false}) =>
        LocalDbService.updateEventStatus(id, status, scope: scope, forceSet: forceSet),
      showNotification: ({required int id, required String title, required String body}) {
        scope.checkActive();
        return NotificationService.showForSession(scope, id: id, title: title, body: body);
      });
    _sync = CloudSyncService(scope, context.read<AuthProvider>().refreshAccess);
    _boot();
  }
  Future<void> _boot() async {
    if (_booting) return;
    setState(() { _booting = true; _error = null; });
    try {
      await _sync.start();
      widget.scope.checkActive();
      if (!await LocalDbService.hasInitialSnapshot(widget.scope)) {
        throw StateError('Connect once to download your organization data. ${_sync.lastError ?? ''}');
      }
      // Establish the historical baseline before the camera creates new events.
      await _alerts.start();
      await TFLiteDetectionService.instance.init();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message.toString() : 'Could not prepare the app. Check the connection and model assets, then retry.');
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }
  @override
  void dispose() { _alerts.dispose(); _sync.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_booting) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('Connecting to your organization…',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('Downloading cameras, zones, and events',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.white54)),
                  ],
                  if (!_booting && _error != null) ...[
                    const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.5)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _boot,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.read<AuthProvider>().logout(),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _alerts),
        ChangeNotifierProvider.value(value: _sync),
      ],
      child: const MainShell(),
    );
  }
}

