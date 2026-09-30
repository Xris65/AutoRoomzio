import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add import
if 'import \'package:flutter_markdown/flutter_markdown.dart\';' not in content:
    content = content.replace("import 'package:http/http.dart' as http;", "import 'package:http/http.dart' as http;\nimport 'package:flutter_markdown/flutter_markdown.dart';")

# Replace _buildReleaseNotes with MarkdownBody
bad_logic = """          // Helper pour nettoyer et formater les notes
          List<Widget> _buildReleaseNotes(String text) {
            List<Widget> widgets = [];
            final lines = text.split('\\n');
            for (var line in lines) {
              line = line.trim();
              if (line.isEmpty) {
                widgets.add(const SizedBox(height: 8));
                continue;
              }
              if (line.toLowerCase().contains('nouveautés') || line.toLowerCase().contains('correctifs') || line.startsWith('###')) {
                final title = line.replaceAll(RegExp(r'#|\\*'), '').trim();
                widgets.add(
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                  ),
                );
              } else {
                final body = line.replaceAll(RegExp(r'\\*\\*'), '');
                widgets.add(Text(body, style: const TextStyle(fontSize: 13)));
              }
            }
            return widgets;
          }"""
content = content.replace(bad_logic, "")

bad_ui = """                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._buildReleaseNotes(rawNotes),
                    const SizedBox(height: 16),"""
good_ui = """                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      child: MarkdownBody(data: rawNotes),
                    ),
                    const SizedBox(height: 16),"""
content = content.replace(bad_ui, good_ui)

# If it was the OLD ui without _buildReleaseNotes
old_ui = """                    Text('Une nouvelle version (v$latestVersion) est prête !', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(releaseNotes, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 16),"""
content = content.replace(old_ui, good_ui.replace("rawNotes", "releaseNotes"))

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
