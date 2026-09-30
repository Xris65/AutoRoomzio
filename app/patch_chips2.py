import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(
    r'(FilterChip\(\s*label:\s*const Text\("Toutes mes r[A-Za-zÀ-ÿœŒ]+servations"\)[\s\S]*?onSelected: \(val\) => setState\(\(\) => _showAllReservations = val\),\s*\),)',
    r'\1\n                      const SizedBox(width: 8),\n                      FilterChip(\n                        label: const Text("Délégations"),\n                        selected: _showDelegatedReservations,\n                        onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },\n                      ),',
    content
)

content = re.sub(
    r'(FilterChip\(\s*label:\s*const Text\("Toutes mes places"[\s\S]*?onSelected: \(val\) => setState\(\(\) => _showAllReservations = val\),\s*\),)',
    r'\1\n                            const SizedBox(width: 8),\n                            FilterChip(\n                              label: const Text("Délégations", style: TextStyle(fontSize: 11)),\n                              visualDensity: VisualDensity.compact,\n                              selected: _showDelegatedReservations,\n                              onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },\n                            ),',
    content
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)