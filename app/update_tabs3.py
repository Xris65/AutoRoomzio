with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

start_idx = content.find("body: PageView(")
end_idx = content.find("      );", start_idx)

if start_idx != -1 and end_idx != -1:
    print("Found!")
    old = content[start_idx:end_idx]
    
    new_pageview = """body: Builder(
          builder: (context) {
            final List<Map<String, dynamic>> tabs = [
              {'icon': Icons.home_rounded, 'label': 'Accueil', 'widget': _buildHomeTab()},
              {'icon': Icons.calendar_month_rounded, 'label': 'Calendrier', 'widget': _buildCalendarTab()},
              if (_showAutomation) {'icon': Icons.auto_awesome, 'label': 'Automate', 'widget': _buildAutomationTab()},
              if (_showStats) {'icon': Icons.insights_rounded, 'label': 'Stats', 'widget': _buildStatsTab()},
              {'icon': Icons.settings_rounded, 'label': 'Paramètres', 'widget': _buildSettingsTab()},
            ];

            if (_currentIndex >= tabs.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _currentIndex = 0;
                  _pageController.jumpToPage(0);
                });
              });
            }

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
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
        )"""
    
    content = content[:start_idx] + new_pageview + content[end_idx:]
    with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
else:
    print("Not found")