import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

helper_method = """  Future<bool> _cancelDelegationAction(String dateStr) async {
    final token = await _api.refreshMyToken();
    final workspaceId = await _storage.getWorkspaceId();
    if (token == null || workspaceId == null) return false;
    
    final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
    final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
    final eventId = parts.length > 3 ? parts[3] : null;
    final orgId = parts.length > 4 ? parts[4] : null;
    if (!wsId.contains('-')) {
       if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
       return false;
    }
    
    final success = await _api.cancelReservation(dateStr, token, wsId, eventId: eventId, forUserId: orgId);
    if (success) {
      setState(() {
        _delegatedBookingsMap.remove(dateStr);
      });
      _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
      if (mounted) _showTopToast('La délégation a été annulée.', isSuccess: true);
      return true;
    } else {
      if (mounted) _showTopToast('Erreur lors de l\\'annulation.', isError: true);
      return false;
    }
  }

"""

# Insert helper method before _quickAction
content = content.replace("  Future<void> _quickAction", helper_method + "  Future<void> _quickAction")

bad_quick = """        if (source == 'Délégué') {
          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          if (!wsId!.contains('-')) {
             if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
             return;
          }
          final success = await _api.cancelReservation(dateStr, token, wsId);
          if (!success) return;
        }"""

good_quick = """        if (source == 'Délégué') {
          final success = await _cancelDelegationAction(dateStr);
          if (!success) return;
        }"""
content = content.replace(bad_quick, good_quick)

bad_handle = """      } else if (action == 'cancel_delegation') {
        final token = await _api.refreshMyToken();
        final workspaceId = await _storage.getWorkspaceId();
        if (token != null && workspaceId != null) {
          final parts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];
          final wsId = parts.isNotEmpty ? parts[0] : workspaceId;
          final eventId = parts.length > 3 ? parts[3] : null;
          final orgId = parts.length > 4 ? parts[4] : null;
          if (!wsId.contains('-')) {
             if (mounted) _showTopToast('Veuillez d\\'abord synchroniser le calendrier.', isError: true);
             return;
          }
          final success = await _api.cancelReservation(dateStr, token, wsId, eventId: eventId, forUserId: orgId);
          if (success) {
            setState(() {
              _delegatedBookingsMap.remove(dateStr);
            });
            _storage.saveDelegatedBookingsMap(_delegatedBookingsMap);
            if (mounted) _showTopToast('La délégation a été annulée.', isSuccess: true);
          } else {
            if (mounted) _showTopToast('Erreur lors de l\\'annulation.', isError: true);
          }
        }
      }"""
      
good_handle = """      } else if (action == 'cancel_delegation') {
        await _cancelDelegationAction(dateStr);
      }"""
      
content = content.replace(bad_handle, good_handle)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)