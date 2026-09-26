import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:table_calendar/table_calendar.dart';
import '../api_service.dart';
import '../storage_service.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
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

  final Map<int, String> _weekDays = {
    1: 'Lundi',
    2: 'Mardi',
    3: 'Mercredi',
    4: 'Jeudi',
    5: 'Vendredi',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final days = await _storage.getDays();
    final name = await _storage.getWorkspaceName();
    final requested = await _storage.getRequestedDates();
    final booked = await _storage.getBookedDates();
    final autoEnabled = await _storage.getAutomationEnabled();
    if (mounted) {
      setState(() {
        _selectedDays = days;
        _workspaceName = name;
        _requestedDates = requested.toSet();
        _bookedDates = booked.toSet();
        _automationEnabled = autoEnabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAutomation(bool val) async {
    setState(() => _automationEnabled = val);
    await _storage.saveAutomationEnabled(val);

    if (val) {
      if (Platform.isAndroid) {
        Workmanager().registerPeriodicTask(
          "1",
          "autoReservationTask",
          frequency: const Duration(hours: 24),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Calendrier'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Paramètres'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
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

          // ── Toggle Automatisation ────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              title: const Text('Automatisation', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Réserver automatiquement mes places', style: TextStyle(fontSize: 12)),
              value: _automationEnabled,
              onChanged: _workspaceName == null ? null : _toggleAutomation,
              secondary: Icon(
                _automationEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                color: _automationEnabled ? Colors.green : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Jours récurrents ─────────────────────────────────────────
          const Text(
            '📅 Jours de présence au bureau',
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
    );
  }

  Widget _buildUpcomingBookings() {
    List<Map<String, dynamic>> upcoming = [];
    final now = DateTime.now();
    for (int i = 0; upcoming.length < 4 && i < 60; i++) {
      final date = now.add(Duration(days: i));
      final dateStr = date.toIso8601String().split('T').first;
      
      if (_requestedDates.contains(dateStr)) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": _bookedDates.contains(dateStr)});
      } else if (_automationEnabled && _selectedDays.contains(date.weekday)) {
        upcoming.add({"date": date, "source": "Récurrent", "isBooked": _bookedDates.contains(dateStr)});
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
            trailing: Chip(
              label: Text(source, style: const TextStyle(fontSize: 10)),
              backgroundColor: source == 'Calendrier' 
                ? Colors.purple.withValues(alpha: 0.1) 
                : Colors.orange.withValues(alpha: 0.1),
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

    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;

    if (isBooked) {
      bgColor = Colors.green;
      textColor = Colors.white;
    } else if (isRequested) {
      bgColor = Colors.blue;
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
        style: TextStyle(color: textColor, fontWeight: (isBooked || isRequested) ? FontWeight.bold : FontWeight.normal),
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

      // Check requested dates + the next 14 days
      Set<String> datesToCheck = Set.from(_requestedDates);
      final now = DateTime.now();
      for (int i = 0; i < 14; i++) {
        final d = now.add(Duration(days: i));
        datesToCheck.add(d.toIso8601String().split('T').first);
      }

      Set<String> newBookedDates = {};
      Set<String> newRequestedDates = Set.from(_requestedDates);

      for (final dateStr in datesToCheck) {
        final isReserved = await _api.isAlreadyReserved(dateStr, accessToken, floorId, workspaceId);
        
        if (isReserved) {
          newBookedDates.add(dateStr);
          newRequestedDates.add(dateStr);
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
        });
        _storage.saveBookedDates(_bookedDates.toList());
        _storage.saveRequestedDates(_requestedDates.toList());
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

    if (_bookedDates.contains(dateStr)) {
      // Prompt to cancel
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Annuler la réservation ?'),
          content: Text('Voulez-vous libérer votre place pour le $dateStr ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Non'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Oui, libérer', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() => _isCalendarBusy = true);
        try {
          final token = await _api.refreshMyToken();
          final workspaceId = await _storage.getWorkspaceId();
          if (token != null && workspaceId != null) {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
          setState(() {
            _requestedDates.remove(dateStr);
            _bookedDates.remove(dateStr);
            _focusedDay = day;
          });
          _storage.saveRequestedDates(_requestedDates.toList());
          _storage.saveBookedDates(_bookedDates.toList());
        } finally {
          if (mounted) setState(() => _isCalendarBusy = false);
        }
      }
      return;
    } else if (_requestedDates.contains(dateStr)) {
      // It's only pending (blue), remove immediately without API call or popup
      setState(() {
        _requestedDates.remove(dateStr);
        _focusedDay = day;
      });
      _storage.saveRequestedDates(_requestedDates.toList());
      return;
    }

    // Otherwise, toggle on and attempt to book
    setState(() {
      _focusedDay = day;
      _requestedDates.add(dateStr);
      _isCalendarBusy = true;
    });

    try {
      _storage.saveRequestedDates(_requestedDates.toList());

      final accessToken = await _api.refreshMyToken();
      if (accessToken == null) return;
      final workspaceId = await _storage.getWorkspaceId();
      if (workspaceId == null) return;

      final success = await _api.reserveWorkspace(dateStr, accessToken, workspaceId);
      if (success) {
        setState(() {
          _bookedDates.add(dateStr);
        });
        _storage.saveBookedDates(_bookedDates.toList());
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
          child: ValueListenableBuilder<ThemeMode>(
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
