import re

with open('lib/screens/setup_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 3. Replace _loadingSites
old_loading_sites = """    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: _loadingSites
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null"""
new_loading_sites = """    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: _loadingSites
          ? _buildFullSkeleton()
          : _errorMessage != null"""
if old_loading_sites in content:
    content = content.replace(old_loading_sites, new_loading_sites)
else:
    print("Could not find _loadingSites")


with open('lib/screens/setup_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)