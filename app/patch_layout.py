import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix upcoming bookings chips
bad_up = r"""Row\(\s*mainAxisAlignment: MainAxisAlignment\.spaceBetween,\s*children: \[\s*const Text\(\s*'📅 Prochaines réservations',\s*style: TextStyle\(fontSize: 16, fontWeight: FontWeight\.bold\),\s*\),\s*FilterChip\([\s\S]*?onSelected: \(val\) => setState\(\(\) => _showAllReservations = val\),\s*\),(?:\s*const SizedBox\(width: 8\),\s*FilterChip\([\s\S]*?_storage\.saveShowDelegatedBookings\(val\); \},\s*\),)*\s*\],\s*\),"""
# Note: Since the file has "📅 Prochaines réservations", but it might be encoded differently, I will just match `const Text(` and `Prochaines`

bad_up = r"""Row\(\s*mainAxisAlignment: MainAxisAlignment\.spaceBetween,\s*children: \[\s*const Text\(\s*'[^\']*Prochaines r[A-Za-zÀ-ÿœŒ]+servations',\s*style: TextStyle\(fontSize: 16, fontWeight: FontWeight\.bold\),\s*\),\s*FilterChip\([\s\S]*?onSelected: \(val\) => setState\(\(\) => _showAllReservations = val\),\s*\),(?:\s*const SizedBox\(width: 8\),\s*FilterChip\([\s\S]*?_storage\.saveShowDelegatedBookings\(val\); \},\s*\),)*\s*\],\s*\),"""

good_up = """Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📅 Prochaines réservations',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8.0,
                              children: [
                                FilterChip(
                                  label: const Text("Toutes mes places", style: TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  selected: _showAllReservations,
                                  onSelected: (val) => setState(() => _showAllReservations = val),
                                ),
                                FilterChip(
                                  label: const Text("Délégations", style: TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  selected: _showDelegatedReservations,
                                  onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },
                                ),
                              ],
                            ),
                          ],
                        ),"""

content = re.sub(bad_up, good_up, content)

# Fix calendar chips
bad_cal = r"""Row\(\s*mainAxisAlignment: MainAxisAlignment\.spaceBetween,\s*children: \[\s*const Text\('Mon Calendrier', style: TextStyle\(fontSize: 18, fontWeight: FontWeight\.bold\)\),\s*Row\(\s*children: \[\s*FilterChip\([\s\S]*?onSelected: \(val\) => setState\(\(\) => _showAllReservations = val\),\s*\),(?:\s*const SizedBox\(width: 8\),\s*FilterChip\([\s\S]*?_storage\.saveShowDelegatedBookings\(val\); \},\s*\),)*\s*IconButton\([\s\S]*?onPressed: _syncCalendar,\s*\),\s*\],\s*\),\s*\],\s*\),"""

good_cal = """Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mon Calendrier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.sync),
                        tooltip: 'Synchroniser avec MyRoomz',
                        onPressed: _syncCalendar,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8.0,
                    children: [
                      FilterChip(
                        label: const Text("Toutes mes réservations"),
                        selected: _showAllReservations,
                        onSelected: (val) => setState(() => _showAllReservations = val),
                      ),
                      FilterChip(
                        label: const Text("Délégations"),
                        selected: _showDelegatedReservations,
                        onSelected: (val) { setState(() => _showDelegatedReservations = val); _storage.saveShowDelegatedBookings(val); },
                      ),
                    ],
                  ),
                ],
              ),"""

content = re.sub(bad_cal, good_cal, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)