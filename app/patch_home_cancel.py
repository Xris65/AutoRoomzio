import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          if (!wsId.contains('-')) {
             if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
             return;
          }
          final success = await _api.cancelReservation(dateStr, token, wsId);"""
          
good = """          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          final eventId = parts.length > 3 ? parts[3] : null;
          final orgId = parts.length > 4 ? parts[4] : null;
          if (!wsId.contains('-')) {
             if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
             return;
          }
          final success = await _api.cancelReservation(dateStr, token, wsId, eventId: eventId, forUserId: orgId);"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)