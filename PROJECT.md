# Project: AutoRoomzio v1.6.0

## Architecture
AutoRoomzio is a multi-platform Flutter application (Android, Windows, Web) for desk booking and presence management.
- **Presentation Layer**:
  - `LoginScreen` (`app/lib/screens/login_screen.dart`): Authentication, Web Form with regex validation, email remembering.
  - `HomeScreen` (`app/lib/screens/home_screen.dart`): Navigation bar, dynamic tab rendering (Home, Calendar, Automate, Stats, Settings), multi-platform auto-updates.
  - `TeamMapScreen` (`app/lib/screens/team_map_screen.dart`): 2D interactive floor plan view, date navigation, presence filter panel, free desk booking & cancellation bottom sheets.
  - `WorkspaceMapViewer` (`app/lib/widgets/workspace_map_viewer.dart`): Custom SVG/canvas floor rendering, `TransformationController` camera centering & zooming, desk tap dispatching.
  - `OccupantDetailsSheet` (`app/lib/widgets/occupant_details_sheet.dart`): Colleague detail card, favorite toggle, own-desk booking cancellation button.
- **Service Layer**:
  - `StorageService` (`app/lib/storage_service.dart`): Local persistence via `SharedPreferences` and `FlutterSecureStorage`, preserving remembered email across `clearAllData()` / `clearTokens()`.
  - `ApiService` (`app/lib/api_service.dart`): Direct and delegated booking API endpoints, roomzauth worker calls.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | R1.1 Web Form & TextFormField | Replace simple TextFields with Form & GlobalKey<FormState> in LoginScreen for Web | M1 | ORIGINAL_REQUEST §R1 |
| 2 | R1.2 Strict Email Regex Validation | Enforce non-empty, trimmed, regex `^[^\s@]+@[^\s@]+\.[^\s@]+$` with explicit error message | M1 | ORIGINAL_REQUEST §R1 |
| 3 | R1.3 Password Min-Length Validation | Enforce non-empty, min 6 characters with error message under password field | M1 | ORIGINAL_REQUEST §R1 |
| 4 | R1.4 Network Call Blocking | Prevent any call to `_api.login()` or Cloudflare Worker if form validation fails | M1 | ORIGINAL_REQUEST §R1 |
| 5 | R1.5 Remember My Email Option | Checkbox "Se souvenir de mon email" (default true), persist in StorageService, preserve on logout if checked, erase if unchecked | M1 | ORIGINAL_REQUEST §R1 |
| 6 | R2.1 Web Auto-Update Disable | Skip `_checkUpdatesOnStartup()` on Web (`kIsWeb`) | M2 | ORIGINAL_REQUEST §R2 |
| 7 | R2.2 Windows Auto-Update Target | Find asset ending in `.zip` (or html_url fallback) and launch via `launchUrl(..., mode: LaunchMode.externalApplication)` on Windows | M2 | ORIGINAL_REQUEST §R2 |
| 8 | R2.3 Android Auto-Update Target | Target asset ending in `.apk` on Android using `DownloadDialog` + `OpenFilex` | M2 | ORIGINAL_REQUEST §R2 |
| 9 | R3.1 Web Stats Banner Clean-up | Hide or adapt "Rythme de Présence Paramétré" banner on Web when `_selectedDays` is empty, avoiding mention of hidden Automate tab | M2 | ORIGINAL_REQUEST §R3 |
| 10 | R3.2 Settings Tab Index Fix | Deterministic `_currentIndex` calculation when toggling Automate and Stats switches, preventing RangeError / tab shift | M2 | ORIGINAL_REQUEST §R3 |
| 11 | R4.1 Free Desk Tap & BottomSheet | Wire `WorkspaceMapViewer.onSelected`, open bottom sheet displaying desk, room, and date info | M3 | ORIGINAL_REQUEST §R4 |
| 12 | R4.2 Booking Date Guard | Show non-availability message if date is in the past or beyond J+13 | M3 | ORIGINAL_REQUEST §R4 |
| 13 | R4.3 Reserve For Me (Direct) | Reserve workspace without overriding default favorite desk, update local state and refresh floor occupancy | M3 | ORIGINAL_REQUEST §R4 |
| 14 | R4.4 Reserve For Colleague (Delegated) | Open `ColleagueSelectionDialog`, call `reserveWorkspaceForColleague`, persist delegation, refresh occupancy | M3 | ORIGINAL_REQUEST §R4 |
| 15 | R4.5 Cancel Own Reservation from Map | Show "Libérer ma place" button in `OccupantDetailsSheet` when `occupant.isMe == true`, call cancellation API and refresh map | M3 | ORIGINAL_REQUEST §R4 |
| 16 | R5.1 Desk Camera Centering & Zoom | Implement camera focus on desk coordinates via `TransformationController` in `WorkspaceMapViewer` | M3 | ORIGINAL_REQUEST §R5 |
| 17 | R5.2 Colleagues Search & Filter | Add search field in "Collègues présents" panel in `TeamMapScreen` filtering by name or room | M3 | ORIGINAL_REQUEST §R5 |
| 18 | R5.3 Colleague Tap to Camera Focus | Tapping a colleague focuses/zooms the camera on their desk and opens their `OccupantDetailsSheet` | M3 | ORIGINAL_REQUEST §R5 |
| 19 | R6.1 Version Bump 1.5.2 | Update `version: 1.5.2` in `app/pubspec.yaml` | M4 | ORIGINAL_REQUEST §R6 |
| 20 | R6.2 CHANGELOG 1.5.2 Entry | Add `## [1.5.2] - 2026-10-11` entry at top of root `CHANGELOG.md` | M4 | ORIGINAL_REQUEST §R6 |
| 21 | R6.3 Static Analysis Clean-up | Resolve existing linter issues in `lib/` and `test/` to achieve `flutter analyze` exit 0 (No issues found!) | M4 | ORIGINAL_REQUEST §R6 |
| 22 | R6.4 Test Suite & 100% Pass Rate | Add/update comprehensive unit & widget tests covering R1-R5, ensure `flutter test` passes 100% | M5 | ORIGINAL_REQUEST §R6 |
| 23 | R6.5 Strict Git Conformance | Work strictly on local branch `version-1.5.2`, 0 remote pushes, no changes to main/develop | M4 | ORIGINAL_REQUEST §R6 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Web Login Form & Email Remember | R1.1, R1.2, R1.3, R1.4, R1.5 | None | DONE |
| M2 | Multi-Platform Update & Web Stats/Settings | R2.1, R2.2, R2.3, R3.1, R3.2 | None | DONE |
| M3 | 2D Team Map Booking, Cancel, Focus & Search | R4.1–R4.5, R5.1–R5.3 | None | DONE |
| M4 | Version 1.5.2, CHANGELOG & Linter Clean-up | R6.1, R6.2, R6.3, R6.5 | M1, M2, M3 | DONE |
| M5 | Comprehensive Testing Track & Verification Gate | R6.4 (Tiers 1-4 tests, Challenger & Auditor) | M1, M2, M3, M4 | DONE (Streamlined per user directive) |

## Interface Contracts
### `app/lib/storage_service.dart` (M1)
- `Future<void> saveRememberEmail(bool remember)`
- `Future<bool> getRememberEmail()`
- `Future<void> saveSavedEmail(String email)`
- `Future<String?> getSavedEmail()`
- `Future<void> clearAll()` / `clearAllData()`: Must preserve `saved_email` and `remember_email` if `remember_email == true`; if `false`, remove both.

### `app/lib/screens/login_screen.dart` (M1)
- Form validation via `final _formKey = GlobalKey<FormState>()`.
- Regex: `RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')`.
- Password: min 6 chars.

### `app/lib/screens/home_screen.dart` (M2)
- Updates check:
  - If `kIsWeb`, return immediately.
  - If Android (`Platform.isAndroid`), filter asset ending in `.apk`.
  - If Windows (`Platform.isWindows`), filter asset ending in `.zip` or fallback `html_url`, call `launchUrl(..., mode: LaunchMode.externalApplication)`.
- Tab indexing:
  - `_currentIndex = 2 + (_showAutomation && !kIsWeb ? 1 : 0) + (_showStats ? 1 : 0)` when switches toggle.

### `app/lib/widgets/workspace_map_viewer.dart` ↔ `app/lib/screens/team_map_screen.dart` (M3)
- `WorkspaceMapViewer`:
  - `final String? focusedWorkspaceId;` (or `void focusWorkspace(String workspaceId)`)
  - Calculates desk center and applies `TransformationController` matrix with zoom factor ~1.8.
  - `onSelected: (Workspace ws) => void` triggered when free desk tapped.
- `OccupantDetailsSheet`:
  - `final VoidCallback? onCancelMyBooking;`
  - Shows "Libérer ma place" button when `occupant.isMe == true` and `onCancelMyBooking != null`.

## Code Layout
- `app/lib/screens/login_screen.dart`: Owned exclusively by Milestone 1 Worker
- `app/lib/storage_service.dart`: Owned exclusively by Milestone 1 Worker
- `app/lib/screens/home_screen.dart`: Owned exclusively by Milestone 2 Worker
- `app/lib/screens/team_map_screen.dart`: Owned exclusively by Milestone 3 Worker
- `app/lib/widgets/workspace_map_viewer.dart`: Owned exclusively by Milestone 3 Worker
- `app/lib/widgets/occupant_details_sheet.dart`: Owned exclusively by Milestone 3 Worker
- `app/pubspec.yaml`, `CHANGELOG.md`, lint fixes in `app/lib/`: Owned by Milestone 4 Worker
- `app/test/`: Owned by Milestone 5 Worker / Test Writer
