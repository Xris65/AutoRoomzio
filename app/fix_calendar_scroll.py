import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove PageStorageKey from KeyedSubtree
old_map = "children: tabs.map((t) => KeyedSubtree(key: PageStorageKey(t['id']), child: t['widget'] as Widget)).toList(),"
new_map = "children: tabs.map((t) => KeyedSubtree(key: ValueKey(t['id']), child: t['widget'] as Widget)).toList(),"
content = content.replace(old_map, new_map)

# Add PageStorageKey to SettingsTab ListView
old_settings = """  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),"""
new_settings = """  Widget _buildSettingsTab() {
    return ListView(
      key: const PageStorageKey('settings_scroll'),
      padding: const EdgeInsets.all(16),"""
content = content.replace(old_settings, new_settings)

# Add PageStorageKey to HomeTab SingleChildScrollView
old_home = """          child: LayoutBuilder(
            builder: (context, constraints) {
              return _wrapWithPtr(
                SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),"""
new_home = """          child: LayoutBuilder(
            builder: (context, constraints) {
              return _wrapWithPtr(
                SingleChildScrollView(
                  key: const PageStorageKey('home_scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),"""
content = content.replace(old_home, new_home)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)