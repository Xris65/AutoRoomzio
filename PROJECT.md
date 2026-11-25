# Project: AutoRoomzio v2.0.0 (Modular Architecture, Adaptive M3, Wasm Web & Multi-ABI Android)

## Architecture
AutoRoomzio is a multi-platform Flutter application (Android, Windows, Web/WebAssembly) for desk booking, 2D interactive team floor mapping, and background presence automation.

### Core Services & Network Layer
- **API & Auth (`app/lib/api_service.dart`)**: Persistent `http.Client` lifecycle with explicit timeouts, shared static OAuth2 refresh mutex, JWT `exp` pre-check, single automatic `401` retry without ever sending `refresh_token` as Bearer, and guarded response body streams.
- **Offline Reactivity (`app/lib/offline_state_manager.dart`)**: Central singleton `OfflineStateManager` (`ValueNotifier<bool> isOfflineNotifier`) paired with `OfflineAwareHttpClient` and global `OfflineRibbon` (`app/lib/widgets/offline_ribbon.dart`) mounted via `MaterialApp.builder` (`app/lib/main.dart`).
- **Unified Persistence (`app/lib/storage_service.dart` & `app/lib/services/reservation_store.dart`)**:
  - `ReservationStore` consolidates the 6 legacy reservation keys into a single canonical JSON key (`reservations_v2`) with idempotent migration, 400-day retention pruning, and instant `hereDates` / `elsewhereMap` recalculation on default workspace changes.
  - Backed by `SharedPreferencesAsync` in production/background isolates (`_PrefsStore` / `ReservationPrefsBackend`) with transparent fallback to `SharedPreferences.getInstance()` under `flutter test`, plus non-destructive offline caches (`floor_occupants_*`, `floor_plan_*`, `floor_workspaces_*`), multi-desk `AutomationRule` storage, and holiday preferences.
- **Unified Automation (`app/lib/services/automation_engine.dart` & `app/lib/background_task.dart`)**: Single shared `AutomationEngine` used by both foreground manual triggers and Android `Workmanager` background workers, with calendar-safe DST date arithmetic (`app/lib/utils/date_helpers.dart`), public holiday skipping (`app/lib/holiday_service.dart`), and multi-desk conflict guards.
- **App Updates & Multi-ABI OTA (`app/lib/services/app_update_service.dart`, `app/lib/utils/abi_helper*.dart`, `app/lib/widgets/update_download_dialog.dart`, `app/lib/utils/apk_installer*.dart`)**: GitHub release checker with 15-second timeout, native Android ABI detection (`MainActivity.kt` MethodChannel `com.autoroomzio.app/device` -> `abi_helper_io.dart`) selecting `arm64-v8a`, `armeabi-v7a`, or `universal` fallback APKs, cancellable streaming downloader with 20-second timeout, Android install-package permission checks, and platform stubs for Web/Windows.
- **Security, Crypto & Profile Sync (`app/lib/token_crypto.dart`, `app/lib/services/profile_sync_service.dart`, `app/lib/utils/html_helper*.dart`, `app/lib/utils/windows_webview_helper*.dart`)**:
  - `TokenCryptoService` powered by `cryptography`: authenticated AES-256-GCM (`v2_...`) with HKDF-SHA256 key derivation (`encryptToken` / `decryptToken`), plus legacy AES-256-CBC (`encryptLegacyCbc`) compatibility for the Cloudflare PKCE Worker. Zero `encrypt` / `pointycastle` dependencies.
  - `ProfileSyncService` exports/imports GZip-compressed, AES-256-GCM encrypted `.roomzio` codes (`ROOMZIO2:...`) and `#bundle=...` Web QR pairing URLs (rules, favorites, vacations, scheduled dates, UI/automation settings, and optional auth token).
- **Offline Bundled Fonts (`app/assets/fonts/` & `app/pubspec.yaml`)**: Bundled `Roboto`, `Poppins`, and `FiraCode` TTF font families declared directly in `pubspec.yaml` (`main.dart` font switcher) with zero runtime `google_fonts` CDN dependency.

### Modular UI Architecture (v2.0.0)
- **Adaptive Material 3 Shell & Home (`app/lib/screens/home_screen.dart` & `app/lib/screens/home/widgets/*`)**:
  - `AdaptiveAppShell` (`adaptive_app_shell.dart`): 3 responsive breakpoints — Compact (`< 600px`: M3 bottom `NavigationBar` with `Plan` promoted to top-level), Medium (`600..1099px`: labeled `NavigationRail`), Expanded (`>= 1100px`: `NavigationRail` extended at `>= 1360px` + toggleable Split-View pairing Home/Calendar on the left with a live embedded `TeamMapScreen` on the right via shared `_focusedMapDateNotifier`).
  - `WeeklyCockpitCard` (`weekly_cockpit_card.dart`): Interactive « Ma semaine » cockpit on the Home tab with week navigation (`<` / `>`), booking/automation/vacation/holiday status badges, and cached favorite counts (`⭐ N`).
  - `profile_sync_dialogs.dart`: Encrypted `.roomzio` export/import dialogs in `SettingsTab` preserving the active `refresh_token`.
  - Tabs & dialogs: `home_dashboard_tab.dart`, `calendar_tab.dart`, `automation_tab.dart`, `stats_tab.dart`, `settings_tab.dart`, `delegation_dialogs.dart`, `vacation_dialogs.dart`, `update_available_dialog.dart`.
- **Team Map Screen (`app/lib/screens/team_map_screen.dart` & `app/lib/screens/team_map/*`)**:
  - Embeddable (`isEmbedded: true`, `externalDateNotifier`, `onReservationChanged`) for Desktop/Web Split-View and full-screen `Plan` tab.
  - Pure domain helpers & false-positive-free favorite matching in `models/team_map_models.dart`.
  - Modular UI components in `widgets/`: `team_map_filter_bar.dart`, `occupants_summary_panel.dart`, `free_desk_booking_sheet.dart`, `desk_automation_sheet.dart`, `favorites_week_modal.dart` (multi-week `<` / `>` navigation, week range header, reset to current week, and per-week occupancy cache loading), `colleague_management_dialogs.dart`, `team_map_skeleton.dart`.
- **2D Map Viewer (`app/lib/widgets/workspace_map_viewer.dart` & `app/lib/widgets/workspace_map/*`)**:
  - `floor_geometry_cache.dart` (memoized floor bounds, room polygons, and desk hit-boxes)
  - `floor_background_painter.dart` (cached static floor outline rendering)
  - `desk_marker_widget.dart` (direct alpha attenuation on colors without GPU `Opacity` `saveLayer`)
  - `map_camera_helper.dart` & `room_occupancy_stats.dart`
  - `mini_map_overlay.dart`, `time_slider_bar.dart`, `occupant_details_sheet.dart`, `colleague_selection_dialog.dart`

### Platform Build & Quality Pipeline
- **Static Analysis (`app/analysis_options.yaml`)**: Strict Dart 3 type system (`strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`), `avoid_void_async: true`, `deprecated_member_use: error`, `cancel_subscriptions: true`, `close_sinks: true`, `avoid_empty_else: true`.
- **WebAssembly (`web --release --wasm`)**: Full `package:web` compatibility with defensive `WebAssembly` guard in `app/web/index.html` and zero `dart:html` / `js` dependencies.
- **Android Release (`apk --release --split-per-abi`)**: R8 code shrinking/obfuscation (`app/android/app/proguard-rules.pro`), stripped unnecessary media permissions, and interchangeable split APKs (`arm64-v8a`, `armeabi-v7a`, `universal`) sharing `versionCode = 20000` via `force-version-code-ignoring-abi=true` in `app/android/gradle.properties`.
- **Windows Release (`windows --release`)**: Native desktop executable with WebView2 OIDC login and portable ZIP packaging.
