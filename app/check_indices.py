import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the PageView and bottomNavigationBar
old_pageview = """      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
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

new_pageview = """      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        children: [
          _buildHomeTab(),
          _buildCalendarTab(),
          if (_showAutomation) _buildAutomationTab(),
          if (_showStats) _buildStatsTab(),
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
                if (_showAutomation) _buildNavItem(2, Icons.auto_awesome, 'Automate'),
                if (_showStats) _buildNavItem(3, Icons.insights_rounded, 'Stats'),
                _buildNavItem(4, Icons.settings_rounded, 'Paramètres'),
              ],
            ),
          ),
        ),
      ),"""
content = content.replace(old_pageview, new_pageview)
content = content.replace("Paramtres", "Paramètres")

# Also need to fix the _buildNavItem logic
# Because _currentIndex won't match the tab index anymore if we just hide items!
# Wait, if we hide item 2, the 4th item (Settings) will have index 3 in the PageView!
# But the hardcoded `_buildNavItem(4, ...)` assumes Settings is index 4!