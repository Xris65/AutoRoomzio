import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        if (isBooked) {
          if (source == 'Délégué') {
            final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
            final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
            await _api.cancelReservation(dateStr, token, wsId);
          } else if (source == 'Ailleurs') {"""
          
good = """        if (isBooked) {
          if (source == 'Délégué') {
            final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
            final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
            if (!wsId.contains('-')) {
               if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
               return;
            }
            final success = await _api.cancelReservation(dateStr, token, wsId);
            if (!success) return;
          } else if (source == 'Ailleurs') {"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)