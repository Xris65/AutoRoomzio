import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:table_calendar/table_calendar.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
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
  bool _autoSync = true;
  int _projectionsCount = 4;

  @override
  void initState() {
    super.initState();
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
    final autoEnabled = await _storage.getAutomationEnabled();
    final autoTimeMap = await _storage.getAutomationTime();
    final notifSuccess = await _storage.getNotifySuccess();
    final notifFailure = await _storage.getNotifyFailure();
    final autoSync = await _storage.getAutoSync();
    final projCount = await _storage.getProjectionsCount();
    
    if (mounted) {
      setState(() {
        _selectedDays = days;
        _workspaceName = name;
        _requestedDates = requested.toSet();
        _bookedDates = booked.toSet();
        _ignoredDates = ignored.toSet();
        _automationEnabled = autoEnabled;
        _automationTime = TimeOfDay(hour: autoTimeMap['hour']!, minute: autoTimeMap['minute']!);
        _notifySuccess = notifSuccess;
        _notifyFailure = notifFailure;
        _autoSync = autoSync;
        _projectionsCount = projCount;
      });
    }

    if (_autoSync) {
      await _syncCalendar();
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAutomation(bool val) async {
    setState(() => _automationEnabled = val);
    await _storage.saveAutomationEnabled(val);

    if (val) {
      if (Platform.isAndroid) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Automatisation activée'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (Platform.isAndroid) {
        Workmanager().cancelAll();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Automatisation désactivée')),
        );
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SetupScreen(accessToken: token)),
    ).then((_) => _loadData());
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

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: FunLoadingWidget());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoRoomzio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildCalendarTab(),
          _buildAutomationTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Calendrier'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Automate'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Paramètres'),
        ],
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
                  const SizedBox(height: 24),

                  // ── Prochaines réservations ──────────────────────────────────
                  if (_workspaceName != null) ...[
                    const Text(
                      '🔮 Prochaines réservations',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
      bool isRecurring = _automationEnabled && _selectedDays.contains(date.weekday);

      if (isRequested) {
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
            leading: Icon(
              isBooked ? Icons.check_circle : Icons.pending,
              color: isBooked ? Colors.green : Colors.blue,
            ),
            title: Text('$weekDayName ${date.day}/${date.month}'),
            subtitle: Text(
              isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)',
              style: TextStyle(color: isBooked ? Colors.green : Colors.blue, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(source, style: const TextStyle(fontSize: 10)),
                  backgroundColor: source == 'Calendrier' 
                    ? Colors.purple.withValues(alpha: 0.1) 
                    : Colors.orange.withValues(alpha: 0.1),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(source == 'Calendrier' ? Icons.delete_outline : Icons.block, size: 20),
                  color: Colors.redAccent,
                  tooltip: source == 'Calendrier' ? 'Supprimer' : 'Bloquer',
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Mon Calendrier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Synchroniser avec MyRoomz',
                onPressed: _syncCalendar,
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
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
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
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegend(Colors.green, 'Réservé'),
              _buildLegend(Colors.blue, 'En attente'),
              _buildLegend(Colors.red.withValues(alpha: 0.8), 'Bloqué'),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildDayCell(DateTime day, {bool isToday = false, bool isOutside = false}) {
    final dateStr = day.toIso8601String().split('T').first;
    final isBooked = _bookedDates.contains(dateStr);
    final isRequested = _requestedDates.contains(dateStr);
    final isIgnored = _ignoredDates.contains(dateStr);

    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;

    if (isBooked) {
      bgColor = Colors.green;
      textColor = Colors.white;
    } else if (isRequested) {
      bgColor = Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: 0.8);
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: 0.3);
    }

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(color: textColor, fontWeight: (isBooked || isRequested || isIgnored) ? FontWeight.bold : FontWeight.normal),
      ),
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
        if (source == 'Récurrent') {
          _ignoredDates.add(dateStr); // Only block automation
        }
      });
      _storage.saveRequestedDates(_requestedDates.toList());
      _storage.saveBookedDates(_bookedDates.toList());
      if (source == 'Récurrent') {
        _storage.saveIgnoredDates(_ignoredDates.toList());
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(source == 'Calendrier' ? 'Réservation supprimée' : 'Jour bloqué ($dateStr)')),
        );
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
        final dateStr = targetDate.toIso8601String().split('T').first;

        if (_ignoredDates.contains(dateStr) || _bookedDates.contains(dateStr)) continue;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(addedCount > 0 
              ? '✅ $addedCount réservation(s) ajoutée(s) !' 
              : '✅ Le planning est déjà à jour (aucune nouvelle place réservable)'),
            backgroundColor: addedCount > 0 ? Colors.green : Colors.blue,
          ),
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
      final accessToken = await _api.refreshMyToken();
      if (accessToken == null) return;

      // Check requested dates + the next 13 days
      Set<String> datesToCheck = Set.from(_requestedDates);
      final now = DateTime.now();
      for (int i = 0; i <= 13; i++) {
        final d = now.add(Duration(days: i));
        datesToCheck.add(d.toIso8601String().split('T').first);
      }

      Set<String> newBookedDates = {};
      Set<String> newRequestedDates = Set.from(_requestedDates);
      Set<String> newIgnoredDates = Set.from(_ignoredDates);

      for (final dateStr in datesToCheck) {
        final isReserved = await _api.isAlreadyReserved(dateStr, accessToken, floorId, workspaceId);
        
        if (isReserved) {
          newBookedDates.add(dateStr);
          newRequestedDates.add(dateStr);
          newIgnoredDates.remove(dateStr); // If it's booked, override ignore
        } else {
          if (_bookedDates.contains(dateStr)) {
            // It was booked locally but not on server -> user cancelled it externally
            newRequestedDates.remove(dateStr);
          }
        }
      }

      if (mounted) {
        setState(() {
          _bookedDates = newBookedDates;
          _requestedDates = newRequestedDates;
          _ignoredDates = newIgnoredDates;
        });
        _storage.saveBookedDates(_bookedDates.toList());
        _storage.saveRequestedDates(_requestedDates.toList());
        _storage.saveIgnoredDates(_ignoredDates.toList());
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de modifier le passé.')),
      );
      return;
    }

    final dateStr = day.toIso8601String().split('T').first;
    final isBooked = _bookedDates.contains(dateStr);
    final isRequested = _requestedDates.contains(dateStr);
    final isIgnored = _ignoredDates.contains(dateStr);

    final differenceInDays = day.difference(today).inDays;
    final isBookableNow = differenceInDays <= 13;

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
              if (!isIgnored)
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: const Text('Bloquer (Ignorer l\'automatisation)'),
                  onTap: () => Navigator.pop(context, 'block'),
                ),
              if (isIgnored)
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
      } else if (action == 'unblock') {
        setState(() => _ignoredDates.remove(dateStr));
        _storage.saveIgnoredDates(_ignoredDates.toList());
      }
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
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
                    value: currentMode == ThemeMode.dark,
                    onChanged: (val) {
                      themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                      _storage.saveDarkMode(val);
                    },
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Couleur du thème'),
                leading: const Icon(Icons.color_lens_rounded),
                trailing: DropdownButton<int>(
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
              SwitchListTile(
                title: const Text('Synchronisation au démarrage'),
                subtitle: const Text('Mettre à jour le calendrier à l\'ouverture de l\'app. Cela permet d\'afficher des données fiables.', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.sync),
                value: _autoSync,
                onChanged: (val) {
                  setState(() => _autoSync = val);
                  _storage.saveAutoSync(val);
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Prévisions à afficher'),
                subtitle: const Text('Nombre de réservations futures dans l\'accueil', style: TextStyle(fontSize: 12)),
                leading: const Icon(Icons.format_list_numbered),
                trailing: DropdownButton<int>(
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
          child: const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Version'),
            trailing: Text('1.0.0'),
          ),
        ),
      ],
    );
  }
}

