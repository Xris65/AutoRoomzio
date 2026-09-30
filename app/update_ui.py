import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Wrap automation card
auto_block = """                  // 🎛 Toggle Automatisation 🎛
                  Card("""
auto_replacement = """                  if (_showAutomation)
                  // 🎛 Toggle Automatisation 🎛
                  Card("""
content = content.replace(auto_block, auto_replacement)


# Wrap stats block
stats_block = """                  // 📊 Stats 📊
                  const Row("""
stats_replacement = """                  if (_showStats) ...[
                  // 📊 Stats 📊
                  const Row("""
content = content.replace(stats_block, stats_replacement)

# End stats block wrapper
stats_end_block = """              _buildStatCard(
                'Taux de russite',
                '${total > 0 ? (successRate).toStringAsFixed(1) : "0"}%',
                Icons.check_circle_outline,
                Colors.green,
                "Ce pourcentage reprsente la proportion de vos rservations (manuelles et automatiques) qui ont russi par rapport au total de vos demandes.",
              ),
            ],
          ),
          const SizedBox(height: 24),
"""
stats_end_replacement = """              _buildStatCard(
                'Taux de russite',
                '${total > 0 ? (successRate).toStringAsFixed(1) : "0"}%',
                Icons.check_circle_outline,
                Colors.green,
                "Ce pourcentage reprsente la proportion de vos rservations (manuelles et automatiques) qui ont russi par rapport au total de vos demandes.",
              ),
            ],
          ),
          const SizedBox(height: 24),
          ],
"""
# Need to use regex because of encoding issues with accents
content = re.sub(r'              _buildStatCard\(\s*\'Taux de r.ussite\',\s*\'.*?\',\s*Icons\.check_circle_outline,\s*Colors\.green,\s*".*?",\s*\),\s*\],\s*\),\s*const SizedBox\(height: 24\),', r'\g<0>\n          ],', content)


# Inject UI toggles in Settings
settings_insert = """
          const SizedBox(height: 24),
          const Text('Interface Accueil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Afficher l\\'encart Automatisation'),
                  secondary: const Icon(Icons.auto_awesome),
                  value: _showAutomation,
                  onChanged: (val) {
                    setState(() => _showAutomation = val);
                    _storage.saveShowAutomation(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Afficher l\\'encart Statistiques'),
                  secondary: const Icon(Icons.insights_rounded),
                  value: _showStats,
                  onChanged: (val) {
                    setState(() => _showStats = val);
                    _storage.saveShowStats(val);
                  },
                ),
              ],
            ),
          ),"""
content = content.replace("const Text('Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: \nColors.lightBlue)),", settings_insert + "\n          const Text('Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: \nColors.lightBlue)),")
content = content.replace("const Text('Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),", settings_insert + "\n          const Text('Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),")


with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)