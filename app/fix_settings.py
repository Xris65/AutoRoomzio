import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# I will write a regex to capture everything from `Widget _buildSettingsTab() {` to `return ListView(` ... until the `const Text('Notifications',`
# Wait, it's easier to just find the ListView children and replace them programmatically.

# Let's extract the widgets that need to be reordered.
# I will use a simple script that modifies the sections manually.

# 1. Rename "Interface Accueil" to "Interface & Navigation"
content = content.replace("const Text('Interface Accueil'", "const Text('Interface & Navigation'")

# 2. Rename "Afficher l'encart" to "Afficher l'onglet"
content = content.replace("Afficher l'encart Automatisation", "Afficher l'onglet Automatisation")
content = content.replace("Afficher l'encart Statistiques", "Afficher l'onglet Statistiques")

# 3. Fix the double SizedBox before Interface & Navigation
content = content.replace("        const SizedBox(height: 24);\n        \n          const SizedBox(height: 24);\n          const Text('Interface & Navigation'", "        const SizedBox(height: 24);\n        const Text('Interface & Navigation'")
content = content.replace("        const SizedBox(height: 24);\n        \n        const SizedBox(height: 24);\n        const Text('Interface & Navigation'", "        const SizedBox(height: 24);\n        const Text('Interface & Navigation'")

# 4. Add the missing SizedBox before Calendrier
content = content.replace("          ),\n          const Text('Calendrier',", "          ),\n        const SizedBox(height: 24);\n        const Text('Calendrier',")

# 5. Rename "Général" to "Apparence & Thème"
content = content.replace("const Text('Général',", "const Text('Apparence & Thème',")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)