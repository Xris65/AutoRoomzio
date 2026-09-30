import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """                if (!isBooked && !isRequested)"""
good1 = """                if (isDelegated)
                  ListTile(
                    leading: Icon(Icons.group_off, color: Colors.purple.shade900),
                    title: Text('Annuler la délégation', style: TextStyle(color: Colors.purple.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text("Annule la réservation faite pour votre collègue ce jour-là.", style: TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(context, 'cancel_delegation'),
                  ),
                if (!isBooked && !isRequested)"""
content = content.replace(bad1, good1)

bad2 = """      } else if (action == 'cancel_elsewhere') {"""
good2 = """      } else if (action == 'cancel_delegation') {
        final token = await _api.refreshMyToken();
        final workspaceId = await _storage.getWorkspaceId();
        if (token != null && workspaceId != null) {
          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          await _api.cancelReservation(dateStr, token, wsId);
          setState(() {
            _delegatedBookingsMap.remove(dateStr);
          });
          _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
          if (mounted) _showTopToast('La délégation a été annulée.', isSuccess: true);
        }
      } else if (action == 'cancel_elsewhere') {"""
content = content.replace(bad2, good2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)