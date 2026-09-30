with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """        if (isElsewhere) {
          if (_showAllReservations) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
          } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": false, "name": _bookedElsewhereMap[dateStr]});
            recurringProjectionsCount++;
          }
        } else if (isOccupiedByOthers) {
          if (isRecurring && recurringProjectionsCount < _projectionsCount) {
            upcoming.add({"date": date, "source": "Occupé", "isBooked": false, "name": _occupiedByOthers[dateStr]});
            recurringProjectionsCount++;
          }
        } else if (isRequested) {
          upcoming.add({"date": date, "source": "Calendrier", "isBooked": isBooked});
        } else if (isBooked) {
          // Réservation orpheline ou issue d'une récurrence
          String source = isRecurring ? "Récurrent" : "Calendrier";
          upcoming.add({"date": date, "source": source, "isBooked": true});
        } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
          // Projection future de l'automatisation
          upcoming.add({"date": date, "source": "Récurrent", "isBooked": false});
          recurringProjectionsCount++;
        }"""
bad = bad.replace("Occupé", "OccupÃ©").replace("Réservation", "RÃ©servation").replace("récurrence", "rÃ©currence").replace("Récurrent", "RÃ©current")

good = """        // We evaluate independent bookings so that multiple tiles can show up for the same day (e.g. My booking + Delegated booking)
        bool addedProjection = false;
        
        if (isElsewhere) {
          if (_showAllReservations) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": true, "name": _bookedElsewhereMap[dateStr]});
          } else if (isRecurring && recurringProjectionsCount < _projectionsCount) {
            upcoming.add({"date": date, "source": "Ailleurs", "isBooked": false, "name": _bookedElsewhereMap[dateStr]});
            recurringProjectionsCount++;
            addedProjection = true;
          }
        }
        
        if (isDelegated) {
          if (_showDelegatedReservations) {
            upcoming.add({"date": date, "source": "Délégué", "isBooked": true, "name": _delegatedBookingsMap[dateStr]});
          }
        }
        
        if (isBooked) {
          String source = isRecurring ? "Récurrent" : "Calendrier";
          upcoming.add({"date": date, "source": source, "isBooked": true});
        } else if (isRequested) {
          upcoming.add({"date": date, "source": "Calendrier", "isBooked": isBooked});
        } else if (isOccupiedByOthers && !addedProjection) {
          if (isRecurring && recurringProjectionsCount < _projectionsCount) {
            upcoming.add({"date": date, "source": "Occupé", "isBooked": false, "name": _occupiedByOthers[dateStr]});
            recurringProjectionsCount++;
            addedProjection = true;
          }
        } else if (isRecurring && !addedProjection && !isElsewhere && !isOccupiedByOthers && recurringProjectionsCount < _projectionsCount) {
          upcoming.add({"date": date, "source": "Récurrent", "isBooked": false});
          recurringProjectionsCount++;
        }"""
good = good.replace("Occupé", "OccupÃ©").replace("Délégué", "DÃ©lÃ©guÃ©").replace("Récurrent", "RÃ©current")

content = content.replace(bad, good)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)