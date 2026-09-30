import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad1 = r"final isElsewhere = !isBooked && _bookedElsewhereMap\.containsKey\(dateStr\) && _showAllReservations;\s*final isDelegated = !isBooked && !isElsewhere && _delegatedBookingsMap\.containsKey\(dateStr\) && _showDelegatedReservations;\s*final isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers\.containsKey\(dateStr\);"
good1 = "final isElsewhere = _bookedElsewhereMap.containsKey(dateStr) && _showAllReservations;\n      final isDelegated = _delegatedBookingsMap.containsKey(dateStr) && _showDelegatedReservations;\n      final isOccupiedByOthers = !isBooked && !isElsewhere && !isDelegated && _occupiedByOthers.containsKey(dateStr);"
content = re.sub(bad1, good1, content)

bad2 = """    Color? bgColor;
    Color textColor = isOutside ? Colors.grey : Theme.of(context).colorScheme.onSurface;
    bool strikeThrough = false;

    if (isBooked) {
      bgColor = Colors.green;
      textColor = Colors.white;
    } else if (isRequested) {
      bgColor = Colors.blue;
      textColor = Colors.white;
    } else if (isIgnored) {
      bgColor = Colors.red.withValues(alpha: 0.8);
      textColor = Colors.white;
    } else if (isElsewhere) {
        bgColor = Colors.orange.shade200;
        textColor = Colors.orange.shade900;
        strikeThrough = false;
      } else if (isDelegated) {
        bgColor = Colors.purple.shade200;
        textColor = Colors.purple.shade900;
        strikeThrough = false;
      } else if (isOccupiedByOthers) {
      bgColor = Colors.grey.shade400;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = Colors.lightBlue.withValues(alpha: 0.3);
    }"""
    
good2 = """    Color? bgColor;
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
content = content.replace(bad2, good2)

bad3 = """        // Small "🔒" indicator for occupied by others
        if (isOccupiedByOthers)
          Positioned(
            bottom: 4,
            child: Icon(Icons.lock, size: _compactMode ? 8 : 10, color: Colors.white),
          ),
      ],
    );"""
    
good3 = """        // Multiple dots for overlapping reservations
        if (dots.isNotEmpty)
          Positioned(
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: dots.map((c) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              )).toList(),
            ),
          ),
        // Small "🔒" indicator for occupied by others
        if (isOccupiedByOthers)
          Positioned(
            bottom: 4,
            child: Icon(Icons.lock, size: _compactMode ? 8 : 10, color: Colors.white),
          ),
      ],
    );"""
content = content.replace(bad3, good3)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)