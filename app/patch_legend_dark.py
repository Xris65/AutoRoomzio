import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildLegend(Colors.green, 'Réservé'),
                _buildLegend(Colors.blue, 'En attente'),
                _buildLegend(Colors.red.withValues(alpha: 0.8), 'Bloqué'),
                _buildLegend(Colors.orange.shade300, 'Ailleurs'),
                _buildLegend(Colors.purple.shade200, 'Délégué'),
              ],
            ),"""

good = """            child: Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildLegend(isDark ? Colors.green.shade700 : Colors.green, 'Réservé'),
                    _buildLegend(isDark ? Colors.blue.shade700 : Colors.blue, 'En attente'),
                    _buildLegend(Colors.red.withValues(alpha: isDark ? 0.6 : 0.8), 'Bloqué'),
                    _buildLegend(isDark ? Colors.orange.shade800 : Colors.orange.shade300, 'Ailleurs'),
                    _buildLegend(isDark ? Colors.purple.shade800 : Colors.purple.shade200, 'Délégué'),
                  ],
                );
              }
            ),"""

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)