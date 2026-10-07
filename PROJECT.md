# Project: AutoRoomzio Web QR Pairing & Security Hardening

## Architecture
AutoRoomzio is a Flutter application deployed on Android, Windows, and Web (static GitHub Pages).
- **Core App Root**: Located in `app/`.
- **State & Storage**: `StorageService` (`app/lib/storage_service.dart`) handles persistent settings and credentials.
- **Pairing Mechanism**: Mobile generates a QR code URL pointing to the Web application (`https://Xris65.github.io/AutoRoomzio/`). Web app (`login_screen.dart`) extracts credentials and context to seamlessly authenticate and initialize the user environment without manual setup.
- **Platform Specialization**: Web platform (`kIsWeb`) operates sandboxed without background workers or local notification daemon, requiring complete censorship of dead automation, notification, and update features.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Dependency Setup | Add `encrypt: ^5.0.3` and `flutter_secure_storage: ^11.2.0` to `app/pubspec.yaml` | M1 | ORIGINAL_REQUEST §3 |
| 2 | Token Cryptography | Implement `TokenCryptoService` (AES-256 CBC, random IV, URL-safe Base64) | M1 | ORIGINAL_REQUEST §3 |
| 3 | Secure Token Storage | Migrate `refresh_token` in `StorageService` to `FlutterSecureStorage` with legacy fallback | M1 | ORIGINAL_REQUEST §3 |
| 4 | Web Censorship: Automate Tab | Hide Automate tab on Web (`!kIsWeb`) and clamp navigation indices safely | M2 | ORIGINAL_REQUEST §1 |
| 5 | Web Censorship: Settings Tab | Hide Automate startup option, Automation switch, Updates tile, startup update check on Web | M2 | ORIGINAL_REQUEST §1 |
| 6 | Web Censorship: Notifications | Completely hide Notifications settings card and test notifications button on Web (`!kIsWeb`) | M2 | ORIGINAL_REQUEST §1 & Follow-up |
| 7 | Web Censorship: Calendar Pending | Completely hide "Programmer (En attente)" day action, legend badge, and indicators on Web (`!kIsWeb`) | M2 | ORIGINAL_REQUEST Follow-up 21:11:33Z |
| 8 | QR Context Generation | Include `buildingId`, `floorId`, `roomId`, `workspaceName` in pairing URL in `home_screen.dart` | M3 | ORIGINAL_REQUEST §2 |
| 9 | QR Dark Mode Legibility | Provide `backgroundColor: Colors.white` and white container to `QrImageView` for dark mode legibility | M3 | ORIGINAL_REQUEST Follow-up 21:14:07Z |
| 10 | QR Encrypted Token URL | Encrypt refresh token using `TokenCryptoService` prior to inserting into pairing URL | M3 | ORIGINAL_REQUEST §3 |
| 11 | Web Context Ingestion & Decrypt | Decrypt token, extract context params in `login_screen.dart`, save to `StorageService`, and navigate | M3 | ORIGINAL_REQUEST §2, §3 |
| 12 | Web Storage Clear on Direct Access | In `login_screen.dart`, if no token in URL on Web, wipe all local storage (`StorageService`) before showing QR scan prompt | M3 | ORIGINAL_REQUEST Follow-up 21:17:07Z |
| 13 | Build & Verification | Comprehensive `flutter analyze`, `flutter test`, and `flutter build web` | M4 | ORIGINAL_REQUEST Completion |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Security & Storage Infrastructure | Dependencies (`encrypt`, `flutter_secure_storage`), `TokenCryptoService`, `StorageService` secure migration (and clear helpers) | none | IN_PROGRESS |
| M2 | Web Censorship & UI Filtering | Hide Automate tab, settings (notifications, updates, test button), calendar pending booking on Web | none | PLANNED |
| M3 | Context Sync, QR Dark Mode, Token Decrypt & Web Storage Clear | QR code generation with AES encryption, context query parameters, QR dark mode styling, Web login ingestion & decryption, and Web storage wipe on direct visit | M1, M2 | PLANNED |
| M4 | Compilation, Test & Quality Assurance | Full test suite execution, static analysis (`flutter analyze`), web build verification (`flutter build web`) | M3 | PLANNED |

## Interface Contracts

### TokenCryptoService
- File: `app/lib/token_crypto.dart`
- API:
  ```dart
  class TokenCryptoService {
    static String encryptToken(String plainText);
    static String? decryptToken(String cipherText);
  }
  ```
- Cipher: AES-256 CBC, PKCS7 padding.
- IV: 16 bytes cryptographically secure random bytes prepended to the ciphertext.
- Encoding: RFC 4648 URL-safe Base64 (`base64Url` without unescaped padding or URI-encoded).
- Key: 32-byte shared symmetric constant.
- Error handling: Returns `null` on corrupt/invalid ciphertexts or decryption failure without throwing uncaught exceptions.

### StorageService ↔ QR Synchronization
- Storage Keys & Methods:
  - `site_id`: `saveSiteId(String)` / `getSiteId()` (alias: `saveBuildingId`/`getBuildingId`)
  - `floor_id`: `saveFloorId(String)` / `getFloorId()`
  - `workspace_id`: `saveWorkspaceId(String)` / `getWorkspaceId()` (alias: `saveRoomId`/`getRoomId`)
  - `workspace_name`: `saveWorkspaceName(String)` / `getWorkspaceName()`
  - `refresh_token`: `saveRefreshToken(String)` / `getRefreshToken()` (persisted in `FlutterSecureStorage`)
  - `clearAll()` / `clearAuthToken()`: clears secure storage and preferences completely

### QR Pairing URL Query Parameters
- Base URL: `https://Xris65.github.io/AutoRoomzio/`
- Parameters:
  - `token`: URL-safe AES encrypted refresh token
  - `buildingId`: ID of the building/site
  - `floorId`: ID of the floor
  - `roomId`: ID of the room/workspace
  - `workspaceName`: Name/label of the workspace
- Example:
  `https://Xris65.github.io/AutoRoomzio/?token=<encrypted_blob>&buildingId=12&floorId=3&roomId=45&workspaceName=Bureau+45`

## Code Layout
- `app/pubspec.yaml`: Dependencies
- `app/lib/token_crypto.dart`: Symmetric encryption & decryption logic
- `app/lib/storage_service.dart`: Credential and context storage (secure storage integration)
- `app/lib/screens/home_screen.dart`: Main dashboard, tabs, settings, calendar, QR pairing modal
- `app/lib/screens/login_screen.dart`: Login screen, web URL query param reader and session initialization
- `app/test/token_crypto_test.dart`: Cryptographic unit tests
