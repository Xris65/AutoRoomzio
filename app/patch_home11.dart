import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('\r\n', '\n');

  final startMarker = "Card(\n                      color: (_vacationStart != null";
  final endMarker = "saveText: 'VALIDER',\n                            builder: (context, child) {";
  
  int startIndex = content.indexOf(startMarker);
  if (startIndex == -1) {
    print("Start marker not found");
    return;
  }
  
  // Find the end of this block
  int endIndex = content.indexOf("    const SizedBox(height: 16),\n                    \n                    //  Toggle Automatisation ", startIndex);
  if (endIndex == -1) {
     endIndex = content.indexOf("    const SizedBox(height: 16),\n                    \n                    //", startIndex);
  }
  if (endIndex == -1) {
    print("End marker not found");
    return;
  }
  
  final newCard = '''Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.beach_access, color: Colors.orange),
                            title: const Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                          ),
                          if (_vacations.isNotEmpty) const Divider(height: 1),
                          ..._vacations.map((v) {
                            return ListTile(
                              dense: true,
                              title: Text('Du \/\ au \/\'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                onPressed: () {
                                  setState(() => _vacations.remove(v));
                                  _storage.saveVacations(_vacations.map((v) => {'start': v.start.toIso8601String(), 'end': v.end.toIso8601String()}).toList());
                                },
                              ),
                            );
                          }),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Ajouter une période'),
                              onPressed: () async {
                                final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: today,
                                  lastDate: today.add(const Duration(days: 365)),
                                  saveText: 'VALIDER',
                                );
                                if (picked != null) {
                                  setState(() => _vacations.add(picked));
                                  _storage.saveVacations(_vacations.map((v) => {'start': v.start.toIso8601String(), 'end': v.end.toIso8601String()}).toList());
                                  
                                  // AUTO-CANCEL bookings in this new vacation period
                                  final toCancel = <String>[];
                                  for (var i = 0; i <= picked.end.difference(picked.start).inDays; i++) {
                                    final d = picked.start.add(Duration(days: i));
                                    if (_hideWeekends && (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)) continue;
                                    
                                    final maxBookable = today.add(const Duration(days: 13));
                                    if (!d.isAfter(maxBookable)) {
                                      final dateStr = "\-\-\";
                                      if (_bookedDates.contains(dateStr)) {
                                        toCancel.add(dateStr);
                                      }
                                    }
                                  }
                                  
                                  if (toCancel.isNotEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Annulation de \ réservation(s) existante(s)...')));
                                    for (final dateStr in toCancel) {
                                      final token = await _api.refreshMyToken();
                                      if (token != null) {
                                        await _api.cancelBookingByDate(token, dateStr);
                                        setState(() => _bookedDates.remove(dateStr));
                                      }
                                    }
                                    _storage.saveBookedDates(_bookedDates.toList());
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réservations annulées avec succès.')));
                                  }
                                }
                              },
                            ),
                          )
                        ],
                      ),
                    ),
''';

  content = content.replaceRange(startIndex, endIndex, newCard);
  file.writeAsStringSync(content);
}
