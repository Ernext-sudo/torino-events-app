import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'models/models.dart';
import 'screens/calendar_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/swipe_screen.dart';
import 'services/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const TorinoEventsApp(),
    ),
  );
}

/// Palette "Torino di notte": blu profondo + giallo del gonfalone.
const kBg = Color(0xFF0C1220);
const kSurface = Color(0xFF16203A);
const kAccent = Color(0xFFFCA311);

class TorinoEventsApp extends StatelessWidget {
  const TorinoEventsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torino Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
          surface: kSurface,
        ),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kSurface,
          indicatorColor: kAccent.withOpacity(.25),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(['Scopri', 'Calendario', 'Fonti'][_tab],
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_tab < 2)
            IconButton(
              tooltip: 'Filtra categorie',
              icon: Badge(
                isLabelVisible: state.activeCategories.isNotEmpty,
                label: Text('${state.activeCategories.length}'),
                child: const Icon(Icons.tune),
              ),
              onPressed: () => _showFilterSheet(context),
            ),
          IconButton(
            tooltip: 'Aggiorna',
            icon: state.loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: state.loading ? null : state.refresh,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [SwipeScreen(), CalendarScreen(), SourcesScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'Scopri'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendario'),
          NavigationDestination(
              icon: Icon(Icons.rss_feed_outlined),
              selectedIcon: Icon(Icons.rss_feed),
              label: 'Fonti'),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      builder: (_) => Consumer<AppState>(
        builder: (context, state, __) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Categorie',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (state.activeCategories.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          state.activeCategories.clear();
                          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                          state.notifyListeners();
                        },
                        child: const Text('Mostra tutte'),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in categoryMeta.keys)
                      FilterChip(
                        label: Text(categoryLabel(c)),
                        selected: state.activeCategories.contains(c),
                        selectedColor: categoryColor(c).withOpacity(.35),
                        onSelected: (_) => state.toggleCategory(c),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
