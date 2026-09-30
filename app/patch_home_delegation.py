import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_load = """      final currentBookings = await _api.getMyReservations(token, _workspaceId!);
      _bookedDates = currentBookings.here;
      _bookedElsewhereMap = currentBookings.elsewhere;
      _delegatedBookingsMap = currentBookings.delegated;

      final daysToCheck = <String>[];
      final today = DateTime.now();
      for (int i = 0; i < 30; i++) {
        final d = today.add(Duration(days: i));
        if (!_hideWeekends || (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday)) {
          daysToCheck.add(d.toIso8601String().split('T').first);
        }
      }

      final floorId = await _storage.getFloorId();
      if (floorId != null) {
        final occupancy = await _api.getWorkspaceOccupancy(token, _workspaceId!, floorId, daysToCheck);
        _occupiedByOthers = occupancy;
      }"""

good_load = """      final myUserId = await _api.getCurrentUserId(token);
      final currentBookings = await _api.getMyReservations(token, _workspaceId!);
      _bookedDates = currentBookings.here;
      _bookedElsewhereMap = currentBookings.elsewhere;

      final daysToCheck = <String>[];
      final today = DateTime.now();
      for (int i = 0; i < 30; i++) {
        final d = today.add(Duration(days: i));
        if (!_hideWeekends || (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday)) {
          daysToCheck.add(d.toIso8601String().split('T').first);
        }
      }

      final floorId = await _storage.getFloorId();
      if (floorId != null) {
        final occResult = await _api.getWorkspaceOccupancy(token, _workspaceId!, floorId, daysToCheck, myUserId);
        _occupiedByOthers = occResult.occupiedByOthers;
        _delegatedBookingsMap = occResult.delegatedBookings;
        
        // Remove delegated dates from booked and elsewhere so they don't double count
        for (final dateStr in _delegatedBookingsMap.keys) {
          _bookedDates.remove(dateStr);
          _bookedElsewhereMap.remove(dateStr);
        }
      } else {
        _delegatedBookingsMap = {};
      }"""

content = content.replace(bad_load, good_load)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)