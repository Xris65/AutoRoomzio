import re

with open('lib/screens/setup_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Make sure shimmer is imported
if 'import \'package:shimmer/shimmer.dart\';' not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:shimmer/shimmer.dart';")

# Add the skeleton method
skeleton_method = """  Widget _buildMapSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: [
          // Fake SegmentedButton
          Container(
            height: 40,
            width: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 16),
          // Fake Map Area
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
                Positioned(bottom: 120, left: 150, child: Container(width: 40, height: 40, shape: BoxShape.circle, color: Colors.white)),
                Positioned(bottom: 180, left: 80, child: Container(width: 40, height: 20, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override"""

content = content.replace("  @override\n  Widget build(BuildContext context) {", skeleton_method + "\n  Widget build(BuildContext context) {")


# Replace the circular progress indicator
old_loader = "_loadingWorkspaces\n                            ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())\n                            : Column("
new_loader = "_loadingWorkspaces\n                            ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: _buildMapSkeleton())\n                            : Column("

content = content.replace(old_pageview := "_loadingWorkspaces\n                            ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())\n                            : Column(", new_loader)
if old_pageview not in content:
    # try regex
    content = re.sub(r"_loadingWorkspaces\s*\?\s*const Padding\(padding:\s*EdgeInsets\.all\(16\),\s*child:\s*CircularProgressIndicator\(\)\)\s*:\s*Column\(", "_loadingWorkspaces ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: _buildMapSkeleton()) : Column(", content)


with open('lib/screens/setup_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)