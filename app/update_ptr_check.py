import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update _buildHomeTab
# Wait, let's find the SingleChildScrollView in _buildHomeTab
home_scroll = """            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column("""
home_refresh = """            child: RefreshIndicator(
              onRefresh: _syncCalendar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column("""
# We also need to close the RefreshIndicator bracket
home_scroll_close = """                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }"""
home_refresh_close = """                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }"""
# Wait, just matching brackets by regex is risky. Let's do it exactly:
content = content.replace(home_scroll, home_refresh)
# Close bracket for home_refresh
content = content.replace("              ),", "              ),\n            ),", 1) 
# ACTUALLY, doing `.replace("              ),", "...", 1)` is too dangerous.