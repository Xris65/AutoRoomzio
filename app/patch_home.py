import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add _showDelegatedReservations state and _delegatedMap state
if 'bool _showDelegatedReservations = true;' not in content:
    content = content.replace("bool _showAllReservations = true;", "bool _showAllReservations = true;\n  bool _showDelegatedReservations = true;\n  Map<String, String> _delegatedBookingsMap = {};")

# 2. Add loading of these states in _checkAuthAndLoad
if '_showDelegatedReservations = await _storage.getShowDelegatedBookings();' not in content:
    content = content.replace("_showAllReservations = await _storage.getShowAllReservations();", "_showAllReservations = await _storage.getShowAllReservations();\n      _showDelegatedReservations = await _storage.getShowDelegatedBookings();")

# 3. Handle it in _syncCalendar
bad_sync = """        final myBookings = await _api.getMyReservations(accessToken, workspaceId);
        final bookedHere = myBookings.here;
        final bookedElsewhere = myBookings.elsewhere;"""

good_sync = """        final myBookings = await _api.getMyReservations(accessToken, workspaceId);
        final bookedHere = myBookings.here;
        final bookedElsewhere = myBookings.elsewhere;
        final delegated = myBookings.delegated;"""

content = content.replace(bad_sync, good_sync)

bad_sync2 = """          setState(() {
            _bookedDates = newBookedDates;
            _requestedDates = newRequestedDates;
            _ignoredDates = newIgnoredDates;
            _bookedElsewhereMap = bookedElsewhere; // reuse field for "booked elsewhere by me"
          });"""

good_sync2 = """          setState(() {
            _bookedDates = newBookedDates;
            _requestedDates = newRequestedDates;
            _ignoredDates = newIgnoredDates;
            _bookedElsewhereMap = bookedElsewhere;
            _delegatedBookingsMap = delegated;
          });"""

content = content.replace(bad_sync2, good_sync2)

# 4. Modify Calendar build day
bad_cal = """      final isElsewhere = !isBooked && _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
      final isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers.containsKey(dateStr);"""

good_cal = """      final isElsewhere = !isBooked && _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;
      final isDelegated = !isBooked && !isElsewhere && _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;
      final isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);"""

content = content.replace(bad_cal, good_cal)

bad_cal2 = """      } else if (isElsewhere) {
        bgColor = Colors.orange.shade200;
        textColor = Colors.orange.shade900;
        strikeThrough = false;
      } else if (isOccupiedByOthers) {"""

good_cal2 = """      } else if (isElsewhere) {
        bgColor = Colors.orange.shade200;
        textColor = Colors.orange.shade900;
        strikeThrough = false;
      } else if (isDelegated) {
        bgColor = Colors.purple.shade200;
        textColor = Colors.purple.shade900;
        strikeThrough = false;
      } else if (isOccupiedByOthers) {"""

content = content.replace(bad_cal2, good_cal2)

# 5. Calendar chips
bad_chips = """                      FilterChip(
                        label: const Text("Toutes mes réservations"),
                        selected: _showAllReservations,
                        onSelected: (val) {
                          setState(() => _showAllReservations = val);
                          _storage.saveShowAllReservations(val);
                        },
                      ),"""
                      
good_chips = """                      FilterChip(
                        label: const Text("Toutes mes réservations"),
                        selected: _showAllReservations,
                        onSelected: (val) {
                          setState(() => _showAllReservations = val);
                          _storage.saveShowAllReservations(val);
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text("Délégations"),
                        selected: _showDelegatedReservations,
                        onSelected: (val) {
                          setState(() => _showDelegatedReservations = val);
                          _storage.saveShowDelegatedBookings(val);
                        },
                      ),"""

content = content.replace(bad_chips, good_chips)

# 6. Home page upcoming bookings
bad_up = """        bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr);
        bool isOccupiedByOthers = !isBooked && !isElsewhere && _occupiedByOthers.containsKey(dateStr);"""

good_up = """        bool isElsewhere = _bookedElsewhereMap.containsKey(dateStr);
        bool isDelegated = _delegatedBookingsMap.containsKey(dateStr);
        bool isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);"""

content = content.replace(bad_up, good_up)

bad_up2 = """        if (isElsewhere) {
          if (_showAllReservations) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
          }
          // Si _showAllReservations est faux, on l'ignore de la liste (mais ça bloque quand même l'automatisation de ce bureau)
        } else if (isOccupiedByOthers) {"""

good_up2 = """        if (isElsewhere) {
          if (_showAllReservations) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
          }
        } else if (isDelegated) {
          if (_showDelegatedReservations) {
            upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": _delegatedBookingsMap[dateStr]});
          }
        } else if (isOccupiedByOthers) {"""

content = content.replace(bad_up2, good_up2)

bad_ui = """              leading: Icon(
                source == 'Ailleurs' ? Icons.person : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending)),
                color: source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue)),
              ),
              title: Text('$weekDayName ${date.day}/${date.month}'),
              subtitle: Text(
                source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)')),
                style: TextStyle(color: source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue)), fontSize: _compactMode ? 10 : 12),
              ),"""

good_ui = """              leading: Icon(
                source == 'Ailleurs' ? Icons.person : (source == 'Délégué' ? Icons.group : (source == 'Occupé' ? Icons.person_off : (isBooked ? Icons.check_circle : Icons.pending))),
                color: source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Délégué' ? Colors.purple.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue))),
              ),
              title: Text('$weekDayName ${date.day}/${date.month}'),
              subtitle: Text(
                source == 'Ailleurs' ? 'Réservé sur un autre bureau (${item["name"] ?? "Ailleurs"})' : (source == 'Délégué' ? 'Réservé pour ${item["name"]}' : (source == 'Occupé' ? 'Indisponible (réservé par ${item["name"] ?? "qqn d\\'autre"})' : (isBooked ? 'Déjà réservé' : 'Sera réservé (Automatique)'))),
                style: TextStyle(color: source == 'Ailleurs' ? Colors.orange.shade900 : (source == 'Délégué' ? Colors.purple.shade900 : (source == 'Occupé' ? Colors.grey.shade700 : (isBooked ? Colors.green : Colors.blue))), fontSize: _compactMode ? 10 : 12),
              ),"""

content = content.replace(bad_ui, good_ui)

bad_chip_color = """                    backgroundColor: source == 'Calendrier' 
                      ? Colors.blue.withValues(alpha: 0.1) 
                      : (source == 'Récurrent' 
                      ? Colors.purple.withValues(alpha: 0.1) 
                      : (source == 'Ailleurs' ? Colors.orange.withValues(alpha: 0.3) : (source == 'Occupé' ? Colors.grey.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1)))),"""

good_chip_color = """                    backgroundColor: source == 'Calendrier' 
                      ? Colors.blue.withValues(alpha: 0.1) 
                      : (source == 'Récurrent' 
                      ? Colors.purple.withValues(alpha: 0.1) 
                      : (source == 'Ailleurs' ? Colors.orange.withValues(alpha: 0.3) : (source == 'Délégué' ? Colors.purple.withValues(alpha: 0.3) : (source == 'Occupé' ? Colors.grey.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.1))))),"""

content = content.replace(bad_chip_color, good_chip_color)

# Filter chip on Home Screen list
bad_home_chip = """                            FilterChip(
                              label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              selected: _showAllReservations,
                              onSelected: (val) {
                                setState(() => _showAllReservations = val);
                                _storage.saveShowAllReservations(val);
                              },
                            ),"""

good_home_chip = """                            FilterChip(
                              label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              selected: _showAllReservations,
                              onSelected: (val) {
                                setState(() => _showAllReservations = val);
                                _storage.saveShowAllReservations(val);
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text("Délégations", style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              selected: _showDelegatedReservations,
                              onSelected: (val) {
                                setState(() => _showDelegatedReservations = val);
                                _storage.saveShowDelegatedBookings(val);
                              },
                            ),"""

content = content.replace(bad_home_chip, good_home_chip)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
