with open('lib/screens/setup_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Imports
if 'import \'package:shimmer/shimmer.dart\';' not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:shimmer/shimmer.dart';")

# 2. Add the skeleton methods
skeleton_methods = """  Widget _buildMapSkeletonContent() {
    return Column(
      children: [
        Container(
          height: 40,
          width: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 350,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned(top: 40, left: 30, child: Container(width: 50, height: 20, color: Colors.white)),
              Positioned(top: 40, left: 90, child: Container(width: 50, height: 20, color: Colors.white)),
              Positioned(top: 100, right: 40, child: Container(width: 30, height: 60, color: Colors.white)),
              Positioned(top: 180, right: 40, child: Container(width: 30, height: 60, color: Colors.white)),
              Positioned(bottom: 60, left: 50, child: Container(width: 80, height: 30, color: Colors.white)),
              Positioned(bottom: 120, left: 150, child: Container(width: 40, height: 40, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
              Positioned(bottom: 180, left: 80, child: Container(width: 40, height: 20, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: _buildMapSkeletonContent(),
    );
  }

  Widget _buildFullSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            Container(width: 28, height: 28, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            const SizedBox(width: 16),
            Container(width: 150, height: 20, color: Colors.white),
          ]),
          Container(margin: const EdgeInsets.only(left: 13, top: 12, bottom: 12), width: 2, height: 30, color: Colors.white),
          Row(children: [
            Container(width: 28, height: 28, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            const SizedBox(width: 16),
            Container(width: 100, height: 20, color: Colors.white),
          ]),
          Container(margin: const EdgeInsets.only(left: 13, top: 12, bottom: 12), width: 2, height: 30, color: Colors.white),
          Row(children: [
            Container(width: 28, height: 28, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            const SizedBox(width: 16),
            Container(width: 120, height: 20, color: Colors.white),
          ]),
          const SizedBox(height: 24),
          _buildMapSkeletonContent(),
        ],
      ),
    );
  }

"""

build_idx = content.find("  @override\n  Widget build(BuildContext context) {")
if build_idx != -1:
    content = content[:build_idx] + skeleton_methods + content[build_idx:]
else:
    print("Could not find build method")


# 3. Replace _loadingSites
old_loading_sites = """      return Scaffold(
        appBar: AppBar(title: const Text('Configuration')),
        body: _loadingSites
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null"""
new_loading_sites = """      return Scaffold(
        appBar: AppBar(title: const Text('Configuration')),
        body: _loadingSites
            ? _buildFullSkeleton()
            : _errorMessage != null"""
if old_loading_sites in content:
    content = content.replace(old_loading_sites, new_loading_sites)
else:
    print("Could not find _loadingSites")


# 4. Replace _loadingWorkspaces
old_loading_workspaces = """                      content: _loadingWorkspaces
                          ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                          : Column("""
new_loading_workspaces = """                      content: _loadingWorkspaces
                          ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: _buildMapSkeleton())
                          : Column("""
if old_loading_workspaces in content:
    content = content.replace(old_loading_workspaces, new_loading_workspaces)
else:
    print("Could not find _loadingWorkspaces")


with open('lib/screens/setup_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)