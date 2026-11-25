import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import '../api_service.dart';
import '../holiday_service.dart';
import '../main.dart';
import '../models/booking_result.dart';
import '../models/colleague.dart';
import '../offline_state_manager.dart';
import '../services/app_update_service.dart';
import '../services/automation_engine.dart';
import '../services/profile_sync_service.dart';
import '../storage_service.dart';
import '../utils/date_helpers.dart';
import '../utils/error_sanitizer.dart';
import '../widgets/colleague_selection_dialog.dart';
import '../widgets/fun_loading_widget.dart';
import '../widgets/web_pairing_dialog.dart';
import 'home/widgets/adaptive_app_shell.dart';
import 'home/widgets/automation_tab.dart';
import 'home/widgets/calendar_tab.dart';
import 'home/widgets/delegation_dialogs.dart';
import 'home/widgets/home_dashboard_tab.dart';
import 'home/widgets/profile_sync_dialogs.dart';
import 'home/widgets/settings_tab.dart';
import 'home/widgets/stats_tab.dart';
import 'home/widgets/update_available_dialog.dart';
import 'home/widgets/vacation_dialogs.dart';
import 'login_screen.dart';
import 'optimization_screen.dart';
import 'setup_screen.dart';
import 'team_map_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final StorageService _storage;
  late final RoomzApiService _api;
  late final AppUpdateService _updateService;

  List<int> _selectedDays = <int>[];
  List<AutomationRule> _automationRules = <AutomationRule>[];
  String? _workspaceName;
  String? _defaultWorkspaceId;
  String? _floorId;
  bool _isLoading = true;
  bool _isCalendarBusy = false;
  bool _automationEnabled = false;
  bool _showAutomation = true;
  bool _showStats = true;
  bool _showFavoriteWeekIndicators = true;
  bool _skipPublicHolidays = true;
  String _holidayCountryCode = HolidayService.countryFrance;
  bool _canExit = false;
  bool _initialTabApplied = false;
  int _initialTab = 0;
  String _appVersion = '...';

  Map<String, int> _statsMap = <String, int>{'manual': 0, 'auto': 0};

  // Calendar State
  DateTime _focusedDay = DateTime.now();
  Set<String> _requestedDates = <String>{};
  Map<String, String> _requestedWorkspacesMap = <String, String>{};
  Map<String, String> _requestedWorkspaceNamesMap = <String, String>{};
  Set<String> _bookedDates = <String>{};
  Set<String> _ignoredDates = <String>{};
  Map<String, String> _bookedElsewhereMap = <String, String>{};
  Map<String, String> _occupiedByOthers = <String, String>{};
  Map<String, String> _delegatedBookingsMap = <String, String>{};

  // Settings State
  TimeOfDay _automationTime = const TimeOfDay(hour: 8, minute: 0);
  bool _notifySuccess = true;
  bool _notifyFailure = true;
  int _projectionsCount = 4;
  bool _hideWeekends = true;
  bool _pullToRefreshEnabled = true;
  List<DateTimeRange> _vacations = <DateTimeRange>[];
  bool _compactMode = false;
  bool _showAllReservations = true;
  bool _showDelegatedReservations = true;
  final ValueNotifier<String> _loadingTextNotifier =
      ValueNotifier<String>("Démarrage d'AutoRoomzio...");
  late final ValueNotifier<DateTime> _focusedMapDateNotifier;
  AppDestination _selectedDestination = AppDestination.home;
  bool _isSplitMapVisible = true;
  int _cockpitRefreshToken = 0;
  int _permissionStatus = 0;

  // All-time historical bookings for stats
  Set<String> _allTimeBookedDates = <String>{};
  Set<String> _allTimeElsewhereDates = <String>{};

  static bool _urlTokenProcessed = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isFlutterTest =>
      const bool.fromEnvironment('FLUTTER_TEST') ||
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _storage = widget.storageService ?? StorageService();
    _api = widget.apiService ?? RoomzApiService();
    _updateService = AppUpdateService(storage: _storage);
    _focusedMapDateNotifier = ValueNotifier<DateTime>(
      normalizeLocalDate(DateTime.now()),
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadAppVersion());
    if (!kIsWeb) {
      unawaited(_checkUpdatesOnStartup());
    }
    unawaited(_checkAuthAndLoad());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTextNotifier.dispose();
    _focusedMapDateNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    await _storage.reloadFromDisk();
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _loadAppVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = info.version);
      }
    } catch (_) {
      // Ignore in headless tests without platform channel.
    }
  }

  bool _isVacation(DateTime date) {
    if (!_showAutomation) return false;
    final DateTime d = normalizeLocalDate(date);
    for (final DateTimeRange v in _vacations) {
      final DateTime start = normalizeLocalDate(v.start);
      final DateTime end = normalizeLocalDate(v.end);
      if (!d.isBefore(start) && !d.isAfter(end)) return true;
    }
    return false;
  }

  void _showTopToast(String message, {bool isError = false}) {
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _checkAuthAndLoad() async {
    if (kIsWeb && !_urlTokenProcessed) {
      final String? tokenInUrl = Uri.base.queryParameters['token'];
      if (tokenInUrl != null && tokenInUrl.isNotEmpty) {
        _urlTokenProcessed = true;
        if (mounted) {
          await Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const LoginScreen(),
              settings: const RouteSettings(name: '/'),
            ),
          );
        }
        return;
      }
    }

    final String? token = await _storage.getRefreshToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        await Navigator.of(context).pushReplacement<void, void>(
          PageRouteBuilder<void>(
            pageBuilder: (
              BuildContext _,
              Animation<double> animation1,
              Animation<double> animation2,
            ) =>
                const LoginScreen(),
            settings: const RouteSettings(name: '/'),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      }
      return;
    }

    await _loadData();
  }

  bool get _canShowSplitMap =>
      (_defaultWorkspaceId != null && _defaultWorkspaceId!.isNotEmpty) &&
      (_floorId != null && _floorId!.isNotEmpty);

  void _syncFocusedMapDate(DateTime date) {
    final DateTime normalized = normalizeLocalDate(date);
    _focusedMapDateNotifier.value = normalized;
    if (mounted) {
      setState(() => _focusedDay = normalized);
    }
  }

  Future<void> _openTeamMap({DateTime? date}) async {
    final DateTime targetDate = normalizeLocalDate(date ?? _focusedDay);
    _syncFocusedMapDate(targetDate);

    final bool isExpanded =
        mounted && MediaQuery.sizeOf(context).width >= 1100;
    if (isExpanded && _canShowSplitMap && _isSplitMapVisible) {
      if (_selectedDestination != AppDestination.home &&
          _selectedDestination != AppDestination.calendar) {
        setState(() => _selectedDestination = AppDestination.home);
      }
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => TeamMapScreen(
          initialDate: targetDate,
          hideWeekends: _hideWeekends,
          storageService: _storage,
          apiService: _api,
        ),
      ),
    );
    if (mounted) {
      await _reloadPendingSchedules();
      await _reloadAutomationAndSettings();
      await _syncCalendar();
    }
  }

  Future<void> _reloadLocalBookingSnapshot() async {
    final String? wsId = await _storage.getWorkspaceId();
    final String? flId = await _storage.getFloorId();
    final ({Set<String> here, Map<String, String> elsewhere}) partition =
        await _storage.partitionUserReservations(wsId);
    final List<String> reqDates = await _storage.getRequestedDates();
    final Map<String, String> reqWs =
        await _storage.getRequestedWorkspacesMap();
    final Map<String, String> reqNames =
        await _storage.getRequestedWorkspaceNamesMap();
    final Map<String, int> stats = await _storage.getBookingStats();
    if (!mounted) return;
    setState(() {
      _defaultWorkspaceId = wsId;
      _floorId = flId;
      _bookedDates = partition.here;
      _bookedElsewhereMap = partition.elsewhere;
      _requestedDates = reqDates.toSet();
      _requestedWorkspacesMap = reqWs;
      _requestedWorkspaceNamesMap = reqNames;
      _statsMap = stats;
      _cockpitRefreshToken++;
    });
    await _reloadAutomationAndSettings();
  }

  void _handleMapReservationChanged() {
    if (!mounted) return;
    unawaited(_reloadLocalBookingSnapshot());
  }

  Future<void> _reloadThemePreferencesFromStorage() async {
    final int modeIndex = await _storage.getThemeModeIndex();
    themeNotifier.value = modeIndex == 1
        ? ThemeMode.light
        : (modeIndex == 2 ? ThemeMode.dark : ThemeMode.system);
    themeColorNotifier.value = await _storage.getThemeColorIndex();
    fontNotifier.value = await _storage.getFontFamilyIndex();
    uiScaleNotifier.value = await _storage.getUiScale();
  }

  Future<void> _reloadAutomationAndSettings() async {
    final bool hasRulesKey = await _storage.hasAutomationRules();
    final List<AutomationRule> rules = await _storage.getAutomationRules();
    final bool showFavWeek = await _storage.getShowFavoriteWeekIndicators();
    final List<int> days;
    if (rules.isNotEmpty) {
      days = rules.expand((AutomationRule r) => r.days).toSet().toList()
        ..sort();
    } else if (!hasRulesKey) {
      days = await _storage.getDays();
    } else {
      days = <int>[];
    }
    if (mounted) {
      setState(() {
        _automationRules = rules;
        _selectedDays = days;
        _showFavoriteWeekIndicators = showFavWeek;
        _cockpitRefreshToken++;
      });
    }
  }

  Future<void> _reloadPendingSchedules() async {
    final List<String> reqDates = await _storage.getRequestedDates();
    final Map<String, String> reqWorkspaces =
        await _storage.getRequestedWorkspacesMap();
    final Map<String, String> reqNames =
        await _storage.getRequestedWorkspaceNamesMap();
    if (mounted) {
      setState(() {
        _requestedDates = reqDates.toSet();
        _requestedWorkspacesMap = reqWorkspaces;
        _requestedWorkspaceNamesMap = reqNames;
        _cockpitRefreshToken++;
      });
    }
  }

  void _openFavoritesManager() {
    final String todayStr = DateHelpers.formatIsoDate(DateTime.now());
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext _) => ColleagueSelectionDialog(
          date: todayStr,
          storageService: _storage,
          apiService: _api,
          isManagementMode: true,
        ),
      ).then((void _) {
        if (mounted) {
          setState(() => _cockpitRefreshToken++);
        }
      }),
    );
  }

  int _sanitizeInitialTab(
    int rawTab, {
    required bool showAutomation,
    bool showStats = true,
  }) {
    if ((kIsWeb || !showAutomation) && rawTab == 2) {
      return 0;
    }
    if (!showStats && rawTab == 3) {
      return 0;
    }
    if (rawTab < 0 || rawTab > 5) {
      return 0;
    }
    return rawTab;
  }

  AppDestination _destinationFromCanonicalTab(
    int rawTab, {
    required bool showAutomation,
    required bool showStats,
  }) {
    return switch (rawTab) {
      1 => AppDestination.calendar,
      2 => (showAutomation && !kIsWeb)
          ? AppDestination.automation
          : AppDestination.home,
      3 => showStats ? AppDestination.stats : AppDestination.home,
      4 => AppDestination.settings,
      5 => AppDestination.map,
      _ => AppDestination.home,
    };
  }

  bool _isDestinationVisible(
    AppDestination dest, {
    required bool showAutomation,
    required bool showStats,
  }) {
    return switch (dest) {
      AppDestination.automation => showAutomation && !kIsWeb,
      AppDestination.stats => showStats,
      _ => true,
    };
  }

  Future<void> _loadData() async {
    try {
    final bool hasRulesKey = await _storage.hasAutomationRules();
    final List<AutomationRule> rules = await _storage.getAutomationRules();
    final List<int> days;
    if (rules.isNotEmpty) {
      days = rules.expand((AutomationRule r) => r.days).toSet().toList()
        ..sort();
    } else if (!hasRulesKey) {
      days = await _storage.getDays();
    } else {
      days = <int>[];
    }
    final String? name = await _storage.getWorkspaceName();
    final List<String> requested = await _storage.getRequestedDates();
    final Map<String, String> requestedWorkspaces =
        await _storage.getRequestedWorkspacesMap();
    final Map<String, String> requestedNames =
        await _storage.getRequestedWorkspaceNamesMap();
    final List<String> ignored = await _storage.getIgnoredDates();
    final String? wsId = await _storage.getWorkspaceId();
    final String? flId = await _storage.getFloorId();
    final ({Set<String> here, Map<String, String> elsewhere}) partition =
        await _storage.partitionUserReservations(wsId);
    final bool autoEnabled = await _storage.getAutomationEnabled();
    final Map<String, int> autoTimeMap = await _storage.getAutomationTime();
    final bool showAuto = await _storage.getShowAutomation();
    final bool showStats = await _storage.getShowStats();
    final bool showFavWeek = await _storage.getShowFavoriteWeekIndicators();
    final bool skipHolidays = await _storage.getSkipPublicHolidays();
    final String holidayCountry = await _storage.getHolidayCountryCode();
    final bool notifSuccess = await _storage.getNotifySuccess();
    final bool notifFailure = await _storage.getNotifyFailure();
    final int projCount = await _storage.getProjectionsCount();
    final int rawInitialTab = await _storage.getInitialTab();
    final bool hideWe = await _storage.getHideWeekends();
    final bool pullToRefresh = await _storage.getPullToRefresh();
    final bool showDelegated = await _storage.getShowDelegatedBookings();
    final List<Map<String, String>> vacs = await _storage.getVacations();
    final bool comp = await _storage.getCompactMode();
    final List<String> allTimeBooked = await _storage.getAllTimeBookedDates();
    final List<String> allTimeElsewhere =
        await _storage.getAllTimeElsewhereDates();
    final Map<String, String> delegated =
        await _storage.getDelegatedBookingsMap();
    final Map<String, String> occupied = await _storage.getOccupiedByOthers();

    final int safeInitialTab = _sanitizeInitialTab(
      rawInitialTab,
      showAutomation: showAuto,
      showStats: showStats,
    );

    if (mounted) {
      setState(() {
        _automationRules = rules;
        _selectedDays = days;
        _workspaceName = name;
        _defaultWorkspaceId = wsId;
        _floorId = flId;
        _requestedDates = requested.toSet();
        _requestedWorkspacesMap = requestedWorkspaces;
        _requestedWorkspaceNamesMap = requestedNames;
        _bookedDates = partition.here;
        _ignoredDates = ignored.toSet();
        _bookedElsewhereMap = partition.elsewhere;
        _delegatedBookingsMap = delegated;
        _occupiedByOthers = occupied;
        _allTimeBookedDates = allTimeBooked.toSet();
        _allTimeElsewhereDates = allTimeElsewhere.toSet();
        _automationEnabled = autoEnabled;
        _showAutomation = showAuto;
        _showStats = showStats;
        _showFavoriteWeekIndicators = showFavWeek;
        _skipPublicHolidays = skipHolidays;
        _holidayCountryCode = holidayCountry;
        _automationTime = TimeOfDay(
          hour: autoTimeMap['hour'] ?? 8,
          minute: autoTimeMap['minute'] ?? 0,
        );
        _notifySuccess = notifSuccess;
        _notifyFailure = notifFailure;
        _projectionsCount = projCount;
        _hideWeekends = hideWe;
        _pullToRefreshEnabled = pullToRefresh;
        _showDelegatedReservations = showDelegated;
        _initialTab = safeInitialTab;
        _vacations = vacs
            .map<DateTimeRange?>((Map<String, String> v) {
              final DateTime? s =
                  v['start'] != null ? DateTime.tryParse(v['start']!) : null;
              final DateTime? e =
                  v['end'] != null ? DateTime.tryParse(v['end']!) : null;
              if (s == null || e == null) return null;
              return DateTimeRange(start: s, end: e);
            })
            .whereType<DateTimeRange>()
            .toList()
          ..sort(
            (DateTimeRange a, DateTimeRange b) => a.start.compareTo(b.start),
          );
        _compactMode = comp;
        _cockpitRefreshToken++;
        if (!_initialTabApplied) {
          _initialTabApplied = true;
          _selectedDestination = _destinationFromCanonicalTab(
            safeInitialTab,
            showAutomation: showAuto,
            showStats: showStats,
          );
        } else if (!_isDestinationVisible(
          _selectedDestination,
          showAutomation: showAuto,
          showStats: showStats,
        )) {
          _selectedDestination = AppDestination.home;
        }
      });
    }

    unawaited(_refreshStats());
    await _syncCalendar();
    await _checkPermissionsStatus();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkPermissionsStatus() async {
    if (!_isAndroid || _isFlutterTest) return;
    final bool batteryOpt;
    final bool notif;
    try {
      batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
      notif = await Permission.notification.isGranted;
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
    bool autostart = await _storage.getAutostartVerified();

    if (autostart && _automationEnabled) {
      final DateTime? lastRun = await _storage.getLastAutomationRun();
      if (lastRun != null) {
        final int hoursSinceLastRun =
            DateTime.now().difference(lastRun).inHours;
        if (hoursSinceLastRun > 48) {
          autostart = false;
          await _storage.saveAutostartVerified(false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "L'automatisation semble avoir été bloquée par le système en arrière-plan. Veuillez vérifier l'autostart.",
                ),
                backgroundColor: Colors.redAccent,
              ),
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
    final bool hasAnyDays = _selectedDays.isNotEmpty ||
        _automationRules.any((AutomationRule r) => r.days.isNotEmpty);
    if (val && !hasAnyDays) {
      _showTopToast(
        'Veuillez sélectionner au moins un jour récurrent.',
        isError: true,
      );
      return;
    }

    setState(() => _automationEnabled = val);
    await _storage.saveAutomationEnabled(val);

    if (val) {
      if (_isAndroid) {
        if (!_isFlutterTest) {
          final bool hasSeen = await _storage.getHasSeenOptimization();
          if (!hasSeen && mounted) {
            await _storage.saveHasSeenOptimization(true);
            if (!mounted) return;
            unawaited(
              Navigator.of(context)
                  .push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const OptimizationScreen(),
                    ),
                  )
                  .then((void _) => _checkPermissionsStatus()),
            );
          }
        }

        final DateTime now = DateTime.now();
        DateTime targetDate = DateTime(
          now.year,
          now.month,
          now.day,
          _automationTime.hour,
          _automationTime.minute,
        );
        if (targetDate.isBefore(now)) {
          final DateTime nextDay = addCalendarDays(now, 1);
          targetDate = DateTime(
            nextDay.year,
            nextDay.month,
            nextDay.day,
            _automationTime.hour,
            _automationTime.minute,
          );
        }
        final Duration delay = targetDate.difference(now);

        try {
          await Workmanager().registerPeriodicTask(
            '1',
            'autoReservationTask',
            frequency: const Duration(hours: 24),
            initialDelay: delay,
            existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
            constraints: Constraints(networkType: NetworkType.connected),
          );
        } on MissingPluginException {
          // Headless test environment without native Workmanager plugin.
        } catch (_) {}
      }
    } else {
      if (_isAndroid) {
        try {
          await Workmanager().cancelAll();
        } on MissingPluginException {
          // Headless test environment without native Workmanager plugin.
        } catch (_) {}
      }
    }
  }

  Future<void> _persistAutomationRules() async {
    await _storage.saveAutomationRules(_automationRules);
    final List<AutomationRule> reloaded = await _storage.getAutomationRules();
    final List<int> unionDays = reloaded
        .expand((AutomationRule r) => r.days)
        .toSet()
        .toList()
      ..sort();
    final bool shouldDisable = unionDays.isEmpty && _automationEnabled;
    if (shouldDisable) {
      await _storage.saveAutomationEnabled(false);
      if (_isAndroid) {
        try {
          await Workmanager().cancelAll();
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() {
        _automationRules = reloaded;
        _selectedDays = unionDays;
        if (shouldDisable) {
          _automationEnabled = false;
        }
      });
    }
  }

  Future<void> _addAutomationPlace() async {
    final String? token = await _api.refreshMyToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      _showTopToast(
        "Impossible d'actualiser la session. Veuillez vérifier votre connexion.",
        isError: true,
      );
      return;
    }
    final Map<String, String>? picked =
        await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        builder: (BuildContext _) => SetupScreen(
          accessToken: token,
          apiService: _api,
          storageService: _storage,
          pickOnly: true,
          titleOverride: 'Ajouter une place automatisée',
        ),
      ),
    );
    if (!mounted || picked == null) return;

    final String wsId = picked['workspaceId'] ?? '';
    final String wsName = picked['workspaceName'] ?? wsId;
    final String siteId = picked['siteId'] ?? '';
    final String floorId = picked['floorId'] ?? '';
    if (wsId.isEmpty) return;

    final bool alreadyExists = _automationRules.any(
      (AutomationRule r) => r.workspaceId.toLowerCase() == wsId.toLowerCase(),
    );
    if (alreadyExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La place "$wsName" est déjà dans vos automatisations.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _automationRules.add(
        AutomationRule(
          id: wsId,
          siteId: siteId,
          floorId: floorId,
          workspaceId: wsId,
          workspaceName: wsName,
          days: const <int>[],
        ),
      );
    });
    await _persistAutomationRules();
  }

  Future<void> _changeRulePlace(AutomationRule targetRule) async {
    final String? token = await _api.refreshMyToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      _showTopToast(
        "Impossible d'actualiser la session. Veuillez vérifier votre connexion.",
        isError: true,
      );
      return;
    }
    final Map<String, String>? picked =
        await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        builder: (BuildContext _) => SetupScreen(
          accessToken: token,
          apiService: _api,
          storageService: _storage,
          pickOnly: true,
          titleOverride: 'Changer la place automatisée',
        ),
      ),
    );
    if (!mounted || picked == null) return;

    final String newWsId = picked['workspaceId'] ?? '';
    final String newWsName = picked['workspaceName'] ?? newWsId;
    final String newSiteId = picked['siteId'] ?? '';
    final String newFloorId = picked['floorId'] ?? '';
    if (newWsId.isEmpty) return;

    final bool duplicateOther = _automationRules.any(
      (AutomationRule r) =>
          r.workspaceId != targetRule.workspaceId &&
          r.workspaceId.toLowerCase() == newWsId.toLowerCase(),
    );
    if (duplicateOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La place "$newWsName" est déjà configurée sur une autre carte.',
          ),
        ),
      );
      return;
    }

    setState(() {
      final int idx = _automationRules.indexWhere(
        (AutomationRule r) => r.workspaceId == targetRule.workspaceId,
      );
      if (idx >= 0) {
        _automationRules[idx] = targetRule.copyWith(
          id: newWsId,
          siteId: newSiteId,
          floorId: newFloorId,
          workspaceId: newWsId,
          workspaceName: newWsName,
        );
      }
    });
    await _persistAutomationRules();
  }

  Future<void> _deleteAutomationRule(AutomationRule rule) async {
    setState(() {
      _automationRules.removeWhere(
        (AutomationRule r) => r.workspaceId == rule.workspaceId,
      );
    });
    await _persistAutomationRules();
  }

  Future<void> _onRuleDayPressed(
    AutomationRule rule,
    int day,
    AutomationRule? conflictingRule,
  ) async {
    if (rule.days.contains(day)) {
      setState(() {
        final int idx = _automationRules.indexWhere(
          (AutomationRule r) => r.workspaceId == rule.workspaceId,
        );
        if (idx >= 0) {
          final List<int> updatedDays = List<int>.from(
            _automationRules[idx].days,
          )..remove(day);
          _automationRules[idx] =
              _automationRules[idx].copyWith(days: updatedDays);
        }
      });
      await _persistAutomationRules();
      return;
    }

    if (conflictingRule != null &&
        conflictingRule.workspaceId != rule.workspaceId) {
      final String dayName = DateHelpers.frenchWeekdaysMap[day] ?? 'Jour $day';
      final bool confirmed = await showRuleConflictDialog(
        context,
        dayName: dayName,
        targetRule: rule,
        conflictingRule: conflictingRule,
      );

      if (!confirmed || !mounted) return;

      setState(() {
        final int otherIdx = _automationRules.indexWhere(
          (AutomationRule r) => r.workspaceId == conflictingRule.workspaceId,
        );
        if (otherIdx >= 0) {
          final List<int> otherDays = List<int>.from(
            _automationRules[otherIdx].days,
          )..remove(day);
          _automationRules[otherIdx] =
              _automationRules[otherIdx].copyWith(days: otherDays);
        }
        final int idx = _automationRules.indexWhere(
          (AutomationRule r) => r.workspaceId == rule.workspaceId,
        );
        if (idx >= 0) {
          final List<int> nextDays = List<int>.from(_automationRules[idx].days)
            ..add(day);
          _automationRules[idx] =
              _automationRules[idx].copyWith(days: nextDays);
        }
      });
      await _persistAutomationRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$dayName attribué à ${rule.workspaceName}.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      final int idx = _automationRules.indexWhere(
        (AutomationRule r) => r.workspaceId == rule.workspaceId,
      );
      if (idx >= 0) {
        final List<int> nextDays = List<int>.from(_automationRules[idx].days)
          ..add(day);
        _automationRules[idx] = _automationRules[idx].copyWith(days: nextDays);
      }
    });
    await _persistAutomationRules();
  }

  Future<void> _changeWorkspace() async {
    final String? token = await _api.refreshMyToken();
    if (!mounted) return;
    if (token == null) {
      _showTopToast(
        "Impossible d'actualiser la session. Veuillez vérifier votre connexion.",
        isError: true,
      );
      return;
    }
    final bool? didChange = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => SetupScreen(accessToken: token),
      ),
    );

    if (didChange == true) {
      setState(() {
        _occupiedByOthers = <String, String>{};
        _workspaceName = null;
      });
      await _storage.saveOccupiedByOthers(<String, String>{});
      await _storage.saveLastSyncTime(forceReset: true);
      await _loadData();
    }
  }

  Future<void> _logout() async {
    await _storage.clearTokens();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const LoginScreen(ignoreUrlToken: true),
        settings: const RouteSettings(name: '/'),
      ),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _resetWorkspace() async {
    await _storage.resetWorkspace();
    if (mounted) {
      setState(() {
        _workspaceName = null;
        _defaultWorkspaceId = null;
        _floorId = null;
        _cockpitRefreshToken++;
      });
    }
  }

  Future<void> _handleAddVacation() async {
    final VacationAddResult? result = await showAddVacationFlow(
      context,
      requestedDates: _requestedDates,
      bookedDates: _bookedDates,
      bookedElsewhereMap: _bookedElsewhereMap,
    );
    if (result == null || !mounted) return;

    if (result.conflicts.isNotEmpty) {
      final String? token = await _api.refreshMyToken();
      if (token != null) {
        await Future.wait<bool>(
          result.conflicts.map<Future<bool>>(
            (String dateStr) => _api.cancelBookingByDate(token, dateStr),
          ),
        );
      }

      if (result.toCleanLocally.isNotEmpty) {
        if (mounted) {
          setState(() {
            for (final String dateStr in result.toCleanLocally) {
              _bookedDates.remove(dateStr);
              _occupiedByOthers.remove(dateStr);
              _requestedDates.remove(dateStr);
              _bookedElsewhereMap.remove(dateStr);
            }
          });
        }
        await _storage.saveBookedDates(_bookedDates.toList());
        await _storage.saveRequestedDates(_requestedDates.toList());
        await _storage.saveBookedElsewhereDates(
          _bookedElsewhereMap.keys.toList(),
        );
        for (final String dateStr in result.toCleanLocally) {
          await _storage.removeUserReservation(dateStr);
        }
      }
    }

    if (mounted) {
      setState(() {
        _vacations.add(result.range);
        _vacations.sort(
          (DateTimeRange a, DateTimeRange b) => a.start.compareTo(b.start),
        );
      });
    }
    await _storage.saveVacations(
      _vacations
          .map<Map<String, String>>(
            (DateTimeRange v) => <String, String>{
              'start': v.start.toIso8601String(),
              'end': v.end.toIso8601String(),
            },
          )
          .toList(),
    );
  }

  void _handleDeleteVacation(DateTimeRange vacation) {
    setState(() => _vacations.remove(vacation));
    unawaited(
      _storage.saveVacations(
        _vacations
            .map<Map<String, String>>(
              (DateTimeRange v) => <String, String>{
                'start': v.start.toIso8601String(),
                'end': v.end.toIso8601String(),
              },
            )
            .toList(),
      ),
    );
  }

  Future<bool> _cancelDelegationAction(String dateStr) async {
    final String? token = await _api.refreshMyToken();
    final String? workspaceId = await _storage.getWorkspaceId();
    if (token == null || workspaceId == null) return false;

    final List<String> parts =
        _delegatedBookingsMap[dateStr]?.split('|') ?? <String>[];
    final String wsId =
        parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : workspaceId;
    if (wsId.isEmpty) {
      if (mounted) {
        _showTopToast(
          "Veuillez d'abord synchroniser le calendrier.",
          isError: true,
        );
      }
      return false;
    }

    final String? eventId = parts.length > 3 ? parts[3] : null;
    final String? orgId = parts.length > 4 ? parts[4] : null;

    final bool success = await _api.cancelReservation(
      dateStr,
      token,
      wsId,
      eventId: eventId,
      forUserId: orgId,
    );
    if (success) {
      if (mounted) {
        setState(() {
          _delegatedBookingsMap.remove(dateStr);
        });
      }
      await _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
      return true;
    } else {
      if (mounted) {
        _showTopToast("Erreur lors de l'annulation.", isError: true);
      }
      return false;
    }
  }

  Future<void> _quickAction(
    DateTime day,
    bool isBooked,
    String source, {
    bool isRequested = false,
  }) async {
    final String dateStr = DateHelpers.formatIsoDate(day);

    setState(() => _isCalendarBusy = true);
    try {
      if (source == 'Délégué') {
        await _cancelDelegationAction(dateStr);
        if (mounted) setState(() => _isCalendarBusy = false);
        await _syncCalendar();
        return;
      }

      if (isRequested || (!isBooked && source == 'Calendrier')) {
        setState(() {
          _requestedDates.remove(dateStr);
          _requestedWorkspacesMap.remove(dateStr);
          _requestedWorkspaceNamesMap.remove(dateStr);
          _ignoredDates.remove(dateStr);
          _isCalendarBusy = false;
        });
        await _storage.removeRequestedDate(dateStr);
        await _storage.saveRequestedDates(_requestedDates.toList());
        await _storage.saveRequestedWorkspacesMap(_requestedWorkspacesMap);
        await _storage
            .saveRequestedWorkspaceNamesMap(_requestedWorkspaceNamesMap);
        await _storage.saveIgnoredDates(_ignoredDates.toList());
        await _syncCalendar();
        return;
      }

      final String? token = await _api.refreshMyToken();
      final String? workspaceId = await _storage.getWorkspaceId();
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
            _allTimeElsewhereDates.remove(dateStr);
          } else {
            _bookedDates.remove(dateStr);
            _allTimeBookedDates.remove(dateStr);
            _occupiedByOthers.remove(dateStr);
            _requestedDates.remove(dateStr);
            _requestedWorkspacesMap.remove(dateStr);
            _requestedWorkspaceNamesMap.remove(dateStr);
          }
        } else {
          _ignoredDates.add(dateStr);
        }
      });

      if (isBooked) {
        await _storage.removeUserReservation(dateStr);
        await _storage.removeRequestedDate(dateStr);
        await _storage.saveRequestedDates(_requestedDates.toList());
        await _storage.saveRequestedWorkspacesMap(_requestedWorkspacesMap);
        await _storage
            .saveRequestedWorkspaceNamesMap(_requestedWorkspaceNamesMap);
        await _storage.saveBookedDates(_bookedDates.toList());
        await _storage.saveAllTimeBookedDates(_allTimeBookedDates.toList());
        if (source == 'Ailleurs') {
          await _storage.saveBookedElsewhereDates(
            _bookedElsewhereMap.keys.toList(),
          );
          await _storage
              .saveAllTimeElsewhereDates(_allTimeElsewhereDates.toList());
        }
        if (mounted) setState(() => _isCalendarBusy = false);
        await _syncCalendar();
      } else {
        await _storage.saveIgnoredDates(_ignoredDates.toList());
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      if (mounted) {
        _showTopToast(
          ErrorSanitizer.sanitize(
            e,
            fallback: "Erreur lors de l'opération.",
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _runAutomationNow() async {
    if (!_automationEnabled) return;
    setState(() => _isCalendarBusy = true);
    try {
      final AutomationRunResult result = await AutomationEngine.run(
        apiService: _api,
        storageService: _storage,
        enforceAutomationEnabled: true,
      );

      final String? wsId = await _storage.getWorkspaceId();
      final ({Set<String> here, Map<String, String> elsewhere}) partition =
          await _storage.partitionUserReservations(wsId);
      final List<String> reqDates = await _storage.getRequestedDates();
      final Map<String, String> reqWs =
          await _storage.getRequestedWorkspacesMap();
      final Map<String, String> reqNames =
          await _storage.getRequestedWorkspaceNamesMap();

      if (mounted) {
        setState(() {
          _bookedDates = partition.here;
          _bookedElsewhereMap = partition.elsewhere;
          _requestedDates = reqDates.toSet();
          _requestedWorkspacesMap = reqWs;
          _requestedWorkspaceNamesMap = reqNames;
        });
      }
      if (result.newlyBookedCount > 0) {
        await _refreshStats();
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      if (mounted) {
        _showTopToast(
          ErrorSanitizer.sanitize(
            e,
            fallback: "Erreur lors de l'exécution de l'automatisation.",
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _refreshStats() async {
    final Map<String, int> stats = await _storage.getBookingStats();
    if (mounted) {
      setState(() {
        _statsMap = stats;
      });
    }
  }

  Future<void> _syncCalendar({bool isManual = false}) async {
    if (_isCalendarBusy) return;

    final String? workspaceId = await _storage.getWorkspaceId();
    final String? floorId = await _storage.getFloorId();

    if (workspaceId == null || floorId == null) {
      return;
    }

    void showOfflineNotice() {
      if (isManual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: <Widget>[
                Icon(Icons.wifi_off_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Impossible de synchroniser : pas de connexion Internet. Données du cache conservées.',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    setState(() => _isCalendarBusy = true);

    try {
      if (_isLoading) {
        _loadingTextNotifier.value = 'Connexion aux serveurs MyRoomz...';
      }
      final String? accessToken = await _api.refreshMyToken();
      if (accessToken == null) {
        showOfflineNotice();
        return;
      }

      if (_isLoading) {
        _loadingTextNotifier.value =
            'Vérification de la configuration du bureau...';
      }

      final List<String> freshReq = await _storage.getRequestedDates();
      final Map<String, String> freshWsMap =
          await _storage.getRequestedWorkspacesMap();
      final Map<String, String> freshNamesMap =
          await _storage.getRequestedWorkspaceNamesMap();
      _requestedDates = freshReq.toSet();
      _requestedWorkspacesMap = freshWsMap;
      _requestedWorkspaceNamesMap = freshNamesMap;

      final Set<String> datesToCheck = Set<String>.from(_requestedDates);
      final DateTime now = normalizeLocalDate(DateTime.now());
      for (int i = 0; i <= 13; i++) {
        final DateTime d = addCalendarDays(now, i);
        datesToCheck.add(DateHelpers.formatIsoDate(d));
      }

      if (_isLoading) {
        _loadingTextNotifier.value = "Récupération de l'occupation du bureau...";
      }

      final List<String> visibleDates = <String>[];
      for (int i = 0; i <= 13; i++) {
        final DateTime d = addCalendarDays(now, i);
        if (_hideWeekends &&
            (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) {
          continue;
        }
        visibleDates.add(DateHelpers.formatIsoDate(d));
      }

      final String? currentFloorId = await _storage.getFloorId();
      final ({
        Set<String> here,
        Map<String, String> elsewhere,
        Map<String, String> delegated,
        Map<String, Map<String, String>> allReservations,
        String? myUserId,
      }) myBookings = await _api.getMyReservations(accessToken, workspaceId);
      final String? myUserId =
          myBookings.myUserId ?? await _api.getCurrentUserId(accessToken);

      final ({
        Map<String, String> occupiedByOthers,
        Map<String, String> delegatedBookings,
        Set<String> delegatedHere,
        Set<String> delegatedElsewhere,
      }) occResult = currentFloorId != null
          ? await _api.getWorkspaceOccupancy(
              accessToken,
              workspaceId,
              currentFloorId,
              visibleDates,
              myUserId,
              myBookings.elsewhere,
            )
          : (
              occupiedByOthers: <String, String>{},
              delegatedBookings: <String, String>{},
              delegatedHere: <String>{},
              delegatedElsewhere: <String>{},
            );

      // Guard BEFORE mutating any state or storage: never overwrite local cache while offline.
      if (OfflineStateManager.instance.isOffline) {
        debugPrint(
          'ℹ️ _syncCalendar: offline detected, aborting state overwrite to preserve local cache.',
        );
        showOfflineNotice();
        return;
      }

      final Map<String, String> occupiedDates = occResult.occupiedByOthers;
      final Map<String, String> mergedDelegated =
          Map<String, String>.from(occResult.delegatedBookings);
      myBookings.delegated.forEach(
        (String date, String value) => mergedDelegated[date] = value,
      );

      final Set<String> bookedHere = Set<String>.from(myBookings.here);
      final Map<String, String> bookedElsewhere =
          Map<String, String>.from(myBookings.elsewhere);
      final Map<String, Map<String, String>> allUserReservations =
          Map<String, Map<String, String>>.from(myBookings.allReservations);

      for (final String d in occResult.delegatedHere) {
        bookedHere.remove(d);
        allUserReservations.remove(d);
      }
      for (final String d in occResult.delegatedElsewhere) {
        bookedElsewhere.remove(d);
        allUserReservations.remove(d);
      }

      final Set<String> newBookedDates = <String>{};
      final Set<String> newRequestedDates = Set<String>.from(_requestedDates);
      final Map<String, String> newRequestedWorkspaces =
          Map<String, String>.from(_requestedWorkspacesMap);
      final Map<String, String> newRequestedNames =
          Map<String, String>.from(_requestedWorkspaceNamesMap);
      final Set<String> newIgnoredDates = Set<String>.from(_ignoredDates);

      for (final String dateStr in datesToCheck) {
        if (bookedHere.contains(dateStr)) {
          newBookedDates.add(dateStr);
          newRequestedDates.remove(dateStr);
          newRequestedWorkspaces.remove(dateStr);
          newRequestedNames.remove(dateStr);
          newIgnoredDates.remove(dateStr);
        } else if (bookedElsewhere.containsKey(dateStr)) {
          newRequestedDates.remove(dateStr);
          newRequestedWorkspaces.remove(dateStr);
          newRequestedNames.remove(dateStr);
        }
      }

      if (OfflineStateManager.instance.isOffline) {
        showOfflineNotice();
        return;
      }

      if (mounted) {
        setState(() {
          _bookedDates = newBookedDates;
          _requestedDates = newRequestedDates;
          _requestedWorkspacesMap = newRequestedWorkspaces;
          _requestedWorkspaceNamesMap = newRequestedNames;
          _ignoredDates = newIgnoredDates;
          _bookedElsewhereMap = bookedElsewhere;
          _delegatedBookingsMap = mergedDelegated;
          _occupiedByOthers = occupiedDates;
          _allTimeBookedDates.addAll(bookedHere);
          _allTimeElsewhereDates.addAll(bookedElsewhere.keys);
          _cockpitRefreshToken++;
        });
        await _storage.saveAllTimeBookedDates(_allTimeBookedDates.toList());
        await _storage
            .saveAllTimeElsewhereDates(_allTimeElsewhereDates.toList());
        await _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
        await _storage.saveOccupiedByOthers(_occupiedByOthers);
        await _storage.saveUserReservationsMap(allUserReservations);
        await _storage.saveRequestedDates(_requestedDates.toList());
        await _storage.saveRequestedWorkspacesMap(_requestedWorkspacesMap);
        await _storage
            .saveRequestedWorkspaceNamesMap(_requestedWorkspaceNamesMap);
        await _storage.saveIgnoredDates(_ignoredDates.toList());
        await _storage.saveLastSyncTime();
        await _refreshStats();
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint('❌ _syncCalendar error: $e');
      showOfflineNotice();
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _quickBook(int daysOffset) async {
    if (_isCalendarBusy) return;

    final DateTime targetDate = addCalendarDays(DateTime.now(), daysOffset);
    if (_hideWeekends &&
        (targetDate.weekday == DateTime.saturday ||
            targetDate.weekday == DateTime.sunday)) {
      _showTopToast('Réservation le week-end désactivée.', isError: true);
      return;
    }

    final String dateStr = DateHelpers.formatIsoDate(targetDate);
    if (_bookedDates.contains(dateStr)) {
      _showTopToast('Déjà réservé !', isError: true);
      return;
    }

    final String? workspaceId = await _storage.getWorkspaceId();
    if (workspaceId == null || workspaceId.isEmpty) {
      _showTopToast(
        "Veuillez d'abord configurer votre bureau.",
        isError: true,
      );
      return;
    }

    setState(() => _isCalendarBusy = true);
    try {
      final String? token = await _api.refreshMyToken();
      if (token == null || token.isEmpty) {
        _showTopToast(
          'Impossible de réserver : vérifiez votre connexion Internet.',
          isError: true,
        );
        return;
      }

      final bool success =
          await _api.reserveWorkspace(dateStr, token, workspaceId);
      if (success) {
        await _storage.recordBookingStat(false);
        await _refreshStats();
        setState(() {
          _bookedDates.add(dateStr);
          _requestedDates.remove(dateStr);
          _ignoredDates.remove(dateStr);
        });
        await _storage.saveBookedDates(_bookedDates.toList());
        await _storage.removeRequestedDate(dateStr);
        await _storage.saveRequestedDates(_requestedDates.toList());
        await _storage.saveIgnoredDates(_ignoredDates.toList());
        await _storage.saveUserReservation(
          dateStr,
          workspaceId,
          _workspaceName ?? 'Mon bureau',
        );
        _showTopToast('Réservation confirmée !');
      } else {
        _showTopToast(
          "Ce bureau n'est plus disponible pour cette date.",
          isError: true,
        );
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      _showTopToast(
        ErrorSanitizer.sanitize(
          e,
          fallback:
              'Impossible de réserver : vérifiez votre connexion Internet.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _handleDateTap(DateTime selectedDay) async {
    if (_isCalendarBusy) return;
    final DateTime today = normalizeLocalDate(DateTime.now());
    final DateTime day = normalizeLocalDate(selectedDay);
    _syncFocusedMapDate(day);

    if (day.isBefore(today)) {
      _showTopToast('Impossible de modifier le passé.', isError: true);
      return;
    }

    final String dateStr = DateHelpers.formatIsoDate(day);
    final bool isBooked =
        _bookedDates.contains(dateStr) && _showAllReservations;
    final bool isRequested =
        _requestedDates.contains(dateStr) && _showAllReservations;
    final bool isIgnored =
        _ignoredDates.contains(dateStr) && _showAllReservations;
    final bool isElsewhere =
        _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
    final bool isDelegated =
        _delegatedBookingsMap.containsKey(dateStr) &&
            _showDelegatedReservations;
    final bool deskOccupiedByThirdParty =
        _occupiedByOthers.containsKey(dateStr);
    final int differenceInDays = calendarDaysBetween(today, day);
    final bool isBookableNow = differenceInDays <= 13;
    final bool isWeekendAndHidden = _hideWeekends &&
        (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday);

    final List<String> dParts =
        _delegatedBookingsMap[dateStr]?.split('|') ?? <String>[];
    final String dName = dParts.length > 1 ? dParts[1] : 'votre collègue';
    final String dLoc = dParts.length > 2 ? dParts[2] : '';
    final String? dCreator =
        dParts.length > 5 && dParts[5].isNotEmpty ? dParts[5] : null;

    final String? myWsId = await _storage.getWorkspaceId();
    if (!mounted) return;
    final bool isDelegatedOnMyDesk =
        isDelegated && dParts.isNotEmpty && dParts[0] == myWsId;
    final String? holidayName = _skipPublicHolidays
        ? HolidayService.getHolidayName(day, countryCode: _holidayCountryCode)
        : null;

    final String? action = await showDateActionSheet(
      context,
      dateStr: dateStr,
      holidayName: holidayName,
      isDelegated: isDelegated,
      delegateName: dName,
      delegateLocation: dLoc,
      delegateCreator: dCreator,
      isBooked: isBooked,
      isRequested: isRequested,
      isIgnored: isIgnored,
      isElsewhere: isElsewhere,
      elsewhereName: _bookedElsewhereMap[dateStr],
      deskOccupiedByThirdParty: deskOccupiedByThirdParty,
      occupiedByText: _occupiedByOthers[dateStr],
      isWeekendAndHidden: isWeekendAndHidden,
      isDelegatedOnMyDesk: isDelegatedOnMyDesk,
      isBookableNow: isBookableNow,
      requestedWorkspaceName: _requestedWorkspaceNamesMap[dateStr],
      requestedWorkspaceId: _requestedWorkspacesMap[dateStr],
    );

    if (action == null || !mounted) return;

    if (action == 'reserve_for_colleague') {
      final Colleague? colleague = await showDialog<Colleague>(
        context: context,
        builder: (BuildContext _) => ColleagueSelectionDialog(
          date: dateStr,
          deskName: _workspaceName,
          apiService: _api,
          storageService: _storage,
        ),
      );

      if (colleague != null && mounted) {
        setState(() {
          _isCalendarBusy = true;
          _focusedDay = day;
        });

        try {
          final String? token = await _api.refreshMyToken();
          final String? workspaceId = await _storage.getWorkspaceId();
          if (token != null && workspaceId != null) {
            final BookingResult result =
                await _api.reserveWorkspaceForColleague(
              date: dateStr,
              token: token,
              workspaceId: workspaceId,
              colleagueId: colleague.id,
              colleagueName: colleague.name,
              colleagueEmail: colleague.email,
            );

            if (result.status == BookingStatus.unauthorized) {
              if (mounted) {
                _showTopToast(
                  'Session expirée. Veuillez vous reconnecter.',
                  isError: true,
                );
                await _logout();
              }
            } else if (result.isSuccess) {
              final String eventId = result.eventId ?? '';
              _delegatedBookingsMap[dateStr] =
                  '$workspaceId|${colleague.name}|${_workspaceName ?? ""}|$eventId|${colleague.id}|vous';
              await _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
              _requestedDates.remove(dateStr);
              await _storage.saveRequestedDates(_requestedDates.toList());
              if (mounted) setState(() {});
            } else {
              if (mounted) {
                _showTopToast(
                  result.getLocalizedMessage(colleague.name),
                  isError: true,
                );
              }
            }
          } else {
            if (mounted) {
              _showTopToast(
                'Action impossible : serveur temporairement indisponible.',
                isError: true,
              );
            }
          }
        } catch (e) {
          OfflineStateManager.instance.reportException(e);
          if (mounted) {
            _showTopToast(
              ErrorSanitizer.sanitize(
                e,
                fallback:
                    'Erreur lors de la réservation : connexion indisponible.',
              ),
              isError: true,
            );
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
        if (_bookedDates.contains(dateStr) ||
            _bookedElsewhereMap.containsKey(dateStr)) {
          if (mounted) {
            _showTopToast(
              'Place déjà réservée (filtre désactivé)',
              isError: true,
            );
          }
          return;
        }

        if (isBookableNow) {
          setState(() {
            _ignoredDates.remove(dateStr);
            _requestedDates.remove(dateStr);
          });
          await _storage.removeRequestedDate(dateStr);
          await _storage.saveIgnoredDates(_ignoredDates.toList());

          try {
            final String? accessToken = await _api.refreshMyToken();
            if (accessToken == null || accessToken.isEmpty) {
              if (mounted) {
                _showTopToast(
                  'Impossible de réserver : vérifiez votre connexion Internet.',
                  isError: true,
                );
              }
              return;
            }

            final String? workspaceId = await _storage.getWorkspaceId();
            if (workspaceId == null || workspaceId.isEmpty) {
              if (mounted) {
                _showTopToast(
                  "Veuillez d'abord configurer votre bureau.",
                  isError: true,
                );
              }
              return;
            }

            final String targetWsId =
                _requestedWorkspacesMap[dateStr] ?? workspaceId;
            final String wsName = _requestedWorkspaceNamesMap[dateStr] ??
                _workspaceName ??
                'Mon bureau';
            final bool success =
                await _api.reserveWorkspace(dateStr, accessToken, targetWsId);
            if (success) {
              await _storage.recordBookingStat(false);
              await _refreshStats();
              if (mounted) {
                setState(() {
                  _bookedDates.add(dateStr);
                  _allTimeBookedDates.add(dateStr);
                  _requestedDates.remove(dateStr);
                  _requestedWorkspacesMap.remove(dateStr);
                  _requestedWorkspaceNamesMap.remove(dateStr);
                });
              }
              await _storage.saveBookedDates(_bookedDates.toList());
              await _storage
                  .saveAllTimeBookedDates(_allTimeBookedDates.toList());
              await _storage.removeRequestedDate(dateStr);
              await _storage.saveRequestedDates(_requestedDates.toList());
              await _storage
                  .saveRequestedWorkspacesMap(_requestedWorkspacesMap);
              await _storage
                  .saveRequestedWorkspaceNamesMap(_requestedWorkspaceNamesMap);
              await _storage.saveUserReservation(dateStr, targetWsId, wsName);
              if (mounted) {
                _showTopToast('Réservation confirmée !');
              }
            } else {
              if (mounted) {
                _showTopToast(
                  "Ce bureau n'est plus disponible à cette date",
                  isError: true,
                );
              }
            }
          } catch (e) {
            OfflineStateManager.instance.reportException(e);
            if (mounted) {
              _showTopToast(
                ErrorSanitizer.sanitize(
                  e,
                  fallback:
                      'Impossible de réserver : vérifiez votre connexion Internet.',
                ),
                isError: true,
              );
            }
          } finally {
            if (!_bookedDates.contains(dateStr)) {
              if (mounted) {
                setState(() {
                  _requestedDates.remove(dateStr);
                  _requestedWorkspacesMap.remove(dateStr);
                  _requestedWorkspaceNamesMap.remove(dateStr);
                });
              } else {
                _requestedDates.remove(dateStr);
                _requestedWorkspacesMap.remove(dateStr);
                _requestedWorkspaceNamesMap.remove(dateStr);
              }
              await _storage.removeRequestedDate(dateStr);
              await _storage.saveRequestedDates(_requestedDates.toList());
              await _storage
                  .saveRequestedWorkspacesMap(_requestedWorkspacesMap);
              await _storage
                  .saveRequestedWorkspaceNamesMap(_requestedWorkspaceNamesMap);
            }
          }
        } else {
          setState(() {
            _ignoredDates.remove(dateStr);
            _requestedDates.add(dateStr);
          });
          await _storage.saveRequestedDates(_requestedDates.toList());
          await _storage.saveIgnoredDates(_ignoredDates.toList());
          if (mounted) {
            _showTopToast('Date programmée en attente');
          }
        }
      } else if (action == 'cancel' || action == 'block') {
        if (isBooked) {
          final String? token = await _api.refreshMyToken();
          final String? workspaceId = await _storage.getWorkspaceId();
          if (token != null && workspaceId != null) {
            final String targetWsId =
                _requestedWorkspacesMap[dateStr] ?? workspaceId;
            await _api.cancelReservation(dateStr, token, targetWsId);
          }
        }
        setState(() {
          _requestedDates.remove(dateStr);
          _requestedWorkspacesMap.remove(dateStr);
          _requestedWorkspaceNamesMap.remove(dateStr);
          _bookedDates.remove(dateStr);
          _allTimeBookedDates.remove(dateStr);
          _occupiedByOthers.remove(dateStr);
          if (action == 'block') {
            _ignoredDates.add(dateStr);
          } else {
            _ignoredDates.remove(dateStr);
          }
        });
        await _storage.removeRequestedDate(dateStr);
        await _storage.saveRequestedDates(_requestedDates.toList());
        await _storage.saveRequestedWorkspacesMap(_requestedWorkspacesMap);
        await _storage
            .saveRequestedWorkspaceNamesMap(_requestedWorkspaceNamesMap);
        await _storage.saveBookedDates(_bookedDates.toList());
        await _storage.saveAllTimeBookedDates(_allTimeBookedDates.toList());
        await _storage.saveIgnoredDates(_ignoredDates.toList());
        await _storage.removeUserReservation(dateStr);
        if (action == 'cancel') {
          if (mounted) setState(() => _isCalendarBusy = false);
          await _syncCalendar();
        }
      } else if (action == 'cancel_delegation') {
        await _cancelDelegationAction(dateStr);
      } else if (action == 'cancel_elsewhere') {
        final String? token = await _api.refreshMyToken();
        if (token != null) {
          final bool success = await _api.cancelBookingByDate(token, dateStr);
          if (success) {
            await _storage.removeUserReservation(dateStr);
            if (mounted) {
              setState(() {
                _bookedElsewhereMap.remove(dateStr);
                _allTimeElsewhereDates.remove(dateStr);
              });
            }
            await _storage.saveBookedElsewhereDates(
              _bookedElsewhereMap.keys.toList(),
            );
            await _storage
                .saveAllTimeElsewhereDates(_allTimeElsewhereDates.toList());
          } else {
            if (mounted) {
              _showTopToast(
                "Impossible d'annuler la réservation.",
                isError: true,
              );
            }
          }
        }
      } else if (action == 'unblock') {
        setState(() => _ignoredDates.remove(dateStr));
        await _storage.saveIgnoredDates(_ignoredDates.toList());
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      if (mounted) {
        _showTopToast(
          ErrorSanitizer.sanitize(
            e,
            fallback: "Erreur lors de l'opération.",
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }

  Future<void> _checkUpdatesOnStartup() async {
    if (kIsWeb) return;
    final AppUpdateCheckResult result = await _updateService.checkForUpdates(
      respectIgnoredVersion: true,
    );
    if (!mounted) return;
    if (result.status == AppUpdateStatus.updateAvailable &&
        result.updateInfo != null) {
      await showUpdateAvailableDialog(
        context,
        info: result.updateInfo!,
        onIgnoreVersion: (String v) => _storage.saveIgnoredUpdateVersion(v),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    bool isLoaderOpen = false;

    void closeLoader() {
      if (isLoaderOpen && mounted) {
        isLoaderOpen = false;
        Navigator.of(context).pop();
      }
    }

    try {
      isLoaderOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext _) =>
              const Center(child: CircularProgressIndicator(color: Colors.blue)),
        ).then((void _) {
          isLoaderOpen = false;
        }),
      );

      final AppUpdateCheckResult result = await _updateService.checkForUpdates(
        respectIgnoredVersion: false,
      );
      if (!mounted) return;
      closeLoader();

      switch (result.status) {
        case AppUpdateStatus.updateAvailable:
          final AppUpdateInfo? info = result.updateInfo;
          if (info != null) {
            await showUpdateAvailableDialog(
              context,
              info: info,
              onIgnoreVersion: (String v) =>
                  _storage.saveIgnoredUpdateVersion(v),
            );
          }
        case AppUpdateStatus.upToDate:
          _showTopToast('Vous utilisez déjà la dernière version !');
        case AppUpdateStatus.serverError:
          _showTopToast(
            'Erreur serveur lors de la vérification.',
            isError: true,
          );
        case AppUpdateStatus.networkError:
          _showTopToast(
            'Impossible de vérifier les mises à jour (Pas de connexion)',
            isError: true,
          );
      }
    } catch (e) {
      closeLoader();
      if (mounted) {
        _showTopToast(
          ErrorSanitizer.sanitize(
            e,
            fallback:
                'Impossible de vérifier les mises à jour (Pas de connexion)',
          ),
          isError: true,
        );
      }
    }
  }

  void _onDestinationSelected(AppDestination destination) {
    if (destination == _selectedDestination) return;
    setState(() => _selectedDestination = destination);
    if (destination == AppDestination.home ||
        destination == AppDestination.calendar ||
        destination == AppDestination.map) {
      unawaited(_reloadPendingSchedules());
    }
    unawaited(_reloadAutomationAndSettings());
  }

  Widget _buildEmbeddedTeamMap({Key? key}) {
    return TeamMapScreen(
      key: key,
      apiService: _api,
      storageService: _storage,
      initialDate: _focusedMapDateNotifier.value,
      hideWeekends: _hideWeekends,
      isEmbedded: true,
      externalDateNotifier: _focusedMapDateNotifier,
      onReservationChanged: _handleMapReservationChanged,
    );
  }

  Widget _buildTabContent(
    AppDestination destination, {
    required bool isSplitActive,
  }) {
    switch (destination) {
      case AppDestination.home:
        return HomeDashboardTab(
          isCalendarBusy: _isCalendarBusy,
          pullToRefreshEnabled: _pullToRefreshEnabled,
          onRefresh: () => _syncCalendar(isManual: true),
          showAutomation: _showAutomation,
          vacations: _vacations,
          isVacation: _isVacation,
          workspaceName: _workspaceName,
          defaultWorkspaceId: _defaultWorkspaceId,
          onChangeWorkspace: () => unawaited(_changeWorkspace()),
          onResetWorkspace: () => unawaited(_resetWorkspace()),
          hideWeekends: _hideWeekends,
          onQuickBook: _quickBook,
          onOpenTeamMapToday: () =>
              unawaited(_openTeamMap(date: DateTime.now())),
          onOpenFavoritesManager: _openFavoritesManager,
          showAllReservations: _showAllReservations,
          onToggleShowAllReservations: (bool val) =>
              setState(() => _showAllReservations = val),
          showDelegatedReservations: _showDelegatedReservations,
          onToggleShowDelegatedReservations: (bool val) {
            setState(() => _showDelegatedReservations = val);
            unawaited(_storage.saveShowDelegatedBookings(val));
          },
          compactMode: _compactMode,
          automationEnabled: _automationEnabled,
          automationRules: _automationRules,
          selectedDays: _selectedDays,
          projectionsCount: _projectionsCount,
          skipPublicHolidays: _skipPublicHolidays,
          holidayCountryCode: _holidayCountryCode,
          ignoredDates: _ignoredDates,
          bookedDates: _bookedDates,
          requestedDates: _requestedDates,
          requestedWorkspacesMap: _requestedWorkspacesMap,
          requestedWorkspaceNamesMap: _requestedWorkspaceNamesMap,
          bookedElsewhereMap: _bookedElsewhereMap,
          delegatedBookingsMap: _delegatedBookingsMap,
          occupiedByOthers: _occupiedByOthers,
          onDateTap: _handleDateTap,
          onQuickAction: _quickAction,
          focusedDate: _focusedDay,
          onCockpitDaySelected: (DateTime day) {
            _syncFocusedMapDate(day);
            if (!isSplitActive) {
              final DateTime today = normalizeLocalDate(DateTime.now());
              if (!normalizeLocalDate(day).isBefore(today)) {
                unawaited(_handleDateTap(day));
              } else {
                unawaited(_openTeamMap(date: day));
              }
            }
          },
          storageService: _storage,
          floorId: _floorId,
          showFavoriteWeekIndicators: _showFavoriteWeekIndicators,
          cockpitRefreshToken: _cockpitRefreshToken,
        );
      case AppDestination.map:
        return _buildEmbeddedTeamMap(
          key: const ValueKey<String>('embedded_tab_team_map'),
        );
      case AppDestination.calendar:
        return CalendarTab(
          workspaceName: _workspaceName,
          isCalendarBusy: _isCalendarBusy,
          pullToRefreshEnabled: _pullToRefreshEnabled,
          onRefresh: () => _syncCalendar(isManual: true),
          onOpenFavoritesManager: _openFavoritesManager,
          onOpenTeamMapFocused: () =>
              unawaited(_openTeamMap(date: _focusedDay)),
          onManualSync: () => unawaited(_syncCalendar(isManual: true)),
          showAllReservations: _showAllReservations,
          onToggleShowAllReservations: (bool val) =>
              setState(() => _showAllReservations = val),
          showDelegatedReservations: _showDelegatedReservations,
          onToggleShowDelegatedReservations: (bool val) {
            setState(() => _showDelegatedReservations = val);
            unawaited(_storage.saveShowDelegatedBookings(val));
          },
          focusedDay: _focusedDay,
          onPageChanged: (DateTime focusedDay) {
            _focusedDay = focusedDay;
          },
          onDateTap: _handleDateTap,
          hideWeekends: _hideWeekends,
          showAutomation: _showAutomation,
          vacations: _vacations,
          compactMode: _compactMode,
          skipPublicHolidays: _skipPublicHolidays,
          holidayCountryCode: _holidayCountryCode,
          bookedDates: _bookedDates,
          requestedDates: _requestedDates,
          ignoredDates: _ignoredDates,
          bookedElsewhereMap: _bookedElsewhereMap,
          delegatedBookingsMap: _delegatedBookingsMap,
          occupiedByOthers: _occupiedByOthers,
        );
      case AppDestination.automation:
        return AutomationTab(
          isCalendarBusy: _isCalendarBusy,
          hideWeekends: _hideWeekends,
          showAutomation: _showAutomation,
          automationEnabled: _automationEnabled,
          automationTime: _automationTime,
          vacations: _vacations,
          automationRules: _automationRules,
          onAddVacation: _handleAddVacation,
          onDeleteVacation: _handleDeleteVacation,
          onToggleAutomation: _toggleAutomation,
          onAutomationTimeChanged: (TimeOfDay time) async {
            setState(() => _automationTime = time);
            await _storage.saveAutomationTime(time.hour, time.minute);
            await _toggleAutomation(true);
          },
          onRunAutomationNow: _runAutomationNow,
          onAddAutomationPlace: _addAutomationPlace,
          onChangeRulePlace: _changeRulePlace,
          onDeleteAutomationRule: _deleteAutomationRule,
          onRuleDayPressed: _onRuleDayPressed,
        );
      case AppDestination.stats:
        return StatsTab(
          statsMap: _statsMap,
          bookedDates: _bookedDates,
          bookedElsewhereMap: _bookedElsewhereMap,
          selectedDays: _selectedDays,
          workspaceName: _workspaceName,
        );
      case AppDestination.settings:
        return SettingsTab(
          initialTab: _initialTab,
          onInitialTabChanged: (int val) {
            final int safeVal = _sanitizeInitialTab(
              val,
              showAutomation: _showAutomation,
              showStats: _showStats,
            );
            setState(() => _initialTab = safeVal);
            unawaited(_storage.saveInitialTab(safeVal));
          },
          showAutomation: _showAutomation,
          onShowAutomationChanged: (bool val) {
            setState(() {
              _showAutomation = val;
              if (!val && _initialTab == 2) {
                _initialTab = 0;
                unawaited(_storage.saveInitialTab(0));
              }
              if (!val && _selectedDestination == AppDestination.automation) {
                _selectedDestination = AppDestination.home;
              }
              if (!val && _automationEnabled) {
                unawaited(_toggleAutomation(false));
              }
            });
            unawaited(_storage.saveShowAutomation(val));
          },
          showStats: _showStats,
          onShowStatsChanged: (bool val) {
            setState(() {
              _showStats = val;
              if (!val && _initialTab == 3) {
                _initialTab = 0;
                unawaited(_storage.saveInitialTab(0));
              }
              if (!val && _selectedDestination == AppDestination.stats) {
                _selectedDestination = AppDestination.home;
              }
            });
            unawaited(_storage.saveShowStats(val));
          },
          pullToRefreshEnabled: _pullToRefreshEnabled,
          onPullToRefreshChanged: (bool val) {
            setState(() => _pullToRefreshEnabled = val);
            unawaited(_storage.savePullToRefresh(val));
          },
          showFavoriteWeekIndicators: _showFavoriteWeekIndicators,
          onShowFavoriteWeekIndicatorsChanged: (bool val) {
            setState(() => _showFavoriteWeekIndicators = val);
            unawaited(_storage.saveShowFavoriteWeekIndicators(val));
          },
          projectionsCount: _projectionsCount,
          onProjectionsCountChanged: (int val) {
            setState(() => _projectionsCount = val);
            unawaited(_storage.saveProjectionsCount(val));
          },
          hideWeekends: _hideWeekends,
          onHideWeekendsChanged: (bool val) {
            setState(() => _hideWeekends = val);
            unawaited(_storage.saveHideWeekends(val));
          },
          skipPublicHolidays: _skipPublicHolidays,
          onSkipPublicHolidaysChanged: (bool val) {
            setState(() => _skipPublicHolidays = val);
            unawaited(_storage.saveSkipPublicHolidays(val));
          },
          holidayCountryCode: _holidayCountryCode,
          onHolidayCountryCodeChanged: (String val) {
            setState(() => _holidayCountryCode = val);
            unawaited(_storage.saveHolidayCountryCode(val));
          },
          compactMode: _compactMode,
          onCompactModeChanged: (bool val) {
            setState(() => _compactMode = val);
            unawaited(_storage.saveCompactMode(val));
          },
          notifySuccess: _notifySuccess,
          onNotifySuccessChanged: (bool val) {
            setState(() => _notifySuccess = val);
            unawaited(_storage.saveNotifySuccess(val));
          },
          notifyFailure: _notifyFailure,
          onNotifyFailureChanged: (bool val) {
            setState(() => _notifyFailure = val);
            unawaited(_storage.saveNotifyFailure(val));
          },
          appVersion: _appVersion,
          onCheckForUpdates: _checkForUpdates,
          onSaveThemeModeIndex: (int idx) =>
              unawaited(_storage.saveThemeModeIndex(idx)),
          onSaveThemeColorIndex: (int idx) =>
              unawaited(_storage.saveThemeColorIndex(idx)),
          onSaveFontFamilyIndex: (int idx) =>
              unawaited(_storage.saveFontFamilyIndex(idx)),
          onSaveUiScale: (double scale) =>
              unawaited(_storage.saveUiScale(scale)),
          onExportProfile: () => unawaited(
            showExportProfileDialog(context, storage: _storage),
          ),
          onImportProfile: () => unawaited(
            showImportProfileDialog(
              context,
              storage: _storage,
              onImportSuccess: (ProfileImportResult _) async {
                await _reloadThemePreferencesFromStorage();
                await _loadData();
              },
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_isLoading) {
      content = Scaffold(
        body: FunLoadingWidget(messageNotifier: _loadingTextNotifier),
      );
    } else {
      final List<AdaptiveNavItem> destinations = <AdaptiveNavItem>[
        const AdaptiveNavItem(
          destination: AppDestination.home,
          label: 'Accueil',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        const AdaptiveNavItem(
          destination: AppDestination.map,
          label: 'Plan',
          icon: Icons.map_outlined,
          selectedIcon: Icons.map_rounded,
        ),
        const AdaptiveNavItem(
          destination: AppDestination.calendar,
          label: 'Calendrier',
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month_rounded,
        ),
        if (_showAutomation && !kIsWeb)
          const AdaptiveNavItem(
            destination: AppDestination.automation,
            label: 'Automate',
            icon: Icons.auto_awesome_outlined,
            selectedIcon: Icons.auto_awesome,
          ),
        if (_showStats)
          const AdaptiveNavItem(
            destination: AppDestination.stats,
            label: 'Stats',
            icon: Icons.insights_outlined,
            selectedIcon: Icons.insights_rounded,
          ),
        const AdaptiveNavItem(
          destination: AppDestination.settings,
          label: 'Paramètres',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
        ),
      ];

      final AppDestination activeDest = _isDestinationVisible(
        _selectedDestination,
        showAutomation: _showAutomation,
        showStats: _showStats,
      )
          ? _selectedDestination
          : AppDestination.home;

      final bool isExpandedWidth = MediaQuery.sizeOf(context).width >= 1100;
      final bool splitEligibleTab = activeDest == AppDestination.home ||
          activeDest == AppDestination.calendar;
      final bool isSplitActive =
          isExpandedWidth && _canShowSplitMap && _isSplitMapVisible && splitEligibleTab;

      final PreferredSizeWidget appBar = AppBar(
        title: const Text('AutoRoomzio'),
        actions: <Widget>[
          if (isExpandedWidth && _canShowSplitMap && splitEligibleTab)
            IconButton(
              key: const ValueKey<String>('toggle_split_map_button'),
              icon: Icon(
                _isSplitMapVisible
                    ? Icons.vertical_split_rounded
                    : Icons.vertical_split_outlined,
              ),
              tooltip: _isSplitMapVisible
                  ? 'Masquer le plan combiné'
                  : 'Afficher le plan combiné',
              onPressed: () =>
                  setState(() => _isSplitMapVisible = !_isSplitMapVisible),
            ),
          if (_isAndroid && _automationEnabled)
            IconButton(
              icon: Icon(
                Icons.shield_rounded,
                color: _permissionStatus == 1
                    ? Colors.green
                    : (_permissionStatus == 2
                        ? Colors.orange
                        : Colors.red.shade300),
              ),
              tooltip: 'Statut des permissions',
              onPressed: () {
                unawaited(
                  Navigator.of(context)
                      .push<void>(
                        MaterialPageRoute<void>(
                          builder: (BuildContext _) =>
                              const OptimizationScreen(),
                        ),
                      )
                      .then((void _) => _checkPermissionsStatus()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Lier un appareil Web',
            onPressed: () => unawaited(
              showWebPairingDialog(
                context,
                storage: _storage,
                workspaceId: _defaultWorkspaceId,
                workspaceName: _workspaceName,
                onLoggedOut: () => unawaited(_logout()),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => unawaited(_logout()),
          ),
        ],
      );

      final Widget body = SizedBox.expand(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          layoutBuilder: (
            Widget? currentChild,
            List<Widget> previousChildren,
          ) {
            return Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                ?currentChild,
              ],
            );
          },
          transitionBuilder: (
            Widget child,
            Animation<double> animation,
          ) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<AppDestination>(activeDest),
            child: _buildTabContent(activeDest, isSplitActive: isSplitActive),
          ),
        ),
      );

      content = AdaptiveAppShell(
        destinations: destinations,
        selectedDestination: activeDest,
        onDestinationSelected: _onDestinationSelected,
        appBar: appBar,
        body: body,
        fullWidthBody: activeDest == AppDestination.map,
        showSplitMap: _canShowSplitMap && _isSplitMapVisible && splitEligibleTab,
        splitMapPanel: (_canShowSplitMap && splitEligibleTab)
            ? _buildEmbeddedTeamMap(
                key: const ValueKey<String>('embedded_split_team_map'),
              )
            : null,
      );
    }

    return PopScope(
      canPop: _canExit,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;

        setState(() {
          _canExit = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appuyez à nouveau pour quitter'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            duration: Duration(seconds: 2),
          ),
        );
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _canExit = false;
            });
          }
        });
      },
      child: content,
    );
  }
}
