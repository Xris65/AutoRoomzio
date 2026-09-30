import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add _wrapWithPtr method right before _buildHomeTab
wrap_method = """  Widget _wrapWithPtr(Widget child) {
    if (_pullToRefreshEnabled) {
      return RefreshIndicator(
        onRefresh: _syncCalendar,
        child: child,
      );
    }
    return child;
  }

  Widget _buildHomeTab() {"""
content = content.replace("  Widget _buildHomeTab() {", wrap_method)

# In _buildHomeTab, replace RefreshIndicator(onRefresh: _syncCalendar, child: SingleChildScrollView
home_old = """            child: RefreshIndicator(
              onRefresh: _syncCalendar,
              child: SingleChildScrollView("""
home_new = """            child: _wrapWithPtr(
              SingleChildScrollView("""
content = content.replace(home_old, home_new)

# In _buildCalendarTab, replace RefreshIndicator(onRefresh: _syncCalendar, child: SingleChildScrollView
cal_old = """    return RefreshIndicator(
      onRefresh: _syncCalendar,
      child: SingleChildScrollView("""
cal_new = """    return _wrapWithPtr(
      SingleChildScrollView("""
content = content.replace(cal_old, cal_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)