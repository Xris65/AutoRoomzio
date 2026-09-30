import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 5. Calendar chips
content = re.sub(
    r'(FilterChip\(\s*label:\s*const Text\("Toutes mes r[A-Za-zÀ-ÿœŒ]+servations"\),\s*selected:\s*_showAllReservations,\s*onSelected:\s*\(val\)\s*=>\s*setState\(\(\)\s*=>\s*_showAllReservations\s*=\s*val\),\s*\),)',
    r'\1\n                      const SizedBox(width: 8),\n                      FilterChip(\n                        label: const Text("Délégations"),\n                        selected: _showDelegatedReservations,\n                        onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },\n                      ),',
    content
)

# 6. Home page upcoming bookings
content = re.sub(
    r'(FilterChip\(\s*label:\s*const Text\("Toutes mes places",\s*style:\s*TextStyle\(fontSize:\s*11\)\),\s*visualDensity:\s*VisualDensity\.compact,\s*selected:\s*_showAllReservations,\s*onSelected:\s*\(val\)\s*=>\s*setState\(\(\)\s*=>\s*_showAllReservations\s*=\s*val\),\s*\),)',
    r'\1\n                            const SizedBox(width: 8),\n                            FilterChip(\n                              label: const Text("Délégations", style: TextStyle(fontSize: 11)),\n                              visualDensity: VisualDensity.compact,\n                              selected: _showDelegatedReservations,\n                              onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },\n                            ),',
    content
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
