import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<void> _quickAction(DateTime day, bool isBooked, String source) async {
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
        
      }"""

good = """  Future<void> _quickAction(DateTime day, bool isBooked, String source) async {
    final dateStr = day.toIso8601String().split('T').first;
    
    setState(() => _isCalendarBusy = true);
    try {
      if (source == 'Délégué') {
         final success = await _cancelDelegationAction(dateStr);
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
        
      }"""
      
content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)