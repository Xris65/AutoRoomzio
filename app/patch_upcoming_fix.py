with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "if (isElsewhere) {" in line and "upcoming.add" in lines[i+1]:
        # we found it
        print("Found the block at line", i)
        lines[i] = "        if (isElsewhere) {\n          if (!isDelegated) upcoming.add({\"date\": date, \"source\": \"Ailleurs\", \"isBooked\": true, \"name\": _bookedElsewhereMap[dateStr]});\n        }\n        if (isBooked) {\n          if (!(isDelegated && _delegatedBookingsMap[dateStr]!.contains('Mon bureau'))) upcoming.add({\"date\": date, \"source\": \"Calendrier\", \"isBooked\": true});\n        } else if (isRequested) {\n"
        # delete the next 4 lines
        del lines[i+1:i+5]
        break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)