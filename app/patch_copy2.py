import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = r"const Text\('Mon Calendrier', style: TextStyle\(fontSize: 18, fontWeight: FontWeight\.bold\)\),\s*IconButton\(\s*icon: const Icon\(Icons\.sync\),"
good = r"const Text('Mon Calendrier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),\n                      IconButton(icon: const Icon(Icons.copy), tooltip: 'Copier JSON', onPressed: () async { final token = await _api.refreshMyToken(); if (token != null) { final resp = await http.get(Uri.parse(\"https://api.my.roomz.io/users/current/bookings\"), headers: {\"Authorization\": \"Bearer $token\", \"roomz-source-type\": \"MyRoomzWeb\"}); flutter_services.Clipboard.setData(flutter_services.ClipboardData(text: resp.body)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copié !'))); } }),\n                      IconButton(\n                        icon: const Icon(Icons.sync),"

content = re.sub(bad, good, content)

if 'import \'package:flutter/services.dart\'' not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart' as flutter_services;\nimport 'package:http/http.dart' as http;")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)