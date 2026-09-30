import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. State variable
content = content.replace("List<DateTimeRange> _vacations = [];", "List<DateTimeRange> _vacations = [];\n  bool _vacationsEnabled = true;")

# 2. _isVacation logic
old_isVacation = """  bool _isVacation(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (final v in _vacations) {"""
new_isVacation = """  bool _isVacation(DateTime date) {
    if (!_vacationsEnabled) return false;
    final d = DateTime(date.year, date.month, date.day);
    for (final v in _vacations) {"""
content = content.replace(old_isVacation, new_isVacation)

# 3. Load from storage
content = content.replace("final vacs = await _storage.getVacations();", "final vacs = await _storage.getVacations();\n      final vacsEnabled = await _storage.getVacationsEnabled();")
content = content.replace("_vacations = vacs.map((v) => DateTimeRange(", "_vacationsEnabled = vacsEnabled;\n          _vacations = vacs.map((v) => DateTimeRange(")

# 4. Settings toggle logic for _showAutomation
old_settings_toggle = """                  onChanged: (val) {
                    setState(() => _showAutomation = val);
                    _storage.saveShowAutomation(val);
                  },"""
new_settings_toggle = """                  onChanged: (val) {
                    setState(() {
                      _showAutomation = val;
                      if (!val) {
                        if (_automationEnabled) _toggleAutomation(false);
                        _vacationsEnabled = false;
                        _storage.saveVacationsEnabled(false);
                      }
                    });
                    _storage.saveShowAutomation(val);
                  },"""
content = content.replace(old_settings_toggle, new_settings_toggle)


# 5. Add SwitchListTile to Automation tab for _vacationsEnabled
old_auto_card = """                        child: Column(
                          children: [
                            const ListTile(
                              leading: Icon(Icons.beach_access, color: Colors.orange),
                              title: Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                            ),
                            if (_vacations.isNotEmpty) const Divider(height: 1),"""
# Note: due to python formatting of strings from earlier, I must match carefully.
old_auto_card_regex = r"                        child: Column\(\s*children: \[\s*const ListTile\(\s*leading: Icon\(Icons\.beach_access, color: Colors\.orange\),\s*title: Text\('Mes Cong.s / Absences', style: TextStyle\(fontWeight: FontWeight\.bold\)\),\s*subtitle: Text\('L\\'automatisation est d.sactiv.e sur ces dates', style: TextStyle\(fontSize: 12\)\),\s*\),\s*if \(_vacations\.isNotEmpty\) const Divider\(height: 1\),"

new_auto_card = """                        child: Column(
                          children: [
                            SwitchListTile(
                              secondary: const Icon(Icons.beach_access, color: Colors.orange),
                              title: const Text('Mes Congés / Absences', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('L\\'automatisation est désactivée sur ces dates', style: TextStyle(fontSize: 12)),
                              value: _vacationsEnabled,
                              onChanged: (val) {
                                setState(() => _vacationsEnabled = val);
                                _storage.saveVacationsEnabled(val);
                              },
                            ),
                            if (_vacationsEnabled && _vacations.isNotEmpty) const Divider(height: 1),"""
content = re.sub(old_auto_card_regex, new_auto_card, content)


# 6. Calendar selectableDayPredicate modification
old_calendar_pred = """                      for (final v in _vacations) {
                        final start = DateTime(v.start.year, v.start.month, v.start.day);
                        final end = DateTime(v.end.year, v.end.month, v.end.day);"""
new_calendar_pred = """                      if (_vacationsEnabled) {
                        for (final v in _vacations) {
                          final start = DateTime(v.start.year, v.start.month, v.start.day);
                          final end = DateTime(v.end.year, v.end.month, v.end.day);
                          if (!normDay.isBefore(start) && !normDay.isAfter(end)) {
                            return false;
                          }
                        }
                      }"""
content = content.replace(old_calendar_pred, new_calendar_pred)
# Need to remove the inner return false logic that got duplicated/orphaned
# Actually let's just use regex for calendar pred
content = re.sub(r"                      for \(final v in _vacations\) \{\s*final start = DateTime\(v\.start\.year, v\.start\.month, v\.start\.day\);\s*final end = DateTime\(v\.end\.year, v\.end\.month, v\.end\.day\);\s*if \(!normDay\.isBefore\(start\) && !normDay\.isAfter\(end\)\) \{\s*return false;\s*\}\s*\}", r"                      if (_vacationsEnabled) {\n                        for (final v in _vacations) {\n                          final start = DateTime(v.start.year, v.start.month, v.start.day);\n                          final end = DateTime(v.end.year, v.end.month, v.end.day);\n                          if (!normDay.isBefore(start) && !normDay.isAfter(end)) {\n                            return false;\n                          }\n                        }\n                      }", content)


# 7. Hide vacation list if disabled
content = re.sub(r"                            \.\.\._vacations\.map\(\(v\) \{", r"                            if (_vacationsEnabled) ..._vacations.map((v) {", content)


with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)