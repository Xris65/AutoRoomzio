# Project: AutoRoomzio v1.6.3 (Web Team Map Stability & Favorites Query Hotfix)

## Architecture
AutoRoomzio is a multi-platform Flutter application for desk booking and presence management.
In v1.6.2, AutoRoomzio introduces a reactive, non-blocking offline mode with global fixed ribbon and comprehensive local cache persistence:
- **Network & State Layer**:
  - `OfflineStateManager` (`app/lib/offline_state_manager.dart`): Central singleton exposing reactive `ValueNotifier<bool> isOfflineNotifier`. Starts with `isOffline == false` (R1).
  - `OfflineAwareHttpClient` (`app/lib/offline_state_manager.dart`): Extends `http.BaseClient`, intercepts `SocketException`, `TimeoutException`, `ClientException` to flip `isOffline = true` (R2). On successful HTTP response (2xx), flips `isOffline = false`. Unconditionally forwards all requests without blocking or short-circuiting (R1).
  - `RoomzApiService` (`app/lib/api_service.dart`): Uses `OfflineAwareHttpClient` for standard and batch parallel HTTP queries. Propagates network errors to prevent destructive cache wiping.
- **Persistence Layer**:
  - `StorageService` (`app/lib/storage_service.dart`): Persistent cache using `SharedPreferences`. In v1.6.2, extended with persistence for `booked_elsewhere_map`, `occupied_by_others_map`, `floor_occupants_${floorId}_$date`, `floor_plan_$floorId`, and `floor_workspaces_$floorId`.
  - Non-destructive caching in `HomeScreen` and `TeamMapScreen`: In case of network failure or offline mode, cached personal reservations, delegated reservations, calendar days, and map occupants are strictly preserved and never overwritten with empty collections (R3).
- **Presentation & Global Ribbon Layer**:
  - `OfflineRibbon` (`app/lib/widgets/offline_ribbon.dart`): Fixed, discrete ribbon displaying exact text: `"Hors ligne • Affichage des dernières données synchronisées"`. Styled with Amber theme and WCAG AAA compliant text contrast.
  - `MaterialApp.builder` (`app/lib/main.dart`): Root shell wrapper mounting `OfflineRibbon` via `ValueListenableBuilder<bool>` above/below the root `Navigator` (`child`), guaranteeing universal presence across all screens, dialogs, and navigation routes without modifying individual screen files (R2).
- **Quality & Test Track**:
  - `flutter analyze`: 0 issues found.
  - Comprehensive unit & widget test suite in `app/test/` validating offline state transitions, ribbon rendering, cache persistence, and screen resilience.
  - Strict local branch execution on `version-1.6.2` without remote push.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | R1.1 Online Startup Default | App starts by default with `isOffline == false` and hidden ribbon | M1 | ORIGINAL_REQUEST §R1 |
| 2 | R1.2 Continuous Unblocked API Requests | All user actions, navigation, and refreshes trigger real API requests without being blocked or short-circuited when offline | M1 | ORIGINAL_REQUEST §R1 |
| 3 | R2.1 Reactive Offline Detection | Switch `isOffline = true` immediately upon network connectivity error (`SocketException`, `TimeoutException`, `ClientException`) | M1 | ORIGINAL_REQUEST §R2 |
| 4 | R2.2 Reactive Online Restoration | Switch `isOffline = false` immediately upon any successful API response (2xx) and hide ribbon | M1 | ORIGINAL_REQUEST §R2 |
| 5 | R2.3 Global Fixed Offline Ribbon | Persistent discrete ribbon with exact text: `"Hors ligne • Affichage des dernières données synchronisées"` mounted globally in `MaterialApp.builder` | M3 | ORIGINAL_REQUEST §R2 |
| 6 | R3.1 Personal Reservations Cache Persistence | Preserve personal reservations in `StorageService` and `HomeScreen` without clearing to empty list on network failure | M2 | ORIGINAL_REQUEST §R3 |
| 7 | R3.2 Delegated Reservations Cache Persistence | Preserve delegated reservations in `StorageService` and `HomeScreen` without clearing to empty list on network failure | M2 | ORIGINAL_REQUEST §R3 |
| 8 | R3.3 Calendar Days Cache Persistence | Preserve calendar days, requested dates, and third-party occupancy in `StorageService` and `HomeScreen` without clearing on network failure | M2 | ORIGINAL_REQUEST §R3 |
| 9 | R3.4 Map Occupants Cache Persistence | Implement `saveFloorOccupants` / `getFloorOccupants` in `StorageService` and preserve occupants in `TeamMapScreen` without clearing on network failure | M2 | ORIGINAL_REQUEST §R3 |
| 10 | R4.1 Version Bump & Metadata Alignment | Bump `pubspec.yaml` to `version: 1.6.2` | M2 | ORIGINAL_REQUEST §R4 |
| 11 | R4.2 Unit & Widget Test Suite | Comprehensive tests in `app/test/` covering offline reactivity, ribbon visibility, and cache persistence | M4 | ORIGINAL_REQUEST §R4 |
| 12 | R4.3 Static Analysis Cleanliness | `flutter analyze` passes with 0 issues | M4 | ORIGINAL_REQUEST §R4 |
| 13 | R4.4 Git Local Branch Conformance | Work exclusively on `version-1.6.2` with 0 remote pushes | M4 | ORIGINAL_REQUEST §R4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Reactive Offline Network Layer | R1.1, R1.2, R2.1, R2.2 | None | DONE (`OfflineStateManager`, `OfflineAwareHttpClient`, 62/62 tests passed) |
| M2 | StorageService Persistence & Screen Protection | R3.1, R3.2, R3.3, R3.4, R4.1 | None (uses OfflineStateManager contract) | DONE (`StorageService`, `HomeScreen`, `TeamMapScreen`, `pubspec.yaml` 1.6.2, 45/45 tests passed) |
| M3 | Global Fixed Offline Ribbon & App Shell | R2.3 | None (uses OfflineStateManager contract) | DONE (`OfflineRibbon`, `main.dart` builder, 13/13 tests passed) |
| M4 | Comprehensive Testing Track & Verification Gate | R4.2, R4.3, R4.4 | M1, M2, M3 | DONE (59/59 E2E tests, 27/27 stress tests, Gate PASS: 2x APPROVE, 2x CHALLENGE PASS, CLEAN AUDIT) |


## Interface Contracts

### `app/lib/offline_state_manager.dart` (M1)
```dart
class OfflineStateManager {
  OfflineStateManager._();
  static final OfflineStateManager instance = OfflineStateManager._();

  final ValueNotifier<bool> isOfflineNotifier = ValueNotifier<bool>(false);
  bool get isOffline => isOfflineNotifier.value;

  void markOffline();
  void markOnline();
  void reset(); // For testing: resets to false
  bool isConnectivityError(Object error);
}

class OfflineAwareHttpClient extends http.BaseClient {
  final http.Client _inner;
  OfflineAwareHttpClient([http.Client? inner]);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request);
}
```

### `app/lib/storage_service.dart` (M2)
```dart
// Personal elsewhere reservations map
Future<void> saveBookedElsewhereMap(Map<String, String> map);
Future<Map<String, String>> getBookedElsewhereMap();

// Calendar third-party occupancy map
Future<void> saveOccupiedByOthers(Map<String, String> map);
Future<Map<String, String>> getOccupiedByOthers();

// Delegated reservations map (save during calendar sync)
Future<void> saveDelegatedBookingsMap(Map<String, String> map);
Future<Map<String, String>> getDelegatedBookingsMap();

// Floor occupants persistence
Future<void> saveFloorOccupants(String floorId, String date, Map<String, DeskOccupant> occupants);
Future<Map<String, DeskOccupant>> getFloorOccupants(String floorId, String date);

// Floor plan and workspaces persistence
Future<void> saveFloorPlanData(String floorId, dynamic planData);
Future<dynamic> getFloorPlanData(String floorId);
Future<void> saveFloorWorkspaces(String floorId, List<Map<String, dynamic>> workspaces);
Future<List<Map<String, dynamic>>> getFloorWorkspaces(String floorId);
```

### `app/lib/widgets/offline_ribbon.dart` ↔ `app/lib/main.dart` (M3)
```dart
class OfflineRibbon extends StatelessWidget {
  const OfflineRibbon({super.key});
  static const String ribbonText = "Hors ligne • Affichage des dernières données synchronisées";
  @override
  Widget build(BuildContext context);
}

// In MaterialApp.builder (main.dart):
builder: (context, child) {
  final mediaQuery = MediaQuery.of(context);
  final targetScale = (mediaQuery.textScaler.scale(1.0) * uiScale).clamp(0.75, 1.35);
  return MediaQuery(
    data: mediaQuery.copyWith(textScaler: TextScaler.linear(targetScale)),
    child: ValueListenableBuilder<bool>(
      valueListenable: OfflineStateManager.instance.isOfflineNotifier,
      builder: (context, isOffline, _) {
        return Column(
          children: [
            Expanded(child: child ?? const SizedBox.shrink()),
            if (isOffline) const OfflineRibbon(),
          ],
        );
      },
    ),
  );
}
```

## Code Layout
- `app/lib/offline_state_manager.dart`: Owned exclusively by Milestone 1 Worker
- `app/lib/api_service.dart`: Owned exclusively by Milestone 1 Worker
- `app/lib/storage_service.dart`: Owned exclusively by Milestone 2 Worker
- `app/lib/screens/home_screen.dart`: Owned exclusively by Milestone 2 Worker
- `app/lib/screens/team_map_screen.dart`: Owned exclusively by Milestone 2 Worker
- `app/pubspec.yaml`: Owned exclusively by Milestone 2 Worker
- `app/lib/widgets/offline_ribbon.dart`: Owned exclusively by Milestone 3 Worker
- `app/lib/main.dart`: Owned exclusively by Milestone 3 Worker
- `app/test/`: Owned by Milestone 4 Testing Track & Test Writer
