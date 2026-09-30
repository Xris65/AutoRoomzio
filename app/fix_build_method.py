import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Reconstruct the build method
start_idx = content.find("  Widget build(BuildContext context) {")
end_idx = content.find("  Widget _buildNavItem(int index, IconData icon, String label) {")

build_method = """  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = Scaffold(body: FunLoadingWidget(messageNotifier: _loadingTextNotifier));
    } else {
      content = Scaffold(
        appBar: AppBar(
          title: const Text('AutoRoomzio'),
          actions: [
            if (Platform.isAndroid && _automationEnabled)
              IconButton(
                icon: Icon(
                  Icons.shield_rounded, 
                  color: _permissionStatus == 1 ? Colors.green : (_permissionStatus == 2 ? Colors.orange : Colors.red.shade300)
                ),
                tooltip: 'Statut des permissions',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OptimizationScreen()),
                  ).then((_) => _checkPermissionsStatus());
                },
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: _logout,
            ),
          ],
        ),
        body: Builder(
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
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(0);
                  }
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
        ),
      );
    }

    return PopScope(
      canPop: _canExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        setState(() { _canExit = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Appuyez à nouveau pour quitter"),
            duration: Duration(seconds: 2),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() { _canExit = false; });
        });
      },
      child: content,
    );
  }

"""

content = content[:start_idx] + build_method + content[end_idx:]

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)