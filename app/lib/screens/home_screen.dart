import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/fun_loading_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:table_calendar/table_calendar.dart';
import '../api_service.dart';
import '../storage_service.dart';
import '../token_crypto.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
import 'optimization_screen.dart';
import 'team_map_screen.dart';
import '../main.dart'; // for themeNotifier
import '../notification_service.dart';
import '../models/colleague.dart';
import '../models/booking_result.dart';
import '../widgets/colleague_selection_dialog.dart';

class HomeScreen extends StatefulWidget {
  final StorageService? storageService;
  final RoomzApiService? apiService;

  const HomeScreen({
    super.key,
    this.storageService,
    this.apiService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final StorageService _storage = widget.storageService ?? StorageService();
  late final RoomzApiService _api = widget.apiService ?? RoomzApiService();

  List<int> _selectedDays = [];
  String? _workspaceName;
  bool _isLoading = true;
  bool _isCalendarBusy = false;
  bool _automationEnabled = false;
  bool _showAutomation = true;
  bool _showStats = true;

  bool _canExit = false;

  Map<String, int> _statsMap = {'manual': 0, 'auto': 0};


  // Calendar State
  DateTime _focusedDay = DateTime.now();
  Set<String> _requestedDates = {};
  Set<String> _bookedDates = {};
  Set<String> _ignoredDates = {};
  Map<String, String> _bookedElsewhereMap = {};
  Map<String, String> _occupiedByOthers = {};
  Map<String, String> _delegatedBookingsMap = {};

  // All-time historical bookings for stats
  Set<String> _allTimeBookedDates = {};
  Set<String> _allTimeElsewhereDates = {};

  final Map<int, String> _weekDays = {
    1: 'Lundi',
    2: 'Mardi',
    3: 'Mercredi',
    4: 'Jeudi',
    5: 'Vendredi',
  };

  // Settings State
  TimeOfDay _automationTime = const TimeOfDay(hour: 8, minute: 0);
  bool _notifySuccess = true;
  bool _notifyFailure = true;
  int _projectionsCount = 4;
  bool _hideWeekends = true;
  bool _pullToRefreshEnabled = true; // Actif par défaut
  List<DateTimeRange> _vacations = [];

  bool _compactMode = false;
  bool _showAllReservations = true;
  bool _showDelegatedReservations = true;
  final ValueNotifier<String> _loadingTextNotifier = ValueNotifier("Démarrage d'AutoRoomzio...");
  int _currentIndex = 0;

  bool _isVacation(DateTime date) {
    if (!_showAutomation) return false;
    final d = DateTime(date.year, date.month, date.day);
    for (final v in _vacations) {
      final start = DateTime(v.start.year, v.start.month, v.start.day);
      final end = DateTime(v.end.year, v.end.month, v.end.day);
      if (!d.isBefore(start) && !d.isAfter(end)) return true;
    }
    return false;
  }

  void _showTopToast(String message, {bool isError = false, bool isSuccess = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars(); // Cancels previous to avoid infinite queue
    
    // On affiche l'alerte en bas, juste au-dessus de la barre de navigation

    Color bgColor = Theme.of(context).colorScheme.inverseSurface;
    Color textColor = Theme.of(context).colorScheme.onInverseSurface;
    IconData icon = Icons.info_outline;
    
    if (isError) {
      bgColor = Colors.red.shade600;
      textColor = Colors.white;
      icon = Icons.error_outline;
    } else if (isSuccess) {
      bgColor = Colors.green.shade600;
      textColor = Colors.white;
      icon = Icons.check_circle_outline;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkUpdatesOnStartup();
    _checkAuthAndLoad();
  }

  static bool _urlTokenProcessed = false;

  Future<void> _checkAuthAndLoad() async {
    if (kIsWeb && !_urlTokenProcessed) {
      final tokenInUrl = Uri.base.queryParameters['token'];
      if (tokenInUrl != null && tokenInUrl.isNotEmpty) {
        _urlTokenProcessed = true;
        // Force processing the new context from the URL
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
              settings: const RouteSettings(name: '/'),
            ),
          );
        }
        return;
      }
    }

    final token = await _storage.getRefreshToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation1, animation2) => const LoginScreen(),
            settings: const RouteSettings(name: '/'),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      }
      return;
    }
    
    // Authenticated -> load data
    await _loadData();
  }

  void _openTeamMap({DateTime? date}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamMapScreen(
          initialDate: date ?? _focusedDay,
          storageService: _storage,
          apiService: _api,
        ),
      ),
    );
  }

  void _openFavoritesManager() {
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    showDialog(
      context: context,
      builder: (_) => ColleagueSelectionDialog(
        date: todayStr,
        storageService: _storage,
        apiService: _api,
        isManagementMode: true,
      ),
    );
  }

  Future<void> _loadData() async {
    final days = await _storage.getDays();
    final name = await _storage.getWorkspaceName();
    final requested = await _storage.getRequestedDates();
    final booked = await _storage.getBookedDates();
    final ignored = await _storage.getIgnoredDates();
    final elsewhere = await _storage.getBookedElsewhereDates();
    final autoEnabled = await _storage.getAutomationEnabled();
    final autoTimeMap = await _storage.getAutomationTime();
    final showAuto = await _storage.getShowAutomation();
    final showStats = await _storage.getShowStats();
    final notifSuccess = await _storage.getNotifySuccess();
    final notifFailure = await _storage.getNotifyFailure();
    final projCount = await _storage.getProjectionsCount();
    final initialTab = await _storage.getInitialTab();
    final hideWe = await _storage.getHideWeekends();
    final vacs = await _storage.getVacations();
    final comp = await _storage.getCompactMode();
    final allTimeBooked = await _storage.getAllTimeBookedDates();
    final allTimeElsewhere = await _storage.getAllTimeElsewhereDates();
    final delegated = await _storage.getDelegatedBookingsMap();
    
    if (mounted) {
      setState(() {
        _selectedDays = days;
        _workspaceName = name;
        _requestedDates = requested.toSet();
        _bookedDates = booked.toSet();
        _ignoredDates = ignored.toSet();
        _bookedElsewhereMap = {for (var d in elsewhere) d: "Ailleurs"};
        _delegatedBookingsMap = delegated;
        _allTimeBookedDates = allTimeBooked.toSet();
        _allTimeElsewhereDates = allTimeElsewhere.toSet();
        _automationEnabled = autoEnabled;
      _showAutomation = showAuto;
      _showStats = showStats;
        _automationTime = TimeOfDay(hour: autoTimeMap['hour']!, minute: autoTimeMap['minute']!);
        _notifySuccess = notifSuccess;
        _notifyFailure = notifFailure;
        _projectionsCount = projCount;
        _hideWeekends = hideWe;
          _vacations = vacs.map((v) => DateTimeRange(
          start: DateTime.parse(v['start']!),
          end: DateTime.parse(v['end']!),
        )).toList()..sort((a, b) => a.start.compareTo(b.start));
        _compactMode = comp;
        if (_currentIndex == 0 && initialTab != 0) {
          _currentIndex = initialTab;
                    }
      });
    }

    // Load stats lazily in background
    _refreshStats();

    // Fetch latest bookings from API every time
    await _syncCalendar();
    

    await _checkPermissionsStatus();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  int _permissionStatus = 0;

  Future<void> _checkPermissionsStatus() async {
    if (!(!kIsWeb && Platform.isAndroid)) return;
    final batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;
    bool autostart = await _storage.getAutostartVerified();

    if (autostart && _automationEnabled) {
      final lastRun = await _storage.getLastAutomationRun();
      if (lastRun != null) {
        final hoursSinceLastRun = DateTime.now().difference(lastRun).inHours;
        if (hoursSinceLastRun > 48) {
          autostart = false;
          await _storage.saveAutostartVerified(false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('L\'automatisation semble avoir été bloquée par le système en arrière-plan. Veuillez vérifier l\'autostart.'),
                backgroundColor: Colors.redAccent,
              )
            );
          }
        }
      }
    }

    int okCount = 0;
    if (batteryOpt) okCount++;
    if (notif) okCount++;
    if (autostart) okCount++;

    if (mounted) {
      setState(() {
        if (okCount == 3) {
          _permissionStatus = 1;
        } else if (okCount > 0) {
          _permissionStatus = 2;
        } else {
          _permissionStatus = 3;
        }
      });
    }
  }

  Future<void> _toggleAutomation(bool val) async {
    if (val && _selectedDays.isEmpty) {
      _showTopToast('Veuillez sélectionner au moins un jour récurrent.', isError: true);
      return;
    }
    
    setState(() => _automationEnabled = val);
    await _storage.saveAutomationEnabled(val);

    if (val) {
      if ((!kIsWeb && Platform.isAndroid)) {
        final hasSeen = await _storage.getHasSeenOptimization();
        if (!hasSeen && mounted) {
          await _storage.saveHasSeenOptimization(true);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OptimizationScreen()),
          ).then((_) => _checkPermissionsStatus());
        }

        final now = DateTime.now();
        var targetDate = DateTime(now.year, now.month, now.day, _automationTime.hour, _automationTime.minute);
        if (targetDate.isBefore(now)) {
          targetDate = targetDate.add(const Duration(days: 1));
        }
        final delay = targetDate.difference(now);

        Workmanager().registerPeriodicTask(
          "1",
          "autoReservationTask",
          frequency: const Duration(hours: 24),
          initialDelay: delay,
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.connected),
        );

        
      }
      if (mounted) {
        _showTopToast('Automatisation activée', isSuccess: true);
      }
    } else {
      if ((!kIsWeb && Platform.isAndroid)) {
        Workmanager().cancelAll();
      }
      if (mounted) {
        _showTopToast('Automatisation désactivée');
      }
    }
  }


  void _onDayToggled(int day, bool selected) {
    setState(() {
      if (selected) {
        _selectedDays.add(day);
        _selectedDays.sort();
      } else {
        _selectedDays.remove(day);
        if (_selectedDays.isEmpty && _automationEnabled) {
          _automationEnabled = false;
          _storage.saveAutomationEnabled(false);
          _showTopToast('Automatisation désactivée (aucun jour sélectionné)');
        }
      }
    });
    _storage.saveDays(_selectedDays);
  }

  Future<void> _changeWorkspace() async {
    final token = await _api.refreshMyToken();
    if (!mounted) return;
    if (token == null) {
      _showTopToast('Impossible d\'actualiser la session. Veuillez vérifier votre connexion.', isError: true);
      return;
    }
    final didChange = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SetupScreen(accessToken: token)),
    );

    if (didChange == true) {
      // Réinitialiser les dates liées à l'ancien bureau
      setState(() {
        _bookedDates = {};
        _requestedDates = {};
        _ignoredDates = {};
        _bookedElsewhereMap = {};
        _workspaceName = null;
      });
      await _storage.saveBookedDates([]);
      await _storage.saveRequestedDates([]);
      await _storage.saveIgnoredDates([]);
      await _storage.saveBookedElsewhereDates([]);
      await _storage.saveLastSyncTime(forceReset: true); // bypass cache
      await _loadData();
    }
  }


  void _showWebPairing() async {
    final token = await _storage.getRefreshToken();
    if (token == null) return;
    
    final bId = await _storage.getBuildingId() ?? '';
    final fId = await _storage.getFloorId() ?? '';
    final wId = await _storage.getWorkspaceId() ?? '';
    
    final encryptedToken = TokenCryptoService.encryptToken(token);
    final encoded = Uri.encodeComponent(encryptedToken);
    final wName = Uri.encodeComponent(await _storage.getWorkspaceName() ?? '');
    
    final baseUrl = kReleaseMode 
        ? 'https://xris65.github.io/AutoRoomzio/' 
        : 'https://xris65.github.io/AutoRoomzio/recette/';
    final url = '$baseUrl?token=$encoded&b=$bId&f=$fId&w=$wId&wn=$wName';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connecter un appareil Web'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scannez ce QR Code avec l\'appareil photo de votre smartphone pour vous connecter automatiquement sur la version Web.\n\nVous pouvez aussi l\'ouvrir directement sur ce PC :'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Attention : se connecter sur le Web va interrompre la session de cette application. Vous serez déconnecté ici une fois le jeton utilisé.',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ouvrir le lien'),
                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copier le lien',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié dans le presse-papiers')));
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _storage.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(ignoreUrlToken: true),
        settings: const RouteSettings(name: '/'),
      ),
      (route) => false,
    );
  }

  Future<void> _resetWorkspace() async {
    await _storage.resetWorkspace();
    setState(() {
      _workspaceName = null;
    });
  }


  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = Scaffold(body: FunLoadingWidget(messageNotifier: _loadingTextNotifier));
    } else {
      content = Scaffold(
        appBar: AppBar(
          title: const Text('AutoRoomzio'),
          actions: [
            if ((!kIsWeb && Platform.isAndroid) && _automationEnabled)
              IconButton(
                icon: Icon(
                  Icons.shield_rounded, 
                  color: _permissionStatus == 1 ? Colors.green : (_permissionStatus == 2 ? Colors.orange : Colors.red.shade300)
                ),
                tooltip: 'Statut des permissions',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OptimizationScreen()),
                  ).then((_) => _checkPermissionsStatus());
                },
              ),
            if (!kIsWeb)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Lier un appareil Web',
                onPressed: _showWebPairing,
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: _logout,
            ),
          ],
        ),
        body: Builder(
          builder: (context) {
            final List<Map<String, dynamic>> tabs = [
              {'id': 'home', 'icon': Icons.home_rounded, 'label': 'Accueil', 'widget': _buildHomeTab()},
              {'id': 'calendar', 'icon': Icons.calendar_month_rounded, 'label': 'Calendrier', 'widget': _buildCalendarTab()},
              if (_showAutomation && !kIsWeb) {'id': 'auto', 'icon': Icons.auto_awesome, 'label': 'Automate', 'widget': _buildAutomationTab()},
              if (_showStats) {'id': 'stats', 'icon': Icons.insights_rounded, 'label': 'Stats', 'widget': _buildStatsTab()},
              {'id': 'settings', 'icon': Icons.settings_rounded, 'label': 'Paramètres', 'widget': _buildSettingsTab()},
            ];

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity == null) return;
                  if (details.primaryVelocity! > 300) {
                    if (_currentIndex > 0) setState(() => _currentIndex--);
                  } else if (details.primaryVelocity! < -300) {
                    if (_currentIndex < tabs.length - 1) setState(() => _currentIndex++);
                  }
                },
                child: SizedBox.expand(child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04), // slight slide up
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(tabs[_currentIndex]['id']),
                  child: tabs[_currentIndex]['widget'] as Widget,
                ),
              ),
              ),
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
                ),
                child: SafeArea(
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      children: List.generate(tabs.length, (index) {
                        return _buildNavItem(index, tabs[index]['icon'] as IconData, tabs[index]['label'] as String);
                      }),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return PopScope(
      canPop: _canExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        setState(() { _canExit = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Appuyez à nouveau pour quitter"),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              duration: Duration(seconds: 2),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() { _canExit = false; });
        });
      },
      child: content,
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (index == _currentIndex) return;
              setState(() => _currentIndex = index);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  
  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 3,
        itemBuilder: (_, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapWithPtr(Widget child) {
    if (_pullToRefreshEnabled) {
      return RefreshIndicator(
        onRefresh: _syncCalendar,
        child: child,
      );
    }
    return child;
  }

  Widget _buildHomeTab() {
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isCalendarBusy,
          child: Opacity(
            opacity: _isCalendarBusy ? 0.5 : 1.0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _wrapWithPtr(
                  SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 32), // -32 for padding (16*2)
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  if (_showAutomation && _vacations.any((v) => DateTime.now().isAfter(v.start.subtract(const Duration(days: 1))) && DateTime.now().isBefore(v.end.add(const Duration(days: 1)))))
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.beach_access, color: Colors.orange),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Mode Congés activé. L'automatisation est en pause sur cette date.",
                                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                  // ── Current workspace card ───────────────────────────────────
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _changeWorkspace,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.desk, color: Colors.lightBlue, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Bureau sélectionné', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _workspaceName ?? 'Aucun bureau configuré',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _workspaceName != null ? Theme.of(context).colorScheme.onSurface : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_workspaceName != null)
                              IconButton(
                                icon: const Icon(Icons.clear, color: Colors.red),
                                tooltip: 'Réinitialiser',
                                onPressed: _resetWorkspace,
                              )
                            else
                              const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_workspaceName != null) ...[
                      // ⚡ Actions Rapides
                      Builder(
                        builder: (context) {
                          final today = DateTime.now();
                          final tomorrow = today.add(const Duration(days: 1));
                          final todayIsWeekend = today.weekday == DateTime.saturday || today.weekday == DateTime.sunday;
                          final tomorrowIsWeekend = tomorrow.weekday == DateTime.saturday || tomorrow.weekday == DateTime.sunday;

                          final todayIsVacation = _isVacation(today);
                          final tomorrowIsVacation = _isVacation(tomorrow);

                          final disableToday = todayIsVacation || (_hideWeekends && todayIsWeekend);
                          final disableTomorrow = tomorrowIsVacation || (_hideWeekends && tomorrowIsWeekend);

                          return Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                  icon: Icon(todayIsVacation ? Icons.beach_access : (disableToday ? Icons.weekend : Icons.flash_on), size: 16),
                                  label: Text(todayIsVacation ? 'En Congés' : (disableToday ? 'Aujourd\'hui (Week-end)' : 'Aujourd\'hui'), style: const TextStyle(fontSize: 11)),
                                  onPressed: disableToday ? null : () => _quickBook(0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                  icon: Icon(tomorrowIsVacation ? Icons.beach_access : (disableTomorrow ? Icons.weekend : Icons.flash_on), size: 16),
                                  label: Text(tomorrowIsVacation ? 'En Congés' : (disableTomorrow ? 'Demain (Week-end)' : 'Demain'), style: const TextStyle(fontSize: 11)),
                                  onPressed: disableTomorrow ? null : () => _quickBook(1),
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openTeamMap(date: DateTime.now()),
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.people_outline, color: Colors.amber, size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Plan d\'équipe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text('Voir où sont assis vos collègues aujourd\'hui', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _openFavoritesManager,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Mes collègues favoris', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text('Rechercher et gérer vos collègues favoris', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📅 Prochaines réservations',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8.0,
                              children: [
                                FilterChip(
                                  label: const Text("Mes places", style: TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  selected: _showAllReservations,
                                  onSelected: (val) => setState(() => _showAllReservations = val),
                                ),
                                FilterChip(
                                  label: const Text("Délégations", style: TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  selected: _showDelegatedReservations,
                                  onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },
                                ),
                              ],
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      _isCalendarBusy ? _buildShimmerLoading() : _buildUpcomingBookings(),
                    ],
                    if (_workspaceName == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Configurez d\'abord votre bureau en cliquant sur la carte ci-dessus.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        },
        ),
        ),
        ),
        if (_isCalendarBusy)
          const Positioned(
            top: 0, left: 0, right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildAutomationTab() {
    if (_workspaceName == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Configurez d\'abord votre bureau dans l\'onglet Accueil pour utiliser l\'automatisation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isCalendarBusy,
          child: Opacity(
            opacity: _isCalendarBusy ? 0.5 : 1.0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Mode Congés ──────────────────────────────────────────────
                  Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ListTile(
                            leading: Icon(Icons.beach_access, color: Colors.orange),
                            title: Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('L\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                          ),
                          if (_vacations.isNotEmpty) const Divider(height: 1),
                          if (_showAutomation) ..._vacations.map((v) {
                            return ListTile(
                              dense: true,
                              title: Text('Du ${v.start.day}/${v.start.month}/${v.start.year} au ${v.end.day}/${v.end.month}/${v.end.year}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                onPressed: () {
                                  setState(() => _vacations.remove(v));
                                  _storage.saveVacations(_vacations.map((v) => {'start': v.start.toIso8601String(), 'end': v.end.toIso8601String()}).toList());
                                },
                              ),
                            );
                          }),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Ajouter une période'),
                              onPressed: () async {
                                final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                                DateTimeRange? picked;
                                bool userConfirmed = false;
                                var conflicts = <String>[];
                                var toCleanLocally = <String>[];
                                
                                while (!userConfirmed) {
                                  picked = await showDateRangePicker(
                                    context: context,
                                    firstDate: today,
                                    lastDate: today.add(const Duration(days: 365)),
                                    initialDateRange: picked,
                                    saveText: 'VALIDER',
                                  );
                                  
                                  if (picked == null) break; // User closed the date picker itself
                                  
                                  // AUTO-CANCEL bookings and requests in this new vacation period
                                  conflicts.clear();
                                  toCleanLocally.clear();
                                  for (var i = 0; i <= picked.end.difference(picked.start).inDays; i++) {
                                    final d = picked.start.add(Duration(days: i));
                                    final dateStr = d.toIso8601String().split('T').first;
                                    
                                    if (_requestedDates.contains(dateStr)) {
                                      toCleanLocally.add(dateStr);
                                    }
                                    
                                    if (_bookedDates.contains(dateStr) || 
                                        _bookedElsewhereMap.containsKey(dateStr)) {
                                      conflicts.add(dateStr);
                                      toCleanLocally.add(dateStr);
                                    }
                                  }
                                  
                                  if (conflicts.isNotEmpty) {
                                    final p = picked;
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Réservations existantes'),
                                        content: Text("Pour vos congés du ${p.start.day}/${p.start.month} au ${p.end.day}/${p.end.month}, vous avez des réservations confirmées :\n\n${conflicts.map((d) => '• $d').join('\n')}\n\nVoulez-vous ajouter ce congé et annuler automatiquement ces journées ?"),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('RECTIFIER'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('CONFIRMER'),
                                          ),
                                        ],
                                      ),
                                    );
                                    
                                    if (confirm == true) {
                                      userConfirmed = true;
                                    } else {
                                      // User clicked RECTIFIER. The while loop continues and re-opens the picker.
                                    }
                                  } else {
                                    userConfirmed = true;
                                  }
                                }
                                
                                if (picked != null && userConfirmed) {
                                  if (conflicts.isNotEmpty) {
                                    if (!mounted) return;
                                    final messenger = ScaffoldMessenger.of(context);
                                    messenger.showSnackBar(SnackBar(content: Text('Annulation de ${conflicts.length} journée(s)...')));
                                    
                                    final token = await _api.refreshMyToken();
                                    if (token != null) {
                                      await Future.wait(
                                        conflicts.map((dateStr) => _api.cancelBookingByDate(token, dateStr))
                                      );
                                    }
                                    
                                    if (toCleanLocally.isNotEmpty) {
                                      setState(() {
                                        for (final dateStr in toCleanLocally) {
                                          _bookedDates.remove(dateStr);
            _occupiedByOthers.remove(dateStr);
                                          _requestedDates.remove(dateStr);
                                          _bookedElsewhereMap.remove(dateStr);
                                        }
                                      });
                                      _storage.saveBookedDates(_bookedDates.toList());
                                      _storage.saveRequestedDates(_requestedDates.toList());
                                      _storage.saveBookedElsewhereDates(_bookedElsewhereMap.keys.toList());
                                    }
                                    
                                    messenger.showSnackBar(const SnackBar(content: Text('Journées libérées avec succès.')));
                                  }
                                  
                                  setState(() {
                                _vacations.add(picked!);
                                _vacations.sort((a, b) => a.start.compareTo(b.start));
                              });
                                  _storage.saveVacations(_vacations.map((v) => {'start': v.start.toIso8601String(), 'end': v.end.toIso8601String()}).toList());
                                }
                              },
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  
                  // ── Toggle Automatisation ────────────────────────────────────
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Automatisation', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Réserver automatiquement mes places', style: TextStyle(fontSize: 12)),
                          value: _automationEnabled,
                          onChanged: _toggleAutomation,
                          secondary: Icon(
                            _automationEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                            color: _automationEnabled ? Colors.green : Colors.grey,
                          ),
                        ),
                        if (_automationEnabled) const Divider(height: 1),
                        if (_automationEnabled)
                          ListTile(
                            leading: const Icon(Icons.schedule, color: Colors.blue),
                            title: const Text("Heure d'exécution"),
                            subtitle: const Text("Heure approximative à laquelle l'automatisation s'exécutera chaque jour", style: TextStyle(fontSize: 11)),
                            trailing: Text(_automationTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _automationTime,
                              );
                              if (time != null) {
                                setState(() => _automationTime = time);
                                await _storage.saveAutomationTime(time.hour, time.minute);
                                // Refresh the task with the new delay
                                _toggleAutomation(true);
                              }
                            },
                          ),
                        if (_automationEnabled) const Divider(height: 1),
                        if (_automationEnabled)
                          ListTile(
                            leading: const Icon(Icons.play_circle_fill, color: Colors.green),
                            title: const Text("Lancer maintenant"),
                            subtitle: const Text("Exécuter manuellement la routine tout de suite", style: TextStyle(fontSize: 11)),
                            onTap: _runAutomationNow,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Jours récurrents ─────────────────────────────────────────
                  const Text(
                    '📅 Jours de présence récurrents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Column(
                      children: _weekDays.entries.map((entry) {
                        return CheckboxListTile(
                          title: Text(entry.value),
                          value: _selectedDays.contains(entry.key),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onChanged: (bool? value) => _onDayToggled(entry.key, value ?? false),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isCalendarBusy)
          const Positioned(
            top: 0, left: 0, right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildUpcomingBookings() {
    List<Map<String, dynamic>> upcoming = [];
    final now = DateTime.now();
    int recurringProjectionsCount = 0;
    
    for (int i = 0; i < 60; i++) {
      final date = now.add(Duration(days: i));
      final dateStr = date.toIso8601String().split('T').first;
      
      if (_ignoredDates.contains(dateStr)) continue;
      
      bool isBooked = _bookedDates.contains(dateStr) && _showAllReservations;
        bool isRequested = _requestedDates.contains(dateStr) && _showAllReservations;
        bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
        bool isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
        String delegateName = "Quelqu'un";
        String delegateLocation = "";
        if (isDelegated) {
           final parts = _delegatedBookingsMap[dateStr]!.split('|');
           delegateName = parts.length > 1 ? parts[1] : parts[0];
           if (parts.length > 2) delegateLocation = parts[2];
        }
        bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);
        bool isRecurring = _automationEnabled && _selectedDays.contains(date.weekday) && _showAllReservations;
      if (_isVacation(date)) isRecurring = false;

      if (isDelegated) {
        upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": delegateName, "location": delegateLocation});
      }
      
        if (isElsewhere) {
          upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
        }
        if (isBooked) {
          upcoming.add({"date": date, "source": "Calendrier", "isBooked": true});
        } else if (isRequested) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": false});
      } else if (isOccupiedByOthers) {
        if (isRecurring && recurringProjectionsCount < _projectionsCount) {
          upcoming.add({"date": date, "source": "Occupé", "isBooked": false, "name": _occupiedByOthers[dateStr]});
          recurringProjectionsCount++;
        }
      } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
        upcoming.add({"date": date, "source": "Récurrent", "isBooked": false});
        recurringProjectionsCount++;
      }
    }

        if (upcoming.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Aucune réservation prévue.', style: TextStyle(color: Colors.grey)),
      );
    }

    final weekdays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

    return Column(
      children: upcoming.map((item) {
        final date = item['date'] as DateTime;
        final source = item['source'] as String;
        final isBooked = item['isBooked'] as bool;
        final weekDayName = weekdays[date.weekday - 1];

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ListTile(
            visualDensity: _compactMode ? VisualDensity.compact : null,
            contentPadding: _compactMode ? const EdgeInsets.symmetric(horizontal: 8, vertical: 0) : null,
                          leading: Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Icon(
                    source == 'Ailleurs' ? Icons.person : (source == 'Délégué' ? Icons.group : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending))),
                    color: source == 'Ailleurs' ? (isDark ? Colors.orange.shade300 : Colors.orange.shade900) : (source == 'Délégué' ? (isDark ? Colors.purple.shade300 : Colors.purple.shade900) : (source == 'Occupé' ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700) : (isBooked ? (isDark ? Colors.green.shade400 : Colors.green) : (isDark ? Colors.blue.shade300 : Colors.blue)))),
                  );
                }
              ),
              title: Text('$weekDayName ${date.day}/${date.month}'),
              subtitle: Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Text(
                    source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Délégué' ? 'Réservé pour ${item["name"]}' + (item["location"] != null && item["location"].toString().isNotEmpty ? ' (${item["location"]})' : '') : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)'))),
                    style: TextStyle(color: source == 'Ailleurs' ? (isDark ? Colors.orange.shade300 : Colors.orange.shade900) : (source == 'Délégué' ? (isDark ? Colors.purple.shade300 : Colors.purple.shade900) : (source == 'Occupé' ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700) : (isBooked ? (isDark ? Colors.green.shade400 : Colors.green) : (isDark ? Colors.blue.shade300 : Colors.blue)))), fontSize: _compactMode ? 10 : 12),
                  );
                }
              ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(source, style: const TextStyle(fontSize: 10)),
                  backgroundColor: source == 'Calendrier' 
                    ? Colors.purple.withValues(alpha: 0.1) 
                    : (source == 'Ailleurs' ? Colors.orange.withValues(alpha: 0.3) : (source == 'Délégué' ? Colors.purple.withValues(alpha: 0.3) : (source == 'Occupé' ? Colors.grey.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1)))),
                  visualDensity: VisualDensity.compact,
                ),
                if (source != 'Occupé')
                  IconButton(
                    icon: Icon(isBooked || source == 'Délégué' || source == 'Ailleurs' ? Icons.delete_outline : Icons.block, size: 20),
                      color: Colors.redAccent,
                      tooltip: isBooked || source == 'Délégué' || source == 'Ailleurs' ? 'Supprimer' : 'Bloquer',
                      onPressed: () => _quickAction(date, isBooked || source == 'Délégué' || source == 'Ailleurs', source),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarTab() {
    if (_workspaceName == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Configurez d\'abord votre bureau dans l\'onglet Accueil pour utiliser le calendrier.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return _wrapWithPtr(
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mon Calendrier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.star_rounded, color: Colors.amber),
                            tooltip: 'Mes collègues favoris',
                            onPressed: _openFavoritesManager,
                          ),
                          IconButton(
                            icon: const Icon(Icons.map_outlined),
                            tooltip: 'Plan d\'équipe (Où sont mes collègues ?)',
                            onPressed: () => _openTeamMap(date: _focusedDay),
                          ),
                          IconButton(
                            icon: const Icon(Icons.sync),
                            tooltip: 'Synchroniser avec MyRoomz',
                            onPressed: _syncCalendar,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8.0,
                    children: [
                      FilterChip(
                        label: const Text("Mes places"),
                        selected: _showAllReservations,
                        onSelected: (val) => setState(() => _showAllReservations = val),
                      ),
                      FilterChip(
                        label: const Text("Délégations"),
                        selected: _showDelegatedReservations,
                        onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },
                      ),
                    ],
                  ),
                ],
              ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              AbsorbPointer(
                absorbing: _isCalendarBusy,
                child: Opacity(
                  opacity: _isCalendarBusy ? 0.5 : 1.0,
                  child: TableCalendar(
                      availableGestures: AvailableGestures.horizontalSwipe,
                    enabledDayPredicate: (day) {
                      final normDay = DateTime(day.year, day.month, day.day);
                      if (_hideWeekends && (normDay.weekday == DateTime.saturday || normDay.weekday == DateTime.sunday)) {
                        return false;
                      }
                      if (_showAutomation) {
                        for (final v in _vacations) {
                          final start = DateTime(v.start.year, v.start.month, v.start.day);
                          final end = DateTime(v.end.year, v.end.month, v.end.day);
                          if (!normDay.isBefore(start) && !normDay.isAfter(end)) {
                            return false;
                          }
                        }
                      }
                      return true;
                    },
                    firstDay: DateTime.now().subtract(const Duration(days: 365)),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    rowHeight: _compactMode ? 42.0 : 52.0,
                    daysOfWeekHeight: _compactMode ? 20.0 : 24.0,
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Colors.lightBlue.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    onPageChanged: (focusedDay) {
                        _focusedDay = focusedDay;
                      },
                    onDaySelected: (selectedDay, focusedDay) {
                      _handleDateTap(selectedDay);
                    },
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) => _buildDayCell(day),
                      todayBuilder: (context, day, focusedDay) => _buildDayCell(day, isToday: true),
                      outsideBuilder: (context, day, focusedDay) => _buildDayCell(day, isOutside: true),
                    ),
                  ),
                ),
              ),
              if (_isCalendarBusy)
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Synchronisation...', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.all(16.0),
                        child: Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildLegend(isDark ? Colors.green.shade700 : Colors.green, 'Réservé'),
                    _buildLegend(isDark ? Colors.blue.shade700 : Colors.blue, 'En attente'),
                    _buildLegend(Colors.red.withValues(alpha: isDark ? 0.6 : 0.8), 'Bloqué'),
                    _buildLegend(isDark ? Colors.orange.shade800 : Colors.orange.shade300, 'Ailleurs'),
                    _buildLegend(isDark ? Colors.purple.shade800 : Colors.purple.shade200, 'Délégué'),
                  ],
                );
              }
            ),
          )
        ],
      ),
      ),
      ),
    );
    },
    );
  }

  Widget _buildDayCell(DateTime day, {bool isToday = false, bool isOutside = false}) {
    final dateStr = day.toIso8601String().split('T').first;
    final isBooked = _bookedDates.contains(dateStr) && _showAllReservations;
      final isRequested = _requestedDates.contains(dateStr) && _showAllReservations;
      final isIgnored = _ignoredDates.contains(dateStr) && _showAllReservations;
      final isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
      final isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
      final isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);

    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;
    bool strikeThrough = false;
    List<Color> dots = [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isBooked) {
      bgColor = isDark ? Colors.green.shade700 : Colors.green;
      textColor = Colors.white;
      if (isElsewhere) dots.add(isDark ? Colors.orange.shade300 : Colors.orange.shade400);
      if (isDelegated) dots.add(isDark ? Colors.purple.shade300 : Colors.purple.shade400);
    } else if (isElsewhere) {
      bgColor = isDark ? Colors.orange.shade800 : Colors.orange.shade200;
      textColor = isDark ? Colors.orange.shade100 : Colors.orange.shade900;
      if (isDelegated) dots.add(isDark ? Colors.purple.shade300 : Colors.purple.shade400);
    } else if (isDelegated) {
      bgColor = isDark ? Colors.purple.shade800 : Colors.purple.shade200;
      textColor = isDark ? Colors.purple.shade100 : Colors.purple.shade900;
    } else if (isRequested) {
      bgColor = isDark ? Colors.blue.shade700 : Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: isDark ? 0.6 : 0.8);
      textColor = Colors.white;
      strikeThrough = true;
    } else if (isOccupiedByOthers) {
      bgColor = isDark ? Colors.grey.shade700 : Colors.grey.shade400;
      textColor = isDark ? Colors.grey.shade200 : Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: isDark ? 0.2 : 0.3);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: isOccupiedByOthers
                ? Border.all(color: Colors.grey.shade400, width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontWeight: (isBooked || isRequested || isIgnored) ? FontWeight.bold : FontWeight.normal,
              decoration: strikeThrough ? TextDecoration.lineThrough : null,
              decorationColor: Colors.grey.shade500,
            ),
          ),
        ),
        // Multi-dot indicators at bottom of cell
        if (dots.isNotEmpty || isOccupiedByOthers)
          Positioned(
            bottom: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...dots.map((c) => Container(
                  width: 7, height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                )),
                if (isOccupiedByOthers)
                  Container(
                    width: 7, height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.orange.shade300 : Colors.orange.shade700,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Future<bool> _cancelDelegationAction(String dateStr) async {
    final token = await _api.refreshMyToken();
    final workspaceId = await _storage.getWorkspaceId();
    if (token == null || workspaceId == null) return false;
    
    final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
    final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
    final eventId = parts.length > 3 ? parts[3] : null;
    final orgId = parts.length > 4 ? parts[4] : null;
    if (!wsId.contains('-')) {
       if (mounted) _showTopToast('Veuillez d\'abord synchroniser le calendrier.', isError: true);
       return false;
    }
    
    final success = await _api.cancelReservation(dateStr, token, wsId, eventId: eventId, forUserId: orgId);
    if (success) {
      setState(() {
        _delegatedBookingsMap.remove(dateStr);
      });
      _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
      if (mounted) _showTopToast('La délégation a été annulée.', isSuccess: true);
      return true;
    } else {
      if (mounted) _showTopToast('Erreur lors de l\'annulation.', isError: true);
      return false;
    }
  }

  Future<void> _quickAction(DateTime day, bool isBooked, String source) async {
    final dateStr = day.toIso8601String().split('T').first;
    
    setState(() => _isCalendarBusy = true);
    try {
      if (source == 'Délégué') {
        await _cancelDelegationAction(dateStr);
        setState(() => _isCalendarBusy = false);
        return;
      }
      
      final token = await _api.refreshMyToken();
      final workspaceId = await _storage.getWorkspaceId();
      if (token == null || workspaceId == null) return;

      if (isBooked) {
        if (source == 'Ailleurs') {
          await _api.cancelBookingByDate(token, dateStr);
        } else {
          await _api.cancelReservation(dateStr, token, workspaceId);
        }
        
      }

      setState(() {
        if (isBooked) {
          if (source == 'Ailleurs') {
            _bookedElsewhereMap.remove(dateStr);
          } else {
            _bookedDates.remove(dateStr);
            _occupiedByOthers.remove(dateStr);
            _requestedDates.remove(dateStr);
          }
        } else {
          _ignoredDates.add(dateStr);
        }
      });

      _storage.saveRequestedDates(_requestedDates.toList());
      _storage.saveBookedDates(_bookedDates.toList());
      _storage.saveIgnoredDates(_ignoredDates.toList());
      
      if (mounted) {
        _showTopToast(isBooked ? 'Réservation supprimée' : 'Jour bloqué ($dateStr)');
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _runAutomationNow() async {
    setState(() => _isCalendarBusy = true);
    try {
      final token = await _api.refreshMyToken();
      final workspaceId = await _storage.getWorkspaceId();
      if (token == null || workspaceId == null) return;

      final now = DateTime.now();
      
      int addedCount = 0;
      for (int i = 1; i <= 13; i++) {
        final targetDate = now.add(Duration(days: i));
        final isWeekend = targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday;
        
        if (_hideWeekends && isWeekend) continue;
        if (_isVacation(targetDate)) continue;

        final dateStr = targetDate.toIso8601String().split('T').first;

        if (_ignoredDates.contains(dateStr) || _bookedDates.contains(dateStr)) continue;

        // Hotfix 6 Pre-flight Conflict Guards:
        // 1. Skip if user already has an active reservation elsewhere on that date
        if (_bookedElsewhereMap.containsKey(dateStr)) {
          debugPrint("📍 User already booked elsewhere on $dateStr, skipping automation.");
          continue;
        }

        // 2. Skip if user's target desk is already occupied by someone else on that date
        if (_occupiedByOthers.containsKey(dateStr)) {
          debugPrint("🔒 Target desk occupied by ${_occupiedByOthers[dateStr]} on $dateStr, skipping automation.");
          continue;
        }

        // If not ignored/booked and it's either already requested or a valid automation day
        if (_requestedDates.contains(dateStr) || _selectedDays.contains(targetDate.weekday)) {
          final success = await _api.reserveWorkspace(dateStr, token, workspaceId);
          if (success) {
            _bookedDates.add(dateStr);
            await _storage.recordBookingStat(true);
            await _refreshStats();
            addedCount++;
          }
        }
      }
      
      if (addedCount > 0) {
        setState(() {}); // refresh UI
        _storage.saveBookedDates(_bookedDates.toList());
      }
      
      if (mounted) {
        _showTopToast(
          addedCount > 0 
            ? '$addedCount réservation(s) ajoutée(s) !' 
            : 'Le planning est déjà à jour (aucune nouvelle place réservable)',
          isSuccess: addedCount > 0
        );
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }


  Future<void> _refreshStats() async {
    final stats = await _storage.getBookingStats();
    if (mounted) {
      setState(() {
        _statsMap = stats;
      });
    }
  }

  Future<void> _syncCalendar() async {
    if (_isCalendarBusy) return;

    final workspaceId = await _storage.getWorkspaceId();
    final floorId = await _storage.getFloorId();

    if (workspaceId == null || floorId == null) {
      return;
    }

    setState(() => _isCalendarBusy = true);

    try {
      if (_isLoading) _loadingTextNotifier.value = "Connexion aux serveurs MyRoomz...";
      final accessToken = await _api.refreshMyToken();
      if (accessToken == null) return;

      if (_isLoading) _loadingTextNotifier.value = "Vérification de la configuration du bureau...";
      
      // We check requested dates + the next horizon days (including weekends, so they can be displayed if booked externally)
      Set<String> datesToCheck = Set.from(_requestedDates);
      final now = DateTime.now();
      for (int i = 0; i <= 13; i++) {
        final d = now.add(Duration(days: i));
        datesToCheck.add(d.toIso8601String().split('T').first);
      }

      if (_isLoading) _loadingTextNotifier.value = "Récupération de vos réservations...";

      // Fetch the user's specific bookings — here (this desk) + elsewhere (other desks)
            if (_isLoading) _loadingTextNotifier.value = "Récupération de l'occupation du bureau...";
      
      // La réservation manuelle par d'autres est limitée à J+13. On ne vérifie que cette période !
      List<String> visibleDates = [];
      final today = DateTime.now();
      for (int i = 0; i <= 13; i++) {
        final d = today.add(Duration(days: i));
        if (_hideWeekends && (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) continue;
        visibleDates.add(d.toIso8601String().split('T').first);
      }
      
      final floorId = await _storage.getFloorId();
              final myBookings = await _api.getMyReservations(accessToken, workspaceId);
        final myUserId = myBookings.myUserId ?? await _api.getCurrentUserId(accessToken);
        
                final occResult = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates, myUserId, myBookings.elsewhere) : (occupiedByOthers: <String, String>{}, delegatedBookings: <String, String>{}, delegatedHere: <String>{}, delegatedElsewhere: <String>{});
        final occupiedDates = occResult.occupiedByOthers;
        // Use myBookings.delegated as source of truth — it comes from /users/current/bookings
        // which has the real workspaceName. Format: "organizerName (wsName)"
        // We merge with occResult.delegatedBookings for dates not covered by myBookings
        final mergedDelegated = Map<String, String>.from(occResult.delegatedBookings);
        myBookings.delegated.forEach((date, value) => mergedDelegated[date] = value);
        _delegatedBookingsMap = mergedDelegated;
        
        final bookedHere = myBookings.here;
        final bookedElsewhere = myBookings.elsewhere;
        
        for (final d in occResult.delegatedHere) {
           bookedHere.remove(d);
        }
        for (final d in occResult.delegatedElsewhere) {
           bookedElsewhere.remove(d);
        }

        _allTimeBookedDates.addAll(bookedHere);
        _allTimeElsewhereDates.addAll(bookedElsewhere.keys);
        await _storage.saveAllTimeBookedDates(_allTimeBookedDates.toList());
        await _storage.saveAllTimeElsewhereDates(_allTimeElsewhereDates.toList());

      Set<String> newBookedDates = {};
      Set<String> newRequestedDates = Set.from(_requestedDates);
      Set<String> newIgnoredDates = Set.from(_ignoredDates);

      for (final dateStr in datesToCheck) {
        if (bookedHere.contains(dateStr)) {
          newBookedDates.add(dateStr);
          newRequestedDates.add(dateStr);
          newIgnoredDates.remove(dateStr);
        } else if (bookedElsewhere.containsKey(dateStr)) {
          // Already booked elsewhere this day — remove from requested (can't double-book)
          newRequestedDates.remove(dateStr);
        } else {
          if (_bookedDates.contains(dateStr)) {
            newRequestedDates.remove(dateStr);
          }
        }
      }

      if (_isLoading) {
        _loadingTextNotifier.value = "On y est presque !";
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      if (mounted) {
        setState(() {
          _bookedDates = newBookedDates;
          _requestedDates = newRequestedDates;
          _ignoredDates = newIgnoredDates;
          _bookedElsewhereMap = bookedElsewhere; // reuse field for "booked elsewhere by me"
        });
          setState(() { _occupiedByOthers = occupiedDates; });
        _storage.saveBookedDates(_bookedDates.toList());
        _storage.saveRequestedDates(_requestedDates.toList());
        _storage.saveIgnoredDates(_ignoredDates.toList());
        _storage.saveBookedElsewhereDates(_bookedElsewhereMap.keys.toList());
        _storage.saveLastSyncTime(); // Cache TTL
          await _refreshStats();
        }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _quickBook(int daysOffset) async {
    if (_isCalendarBusy) return;
    
    final targetDate = DateTime.now().add(Duration(days: daysOffset));
    if (_hideWeekends && (targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday)) {
      _showTopToast('Réservation le week-end désactivée.');
      return;
    }

    final dateStr = targetDate.toIso8601String().split('T').first;
    if (_bookedDates.contains(dateStr)) {
      _showTopToast('Déjà réservé !');
      return;
    }

    final workspaceId = await _storage.getWorkspaceId();
    if (workspaceId == null) return;

    setState(() => _isCalendarBusy = true);
    try {
      final token = await _api.refreshMyToken();
      if (token == null) return;
      
      final success = await _api.reserveWorkspace(dateStr, token, workspaceId);
      if (success) {
        await _storage.recordBookingStat(false);
              await _refreshStats();
        setState(() {
          _bookedDates.add(dateStr);
          _requestedDates.add(dateStr);
          _ignoredDates.remove(dateStr);
        });
        _storage.saveBookedDates(_bookedDates.toList());
        _storage.saveRequestedDates(_requestedDates.toList());
        _storage.saveIgnoredDates(_ignoredDates.toList());
        _showTopToast('Bureau réservé pour ${daysOffset == 0 ? "aujourd'hui" : "demain"} !', isSuccess: true);
      } else {
        _showTopToast('Échec de la réservation.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }


  Future<void> _handleDateTap(DateTime selectedDay) async {
    if (_isCalendarBusy) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    
    if (day.isBefore(today)) {
      _showTopToast('Impossible de modifier le passé.');
      return;
    }

    final dateStr = day.toIso8601String().split('T').first;
    final isBooked = _bookedDates.contains(dateStr) && _showAllReservations;
      final isRequested = _requestedDates.contains(dateStr) && _showAllReservations;
      final isIgnored = _ignoredDates.contains(dateStr) && _showAllReservations;
      final isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
      final isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
      final bool deskOccupiedByThirdParty = _occupiedByOthers.containsKey(dateStr);
      final differenceInDays = day.difference(today).inDays;
    final isBookableNow = differenceInDays <= 13;

    final isWeekendAndHidden = _hideWeekends && (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday);

    final dParts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
    final dName = dParts.length > 1 ? dParts[1] : 'votre collègue';
    final dLoc = dParts.length > 2 ? dParts[2] : '';
    
    final myWsId = await _storage.getWorkspaceId();
    final isDelegatedOnMyDesk = isDelegated && dParts.isNotEmpty && dParts[0] == myWsId;

    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Gestion du $dateStr', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
                  if (isDelegated)
                    ListTile(
                      leading: Icon(Icons.group_off, color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900),
                      title: Text('Annuler la délégation', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text("Annule la réservation faite pour $dName" + (dLoc.isNotEmpty ? " sur $dLoc" : "") + " ce jour-là.", style: const TextStyle(fontSize: 11)),
                      onTap: () => Navigator.pop(context, 'cancel_delegation'),
                      ),
              if (!isBooked && !isRequested)
                if (deskOccupiedByThirdParty)
                  ListTile(
                    leading: const Icon(Icons.person_off, color: Colors.grey),
                    title: const Text('Place indisponible', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text("Réservé par ${_occupiedByOthers[dateStr]}.", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  )
                else if (isWeekendAndHidden)
                  const ListTile(
                    leading: Icon(Icons.weekend, color: Colors.grey),
                    title: Text('Les nouvelles réservations le week-end sont désactivées.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else if (isElsewhere)
                  ListTile(
                    leading: Icon(Icons.person_off, color: Colors.orange.shade900),
                    title: Text('Libérer mon autre bureau (${_bookedElsewhereMap[dateStr] ?? "Ailleurs"})', style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text("Annule la réservation que vous avez faite sur cet autre bureau ce jour-là.", style: TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(context, 'cancel_elsewhere'),
                  )
                else if (isDelegatedOnMyDesk)
                  const SizedBox.shrink()

                else if (!kIsWeb || isBookableNow)
                  ListTile(
                    leading: Icon(
                      isBookableNow ? Icons.check_circle_outline : Icons.pending_actions,
                      color: isBookableNow ? Colors.green : Colors.blue
                    ),
                    title: Text(isBookableNow ? 'Réserver ce jour' : 'Programmer (En attente)'),
                    onTap: () => Navigator.pop(context, 'reserve'),
                  ),
              if (!isBooked && !isDelegated && !deskOccupiedByThirdParty && !isWeekendAndHidden && isBookableNow)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.purple.shade900.withValues(alpha: 0.4)
                          : Colors.purple.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.group_add_outlined,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.purple.shade300
                          : Colors.purple.shade800,
                    ),
                  ),
                  title: const Text('Réserver pour un collègue', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Sélectionner parmi vos favoris ou rechercher'),
                  onTap: () => Navigator.pop(context, 'reserve_for_colleague'),
                ),
              if (isBooked || isRequested)
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text(isBooked ? 'Libérer la place' : 'Annuler la demande'),
                  onTap: () => Navigator.pop(context, 'cancel'),
                ),
              if (!kIsWeb && !isIgnored && !isWeekendAndHidden && !isElsewhere)
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: const Text('Bloquer (Ignorer l\'automatisation)'),
                  onTap: () => Navigator.pop(context, 'block'),
                ),
              if (!kIsWeb && isIgnored && !isWeekendAndHidden)
                ListTile(
                  leading: const Icon(Icons.lock_open, color: Colors.green),
                  title: const Text('Débloquer ce jour'),
                  onTap: () => Navigator.pop(context, 'unblock'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }
    );

    if (action == null) return;

    if (action == 'reserve_for_colleague') {
      if (!mounted) return;
      final colleague = await showDialog<Colleague>(
        context: context,
        builder: (context) => ColleagueSelectionDialog(
          date: dateStr,
          deskName: _workspaceName,
          apiService: _api,
          storageService: _storage,
        ),
      );

      if (colleague != null) {
        setState(() {
          _isCalendarBusy = true;
          _focusedDay = day;
        });

        try {
          final token = await _api.refreshMyToken();
          final workspaceId = await _storage.getWorkspaceId();
          if (token != null && workspaceId != null) {
            final result = await _api.reserveWorkspaceForColleague(
              date: dateStr,
              token: token,
              workspaceId: workspaceId,
              colleagueId: colleague.id,
              colleagueName: colleague.name,
              colleagueEmail: colleague.email,
            );

            if (result.status == BookingStatus.unauthorized) {
              if (mounted) {
                _showTopToast('Session expirée. Veuillez vous reconnecter.', isError: true);
                _logout();
              }
            } else if (result.isSuccess) {
              final eventId = result.eventId ?? '';
              _delegatedBookingsMap[dateStr] =
                  '$workspaceId|${colleague.name}|${_workspaceName ?? ""}|$eventId|${colleague.id}';
              await _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
              _requestedDates.remove(dateStr);
              await _storage.saveRequestedDates(_requestedDates.toList());
              setState(() {});
              if (mounted) {
                _showTopToast(result.getLocalizedMessage(colleague.name), isSuccess: true);
              }
            } else {
              if (mounted) {
                _showTopToast(result.getLocalizedMessage(colleague.name), isError: true);
              }
            }
          } else {
            if (mounted) {
              _showTopToast('Action impossible : serveur temporairement indisponible.', isError: true);
            }
          }
        } catch (e) {
          if (mounted) {
            _showTopToast('Erreur lors de la réservation : $e', isError: true);
          }
        } finally {
          if (mounted) setState(() => _isCalendarBusy = false);
        }
      }
      return;
    }

    setState(() {
      _isCalendarBusy = true;
      _focusedDay = day;
    });

    try {
      if (action == 'reserve') {
          if (_bookedDates.contains(dateStr) || _bookedElsewhereMap.containsKey(dateStr)) {
            if (mounted) _showTopToast('Place déjà réservée (filtre désactivé)', isError: true);
            return;
          }
        setState(() {
          _ignoredDates.remove(dateStr);
          _requestedDates.add(dateStr);
        });
        _storage.saveRequestedDates(_requestedDates.toList());
        _storage.saveIgnoredDates(_ignoredDates.toList());

        if (isBookableNow) {
          final accessToken = await _api.refreshMyToken();
          final workspaceId = await _storage.getWorkspaceId();
          if (accessToken != null && workspaceId != null) {
            final success = await _api.reserveWorkspace(dateStr, accessToken, workspaceId);
            if (success) {
              await _storage.recordBookingStat(false);
              await _refreshStats();
              setState(() {
                _bookedDates.add(dateStr);
                _allTimeBookedDates.add(dateStr);
              });
              _storage.saveBookedDates(_bookedDates.toList());
              _storage.saveAllTimeBookedDates(_allTimeBookedDates.toList());
              if (mounted) _showTopToast('Place réservée pour le $dateStr', isSuccess: true);
            } else {
              if (mounted) _showTopToast('Ce bureau n\'est plus disponible à cette date', isError: true);
            }
          } else if (accessToken == null) {
            if (mounted) {
              _showTopToast('Action impossible : serveur temporairement indisponible.', isError: true);
            }
          }
        }
      } else if (action == 'cancel' || action == 'block') {
        if (isBooked) {
          final token = await _api.refreshMyToken();
          final workspaceId = await _storage.getWorkspaceId();
          if (token != null && workspaceId != null) {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
        }
        setState(() {
          _requestedDates.remove(dateStr);
          _bookedDates.remove(dateStr);
          _allTimeBookedDates.remove(dateStr);
          _occupiedByOthers.remove(dateStr);
          if (action == 'block') {
            _ignoredDates.add(dateStr);
          }
        });
        _storage.saveRequestedDates(_requestedDates.toList());
        _storage.saveBookedDates(_bookedDates.toList());
        _storage.saveAllTimeBookedDates(_allTimeBookedDates.toList());
        _storage.saveIgnoredDates(_ignoredDates.toList());
      } else if (action == 'cancel_delegation') {
        await _cancelDelegationAction(dateStr);
      } else if (action == 'cancel_elsewhere') {
        final token = await _api.refreshMyToken();
        if (token != null) {
          final success = await _api.cancelBookingByDate(token, dateStr);
          if (success) {
            setState(() {
               _bookedElsewhereMap.remove(dateStr);
               _allTimeElsewhereDates.remove(dateStr);
            });
            _storage.saveBookedElsewhereDates(_bookedElsewhereMap.keys.toList());
            _storage.saveAllTimeElsewhereDates(_allTimeElsewhereDates.toList());
            if (mounted) _showTopToast('Votre réservation a été annulée.', isSuccess: true);
          } else {
            if (mounted) _showTopToast('Impossible d\'annuler la réservation.', isError: true);
          }
        }
      } else if (action == 'unblock') {
        setState(() => _ignoredDates.remove(dateStr));
        _storage.saveIgnoredDates(_ignoredDates.toList());
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Widget _buildStyledDropdown<T>({
    required T value,
    required void Function(T?) onChanged,
    required List<DropdownMenuItem<T>> items,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, size: 24),
          focusColor: Colors.transparent,
          dropdownColor: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          onChanged: onChanged,
          items: items,
        ),
      ),
    );
  }


  Widget _buildStatsTab() {
    final manualCount = _statsMap['manual'] ?? 0;
    final autoCount = _statsMap['auto'] ?? 0;

    // Real upcoming bookings from active API state (today and future)
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final upcomingHere = _bookedDates.where((d) => d.compareTo(todayStr) >= 0).toSet();
    final upcomingElsewhere = _bookedElsewhereMap.keys.where((d) => d.compareTo(todayStr) >= 0).toSet();
    final totalUpcoming = upcomingHere.length + upcomingElsewhere.length;

    // Favorite desk loyalty ratio based on active upcoming bookings
    final int favLoyaltyRatio = totalUpcoming > 0
        ? ((upcomingHere.length / totalUpcoming) * 100).round()
        : 100;

    // Configured attendance rhythm (selected days per week)
    final sortedDays = List<int>.from(_selectedDays)..sort();
    final rhythmDaysStr = sortedDays
        .map((d) => _weekDays[d] ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final rhythmValue = _selectedDays.isEmpty
        ? 'Non configuré'
        : '${_selectedDays.length} jour${_selectedDays.length > 1 ? 's' : ''} / sem.';
    final rhythmSubtitle = _selectedDays.isEmpty
        ? 'Définissez vos jours dans l\'onglet Automate'
        : rhythmDaysStr;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Vos Statistiques',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'L\'impact de l\'automatisation sur votre quotidien',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 24),

        // Grid de stats
        Center(
          child: Text(
            'Cliquez sur une carte pour plus de détails',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.80,
          children: [
            // Card 1: Upcoming bookings count
            _buildStatCard(
              title: 'Réservations à venir',
              value: '$totalUpcoming',
              subtitle: totalUpcoming > 0
                  ? '${upcomingHere.length} sur bureau favori'
                  : 'Aucune réservation',
              icon: Icons.event_available_rounded,
              color: Colors.blue,
              tooltip: 'Nombre total de réservations confirmées à venir (aujourd\'hui et 14 prochains jours) issues de MyRoomz.',
            ),
            // Card 2: Favorite desk loyalty ratio
            _buildStatCard(
              title: 'Taux Bureau Favori',
              value: totalUpcoming > 0 ? '$favLoyaltyRatio%' : '-',
              subtitle: totalUpcoming > 0
                  ? '${upcomingHere.length} sur $totalUpcoming à venir'
                  : 'Aucune réservation',
              icon: Icons.star_rounded,
              color: Colors.green,
              tooltip: 'Pourcentage de vos réservations à venir effectuées sur votre bureau habituel${_workspaceName != null ? ' ($_workspaceName)' : ''}.',
            ),
            // Card 3 & 4: Background vs Manual bookings count (Desktop/Android only)
            if (!kIsWeb) ...[
              _buildStatCard(
                title: 'Automatisées',
                value: '$autoCount',
                subtitle: autoCount > 0 ? '$autoCount via automate' : 'Par AutoRoomzio',
                icon: Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary,
                tooltip: 'Nombre total de réservations créées automatiquement par l\'automate en tâche de fond sur cet appareil.',
              ),
              _buildStatCard(
                title: 'Manuelles',
                value: '$manualCount',
                subtitle: manualCount > 0 ? '$manualCount en un clic' : 'En un clic',
                icon: Icons.touch_app_rounded,
                color: Colors.orange,
                tooltip: 'Nombre total de réservations créées manuellement en un clic depuis l\'application sur cet appareil.',
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Bottom Summary Banner: Configured attendance rhythm
        _buildStatCard(
          title: 'Rythme de Présence Paramétré',
          value: rhythmValue,
          subtitle: rhythmSubtitle,
          icon: Icons.schedule_rounded,
          color: Colors.indigo,
          tooltip: 'Rythme de présence configuré dans l\'application pour la réservation automatique de votre bureau.',
        ),
      ],
    );
  }


  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color, String? subtitle, String? tooltip}) {
    return GestureDetector(
      onTap: tooltip != null ? () => _showStatInfo(context, title, tooltip, icon, color) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showStatInfo(BuildContext context, String title, String description, IconData icon, Color color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16).copyWith(bottom: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 10,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 56),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: TextStyle(fontSize: 16, height: 1.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("J'ai compris", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  Future<void> _downloadAndInstallApk(String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadDialog(url: url),
    );
  }

  Future<void> _checkUpdatesOnStartup() async {
    try {
      final response = await http.get(Uri.parse('https://api.github.com/repos/Xris65/AutoRoomzio/releases/latest'));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestTag = data['tag_name'] as String;
        
        String? apkUrl;
        if (data['assets'] != null && data['assets'].isNotEmpty) {
          apkUrl = data['assets'][0]['browser_download_url'] as String?;
        }

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        final latestVersion = latestTag.replaceAll('v', '');
        
        final ignoredVersion = await _storage.getIgnoredUpdateVersion();
        
        if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion) && latestVersion != ignoredVersion) {
          
          String releaseNotes = data['body'] ?? '';
          
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Mise à jour disponible 🎉'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      child: MarkdownBody(data: releaseNotes),
                    ),
                    const SizedBox(height: 16),
                    const Text('Voulez-vous l\'installer maintenant ?'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _storage.saveIgnoredUpdateVersion(latestVersion);
                    Navigator.pop(ctx);
                  },
                  child: Text('Ignorer cette version', style: TextStyle(color: Colors.red.shade400)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (apkUrl != null) {
                      _downloadAndInstallApk(apkUrl);
                    } else {
                      launchUrl(Uri.parse(data['html_url']), mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Installer'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // Échec silencieux
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.blue)),
      );

      final response = await http.get(Uri.parse('https://api.github.com/repos/Xris65/AutoRoomzio/releases/latest'));
      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestTag = data['tag_name'] as String; // e.g. "v1.3.1"
        
        String? apkUrl;
        if (data['assets'] != null && data['assets'].isNotEmpty) {
          apkUrl = data['assets'][0]['browser_download_url'] as String?;
        }

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        
        final latestVersion = latestTag.replaceAll('v', '');
        
        if (latestVersion != currentVersion && _isNewer(latestVersion, currentVersion)) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Mise à jour disponible 🎉'),
              content: Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\n\nVoulez-vous la télécharger et l\'installer maintenant ?'),
              actions: [
                TextButton(
                  onPressed: () {
                    _storage.saveIgnoredUpdateVersion(latestVersion);
                    Navigator.pop(ctx);
                  },
                  child: Text('Ignorer cette version', style: TextStyle(color: Colors.red.shade400)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Plus tard'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (apkUrl != null) {
                      _downloadAndInstallApk(apkUrl);
                    } else {
                      launchUrl(Uri.parse(data['html_url']), mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Installer'),
                ),
              ],
            ),
          );
        } else {
          _showTopToast('Votre application est déjà à jour ! (v$currentVersion)', isSuccess: true);
        }
      } else {
        _showTopToast('Erreur serveur lors de la vérification.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTopToast('Impossible de vérifier les mises à jour (Pas de connexion)', isError: true);
      }
    }
  }

  Widget _buildSettingsTab() {
    return ListView(
      key: const PageStorageKey('settings_scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Apparence & Personnalisation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, currentMode, _) {
                  final isDark = currentMode == ThemeMode.dark || 
                      (currentMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);
                  return SwitchListTile(
                    title: const Text('Mode sombre'),
                    secondary: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                    value: isDark,
                    onChanged: (val) {
                      themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                      _storage.saveThemeModeIndex(val ? 2 : 1);
                    },
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Couleur du thème'),
                leading: const Icon(Icons.color_lens_rounded),
                trailing: _buildStyledDropdown<int>(
                  value: themeColorNotifier.value,
                  onChanged: (val) {
                    if (val != null) {
                      themeColorNotifier.value = val;
                      _storage.saveThemeColorIndex(val);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Bleu (par défaut)')),
                    DropdownMenuItem(value: 1, child: Text('Vert')),
                    DropdownMenuItem(value: 2, child: Text('Violet')),
                    DropdownMenuItem(value: 3, child: Text('Orange')),
                    DropdownMenuItem(value: 4, child: Text('Rouge')),
                  ],
                ),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<int>(
                valueListenable: fontNotifier,
                builder: (context, currentFont, _) {
                  return ListTile(
                    title: const Text('Police d\'écriture'),
                    leading: const Icon(Icons.font_download_rounded),
                    trailing: _buildStyledDropdown<int>(
                      value: currentFont,
                      onChanged: (val) {
                        if (val != null) {
                          fontNotifier.value = val;
                          _storage.saveFontFamilyIndex(val);
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Classique')),
                        DropdownMenuItem(value: 1, child: Text('Moderne (Poppins)')),
                        DropdownMenuItem(value: 2, child: Text('Code (Fira)')),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ValueListenableBuilder<double>(
                valueListenable: uiScaleNotifier,
                builder: (context, currentScale, _) {
                  double selectedValue = 1.0;
                  if ((currentScale - 0.85).abs() < 0.01) {
                    selectedValue = 0.85;
                  } else if ((currentScale - 1.15).abs() < 0.01) {
                    selectedValue = 1.15;
                  }
                  return ListTile(
                    title: const Text('Taille de l\'interface'),
                    leading: const Icon(Icons.format_size_rounded),
                    trailing: _buildStyledDropdown<double>(
                      value: selectedValue,
                      onChanged: (val) {
                        if (val != null) {
                          uiScaleNotifier.value = val;
                          _storage.saveUiScale(val);
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 0.85, child: Text('Réduite (85%)')),
                        DropdownMenuItem(value: 1.0, child: Text('Normale (100%)')),
                        DropdownMenuItem(value: 1.15, child: Text('Agrandie (115%)')),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Interface & Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              FutureBuilder<int>(
                future: _storage.getInitialTab(),
                builder: (context, snapshot) {
                  return ListTile(
                    title: const Text('Page de démarrage'),
                    subtitle: const Text('Onglet affiché à l\'ouverture', style: TextStyle(fontSize: 12)),
                    leading: const Icon(Icons.home_rounded),
                    trailing: _buildStyledDropdown<int>(
                      value: snapshot.data ?? 0,
                      onChanged: (val) {
                        if (val != null) {
                          _storage.saveInitialTab(val);
                          setState(() {}); // refresh FutureBuilder
                        }
                      },
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('Accueil (par défaut)')),
                        const DropdownMenuItem(value: 1, child: Text('Calendrier')),
                        if (!kIsWeb) const DropdownMenuItem(value: 2, child: Text('Automate')),
                      ],
                    ),
                  );
                }
              ),
              if (!kIsWeb) ...[
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Afficher l\'onglet Automatisation'),
                  secondary: const Icon(Icons.auto_awesome),
                  value: _showAutomation,
                  onChanged: (val) {
                    setState(() {
                      if (val) _currentIndex++; else _currentIndex--;
                      _showAutomation = val;
                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                      }
                    });
                    _storage.saveShowAutomation(val);
                  },
                ),
              ],
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Afficher l\'onglet Statistiques'),
                secondary: const Icon(Icons.insights_rounded),
                value: _showStats,
                onChanged: (val) {
                  setState(() {
                    if (val) _currentIndex++; else _currentIndex--;
                    _showStats = val;
                  });
                  _storage.saveShowStats(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text("Tirer pour rafraîchir"),
                subtitle: const Text("Actualiser en glissant vers le bas (Accueil, Calendrier)", style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.refresh_rounded),
                value: _pullToRefreshEnabled,
                onChanged: (val) {
                  setState(() => _pullToRefreshEnabled = val);
                  _storage.savePullToRefresh(val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Paramètres de l\'Accueil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              ListTile(
                title: const Text('Prévisions à afficher'),
                subtitle: const Text('Nombre de jours de réservations futures affichés', style: TextStyle(fontSize: 12)),
                leading: const Icon(Icons.format_list_numbered),
                trailing: _buildStyledDropdown<int>(
                  value: _projectionsCount,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _projectionsCount = val);
                      _storage.saveProjectionsCount(val);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 jours')),
                    DropdownMenuItem(value: 4, child: Text('4 jours (par défaut)')),
                    DropdownMenuItem(value: 7, child: Text('7 jours')),
                    DropdownMenuItem(value: 13, child: Text('13 jours (Max)')),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Paramètres du Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Désactiver le week-end'),
                subtitle: const Text('Grise le samedi/dimanche, bloque les réservations', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.weekend_rounded),
                value: _hideWeekends,
                onChanged: (val) {
                  setState(() => _hideWeekends = val);
                  _storage.saveHideWeekends(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Affichage compact'),
                subtitle: const Text('Réduit les marges pour voir plus d\'informations', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.view_compact_rounded),
                value: _compactMode,
                onChanged: (val) {
                  setState(() => _compactMode = val);
                  _storage.saveCompactMode(val);
                },
              ),
            ],
          ),
        ),
        
        if (!kIsWeb) ...[
          const SizedBox(height: 24),
          const Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Réservations réussies'),
                  subtitle: const Text('Être notifié quand l\'automatisation réserve', style: TextStyle(fontSize: 12)),
                  secondary: const Icon(Icons.notifications_active, color: Colors.green),
                  value: _notifySuccess,
                  onChanged: (val) {
                    setState(() => _notifySuccess = val);
                    _storage.saveNotifySuccess(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Échecs de réservation'),
                  subtitle: const Text('Être notifié en cas d\'erreur (ex: plus de place)', style: TextStyle(fontSize: 12)),
                  secondary: const Icon(Icons.error_outline, color: Colors.red),
                  value: _notifyFailure,
                  onChanged: (val) {
                    setState(() => _notifyFailure = val);
                    _storage.saveNotifyFailure(val);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Tester les notifications', style: TextStyle(color: Colors.blue)),
                  subtitle: const Text('Envoyer une notification de test', style: TextStyle(fontSize: 12)),
                  leading: const Icon(Icons.send_rounded, color: Colors.blue),
                  onTap: () async {
                    final notifService = NotificationService();
                    await notifService.showNotification(
                      title: 'AutoRoomzio - Test',
                      body: 'Ceci est une notification de test ! Si tu vois ça, tout fonctionne. 🎉',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 24),
        const Text('À propos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  return ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Version'),
                    trailing: Text(snapshot.hasData ? snapshot.data!.version : '...'),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Code Source'),
                subtitle: const Text('Voir le projet sur GitHub', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                onTap: () async {
                  final url = Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
              if (!kIsWeb) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: Colors.green),
                  title: const Text('Rechercher des mises à jour', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Vérifier si une nouvelle version est disponible', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.download_rounded, size: 16, color: Colors.green),
                  onTap: _checkForUpdates,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}


class DownloadDialog extends StatefulWidget {
  final String url;
  const DownloadDialog({super.key, required this.url});

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  double _progress = 0.0;
  String _downloaded = "0 MB";
  String _total = "0 MB";

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final request = http.Request('GET', Uri.parse(widget.url));
      final response = await http.Client().send(request);
      
      final contentLength = response.contentLength ?? 0;
      int receivedBytes = 0;
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/AutoRoomzio_update.apk');
      final sink = file.openWrite();

      response.stream.listen(
        (List<int> chunk) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          if (mounted) {
            setState(() {
              if (contentLength > 0) {
                _progress = receivedBytes / contentLength;
                _total = (contentLength / (1024 * 1024)).toStringAsFixed(1);
              }
              _downloaded = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            });
          }
        },
        onDone: () async {
          await sink.close();
          if (!mounted) return;
          Navigator.pop(context);
          
          final result = await OpenFilex.open(file.path);
          if (result.type != ResultType.done) {
            // handle error if needed, but context might be dead.
          }
        },
        onError: (e) async {
          await sink.close();
          if (mounted) Navigator.pop(context);
        },
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Téléchargement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_downloaded MB / $_total MB', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
