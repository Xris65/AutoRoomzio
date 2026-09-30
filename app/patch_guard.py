import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          await _api.cancelReservation(dateStr, token, wsId);
          setState(() {
            _delegatedBookingsMap.remove(dateStr);
          });
          _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
          if (mounted) _showTopToast('La délégation a été annulée.', isSuccess: true);"""
          
good1 = """          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          if (!wsId.contains('-')) {
             if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
             return;
          }
          final success = await _api.cancelReservation(dateStr, token, wsId);
          if (success) {
            setState(() {
              _delegatedBookingsMap.remove(dateStr);
            });
            _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
            if (mounted) _showTopToast('La délégation a été annulée.', isSuccess: true);
          } else {
            if (mounted) _showTopToast('Erreur lors de l\\'annulation.', isError: true);
          }"""
content = content.replace(bad1, good1)

bad2 = """          if (source == 'Délégué') {
            final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
            final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
            await _api.cancelReservation(dateStr, token, wsId);
          } else if (source == 'Ailleurs') {"""
          
good2 = """          if (source == 'Délégué') {
            final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
            final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
            if (!wsId.contains('-')) {
               if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
               return;
            }
            final success = await _api.cancelReservation(dateStr, token, wsId);
            if (!success) return;
          } else if (source == 'Ailleurs') {"""
content = content.replace(bad2, good2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)