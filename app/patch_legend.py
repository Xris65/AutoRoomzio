import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegend(Colors.green, 'Réservé'),
                _buildLegend(Colors.blue, 'En attente'),
                _buildLegend(Colors.red.withValues(alpha: 0.8), 'Bloqué'),
                _buildLegend(Colors.orange.shade300, 'Ailleurs 👤'),
              ],
            ),"""

good = """            child: Wrap(
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

# Account for weird accents in bad block due to encoding differences in regex
bad_regex = r"child:\s*Row\(\s*mainAxisAlignment:\s*MainAxisAlignment\.spaceEvenly,\s*children:\s*\[\s*_buildLegend\(Colors\.green,.*?\),\s*_buildLegend\(Colors\.blue,.*?\),\s*_buildLegend\(Colors\.red\.withValues\(alpha:\s*0\.8\),.*?\),\s*_buildLegend\(Colors\.orange\.shade300,.*?\),\s*\],\s*\),"

content = re.sub(bad_regex, good, content, flags=re.DOTALL)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)