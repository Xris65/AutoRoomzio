with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "if (action == 'reserve') {" in line:
        lines.insert(i+1, "          if (_bookedDates.contains(dateStr) || _bookedElsewhereMap.containsKey(dateStr)) {\n            if (mounted) _showTopToast('Place déjà réservée (filtre désactivé)', isError: true);\n            return;\n          }\n")
        print("Replaced!")
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)