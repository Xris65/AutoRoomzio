with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """                      FilterChip(
                        label: const Text("Toutes mes réservations"),
                        selected: _showAllReservations,
                        onSelected: (val) => setState(() => _showAllReservations = val),
                      ),"""
good1 = bad1 + """
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text("Délégations"),
                        selected: _showDelegatedReservations,
                        onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },
                      ),"""
content = content.replace(bad1, good1)
content = content.replace(bad1.replace("réservations", "rÃ©servations"), good1)

bad2 = """                            FilterChip(
                              label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              selected: _showAllReservations,
                              onSelected: (val) => setState(() => _showAllReservations = val),
                            ),"""
good2 = bad2 + """
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text("Délégations", style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              selected: _showDelegatedReservations,
                              onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },
                            ),"""
content = content.replace(bad2, good2)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)