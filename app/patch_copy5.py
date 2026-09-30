import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "IconButton(icon: const Icon(Icons.copy)" in line:
        new_lines.append("""                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copier JSON',
                        onPressed: () async {
                          final token = await _api.refreshMyToken();
                          if (token != null) {
                            final floorId = await _storage.getFloorId();
                            final dateStr = DateTime.now().toIso8601String().split('T').first;
                            final bodyStr = '{"availableWorkspaceOnly": false, "date": "' + dateStr + '", "timeSlot": "FullDay", "tagIds": [], "workspaceType": "Desk"}';
                            final resp = await http.post(
                              Uri.parse("https://api.my.roomz.io/floors/$floorId/workspaces/calendars?length=100&offset=0"),
                              headers: {
                                "Authorization": "Bearer $token",
                                "roomz-source-type": "MyRoomzWeb",
                                "Content-Type": "application/json"
                              },
                              body: bodyStr
                            );
                            flutter_services.Clipboard.setData(flutter_services.ClipboardData(text: resp.body));
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copié !')));
                          }
                        }
                      ),\n""")
    else:
        new_lines.append(line)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)