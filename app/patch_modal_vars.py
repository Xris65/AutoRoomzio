with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "final dParts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];" in line:
        del lines[i:i+3]
        break

for i, line in enumerate(lines):
    if "final action = await showModalBottomSheet<String>(" in line:
        lines.insert(i, "    final dParts = _delegatedBookingsMap[dateStr]?.split('|') ?? [];\n    final dName = dParts.length > 1 ? dParts[1] : 'votre collègue';\n    final dLoc = dParts.length > 2 ? dParts[2] : '';\n")
        print("Replaced!")
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)