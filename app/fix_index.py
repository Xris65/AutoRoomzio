import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# I will just remove the if (_currentIndex >= tabs.length) block completely. 
# And instead, map the current active tab string. 
# But wait, to keep it extremely simple without breaking `_currentIndex`, I can just compute the new index of the current tab during build!

replacement = """        body: Builder(
          builder: (context) {
            final List<Map<String, dynamic>> tabs = [
              {'id': 'home', 'icon': Icons.home_rounded, 'label': 'Accueil', 'widget': _buildHomeTab()},
              {'id': 'calendar', 'icon': Icons.calendar_month_rounded, 'label': 'Calendrier', 'widget': _buildCalendarTab()},
              if (_showAutomation) {'id': 'auto', 'icon': Icons.auto_awesome, 'label': 'Automate', 'widget': _buildAutomationTab()},
              if (_showStats) {'id': 'stats', 'icon': Icons.insights_rounded, 'label': 'Stats', 'widget': _buildStatsTab()},
              {'id': 'settings', 'icon': Icons.settings_rounded, 'label': 'Paramètres', 'widget': _buildSettingsTab()},
            ];

            // Safely bound _currentIndex
            if (_currentIndex >= tabs.length) {
                // If we are out of bounds, we were on settings, which is now the last tab.
                _currentIndex = tabs.length - 1;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(_currentIndex);
                  }
                });
            }

            return Scaffold(
              backgroundColor: Colors.transparent,"""

pattern = r"        body: Builder\([\s\S]*?return Scaffold\(\s*\n\s*backgroundColor: Colors\.transparent,"

# Let's replace the top part of the Builder
content = re.sub(pattern, replacement, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)