import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Revert Builder to dynamic tabs
new_builder = """        body: Builder(
          builder: (context) {
            final List<Map<String, dynamic>> tabs = [
              {'id': 'home', 'icon': Icons.home_rounded, 'label': 'Accueil', 'widget': _buildHomeTab()},
              {'id': 'calendar', 'icon': Icons.calendar_month_rounded, 'label': 'Calendrier', 'widget': _buildCalendarTab()},
              if (_showAutomation) {'id': 'auto', 'icon': Icons.auto_awesome, 'label': 'Automate', 'widget': _buildAutomationTab()},
              if (_showStats) {'id': 'stats', 'icon': Icons.insights_rounded, 'label': 'Stats', 'widget': _buildStatsTab()},
              {'id': 'settings', 'icon': Icons.settings_rounded, 'label': 'Paramètres', 'widget': _buildSettingsTab()},
            ];

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                children: tabs.map((t) => t['widget'] as Widget).toList(),
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
                ),
                child: SafeArea(
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      children: List.generate(tabs.length, (index) {
                        return _buildNavItem(index, tabs[index]['icon'] as IconData, tabs[index]['label'] as String);
                      }),
                    ),
                  ),
                ),
              ),
            );
          },
        ),"""

content = re.sub(r"        body: Builder\([\s\S]*?\},[\s\n]*\),", new_builder, content)

# 2. Fix the toggles to replace PageController instead of jumpToPage
old_auto_toggle = """                  onChanged: (val) {
                    setState(() {
                      _showAutomation = val;
                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                      }
                    });
                    _storage.saveShowAutomation(val);
                  },"""
new_auto_toggle = """                  onChanged: (val) {
                    setState(() {
                      if (val) _currentIndex++; else _currentIndex--;
                      _showAutomation = val;
                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                      }
                      
                      final oldController = _pageController;
                      _pageController = PageController(initialPage: _currentIndex);
                      oldController.dispose();
                    });
                    _storage.saveShowAutomation(val);
                  },"""
content = content.replace(old_auto_toggle, new_auto_toggle)

old_stats_toggle = """                  onChanged: (val) {
                    setState(() {
                      _showStats = val;
                    });
                    _storage.saveShowStats(val);
                  },"""
new_stats_toggle = """                  onChanged: (val) {
                    setState(() {
                      if (val) _currentIndex++; else _currentIndex--;
                      _showStats = val;
                      
                      final oldController = _pageController;
                      _pageController = PageController(initialPage: _currentIndex);
                      oldController.dispose();
                    });
                    _storage.saveShowStats(val);
                  },"""
content = content.replace(old_stats_toggle, new_stats_toggle)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)