import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """      final firstUse = await _storage.getFirstUse();
      final stats = await _storage.getBookingStats();
      
      if (mounted) {"""
good1 = """      final firstUse = await _storage.getFirstUse();
      final stats = await _storage.getBookingStats();
      final delegatedMap = await _storage.getDelegatedBookingsMap();
      
      if (mounted) {"""
content = content.replace(bad1, good1)

bad2 = """          _bookedElsewhereMap = elsewhere;
          _showAllReservations = true;
          _automationEnabled = autoEnabled;"""
good2 = """          _bookedElsewhereMap = elsewhere;
          _delegatedBookingsMap = delegatedMap;
          _showAllReservations = true;
          _automationEnabled = autoEnabled;"""
content = content.replace(bad2, good2)

bad3 = """        for (final d in _delegatedBookingsMap.keys) {
           bookedHere.remove(d);
           bookedElsewhere.remove(d);
        }
  
        Set<String> newBookedDates = {};"""
        
good3 = """        for (final d in _delegatedBookingsMap.keys) {
           bookedHere.remove(d);
           bookedElsewhere.remove(d);
        }
        await _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
  
        Set<String> newBookedDates = {};"""
content = content.replace(bad3, good3)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)