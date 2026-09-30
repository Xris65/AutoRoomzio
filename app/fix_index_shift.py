import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Update _showAutomation toggle
old_auto_toggle = """                  onChanged: (val) {
                    setState(() {
                      _showAutomation = val;
                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                        _vacationsEnabled = false;
                        _storage.saveVacationsEnabled(false);
                      }
                    });
                    _storage.saveShowAutomation(val);
                  },"""
new_auto_toggle = """                  onChanged: (val) {
                    setState(() {
                      if (val) {
                        _currentIndex++;
                      } else {
                        _currentIndex--;
                      }
                      _showAutomation = val;
                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                        _vacationsEnabled = false;
                        _storage.saveVacationsEnabled(false);
                      }
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(_currentIndex);
                      }
                    });
                    _storage.saveShowAutomation(val);
                  },"""
content = content.replace(old_auto_toggle, new_auto_toggle)

# Update _showStats toggle
old_stats_toggle = """                  onChanged: (val) {
                    setState(() => _showStats = val);
                    _storage.saveShowStats(val);
                  },"""
new_stats_toggle = """                  onChanged: (val) {
                    setState(() {
                      if (val) {
                        _currentIndex++;
                      } else {
                        _currentIndex--;
                      }
                      _showStats = val;
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(_currentIndex);
                      }
                    });
                    _storage.saveShowStats(val);
                  },"""
content = content.replace(old_stats_toggle, new_stats_toggle)

# Now we must remove the hacky bounds check in the Builder, it's not needed anymore!
old_bounds = """            // Safely bound _currentIndex
            if (_currentIndex >= tabs.length) {
                // If we are out of bounds, we were on settings, which is now the last tab.
                _currentIndex = tabs.length - 1;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(_currentIndex);
                  }
                });
            }"""
content = content.replace(old_bounds, "")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)