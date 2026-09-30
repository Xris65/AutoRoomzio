import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = """    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;
    bool strikeThrough = false;
    List<Color> dots = [];

    if (isBooked) {
      bgColor = Colors.green;
      textColor = Colors.white;
      if (isElsewhere) dots.add(Colors.orange.shade400);
      if (isDelegated) dots.add(Colors.purple.shade400);
    } else if (isElsewhere) {
      bgColor = Colors.orange.shade200;
      textColor = Colors.orange.shade900;
      if (isDelegated) dots.add(Colors.purple.shade400);
    } else if (isDelegated) {
      bgColor = Colors.purple.shade200;
      textColor = Colors.purple.shade900;
    } else if (isRequested) {
      bgColor = Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: 0.8);
      textColor = Colors.white;
    } else if (isOccupiedByOthers) {
      bgColor = Colors.grey.shade400;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: 0.3);
    }"""
    
good1 = """    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;
    bool strikeThrough = false;
    List<Color> dots = [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isBooked) {
      bgColor = isDark ? Colors.green.shade700 : Colors.green;
      textColor = Colors.white;
      if (isElsewhere) dots.add(isDark ? Colors.orange.shade300 : Colors.orange.shade400);
      if (isDelegated) dots.add(isDark ? Colors.purple.shade300 : Colors.purple.shade400);
    } else if (isElsewhere) {
      bgColor = isDark ? Colors.orange.shade800 : Colors.orange.shade200;
      textColor = isDark ? Colors.orange.shade100 : Colors.orange.shade900;
      if (isDelegated) dots.add(isDark ? Colors.purple.shade300 : Colors.purple.shade400);
    } else if (isDelegated) {
      bgColor = isDark ? Colors.purple.shade800 : Colors.purple.shade200;
      textColor = isDark ? Colors.purple.shade100 : Colors.purple.shade900;
    } else if (isRequested) {
      bgColor = isDark ? Colors.blue.shade700 : Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: isDark ? 0.6 : 0.8);
      textColor = Colors.white;
    } else if (isOccupiedByOthers) {
      bgColor = isDark ? Colors.grey.shade700 : Colors.grey.shade400;
      textColor = isDark ? Colors.grey.shade200 : Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: isDark ? 0.2 : 0.3);
    }"""
content = content.replace(bad1, good1)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)