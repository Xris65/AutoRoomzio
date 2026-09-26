import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();

  // 1. Quick Action Update
  content = content.replaceFirst(
    '  Future<void> _quickAction(DateTime day, bool isBooked, String source) async {\n' +
    '    final dateStr = day.toIso8601String().split(''T'').first;\n' +
    '    \n' +
    '    setState(() => _isCalendarBusy = true);\n' +
    '    try {\n' +
    '      if (isBooked) {\n' +
    '        final token = await _api.refreshMyToken();\n' +
    '        final workspaceId = await _storage.getWorkspaceId();\n' +
    '        if (token != null && workspaceId != null) {\n' +
    '          await _api.cancelReservation(dateStr, token, workspaceId);\n' +
    '        }\n' +
    '      }\n' +
    '      setState(() {\n' +
    '        _requestedDates.remove(dateStr);\n' +
    '        _bookedDates.remove(dateStr);\n' +
    '        if (source == ''Récurrent'') {\n' +
    '          _ignoredDates.add(dateStr); // Only block automation\n' +
    '        }\n' +
    '      });\n' +
    '      _storage.saveRequestedDates(_requestedDates.toList());\n' +
    '      _storage.saveBookedDates(_bookedDates.toList());\n' +
    '      if (source == ''Récurrent'') {\n' +
    '        _storage.saveIgnoredDates(_ignoredDates.toList());\n' +
    '      }\n' +
    '      \n' +
    '      if (mounted) {\n' +
    '        _showTopToast(source == ''Calendrier'' ? ''Réservation supprimée'' : ''Jour bloqué (\)'');\n' +
    '      }\n' +
    '    } finally {\n' +
    '      if (mounted) setState(() => _isCalendarBusy = false);\n' +
    '    }\n' +
    '  }',
    '''  Future<void> _quickAction(DateTime day, bool isBooked, String source) async {
    final dateStr = day.toIso8601String().split('T').first;
    
    setState(() => _isCalendarBusy = true);
    try {
      final token = await _api.refreshMyToken();
      if (token != null) {
        if (source == 'Ailleurs') {
          final success = await _api.cancelBookingByDate(token, dateStr);
          if (success) {
            setState(() => _bookedElsewhereMap.remove(dateStr));
            _storage.saveBookedElsewhereDates(_bookedElsewhereMap.keys.toList());
            if (mounted) _showTopToast('Réservation annulée', isSuccess: true);
          }
        } else if (isBooked) {
          final workspaceId = await _storage.getWorkspaceId();
          if (workspaceId != null) {
            await _api.cancelReservation(dateStr, token, workspaceId);
          }
        }
      }
      
      if (source != 'Ailleurs') {
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
          _showTopToast(source == 'Calendrier' ? 'Réservation supprimée' : 'Jour bloqué (\)');
        }
      }
    } catch (e) {
      debugPrint("❌ QuickAction failed: \");
    } finally {
      if (mounted) setState(() => _isCalendarBusy = false);
    }
  }'''
  );

  // 2. Hide bloquer
  content = content.replaceFirst(
    'if (!isIgnored && !isWeekendAndHidden)',
    'if (!isIgnored && !isWeekendAndHidden && !_bookedElsewhereMap.containsKey(dateStr))'
  );

  // 3. Update icon and tooltip
  content = content.replaceFirst(
    '''                  IconButton(
                    icon: Icon(source == 'Calendrier' ? Icons.delete_outline : Icons.block, size: 20),
                    color: Colors.redAccent,
                    tooltip: source == 'Calendrier' ? 'Supprimer' : 'Bloquer',
                    onPressed: () => _quickAction(date, isBooked, source),
                  ),''',
    '''                  IconButton(
                    icon: Icon(source == 'Récurrent' ? Icons.block : Icons.delete_outline, size: 20),
                    color: Colors.redAccent,
                    tooltip: source == 'Récurrent' ? 'Bloquer' : 'Supprimer',
                    onPressed: () => _quickAction(date, isBooked, source),
                  ),'''
  );

  // 4. Add refresh button
  content = content.replaceFirst(
    '''                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📅 Prochaines réservations',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          FilterChip(
                            label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            selected: _showAllReservations,
                            onSelected: (val) => setState(() => _showAllReservations = val),
                          ),
                        ],
                      ),''',
    '''                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📅 Prochaines réservations',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              FilterChip(
                                label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                selected: _showAllReservations,
                                onSelected: (val) => setState(() => _showAllReservations = val),
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync, size: 20),
                                tooltip: 'Synchroniser',
                                onPressed: _syncCalendar,
                              ),
                            ],
                          ),
                        ],
                      ),'''
  );

  file.writeAsStringSync(content);
}
