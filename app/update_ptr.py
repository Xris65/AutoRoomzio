import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# For Home Tab
home_tab_idx = content.find("Widget _buildHomeTab() {")
if home_tab_idx != -1:
    scroll_idx = content.find("child: SingleChildScrollView(", home_tab_idx)
    if scroll_idx != -1:
        # replace with RefreshIndicator
        content = content[:scroll_idx] + "child: RefreshIndicator(\n              onRefresh: _syncCalendar,\n              child: SingleChildScrollView(\n                physics: const AlwaysScrollableScrollPhysics()," + content[scroll_idx + len("child: SingleChildScrollView("):]
        
        # find the end of SingleChildScrollView
        # it is right before `if (_isCalendarBusy)`
        busy_idx = content.find("        if (_isCalendarBusy)", scroll_idx)
        if busy_idx != -1:
            content = content[:busy_idx] + "            ),\n" + content[busy_idx:]
        else:
            print("busy not found for home")

# For Calendar Tab
cal_tab_idx = content.find("Widget _buildCalendarTab() {")
if cal_tab_idx != -1:
    scroll_idx = content.find("return SingleChildScrollView(", cal_tab_idx)
    if scroll_idx != -1:
        content = content[:scroll_idx] + "return RefreshIndicator(\n      onRefresh: _syncCalendar,\n      child: SingleChildScrollView(\n        physics: const AlwaysScrollableScrollPhysics()," + content[scroll_idx + len("return SingleChildScrollView("):]
        
        # find the end of SingleChildScrollView
        end_idx = content.find("      );", scroll_idx)
        if end_idx != -1:
            content = content[:end_idx] + "      ),\n" + content[end_idx:]
        else:
            print("end not found for cal")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)