import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_controller.dart';
import 'firebase_options.dart';
import 'services/auth.dart';
import 'services/db/db_factory.dart';
import 'services/feedback.dart';
import 'services/repository.dart';
import 'services/sync.dart';
import 'ui/history_screen.dart';
import 'ui/live_screen.dart';
import 'ui/players_screen.dart';
import 'ui/profile_screen.dart';
import 'ui/session_sheets.dart';
import 'ui/settings_screen.dart';

const kAppName = 'MiEncoder - Compatible con ADR';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final db = await openAppDatabase();
  final repo = Repository(db);
  final controller = AppController(repo: repo, feedback: FeedbackService());
  await controller.init();
  final auth = await initFirebase();
  final sync = auth.available
      ? SyncService(
          repo: repo,
          auth: auth,
          remote: FirestoreRemote(FirebaseFirestore.instance),
          onRemoteChanges: controller.reloadData,
        )
      : null;
  runApp(MiEncoderApp(controller: controller, auth: auth, sync: sync));
}

/// Arranca Firebase. No necesita conexión. Si falla o la plataforma no está
/// configurada (escritorio), la app sigue funcionando solo en local.
Future<AuthService> initFirebase() async {
  final supported = kIsWeb || defaultTargetPlatform == TargetPlatform.android;
  if (!supported) return AuthService.disabled();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Sin caché de Firestore: la copia local es sembast y la cola de
    // pendientes la lleva la propia app (ver services/sync.dart).
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    return AuthService(FirebaseAuth.instance);
  } catch (e) {
    debugPrint('Firebase no disponible: $e');
    return AuthService.disabled();
  }
}

class MiEncoderApp extends StatelessWidget {
  final AppController controller;
  final AuthService? auth;
  final SyncService? sync;
  const MiEncoderApp({
    super.key,
    required this.controller,
    this.auth,
    this.sync,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF26A69A),
        scaffoldBackgroundColor: const Color(0xFF101418),
        useMaterial3: true,
      ),
      home: HomeShell(
        c: controller,
        auth: auth ?? AuthService.disabled(),
        sync: sync,
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppController c;
  final AuthService auth;
  final SyncService? sync;
  const HomeShell({super.key, required this.c, required this.auth, this.sync});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int index = 0;

  /// Día para el que ya se preguntó (no repetir la pregunta el mismo día).
  DateTime? _askedOn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Si la app se queda abierta de un día para otro, preguntar al volver.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeAskSession();
      widget.sync?.syncSoon();
    }
  }

  Future<void> _maybeAskSession() async {
    final c = widget.c;
    final now = c.clock();
    final today = DateTime(now.year, now.month, now.day);
    if (!mounted || _askedOn == today || !c.activeSessionIsFromAnotherDay) {
      return;
    }
    _askedOn = today;
    await askContinueOrNewSession(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final pages = [
      LiveScreen(c: c),
      HistoryScreen(c: c),
      ProfileScreen(c: c),
      PlayersScreen(c: c),
      SettingsScreen(c: c, auth: widget.auth, sync: widget.sync),
    ];
    const items = [
      (Icons.speed, 'En vivo'),
      (Icons.history, 'Historial'),
      (Icons.show_chart, 'Perfil'),
      (Icons.groups, 'Jugadores'),
      (Icons.settings, 'Ajustes'),
    ];
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height * 1.2;
    final body = IndexedStack(index: index, children: pages);
    if (landscape) {
      // En horizontal la altura es lo escaso: navegación en una columna lateral.
      return Scaffold(
        body: SafeArea(
          right: false,
          child: Row(
            children: [
              LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: index,
                        onDestinationSelected: (i) => setState(() => index = i),
                        labelType: NavigationRailLabelType.selected,
                        minWidth: 64,
                        groupAlignment: 0,
                        destinations: [
                          for (final (icon, label) in items)
                            NavigationRailDestination(
                              icon: Icon(icon),
                              label: Text(label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          for (final (icon, label) in items)
            NavigationDestination(icon: Icon(icon), label: label),
        ],
      ),
    );
  }
}
