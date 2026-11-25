# Project: AutoRoomzio v2.0.0 (Modular Architecture, Wasm Web, R8 Android & Strict Dart 3)

## Architecture
AutoRoomzio is a multi-platform Flutter application (Android, Windows, Web/WebAssembly) for desk booking, 2D interactive team floor mapping, and background presence automation.

### Core Services & Network Layer
- **API & Auth (`app/lib/api_service.dart`)**: Persistent `http.Client` lifecycle with explicit timeouts, shared static OAuth2 refresh mutex, JWT `exp` pre-check, single automatic `401` retry without ever sending `refresh_token` as Bearer, and guarded response body streams.
- **Offline Reactivity (`app/lib/offline_state_manager.dart`)**: Central singleton `OfflineStateManager` (`ValueNotifier<bool> isOfflineNotifier`) paired with `OfflineAwareHttpClient` and global `OfflineRibbon` (`app/lib/widgets/offline_ribbon.dart`) mounted via `MaterialApp.builder` (`app/lib/main.dart`).
- **Persistence (`app/lib/storage_service.dart`)**: `SharedPreferences`-backed storage with in-memory JSON cache memoization, non-destructive offline caches (`booked_elsewhere_map`, `occupied_by_others_map`, `floor_occupants_*`, `floor_plan_*`, `floor_workspaces_*`), multi-desk `AutomationRule` storage, and holiday preferences.
- **Unified Automation (`app/lib/services/automation_engine.dart` & `app/lib/background_task.dart`)**: Single shared `AutomationEngine` used by both foreground manual triggers and Android `Workmanager` background workers, with calendar-safe DST date arithmetic (`app/lib/utils/date_helpers.dart`), public holiday skipping (`app/lib/holiday_service.dart`), and multi-desk conflict guards.
- **App Updates (`app/lib/services/app_update_service.dart`, `app/lib/widgets/update_download_dialog.dart`, `app/lib/utils/apk_installer*.dart`)**: GitHub release checker with 15-second timeout, cancellable streaming APK downloader with 20-second timeout, Android install-package permission checks, and platform-conditional stubs for Web/Windows.
- **Security & Crypto (`app/lib/token_crypto.dart`, `app/lib/utils/html_helper*.dart`, `app/lib/utils/windows_webview_helper*.dart`)**: AES-CBC encrypted URL-fragment QR pairing (`#token=...`) for Web without server URL logging, host validation, and isolated Windows WebView2 data directories.

### Modular UI Architecture (v2.0.0)
- **Home Shell (`app/lib/screens/home_screen.dart` & `app/lib/screens/home/widgets/*`)**:
  - `home_dashboard_tab.dart`, `calendar_tab.dart`, `automation_tab.dart`, `stats_tab.dart`, `settings_tab.dart`
  - `delegation_dialogs.dart`, `vacation_dialogs.dart`, `update_available_dialog.dart`
- **Team Map Screen (`app/lib/screens/team_map_screen.dart` & `app/lib/screens/team_map/*`)**:
  - Pure domain helpers & false-positive-free favorite matching in `models/team_map_models.dart`
  - Modular UI components in `widgets/`: `team_map_filter_bar.dart`, `occupants_summary_panel.dart`, `free_desk_booking_sheet.dart`, `desk_automation_sheet.dart`, `favorites_week_modal.dart`, `colleague_management_dialogs.dart`, `team_map_skeleton.dart`
- **2D Map Viewer (`app/lib/widgets/workspace_map_viewer.dart` & `app/lib/widgets/workspace_map/*`)**:
  - `floor_geometry_cache.dart` (memoized floor bounds, room polygons, and desk hit-boxes)
  - `floor_background_painter.dart` (cached static floor outline rendering)
  - `desk_marker_widget.dart` (direct alpha attenuation on colors without GPU `Opacity` `saveLayer`)
  - `map_camera_helper.dart` & `room_occupancy_stats.dart`
  - `mini_map_overlay.dart`, `time_slider_bar.dart`, `occupant_details_sheet.dart`, `colleague_selection_dialog.dart`

### Platform Build & Quality Pipeline
- **Static Analysis (`app/analysis_options.yaml`)**: Strict Dart 3 type system (`strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`), `avoid_void_async: true`, `deprecated_member_use: error`, `cancel_subscriptions: true`, `close_sinks: true`, `avoid_empty_else: true`.
- **WebAssembly (`web --release --wasm`)**: Full `package:web` compatibility with defensive `WebAssembly` guard in `app/web/index.html`.
- **Android Release (`apk --release`)**: R8 code shrinking/obfuscation with tuned ProGuard rules (`app/android/app/proguard-rules.pro`) and stripped unnecessary media permissions.
- **Windows Release (`windows --release`)**: Native desktop executable with WebView2 OIDC login and portable ZIP packaging.
