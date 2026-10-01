# Project: AutoRoomzio v1.4.0

## Architecture
AutoRoomzio is a Flutter mobile application (Android / iOS) for automated and manual workspace desk reservations on MyRoomz (`api.my.roomz.io`).
- **Presentation**: Flutter Material 3 UI (`lib/screens/`, `lib/widgets/`).
- **Services**: `RoomzApiService` for HTTP interaction with MyRoomz REST API; `StorageService` for local caching (`SharedPreferences`).
- **Background Automation**: Android `Workmanager` background task runner.
- **State & Event Flow**: Service-backed state in StatefulWidget controllers with cached persistence.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F0 | Git Branch `version-1.4.0` & Baseline Sanity | Create and checkout branch `version-1.4.0`, fix outdated template test `widget_test.dart`, verify baseline `flutter test` | M0 | ORIGINAL_REQUEST §Contrainte Git |
| F1 | R1 MyRoomz API Spike Test | Automated test/script querying MyRoomz API for past reservation history, proving lack of historical query support | M1 | ORIGINAL_REQUEST §R1 |
| F2 | R1 Statistics Clean UI | Cleanly refactor Stats tab to display real, coherent metrics (upcoming bookings, auto/manual counters, desk loyalty rate, rhythm) | M1 | ORIGINAL_REQUEST §R1 |
| F3 | R2 Colleague Domain Model & Favorites Service | Add `Colleague` model, favorites persistence in `StorageService`, and `getFavorites` / directory search in `RoomzApiService` | M2 | ORIGINAL_REQUEST §R2 |
| F4 | R2 Colleague Reservation API & Error Handling | `reserveWorkspaceForColleague` with typed `BookingResult`, parsing HTTP 409 conflicts & error reasons | M2 | ORIGINAL_REQUEST §R2 |
| F5 | R2 Calendar Day Tap Colleague Popup & Search | Modal popup from Calendar day tap with search bar, favorites selector, and purple delegation display on calendar | M2 | ORIGINAL_REQUEST §R2 |
| F6 | R3 Occupancy & Favorites Cross-Referencing | Fetch floor occupancy via `POST /floors/{floorId}/workspaces/calendars` and match seated users with favorites | M3 | ORIGINAL_REQUEST §R3 |
| F7 | R3 2D Map Visual Markings | Render distinctive visual markings (amber/gold color, star badge) on desks occupied by favorite colleagues | M3 | ORIGINAL_REQUEST §R3 |
| F8 | R3 Desk Click Colleague Identity | Click on marked desk displays colleague identity (name, desk name, room) in tooltip or modal bottom sheet | M3 | ORIGINAL_REQUEST §R3 |
| F9 | R3 Room Focus & Filtering | Room filter chips to focus camera / zoom into rooms where favorite colleagues are seated | M3 | ORIGINAL_REQUEST §R3 |
| F10 | E2E Opaque-Box Test Suite (Tiers 1-4) | Comprehensive requirement-driven opaque-box test suite published via `TEST_READY.md` | M4 | System Specification |
| F11 | Adversarial Coverage Hardening (Tier 5) | White-box stress-testing, boundary edge cases, and code coverage audit | M4 | System Specification |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Git Branch Setup & Baseline Sanity | Create & checkout `version-1.4.0`, fix obsolete default `widget_test.dart`, verify baseline build | none | DONE |
| M1 | R1 Statistics Spike & Clean UI | Automated API spike test (`spike_api_history_test.dart`) + clean coherent stats tab in `home_screen.dart` | M0 | PLANNED |
| M2 | R2 Colleague Reservation Flow | Colleague model, API reservation delegation, error handling (409 conflict), Calendar day popup & search | M0 | PLANNED |
| M3 | R3 "Où est mon équipe ?" (2D Plan) | Occupancy data fetching, visual markings on 2D map, click identity popup, room filtering chips | M0, M2 | PLANNED |
| M4 | Final Milestone: E2E Test Suite & Adversarial Hardening | Phase 1: Pass 100% E2E tests (Tiers 1-4). Phase 2: Adversarial coverage hardening (Tier 5) | M1, M2, M3 | PLANNED |

## Interface Contracts

### 1. Colleague Domain Model (`app/lib/models/colleague.dart`)
```dart
class Colleague {
  final String id;
  final String name;
  final String email;
  final bool isFavorite;
  final String? deskName;
  final String? roomName;

  Colleague({
    required this.id,
    required this.name,
    required this.email,
    this.isFavorite = false,
    this.deskName,
    this.roomName,
  });

  Map<String, dynamic> toJson();
  factory Colleague.fromJson(Map<String, dynamic> json);
}
```

### 2. Booking Result (`app/lib/models/booking_result.dart`)
```dart
enum BookingStatus { success, conflictDesk, conflictColleague, invalidDate, networkError, unauthorized }

class BookingResult {
  final BookingStatus status;
  final String message;
  final String? eventId;

  BookingResult({required this.status, required this.message, this.eventId});
  bool get isSuccess => status == BookingStatus.success;
}
```

### 3. RoomzApiService Extensions (`app/lib/api_service.dart`)
```dart
Future<BookingResult> reserveWorkspaceForColleague({
  required String date,
  required String token,
  required String workspaceId,
  required String colleagueId,
  String? colleagueName,
});

Future<List<Colleague>> getFavorites(String token);
Future<List<Colleague>> searchColleagues(String token, String query);
Future<Map<String, DeskOccupant>> getFloorOccupants(String token, String floorId, String date);
```

### 4. 2D Map Workspace Viewer Extensions (`app/lib/widgets/workspace_map_viewer.dart`)
```dart
// Additional parameters in WorkspaceMapViewer:
final Set<String> favoriteWorkspaceIds;
final Function(Map<String, dynamic> workspace, DeskOccupant occupant)? onOccupantTapped;
final String? focusedRoomPrefix;
```

## Code Layout
- `app/lib/models/`: Domain models (`colleague.dart`, `booking_result.dart`, `desk_occupant.dart`).
- `app/lib/services/`: Services or extensions to `api_service.dart`, `storage_service.dart`.
- `app/lib/screens/`: Screen widgets (`home_screen.dart`, `team_map_screen.dart` or enhanced map widgets).
- `app/lib/widgets/`: Reusable UI (`colleague_selection_dialog.dart`, `workspace_map_viewer.dart`).
- `app/test/`: Unit, widget, and E2E tests (`spike_api_history_test.dart`, `colleague_reservation_test.dart`, `team_map_test.dart`, `e2e_v140_test.dart`).
