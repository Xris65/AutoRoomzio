import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_pageview = """        body: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
          },
          children: [
            _buildHomeTab(),
            _buildCalendarTab(),
            _buildAutomationTab(),
            _buildStatsTab(),
            _buildSettingsTab(),
          ],
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
                children: [
                  _buildNavItem(0, Icons.home_rounded, 'Accueil'),
                  _buildNavItem(1, Icons.calendar_month_rounded, 'Calendrier'),
                  _buildNavItem(2, Icons.auto_awesome, 'Automate'),
                  _buildNavItem(3, Icons.insights_rounded, 'Stats'),
                  _buildNavItem(4, Icons.settings_rounded, 'Paramètres'),
                ],
              ),
            ),
          ),
        ),"""

new_pageview = """        body: Builder(
          builder: (context) {
            final List<Map<String, dynamic>> tabs = [
              {'icon': Icons.home_rounded, 'label': 'Accueil', 'widget': _buildHomeTab()},
              {'icon': Icons.calendar_month_rounded, 'label': 'Calendrier', 'widget': _buildCalendarTab()},
              if (_showAutomation) {'icon': Icons.auto_awesome, 'label': 'Automate', 'widget': _buildAutomationTab()},
              if (_showStats) {'icon': Icons.insights_rounded, 'label': 'Stats', 'widget': _buildStatsTab()},
              {'icon': Icons.settings_rounded, 'label': 'Paramètres', 'widget': _buildSettingsTab()},
            ];

            return Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                    },
                    children: tabs.map((t) => t['widget'] as Widget).toList(),
                  ),
                ),
                Container(
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
              ],
            );
          },
        ),"""

# Need to fix encoding/accents
old_pageview = old_pageview.replace("Paramètres", "Paramtres")
new_pageview = new_pageview.replace("Paramètres", "Paramètres") # Will write clean unicode

# Oh wait, Python reads 'utf-8'. The console printed "Paramtres" because of PowerShell.
# So I should use 'Paramètres' in old_pageview.
old_pageview = old_pageview.replace("Paramtres", "Paramètres")

content = content.replace(old_pageview, new_pageview)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)