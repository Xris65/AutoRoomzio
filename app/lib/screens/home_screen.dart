import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:table_calendar/table_calendar.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
import 'optimization_screen.dart';
import '../widgets/fun_loading_widget.dart';
import '../main.dart'; // for themeNotifier

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  final _api = RoomzApiService();

  List<int> _selectedDays = [];
  String? _workspaceName;
  bool _isLoading = true;
  bool _isCalendarBusy = false;
  bool _automationEnabled = false;

  // Calendar State
  DateTime _focusedDay = DateTime.now();
  Set<String> _requestedDates = {};
  Set<String> _bookedDates = {};
  Set<String> _ignoredDates = {};
  Map<String, String> _bookedElsewhereMap = {};
  Map<String, String> _occupiedByOthers = {};

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
  bool _hideWeekends = true; // Actif par défaut
  List<DateTimeRange> _vacations = [];

  bool _compactMode = false;
  bool _showAllReservations = true;
  final ValueNotifier<String> _loadingTextNotifier = ValueNotifier("Démarrage d'AutoRoomzio...");
  int _currentIndex = 0;
  late PageController _pageController;

  bool _isVacation(DateTime date) {
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
        margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final token = await _storage.getRefreshToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation1, animation2) => const LoginScreen(),
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

  Future<void> _loadData() async {
    final days = await _storage.getDays();
    final name = await _storage.getWorkspaceName();
    final requested = await _storage.getRequestedDates();
    final booked = await _storage.getBookedDates();
    final ignored = await _storage.getIgnoredDates();
    final elsewhere = await _storage.getBookedElsewhereDates();
    final autoEnabled = await _storage.getAutomationEnabled();
    final autoTimeMap = await _storage.getAutomationTime();
    final notifSuccess = await _storage.getNotifySuccess();
    final notifFailure = await _storage.getNotifyFailure();
    final projCount = await _storage.getProjectionsCount();
    final initialTab = await _storage.getInitialTab();
    final hideWe = await _storage.getHideWeekends();
    final vacs = await _storage.getVacations();
    final comp = await _storage.getCompactMode();
    
    if (mounted) {
      setState(() {
        _selectedDays = days;
        _workspaceName = name;
        _requestedDates = requested.toSet();
        _bookedDates = booked.toSet();
        _ignoredDates = ignored.toSet();
        _bookedElsewhereMap = {for (var d in elsewhere) d: "Ailleurs"};
        _automationEnabled = autoEnabled;
        _automationTime = TimeOfDay(hour: autoTimeMap['hour']!, minute: autoTimeMap['minute']!);
        _notifySuccess = notifSuccess;
        _notifyFailure = notifFailure;
        _projectionsCount = projCount;
        _hideWeekends = hideWe;
        _vacations = vacs.map((v) => DateTimeRange(
          start: DateTime.parse(v['start']!),
          end: DateTime.parse(v['end']!),
        )).toList();
        _compactMode = comp;
        if (_currentIndex == 0 && initialTab != 0) {
          _currentIndex = initialTab;
          _pageController.dispose();
          _pageController = PageController(initialPage: _currentIndex);
        }
      });
    }

    // Fetch latest bookings from API every time
    await _syncCalendar();
    

    await _checkPermissionsStatus();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  int _permissionStatus = 0;

  Future<void> _checkPermissionsStatus() async {
    if (!Platform.isAndroid) return;
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
      if (Platform.isAndroid) {
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
      if (Platform.isAndroid) {
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
      _logout();
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

  Future<void> _logout() async {
    await _storage.clearAll();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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
    if (_isLoading) {
      return Scaffold(body: FunLoadingWidget(messageNotifier: _loadingTextNotifier));
    }

    return Scaffold(
      appBar: AppBar(
          title: const Text('AutoRoomzio'),
          actions: [
            if (Platform.isAndroid && _automationEnabled)
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
            IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: _logout,
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        children: [
          _buildHomeTab(),
          _buildCalendarTab(),
          _buildAutomationTab(),
          _buildSettingsTab(),
        ],
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
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Accueil'),
                _buildNavItem(1, Icons.calendar_month_rounded, 'Calendrier'),
                _buildNavItem(2, Icons.auto_awesome, 'Automate'),
                _buildNavItem(3, Icons.settings_rounded, 'Paramètres'),
              ],
            ),
          ),
        ),
      ),
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
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
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

  Widget _buildHomeTab() {
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
                  if (_vacations.any((v) => DateTime.now().isAfter(v.start.subtract(const Duration(days: 1))) && DateTime.now().isBefore(v.end.add(const Duration(days: 1)))))
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
                    // ── 📊 Stats & Quick Actions ──────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            elevation: 0,
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              child: Column(
                                children: [
                                  Text(
                                    '${_bookedDates.where((d) => d.startsWith(DateTime.now().toIso8601String().substring(0, 7))).length}',
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('réservés ce mois', style: TextStyle(fontSize: 10), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final today = DateTime.now();
                              final tomorrow = today.add(const Duration(days: 1));
                              final todayIsWeekend = today.weekday == DateTime.saturday || today.weekday == DateTime.sunday;
                              final tomorrowIsWeekend = tomorrow.weekday == DateTime.saturday || tomorrow.weekday == DateTime.sunday;

                              final todayIsVacation = _isVacation(today);
                              final tomorrowIsVacation = _isVacation(tomorrow);

                              final disableToday = todayIsVacation || (_hideWeekends && todayIsWeekend);
                              final disableTomorrow = tomorrowIsVacation || (_hideWeekends && tomorrowIsWeekend);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                    icon: Icon(todayIsVacation ? Icons.beach_access : (disableToday ? Icons.weekend : Icons.flash_on), size: 16),
                                    label: Text(todayIsVacation ? 'En Congés' : (disableToday ? 'Aujourd\'hui (Week-end)' : 'Aujourd\'hui'), style: const TextStyle(fontSize: 11)),
                                    onPressed: disableToday ? null : () => _quickBook(0),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                    icon: Icon(tomorrowIsVacation ? Icons.beach_access : (disableTomorrow ? Icons.weekend : Icons.flash_on), size: 16),
                                    label: Text(tomorrowIsVacation ? 'En Congés' : (disableTomorrow ? 'Demain (Week-end)' : 'Demain'), style: const TextStyle(fontSize: 11)),
                                    onPressed: disableTomorrow ? null : () => _quickBook(1),
                                  ),
                                ],
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Prochaines réservations ──────────────────────────────────
                  if (_workspaceName != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🔮 Prochaines réservations',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        FilterChip(
                          label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          selected: _showAllReservations,
                          onSelected: (val) => setState(() => _showAllReservations = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildUpcomingBookings(),
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
                          ..._vacations.map((v) {
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
                                  
                                  setState(() => _vacations.add(picked!));
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
      
      bool isBooked = _bookedDates.contains(dateStr);
      bool isRequested = _requestedDates.contains(dateStr);
      bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr);
      bool isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers.containsKey(dateStr);
      bool isRecurring = _automationEnabled && _selectedDays.contains(date.weekday);
      if (_isVacation(date)) isRecurring = false;

      if (isElsewhere) {
        if (_showAllReservations) {
          upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
        } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
          upcoming.add({"date": date, "source": "Ailleurs", "isBooked": false, "name": _bookedElsewhereMap[dateStr]});
          recurringProjectionsCount++;
        }
      } else if (isOccupiedByOthers) {
        if (isRecurring && recurringProjectionsCount < _projectionsCount) {
          upcoming.add({"date": date, "source": "Occupé", "isBooked": false, "name": _occupiedByOthers[dateStr]});
          recurringProjectionsCount++;
        }
      } else if (isRequested) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": isBooked});
      } else if (isBooked) {
        // Réservation orpheline ou issue d'une récurrence
        String source = isRecurring ? "Récurrent" : "Calendrier";
        upcoming.add({"date": date, "source": source, "isBooked": true});
      } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
        // Projection future de l'automatisation
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
            leading: Icon(
              source == 'Ailleurs' ? Icons.person : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending)),
              color: source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue)),
            ),
            title: Text('$weekDayName ${date.day}/${date.month}'),
            subtitle: Text(
              source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)')),
              style: TextStyle(color: source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue)), fontSize: _compactMode ? 10 : 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(source, style: const TextStyle(fontSize: 10)),
                  backgroundColor: source == 'Calendrier' 
                    ? Colors.purple.withValues(alpha: 0.1) 
                    : (source == 'Ailleurs' ? Colors.orange.withValues(alpha: 0.3) : (source == 'Occupé' ? Colors.grey.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1))),
                  visualDensity: VisualDensity.compact,
                ),
                if (source != 'Occupé')
                  IconButton(
                    icon: Icon(isBooked ? Icons.delete_outline : Icons.block, size: 20),
                    color: Colors.redAccent,
                    tooltip: isBooked ? 'Supprimer' : 'Bloquer',
                    onPressed: () => _quickAction(date, isBooked, source),
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

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Mon Calendrier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    FilterChip(
                      label: const Text("Toutes mes réservations"),
                      selected: _showAllReservations,
                      onSelected: (val) => setState(() => _showAllReservations = val),
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
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              AbsorbPointer(
                absorbing: _isCalendarBusy,
                child: Opacity(
                  opacity: _isCalendarBusy ? 0.5 : 1.0,
                  child: TableCalendar(
                    enabledDayPredicate: (day) {
                      final normDay = DateTime(day.year, day.month, day.day);
                      if (_hideWeekends && (normDay.weekday == DateTime.saturday || normDay.weekday == DateTime.sunday)) {
                        return false;
                      }
                      for (final v in _vacations) {
                        final start = DateTime(v.start.year, v.start.month, v.start.day);
                        final end = DateTime(v.end.year, v.end.month, v.end.day);
                        if (!normDay.isBefore(start) && !normDay.isAfter(end)) {
                          return false;
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegend(Colors.green, 'Réservé'),
                _buildLegend(Colors.blue, 'En attente'),
                _buildLegend(Colors.red.withValues(alpha: 0.8), 'Bloqué'),
                _buildLegend(Colors.orange.shade300, 'Ailleurs 👤'),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDayCell(DateTime day, {bool isToday = false, bool isOutside = false}) {
    final dateStr = day.toIso8601String().split('T').first;
    final isBooked = _bookedDates.contains(dateStr);
    final isRequested = _requestedDates.contains(dateStr);
    final isIgnored = _ignoredDates.contains(dateStr);
    final isElsewhere = !isBooked && _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
    final isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers.containsKey(dateStr);

    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;
    bool strikeThrough = false;

    if (isBooked) {
      bgColor = Colors.green;
      textColor = Colors.white;
    } else if (isRequested) {
      bgColor = Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: 0.8);
      textColor = Colors.white;
    } else if (isElsewhere) {
      bgColor = Colors.orange.shade200;
      textColor = Colors.orange.shade900;
      strikeThrough = false;
    } else if (isOccupiedByOthers) {
      bgColor = Colors.grey.shade400;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: 0.3);
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
        // Small "🔒" indicator for occupied by others
        if (isOccupiedByOthers)
          Positioned(
            bottom: 4,
            right: 4,
            child: Icon(Icons.person, size: 8, color: Colors.orange.shade700),
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

  Future<void> _quickAction(DateTime day, bool isBooked, String source) async {
    final dateStr = day.toIso8601String().split('T').first;
    
    setState(() => _isCalendarBusy = true);
    try {
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

        // If not ignored/booked and it's either already requested or a valid automation day
        if (_requestedDates.contains(dateStr) || _selectedDays.contains(targetDate.weekday)) {
          final success = await _api.reserveWorkspace(dateStr, token, workspaceId);
          if (success) {
            _bookedDates.add(dateStr);
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
      final occupiedDates = floorId != null ? await _api.getWorkspaceOccupancy(accessToken, workspaceId, floorId, visibleDates) : <String, String>{};

      final myBookings = await _api.getMyReservations(accessToken, workspaceId);
      final bookedHere = myBookings.here;
      final bookedElsewhere = myBookings.elsewhere;

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
    final isBooked = _bookedDates.contains(dateStr);
    final isRequested = _requestedDates.contains(dateStr);
    final isIgnored = _ignoredDates.contains(dateStr);
    final isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
    final isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers.containsKey(dateStr);

    final differenceInDays = day.difference(today).inDays;
    final isBookableNow = differenceInDays <= 13;

    final isWeekendAndHidden = _hideWeekends && (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday);

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
              if (!isBooked && !isRequested)
                if (isWeekendAndHidden)
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
                else if (isOccupiedByOthers)
                  ListTile(
                    leading: const Icon(Icons.person_off, color: Colors.grey),
                    title: const Text('Place indisponible', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text("Réservé par ${_occupiedByOthers[dateStr]}.", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  )
                else
                  ListTile(
                    leading: Icon(
                      isBookableNow ? Icons.check_circle_outline : Icons.pending_actions,
                      color: isBookableNow ? Colors.green : Colors.blue
                    ),
                    title: Text(isBookableNow ? 'Réserver ce jour' : 'Programmer (En attente)'),
                    onTap: () => Navigator.pop(context, 'reserve'),
                  ),
              if (isBooked || isRequested)
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text(isBooked ? 'Libérer la place' : 'Annuler la demande'),
                  onTap: () => Navigator.pop(context, 'cancel'),
                ),
              if (!isIgnored && !isWeekendAndHidden && !isElsewhere)
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: const Text('Bloquer (Ignorer l\'automatisation)'),
                  onTap: () => Navigator.pop(context, 'block'),
                ),
              if (isIgnored && !isWeekendAndHidden)
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

    setState(() {
      _isCalendarBusy = true;
      _focusedDay = day;
    });

    try {
      if (action == 'reserve') {
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
              setState(() => _bookedDates.add(dateStr));
              _storage.saveBookedDates(_bookedDates.toList());
              if (mounted) _showTopToast('Place réservée pour le $dateStr', isSuccess: true);
            } else {
              if (mounted) _showTopToast('Ce bureau n\'est plus disponible à cette date', isError: true);
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
          if (action == 'block') {
            _ignoredDates.add(dateStr);
          }
        });
        _storage.saveRequestedDates(_requestedDates.toList());
        _storage.saveBookedDates(_bookedDates.toList());
        _storage.saveIgnoredDates(_ignoredDates.toList());
      } else if (action == 'cancel_elsewhere') {
        final token = await _api.refreshMyToken();
        if (token != null) {
          final success = await _api.cancelBookingByDate(token, dateStr);
          if (success) {
            setState(() {
               _bookedElsewhereMap.remove(dateStr);
            });
            _storage.saveBookedElsewhereDates(_bookedElsewhereMap.keys.toList());
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

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Général', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
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
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Accueil (par défaut)')),
                        DropdownMenuItem(value: 1, child: Text('Calendrier')),
                        DropdownMenuItem(value: 2, child: Text('Automate')),
                      ],
                    ),
                  );
                }
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

              ListTile(
                title: const Text('Prévisions à afficher'),
                subtitle: const Text('Nombre de réservations futures dans l\'accueil', style: TextStyle(fontSize: 12)),
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
        const Text('Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
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
                subtitle: const Text('Grise le samedi et dimanche, et empêche toute réservation (auto ou manuelle)', style: TextStyle(fontSize: 12)),
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
                subtitle: const Text('Être notifié quand l\'automatisation réserve une place', style: TextStyle(fontSize: 12)),
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
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('À propos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              return ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                trailing: Text(snapshot.hasData ? snapshot.data!.version : '...'),
              );
            },
          ),
        ),
      ],
    );
  }
}















