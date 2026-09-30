with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1
for i, line in enumerate(lines):
    if line.strip().startswith("if (isDelegated) {") and "Délégué" in lines[i+1]:
        start_idx = i
    if line.strip() == "if (upcoming.isEmpty) {":
        end_idx = i
        break

if start_idx != -1 and end_idx != -1:
    del lines[start_idx:end_idx]
    
    good = """      if (isDelegated) {
        upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": delegateName});
      }
      
      if (isElsewhere) {
        upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
      } else if (isBooked) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": true});
      } else if (isRequested) {
        upcoming.add({"date": date, "source": "Calendrier", "isBooked": false});
      } else if (isOccupiedByOthers) {
        if (isRecurring && recurringProjectionsCount < _projectionsCount) {
          upcoming.add({"date": date, "source": "Occupé", "isBooked": false, "name": _occupiedByOthers[dateStr]});
          recurringProjectionsCount++;
        }
      } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
        upcoming.add({"date": date, "source": "Récurrent", "isBooked": false});
        recurringProjectionsCount++;
      }
    }

    """
    lines.insert(start_idx, good)
    
    with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("Replaced!")
else:
    print(f"Failed to find indices. Start: {start_idx}, End: {end_idx}")