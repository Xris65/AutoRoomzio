import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add variable
var_marker = "  bool _hideWeekends = true;"
new_var = var_marker + "\n  bool _pullToRefreshEnabled = true;"
content = content.replace(var_marker, new_var)

# 2. Add to _loadData
load1_old = "      final comp = await _storage.getCompactMode();"
load1_new = load1_old + "\n      final ptr = await _storage.getPullToRefresh();"
content = content.replace(load1_old, load1_new)

load2_old = "          _compactMode = comp;"
load2_new = load2_old + "\n          _pullToRefreshEnabled = ptr;"
content = content.replace(load2_old, load2_new)

# 3. Add to _buildSettingsTab
toggle_old = """                  onChanged: (val) {
                    setState(() {
                      if (val) _currentIndex++; else _currentIndex--;
                      _showStats = val;
                      
                      final oldController = _pageController;
                      _pageController = PageController(initialPage: _currentIndex);
                      oldController.dispose();
                    });
                    _storage.saveShowStats(val);
                  },
                ),"""
toggle_new = toggle_old + """
                SwitchListTile(
                  title: const Text("Tirer pour rafraîchir"),
                  subtitle: const Text("Actualiser en glissant vers le bas (Accueil, Calendrier)"),
                  value: _pullToRefreshEnabled,
                  onChanged: (val) {
                    setState(() => _pullToRefreshEnabled = val);
                    _storage.savePullToRefresh(val);
                  },
                ),"""
content = content.replace(toggle_old, toggle_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)