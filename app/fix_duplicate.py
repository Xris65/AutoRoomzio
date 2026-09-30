with open('lib/screens/setup_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the second _buildMapSkeleton
first_idx = content.find("  Widget _buildMapSkeleton() {")
second_idx = content.find("  Widget _buildMapSkeleton() {", first_idx + 1)

if second_idx != -1:
    end_idx = content.find("  @override", second_idx)
    content = content[:second_idx] + content[end_idx:]
    with open('lib/screens/setup_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
        print("Removed duplicate")