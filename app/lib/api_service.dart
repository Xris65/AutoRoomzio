import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models/booking_result.dart';
import 'models/colleague.dart';
import 'models/desk_occupant.dart';
import 'offline_state_manager.dart';
import 'storage_service.dart';
import 'token_crypto.dart';
import 'utils/date_helpers.dart';
import 'utils/delegation_display_helper.dart';
import 'utils/workspace_helpers.dart';

class RoomzApiService {
  final StorageService _storage;
  http.Client _client;
  final bool _ownsClient;
  bool _isClosed = false;

  RoomzApiService({StorageService? storage, http.Client? client})
      : _storage = storage ?? StorageService(),
        _ownsClient = client == null,
        _client = client != null
            ? (client is OfflineAwareHttpClient
                ? client
                : OfflineAwareHttpClient(client))
            : OfflineAwareHttpClient();

  http.Client get _httpClient {
    if (_isClosed && _ownsClient) {
      _client = OfflineAwareHttpClient();
      _isClosed = false;
    }
    return _client;
  }

  /// Closes the underlying HTTP client only if owned by this [RoomzApiService] instance.
  /// Subsequent calls safely recreate a fresh [OfflineAwareHttpClient] if needed.
  void close() {
    if (_ownsClient && !_isClosed) {
      _isClosed = true;
      _client.close();
    }
  }

  static String get _loginUrl => kIsWeb
      ? "https://roomzioproxy.krisdhim2.workers.dev/https://login.roomz.io/connect/token"
      : "https://login.roomz.io/connect/token";
  static String get _apiBase => kIsWeb
      ? "https://roomzioproxy.krisdhim2.workers.dev/https://api.my.roomz.io"
      : "https://api.my.roomz.io";
  static const String _clientId = "my-roomz";
  static const String _scope =
      "openid profile email identityServer-api my-roomz-api offline_access";

  /// Callback invoked when a session expires.
  static VoidCallback? onSessionExpired;

  /// Shared static OAuth rotation mutex across all [RoomzApiService] instances
  /// (`HomeScreen`, `TeamMapScreen`, `AutomationEngine`) to prevent concurrent
  /// `400 invalid_grant` token rotation collisions.
  static Future<String?>? _inFlightTokenRefresh;

  @visibleForTesting
  static void resetTokenRefreshStateForTesting() {
    _inFlightTokenRefresh = null;
  }

  String? _cachedAccessToken;
  int _silent401RetryDepth = 0;

  /// Central handler when an unrecoverable token refresh failure is encountered.
  Future<void> handleSessionExpired() async {
    _cachedAccessToken = null;
    try {
      await _storage.clearTokens();
    } catch (_) {}
    onSessionExpired?.call();
  }

  void _checkAuthResponse(http.Response response) {
    if (response.statusCode == 401) {
      _cachedAccessToken = null;
    }
  }

  /// Checks whether a JWT [token] carries a numeric `exp` claim that is already
  /// expired or expiring within [leewaySeconds] (default 60s).
  /// Non-JWT or `exp`-less tokens return `false`.
  static bool isJwtExpiredOrExpiringSoon(
    String token, {
    int leewaySeconds = 60,
    DateTime? now,
  }) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return false;
      final normalized = base64Url.normalize(parts[1]);
      final payloadStr = utf8.decode(base64Url.decode(normalized));
      final Object? decoded = jsonDecode(payloadStr);
      if (decoded is Map<Object?, Object?>) {
        final Object? expRaw = decoded['exp'];
        final int? expSeconds = expRaw is num
            ? expRaw.toInt()
            : (expRaw is String ? int.tryParse(expRaw) : null);
        if (expSeconds != null) {
          final int nowSeconds =
              (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
          return nowSeconds >= (expSeconds - leewaySeconds);
        }
      }
    } catch (_) {}
    return false;
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map<Object?, Object?>) {
      return value.map<String, dynamic>(
        (k, v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    }
    return null;
  }

  static List<Map<String, dynamic>> _extractMapList(Object? value) {
    if (value is List<Object?>) {
      return value
          .whereType<Map<Object?, Object?>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<String?> _refreshFor401Retry() async {
    _silent401RetryDepth++;
    try {
      return await refreshMyToken(force: true);
    } finally {
      _silent401RetryDepth--;
    }
  }

  /// Executes an authenticated request and, on HTTP 401, invalidates the stale
  /// access token, refreshes once via [refreshMyToken], and replays the request once.
  /// Never falls back to sending `refresh_token` in the `Authorization: Bearer` header.
  Future<({http.Response response, String token})> _sendWithAuthRetry(
    String initialToken,
    Future<http.Response> Function(String activeToken) sendRequest,
  ) async {
    String activeToken = initialToken;
    if (activeToken.isEmpty) {
      final refreshed = await refreshMyToken();
      if (refreshed != null && refreshed.isNotEmpty) {
        activeToken = refreshed;
      }
    }

    http.Response response = await sendRequest(activeToken);
    if (response.statusCode == 401) {
      _cachedAccessToken = null;
      final refreshed = await _refreshFor401Retry();
      if (refreshed != null && refreshed.isNotEmpty) {
        activeToken = refreshed;
        response = await sendRequest(activeToken);
      }
    }
    _checkAuthResponse(response);
    return (response: response, token: activeToken);
  }

  // ── Authentication ──────────────────────────────────────────────────────

  static const String defaultAuthWorkerUrl =
      "https://roomzauth.krisdhim2.workers.dev";

  static bool _isValidWorkerUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    if (scheme == 'http' && (host == 'localhost' || host == '127.0.0.1')) {
      return true;
    }
    return false;
  }

  /// Initial login with email + password via Cloudflare PKCE Worker (AES-256 encrypted payload).
  /// Validates that [workerUrl] (when provided) is a valid `https` URL (or `http` localhost for tests).
  Future<String?> login(
    String email,
    String password, {
    String? workerUrl,
  }) async {
    final targetUrl = (workerUrl != null && workerUrl.trim().isNotEmpty)
        ? workerUrl.trim()
        : defaultAuthWorkerUrl;

    if (!_isValidWorkerUrl(targetUrl)) {
      throw ArgumentError.value(
        workerUrl,
        'workerUrl',
        'workerUrl must be a valid HTTPS URL (or HTTP on localhost / 127.0.0.1 for testing).',
      );
    }

    final rawJson = jsonEncode(<String, Object>{
      "email": email.trim(),
      "password": password,
      "ts": DateTime.now().millisecondsSinceEpoch,
    });
    final encryptedPayload = TokenCryptoService.encryptToken(rawJson);

    final response = await _httpClient.post(
      Uri.parse(targetUrl),
      headers: const <String, String>{"Content-Type": "application/json"},
      body: jsonEncode(<String, String>{
        "payload": encryptedPayload,
      }),
    );

    if (response.statusCode == 200) {
      final Object? decoded = jsonDecode(response.body);
      final data = _asStringMap(decoded);
      if (data != null) {
        final rawRefresh = data['refresh_token']?.toString();
        if (rawRefresh != null && rawRefresh.isNotEmpty) {
          await _storage.saveRefreshToken(rawRefresh);
        }
        final token = data['access_token']?.toString();
        _cachedAccessToken = token;
        return token;
      }
    }
    debugPrint("❌ Login failed ${response.statusCode}");
    return null;
  }

  /// Refresh access token using stored refresh token with shared static mutex and JWT `exp` check.
  Future<String?> refreshMyToken({bool force = false}) async {
    if (!force &&
        _cachedAccessToken != null &&
        _cachedAccessToken!.isNotEmpty) {
      if (!isJwtExpiredOrExpiringSoon(_cachedAccessToken!)) {
        return _cachedAccessToken;
      }
      _cachedAccessToken = null;
    } else if (force) {
      _cachedAccessToken = null;
    }

    final existingRefresh = _inFlightTokenRefresh;
    if (existingRefresh != null) {
      final sharedToken = await existingRefresh;
      if (sharedToken != null && sharedToken.isNotEmpty) {
        _cachedAccessToken = sharedToken;
      }
      return sharedToken;
    }

    final Future<String?> refreshFuture = _performRefreshMyToken();
    _inFlightTokenRefresh = refreshFuture;
    try {
      final refreshedToken = await refreshFuture;
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        _cachedAccessToken = refreshedToken;
      }
      return refreshedToken;
    } finally {
      if (identical(_inFlightTokenRefresh, refreshFuture)) {
        _inFlightTokenRefresh = null;
      }
    }
  }

  Future<String?> _performRefreshMyToken({
    bool allowRetryOnChangedToken = true,
  }) async {
    try {
      final oldRefreshToken = await _storage.getRefreshToken();
      if (oldRefreshToken == null || oldRefreshToken.isEmpty) return null;

      final response = await _httpClient.post(
        Uri.parse(_loginUrl),
        body: <String, String>{
          "grant_type": "refresh_token",
          "refresh_token": oldRefreshToken,
          "client_id": _clientId,
          "scope": _scope,
        },
      );

      if (response.statusCode == 200) {
        final Object? decoded = jsonDecode(response.body);
        final data = _asStringMap(decoded);
        if (data != null) {
          final newRefreshToken = data['refresh_token']?.toString();
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await _storage.saveRefreshToken(newRefreshToken);
          }
          final newAccessToken = data['access_token']?.toString();
          _cachedAccessToken = newAccessToken;
          return newAccessToken;
        }
      } else {
        debugPrint("❌ Token refresh failed ${response.statusCode}");
        if (response.statusCode == 401 ||
            response.statusCode == 400 ||
            response.statusCode == 403) {
          // Guard against false concurrent `invalid_grant`:
          // 1) Check if a valid non-expired access token was just cached concurrently.
          final currentAccess = _cachedAccessToken;
          if (currentAccess != null &&
              currentAccess.isNotEmpty &&
              !isJwtExpiredOrExpiringSoon(currentAccess)) {
            return currentAccess;
          }

          // 2) Check if stored refresh_token changed while this request was in flight.
          final currentRefresh = await _storage.getRefreshToken();
          if (currentRefresh != null &&
              currentRefresh.isNotEmpty &&
              currentRefresh != oldRefreshToken) {
            if (allowRetryOnChangedToken) {
              return await _performRefreshMyToken(
                allowRetryOnChangedToken: false,
              );
            }
            return null;
          }

          _cachedAccessToken = null;
          final bodyLower = response.body.toLowerCase();
          final isExplicitInvalidGrant = bodyLower.contains('invalid_grant') ||
              bodyLower.contains('invalid_token');
          if (_silent401RetryDepth == 0 || isExplicitInvalidGrant) {
            await handleSessionExpired();
          }
        }
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("❌ Exception in refreshMyToken: $e");
    }
    return null;
  }

  // ── Discovery ────────────────────────────────────────────────────────────

  /// Fetch the list of buildings (sites).
  Future<List<Map<String, dynamic>>> getSites(String token) async {
    final result = await _sendWithAuthRetry(
      token,
      (activeToken) => _httpClient.get(
        Uri.parse("$_apiBase/buildings"),
        headers: _authHeaders(activeToken)
          ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
      ),
    );
    final response = result.response;
    if (response.statusCode == 200) {
      final Object? data = jsonDecode(response.body);
      if (data is List<Object?>) {
        return _extractMapList(data);
      } else if (data is Map<Object?, Object?>) {
        return _extractMapList(data['data']);
      }
    }
    debugPrint("❌ getSites ${response.statusCode}");
    return <Map<String, dynamic>>[];
  }

  /// Fetch floors for a given building.
  Future<List<Map<String, dynamic>>> getFloors(
    String token,
    String siteId,
  ) async {
    final result = await _sendWithAuthRetry(
      token,
      (activeToken) => _httpClient.get(
        Uri.parse("$_apiBase/buildings/$siteId/floors"),
        headers: _authHeaders(activeToken)
          ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
      ),
    );
    final response = result.response;
    if (response.statusCode == 200) {
      final Object? data = jsonDecode(response.body);
      if (data is List<Object?>) {
        return _extractMapList(data);
      } else if (data is Map<Object?, Object?>) {
        return _extractMapList(data['data']);
      }
    }
    debugPrint("❌ getFloors ${response.statusCode}");
    return <Map<String, dynamic>>[];
  }

  // Debug variable to store API keys
  static String lastApiKeys = "";

  /// Fetch ALL workspaces on a given floor (unfiltered).
  Future<List<Map<String, dynamic>>> getAllWorkspaces(
    String token,
    String siteId,
    String floorId,
  ) async {
    final List<Map<String, dynamic>> allWorkspaces = <Map<String, dynamic>>[];
    int offset = 0;
    const int limit = 100;
    const int maxPages = 20;
    String currentToken = token;

    try {
      for (int page = 0; page < maxPages; page++) {
        final url =
            "$_apiBase/floors/$floorId/workspaces/all?length=$limit&offset=$offset";
        final result = await _sendWithAuthRetry(
          currentToken,
          (activeToken) => _httpClient.get(
            Uri.parse(url),
            headers: _authHeaders(activeToken)
              ..addAll(
                const <String, String>{"roomz-source-type": "MyRoomzWeb"},
              ),
          ),
        );
        currentToken = result.token;
        final response = result.response;

        if (response.statusCode == 200) {
          final Object? data = jsonDecode(response.body);
          lastApiKeys = "GET 200 /workspaces/all";

          List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
          if (data is List<Object?>) {
            list = _extractMapList(data);
          } else if (data is Map<Object?, Object?>) {
            final Object? raw = data['data'] ??
                data['workspaces'] ??
                data['items'] ??
                data['results'] ??
                data['value'];
            list = _extractMapList(raw);
          }

          allWorkspaces.addAll(list);

          if (list.length < limit) break;
          offset += limit;
        } else {
          debugPrint("❌ GET /workspaces/all failed: ${response.statusCode}");
          break;
        }
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("❌ Exception fetching /workspaces/all: $e");
    }

    if (allWorkspaces.isNotEmpty) {
      for (final ws in allWorkspaces) {
        ws['id'] = ws['workspaceId'] ?? ws['id'];
        ws['name'] = ws['name'] ??
            ws['title'] ??
            ws['label'] ??
            ws['workspaceName'] ??
            ws['id'];
        ws['type'] = ws['workspaceType'] ?? ws['type'] ?? "Desk";
      }
      return allWorkspaces;
    }

    lastApiKeys = "ERR: 404 everywhere";
    return <Map<String, dynamic>>[];
  }

  /// Fetch only bookable (desk) workspaces — filters from getAllWorkspaces.
  Future<List<Map<String, dynamic>>> getWorkspaces(
    String token,
    String siteId,
    String floorId,
  ) async {
    final all = await getAllWorkspaces(token, siteId, floorId);
    return all.where(isBookableWorkspace).toList();
  }

  /// Fetch floor plan GeoJSON data for 2D map.
  Future<List<Map<String, dynamic>>> getFloorPlanData(
    String token,
    String siteId,
    String floorId,
  ) async {
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/buildings/$siteId/floors/$floorId/data"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      final response = result.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        if (data is Map<Object?, Object?> && data['features'] is List<Object?>) {
          return _extractMapList(data['features']);
        } else if (data is List<Object?>) {
          return _extractMapList(data);
        }
      }
      debugPrint("❌ getFloorPlanData ${response.statusCode}");
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("❌ Exception getFloorPlanData: $e");
    }
    return <Map<String, dynamic>>[];
  }

  // ── Reservations ─────────────────────────────────────────────────────────

  Future<bool> reserveWorkspace(
    String date,
    String token,
    String workspaceId,
  ) async {
    final result = await _sendWithAuthRetry(
      token,
      (activeToken) => _httpClient.post(
        Uri.parse("$_apiBase/bookings"),
        headers: <String, String>{
          ..._authHeaders(activeToken),
          "roomz-source-type": "1",
          "x-roomz-source-type": "1",
        },
        body: jsonEncode(<String, String>{
          "workspaceId": workspaceId,
          "localDate": date,
          "timeSlot": "FullDay",
        }),
      ),
    );
    final response = result.response;
    if (response.statusCode == 200 || response.statusCode == 201) {
      debugPrint("✅ Booked $date");
      return true;
    } else if (response.statusCode == 409) {
      debugPrint("⚠️ Conflict (Already booked by someone else) $date");
      return false;
    } else if (response.statusCode == 400) {
      debugPrint(
        "⚠️ Not available (already booked elsewhere or unavailable) $date",
      );
      return false;
    } else {
      debugPrint("❌ reserveWorkspace ${response.statusCode} $date");
      return false;
    }
  }

  /// Fetch the user's own bookings.
  Future<
      ({
        Set<String> here,
        Map<String, String> elsewhere,
        Map<String, String> delegated,
        String? myUserId,
        Map<String, Map<String, String>> allReservations,
      })> getMyReservations(String token, String workspaceId) async {
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      final response = result.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        final List<Map<String, dynamic>> bookings = data is List<Object?>
            ? _extractMapList(data)
            : (data is Map<Object?, Object?>
                ? _extractMapList(data['bookings'] ?? data['data'])
                : <Map<String, dynamic>>[]);

        final Set<String> here = <String>{};
        final Map<String, String> elsewhere = <String, String>{};
        final Map<String, String> delegated = <String, String>{};
        final Map<String, Map<String, String>> allReservations =
            <String, Map<String, String>>{};

        String? foundUserId;
        for (final b in bookings) {
          final creatorMap = _asStringMap(b['creator']);
          if (foundUserId == null &&
              creatorMap != null &&
              creatorMap['id'] != null) {
            foundUserId = creatorMap['id']?.toString();
          }
          if (b['type'] != 'Reserved') continue;
          final dateStr = b['eventDate']?.toString().split('T').first;
          if (dateStr == null || dateStr.isEmpty) continue;

          bool isDelegated = false;
          final Object? creatorRaw = b['creator'] ?? b['bookedBy'];
          final creatorObj = _asStringMap(creatorRaw);
          final organizerObj = _asStringMap(b['organizer']);
          final Object? bookedForRaw = b['bookedFor'] ?? b['user'];
          final bookedForObj = _asStringMap(bookedForRaw);

          String targetName = "Quelqu'un";
          String? creatorDisplayName;
          if (creatorObj != null) {
            creatorDisplayName = creatorObj['name']?.toString() ??
                creatorObj['displayName']?.toString();
          } else if (creatorRaw is String) {
            creatorDisplayName = creatorRaw;
          }

          if (bookedForRaw != null) {
            isDelegated = true;
            if (bookedForObj != null) {
              targetName = bookedForObj['name']?.toString() ??
                  bookedForObj['displayName']?.toString() ??
                  targetName;
            } else if (bookedForRaw is String) {
              targetName = bookedForRaw;
            }
          } else if (creatorObj != null && organizerObj != null) {
            final creatorId = creatorObj['id']?.toString();
            final orgId = organizerObj['id']?.toString();
            final creatorEmail = creatorObj['email']?.toString().toLowerCase();
            final orgEmail = organizerObj['email']?.toString().toLowerCase();
            final creatorName = creatorObj['name']?.toString();
            final orgName = organizerObj['name']?.toString() ??
                organizerObj['displayName']?.toString();

            if (creatorId != null && orgId != null && creatorId != orgId) {
              isDelegated = true;
              targetName = orgName ?? targetName;
            } else if (creatorEmail != null &&
                orgEmail != null &&
                creatorEmail != orgEmail) {
              isDelegated = true;
              targetName =
                  orgName ?? organizerObj['email']?.toString() ?? targetName;
            } else if (creatorName != null &&
                orgName != null &&
                creatorName != orgName) {
              isDelegated = true;
              targetName = orgName;
            }
          }

          final wsId = b['workspaceId']?.toString() ?? '';
          final wsNested = _asStringMap(b['workspace']);
          final rawWsName = b['workspaceName']?.toString() ??
              b['workspaceTitle']?.toString() ??
              wsNested?['name']?.toString();
          final wsName = (rawWsName != null && rawWsName.isNotEmpty)
              ? rawWsName
              : (wsId.isNotEmpty &&
                      wsId.toLowerCase() == workspaceId.toLowerCase()
                  ? "Mon bureau"
                  : "Ailleurs");

          if (isDelegated) {
            final location = wsName;
            final rawEventId = b['eventId']?.toString() ?? '';
            final evId = rawEventId.contains('/')
                ? rawEventId.split('/')[1]
                : rawEventId;
            final orgId = organizerObj?['id']?.toString() ??
                organizerObj?['email']?.toString() ??
                '';
            final cName = creatorDisplayName ?? '';
            final entryVal = '$wsId|$targetName|$location|$evId|$orgId|$cName';
            if (!delegated.containsKey(dateStr) ||
                wsId.toLowerCase() == workspaceId.toLowerCase()) {
              delegated[dateStr] = entryVal;
            }
          } else {
            allReservations[dateStr] = <String, String>{
              'workspaceId': wsId,
              'workspaceName': wsName,
            };
            if (wsId.isNotEmpty &&
                wsId.toLowerCase() == workspaceId.toLowerCase()) {
              here.add(dateStr);
            } else {
              elsewhere[dateStr] = wsName;
            }
          }
        }
        return (
          here: here,
          elsewhere: elsewhere,
          delegated: delegated,
          myUserId: foundUserId,
          allReservations: allReservations,
        );
      }
      debugPrint("❌ getMyReservations ${response.statusCode}");
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("❌ Exception getMyReservations: $e");
    }
    return (
      here: <String>{},
      elsewhere: <String, String>{},
      delegated: <String, String>{},
      myUserId: null,
      allReservations: <String, Map<String, String>>{},
    );
  }

  /// Finds a booking on a specific date (any workspace) and cancels it.
  Future<bool> cancelBookingByDate(
    String token,
    String dateStr, {
    String? workspaceId,
    String? forUserId,
    String? eventId,
  }) async {
    try {
      final reqResult = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      final currentToken = reqResult.token;
      final response = reqResult.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        final List<Map<String, dynamic>> bookings = data is List<Object?>
            ? _extractMapList(data)
            : (data is Map<Object?, Object?>
                ? _extractMapList(data['bookings'] ?? data['data'])
                : <Map<String, dynamic>>[]);

        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          if (bDate != dateStr) continue;

          final wsNested = _asStringMap(b['workspace']);
          final bWsId = b['workspaceId']?.toString() ??
              wsNested?['id']?.toString() ??
              wsNested?['workspaceId']?.toString();

          if (workspaceId != null && workspaceId.isNotEmpty) {
            if (bWsId != null &&
                bWsId.toLowerCase() != workspaceId.toLowerCase()) {
              continue;
            }
          }

          final bCreator = _asStringMap(b['creator']);
          final bOrganizer = _asStringMap(b['organizer']);
          final Object? bBookedFor = b['bookedFor'];
          bool isDelegatedBooking = false;
          if (bBookedFor != null) {
            isDelegatedBooking = true;
          } else if (bCreator != null && bOrganizer != null) {
            if (bCreator['id'] != null && bOrganizer['id'] != null) {
              isDelegatedBooking = bCreator['id'] != bOrganizer['id'];
            } else if (bCreator['email'] != null &&
                bOrganizer['email'] != null) {
              isDelegatedBooking = bCreator['email'] != bOrganizer['email'];
            } else if (bCreator['name'] != null && bOrganizer['name'] != null) {
              isDelegatedBooking = bCreator['name'] != bOrganizer['name'];
            }
          }

          if (forUserId != null && forUserId.isNotEmpty) {
            if (!isDelegatedBooking) continue;
            final orgId = bOrganizer?['id']?.toString();
            final orgEmail = bOrganizer?['email']?.toString() ??
                bOrganizer?['mail']?.toString();
            final orgName = bOrganizer?['name']?.toString() ??
                bOrganizer?['displayName']?.toString();
            final targetUserId = forUserId.toLowerCase();
            final matchesDelegate =
                (orgId != null && orgId.toLowerCase() == targetUserId) ||
                    (orgEmail != null &&
                        orgEmail.toLowerCase() == targetUserId) ||
                    (orgName != null && orgName.toLowerCase() == targetUserId);
            if ((orgId != null || orgEmail != null || orgName != null) &&
                !matchesDelegate) {
              continue;
            }
          } else if (workspaceId == null || workspaceId.isEmpty) {
            if (isDelegatedBooking) continue;
          }

          final targetWsId = bWsId ?? workspaceId;
          final bEventId =
              eventId ?? b['eventId']?.toString() ?? b['id']?.toString();
          if (targetWsId != null && targetWsId.isNotEmpty) {
            return await cancelReservation(
              dateStr,
              currentToken,
              targetWsId,
              eventId: bEventId,
              forUserId: forUserId,
            );
          }
        }
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("❌ Exception cancelBookingByDate: $e");
    }
    return false;
  }

  /// Fetch dates where the workspace is booked by someone ELSE.
  /// Paginates by `length=100` (`offset = 0, 100, 200...` up to 10 pages = 1000 desks)
  /// to support large floors with >100 desks.
  Future<
      ({
        Map<String, String> occupiedByOthers,
        Map<String, String> delegatedBookings,
        Set<String> delegatedHere,
        Set<String> delegatedElsewhere,
      })> getWorkspaceOccupancy(
    String token,
    String workspaceId,
    String floorId,
    List<String> dates,
    String? myUserId,
    Map<String, String> elsewhereMap,
  ) async {
    final Map<String, String> occupied = <String, String>{};
    final Map<String, String> delegated = <String, String>{};
    final Set<String> delegatedHere = <String>{};
    final Set<String> delegatedElsewhere = <String>{};

    const int pageSize = 100;
    const int maxPages = 10;

    // Execute in parallel chunks of 15 dates to avoid overwhelming the server
    for (int i = 0; i < dates.length; i += 15) {
      final chunk = dates.skip(i).take(15);
      await Future.wait(
        chunk.map((String date) async {
          try {
            String currentToken = token;
            final payload = <String, Object>{
              "availableWorkspaceOnly": false,
              "date": date,
              "timeSlot": "FullDay",
              "tagIds": const <String>[],
              "workspaceType": "Desk",
            };

            for (int page = 0; page < maxPages; page++) {
              final int offset = page * pageSize;
              final reqResult = await _sendWithAuthRetry(
                currentToken,
                (activeToken) => _httpClient.post(
                  Uri.parse(
                    "$_apiBase/floors/$floorId/workspaces/calendars?length=$pageSize&offset=$offset",
                  ),
                  headers: _authHeaders(activeToken)
                    ..addAll(const <String, String>{
                      "roomz-source-type": "MyRoomzWeb",
                      "Content-Type": "application/json",
                    }),
                  body: jsonEncode(payload),
                ),
              );
              currentToken = reqResult.token;
              final response = reqResult.response;
              if (response.statusCode != 200) break;

              final Object? data = jsonDecode(response.body);
              final List<Map<String, dynamic>> items = data is List<Object?>
                  ? _extractMapList(data)
                  : (data is Map<Object?, Object?>
                      ? _extractMapList(
                          data['data'] ?? data['items'] ?? data['workspaces'],
                        )
                      : <Map<String, dynamic>>[]);

              if (items.isEmpty) break;

              for (final item in items) {
                final isMyDesk =
                    item['workspaceId'] == workspaceId || item['id'] == workspaceId;

                if (item['status'] == 'Reserved') {
                  final bookedTimeSlot = _asStringMap(item['bookedTimeSlot']);
                  if (bookedTimeSlot != null) {
                    final Object? creatorRaw =
                        bookedTimeSlot['creator'] ?? bookedTimeSlot['bookedBy'];
                    final creatorObj = _asStringMap(creatorRaw);
                    final Object? organizerRaw = bookedTimeSlot['organizer'];
                    final organizerObj = _asStringMap(organizerRaw);
                    final Object? bookedForRaw = bookedTimeSlot['bookedFor'] ??
                        bookedTimeSlot['user'] ??
                        bookedTimeSlot['owner'];
                    final bookedForObj = _asStringMap(bookedForRaw);

                    bool isDelegated = false;
                    String delegateName = "Quelqu'un";

                    final creatorId = creatorObj?['id']?.toString() ??
                        creatorObj?['userId']?.toString();
                    final creatorName = creatorObj?['name']?.toString() ??
                        creatorObj?['displayName']?.toString() ??
                        (creatorRaw is String ? creatorRaw : null);
                    final creatorEmail =
                        creatorObj?['email']?.toString().toLowerCase();

                    final organizerId = organizerObj?['id']?.toString() ??
                        organizerObj?['userId']?.toString();
                    final organizerName = organizerObj?['name']?.toString() ??
                        organizerObj?['displayName']?.toString() ??
                        (organizerRaw is String ? organizerRaw : null) ??
                        organizerObj?['email']?.toString();
                    final organizerEmail =
                        organizerObj?['email']?.toString().toLowerCase();

                    final bool isCreatorMe = myUserId != null &&
                        creatorId != null &&
                        creatorId == myUserId;

                    if (isCreatorMe) {
                      if (bookedForRaw != null) {
                        isDelegated = true;
                        final targetName = bookedForObj != null
                            ? (bookedForObj['name']?.toString() ??
                                bookedForObj['displayName']?.toString() ??
                                'Collègue')
                            : bookedForRaw.toString();
                        final wsId = item['workspaceId']?.toString() ??
                            item['id']?.toString() ??
                            workspaceId;
                        final location = isMyDesk
                            ? 'Mon bureau'
                            : (elsewhereMap[date] ??
                                item['workspaceName']?.toString() ??
                                item['name']?.toString() ??
                                'Autre bureau');
                        final evId = bookedTimeSlot['eventId']?.toString() ??
                            bookedTimeSlot['id']?.toString() ??
                            '';
                        final orgId = bookedForObj?['id']?.toString() ?? "";
                        final cName = creatorName ?? 'vous';
                        delegateName =
                            "$wsId|$targetName|$location|$evId|$orgId|$cName";
                      } else if (organizerRaw != null) {
                        final bool diff =
                            (organizerId != null && creatorId != organizerId) ||
                                (organizerEmail != null &&
                                    creatorEmail != null &&
                                    organizerEmail != creatorEmail) ||
                                (organizerName != null &&
                                    creatorName != null &&
                                    organizerName.toLowerCase() !=
                                        creatorName.toLowerCase());
                        if (diff) {
                          isDelegated = true;
                          final wsId = item['workspaceId']?.toString() ??
                              item['id']?.toString() ??
                              workspaceId;
                          final location = isMyDesk
                              ? 'Mon bureau'
                              : (elsewhereMap[date] ??
                                  item['workspaceName']?.toString() ??
                                  item['name']?.toString() ??
                                  'Autre bureau');
                          final evId = bookedTimeSlot['eventId']?.toString() ??
                              bookedTimeSlot['id']?.toString() ??
                              '';
                          final orgId = organizerId ?? organizerEmail ?? "";
                          final cName = creatorName ?? 'vous';
                          delegateName =
                              "$wsId|${organizerName ?? 'Quelqu\'un'}|$location|$evId|$orgId|$cName";
                        }
                      }
                    }

                    if (isDelegated) {
                      if (!delegated.containsKey(date) || isMyDesk) {
                        delegated[date] = delegateName;
                      }
                      if (isMyDesk) {
                        delegatedHere.add(date);
                      } else {
                        delegatedElsewhere.add(date);
                      }
                    } else if (isMyDesk) {
                      if (creatorRaw == null || creatorId != myUserId) {
                        final occupantLabel =
                            DelegationDisplayHelper.extractReservationOccupant(
                          bookedTimeSlot,
                          myUserId: myUserId,
                        );
                        occupied[date] = occupantLabel;
                      }
                    }
                  }
                }
              }

              if (items.length < pageSize) break;
            }
          } catch (_) {}
        }),
      );
    }

    return (
      occupiedByOthers: occupied,
      delegatedBookings: delegated,
      delegatedHere: delegatedHere,
      delegatedElsewhere: delegatedElsewhere,
    );
  }

  Future<bool> cancelReservation(
    String date,
    String token,
    String workspaceId, {
    String? eventId,
    String? forUserId,
  }) async {
    String effectiveDate = date;
    String effectiveWorkspaceId = workspaceId;
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(date) && dateRegex.hasMatch(workspaceId)) {
      effectiveDate = workspaceId;
      effectiveWorkspaceId = date;
    }

    String currentToken = token;
    String? foundBookingId;

    if (eventId != null && eventId.isNotEmpty) {
      final cleanEventId =
          eventId.contains('/') ? eventId.split('/')[1] : eventId;
      debugPrint("⚠️ Try 0: DELETE /bookings/$cleanEventId");
      final delResult = await _sendWithAuthRetry(
        currentToken,
        (activeToken) => _httpClient.delete(
          Uri.parse("$_apiBase/bookings/$cleanEventId"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      currentToken = delResult.token;
      final delResp = delResult.response;
      if (delResp.statusCode == 200 || delResp.statusCode == 204) {
        debugPrint("✅ Cancelled by eventId: $cleanEventId");
        return true;
      }
      debugPrint("❌ Try 0 FAILED: ${delResp.statusCode}");
      foundBookingId = cleanEventId;
    }

    try {
      final getResult = await _sendWithAuthRetry(
        currentToken,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      currentToken = getResult.token;
      final getResp = getResult.response;
      if (getResp.statusCode == 200) {
        final Object? data = jsonDecode(getResp.body);
        final List<Map<String, dynamic>> bookings = data is List<Object?>
            ? _extractMapList(data)
            : (data is Map<Object?, Object?>
                ? _extractMapList(data['bookings'] ?? data['data'])
                : <Map<String, dynamic>>[]);

        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          if (bDate != effectiveDate) continue;

          final wsNested = _asStringMap(b['workspace']);
          final bWsId = b['workspaceId']?.toString() ??
              wsNested?['id']?.toString() ??
              wsNested?['workspaceId']?.toString() ??
              b['id']?.toString();

          if (effectiveWorkspaceId.isNotEmpty &&
              bWsId != null &&
              bWsId.toLowerCase() != effectiveWorkspaceId.toLowerCase()) {
            continue;
          }

          final bCreator = _asStringMap(b['creator']);
          final bOrganizer = _asStringMap(b['organizer']);
          final Object? bBookedFor = b['bookedFor'];
          final bBookedForMap = _asStringMap(bBookedFor);
          bool isDelegatedBooking = false;
          if (bBookedFor != null) {
            isDelegatedBooking = true;
          } else if (bCreator != null && bOrganizer != null) {
            if (bCreator['id'] != null && bOrganizer['id'] != null) {
              isDelegatedBooking = bCreator['id'] != bOrganizer['id'];
            } else if (bCreator['email'] != null &&
                bOrganizer['email'] != null) {
              isDelegatedBooking = bCreator['email'] != bOrganizer['email'];
            } else if (bCreator['name'] != null && bOrganizer['name'] != null) {
              isDelegatedBooking = bCreator['name'] != bOrganizer['name'];
            }
          }

          if (forUserId != null && forUserId.isNotEmpty) {
            if (!isDelegatedBooking) continue;
            final orgId = bOrganizer?['id']?.toString();
            final orgEmail = bOrganizer?['email']?.toString() ??
                bOrganizer?['mail']?.toString();
            final orgName = bOrganizer?['name']?.toString() ??
                bOrganizer?['displayName']?.toString();
            final bookedForId = bBookedForMap?['id']?.toString();
            final bookedForEmail = bBookedForMap?['email']?.toString() ??
                bBookedForMap?['mail']?.toString();
            final bookedForName = bBookedForMap?['name']?.toString() ??
                (bBookedFor is String ? bBookedFor : null);

            final targetUserId = forUserId.toLowerCase();
            final matchesDelegate =
                (orgId != null && orgId.toLowerCase() == targetUserId) ||
                    (orgEmail != null &&
                        orgEmail.toLowerCase() == targetUserId) ||
                    (orgName != null && orgName.toLowerCase() == targetUserId) ||
                    (bookedForId != null &&
                        bookedForId.toLowerCase() == targetUserId) ||
                    (bookedForEmail != null &&
                        bookedForEmail.toLowerCase() == targetUserId) ||
                    (bookedForName != null &&
                        bookedForName.toLowerCase() == targetUserId);

            if ((orgId != null ||
                    orgEmail != null ||
                    orgName != null ||
                    bookedForId != null ||
                    bookedForEmail != null) &&
                !matchesDelegate) {
              continue;
            }
          } else {
            if (isDelegatedBooking) continue;
          }

          foundBookingId = b['eventId']?.toString() ??
              b['id']?.toString() ??
              b['bookingId']?.toString();
          if (foundBookingId != null && foundBookingId.contains('/')) {
            foundBookingId = foundBookingId.split('/')[1];
          }
          if (foundBookingId != null) {
            final targetBookingId = foundBookingId;
            debugPrint(
              "⚠️ Try 1: DELETE /bookings/$targetBookingId (delegated=$isDelegatedBooking, ws=$bWsId)",
            );
            final delResult = await _sendWithAuthRetry(
              currentToken,
              (activeToken) => _httpClient.delete(
                Uri.parse("$_apiBase/bookings/$targetBookingId"),
                headers: _authHeaders(activeToken)
                  ..addAll(
                    const <String, String>{"roomz-source-type": "MyRoomzWeb"},
                  ),
              ),
            );
            currentToken = delResult.token;
            final delResp = delResult.response;
            if (delResp.statusCode == 200 || delResp.statusCode == 204) {
              debugPrint("✅ Cancelled by URL ID: $targetBookingId");
              return true;
            }
            debugPrint("❌ Try 1 FAILED: ${delResp.statusCode}");
            break;
          }
        }
      }
    } catch (_) {}

    final payload = <String, dynamic>{
      "workspaceId": effectiveWorkspaceId,
      "localDate": effectiveDate,
      "timeSlot": "FullDay",
    };
    if (foundBookingId != null && foundBookingId.isNotEmpty) {
      payload["id"] = foundBookingId;
      payload["eventId"] = foundBookingId;
    }
    if (forUserId != null && forUserId.isNotEmpty) {
      payload["forUserId"] = forUserId;
    }

    debugPrint("⚠️ Falling back to body DELETE for $effectiveDate");

    final fallbackResult = await _sendWithAuthRetry(
      currentToken,
      (activeToken) => _httpClient.delete(
        Uri.parse("$_apiBase/bookings"),
        headers: <String, String>{
          ..._authHeaders(activeToken),
          "roomz-source-type": "MyRoomzWeb",
        },
        body: jsonEncode(payload),
      ),
    );
    currentToken = fallbackResult.token;
    final response = fallbackResult.response;

    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    }

    if (foundBookingId != null) {
      final targetBookingId = foundBookingId;
      debugPrint("⚠️ Try 3: DELETE /users/current/bookings/$targetBookingId");
      final altResult = await _sendWithAuthRetry(
        currentToken,
        (activeToken) => _httpClient.delete(
          Uri.parse("$_apiBase/users/current/bookings/$targetBookingId"),
          headers: <String, String>{
            ..._authHeaders(activeToken),
            "roomz-source-type": "MyRoomzWeb",
          },
        ),
      );
      final altResponse = altResult.response;
      if (altResponse.statusCode == 200 || altResponse.statusCode == 204) {
        return true;
      }
      debugPrint("❌ Try 3 FAILED: ${altResponse.statusCode}");
    }

    debugPrint(
      "❌ cancelReservation FAILED (Fallback body): ${response.statusCode}",
    );
    return false;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String?> getCurrentUserId(String token) async {
    final fromJwt = getUserIdFromToken(token);
    if (fromJwt != null && fromJwt.isNotEmpty) return fromJwt;
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/users/current"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      final response = result.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        if (data is Map<Object?, Object?>) {
          return data['id']?.toString() ?? data['userId']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getCurrentUserEmail(String token) async {
    final fromJwt = getUserEmailFromToken(token);
    if (fromJwt != null && fromJwt.isNotEmpty) return fromJwt;
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/users/current"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      final response = result.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        if (data is Map<Object?, Object?>) {
          return data['email']?.toString() ?? data['mail']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Origin": "https://my.roomz.io",
        "Referer": "https://my.roomz.io/",
      };

  // ── Colleague Reservation Flow (Milestone M2 - Requirement R2) ───────────

  /// Reserves a workspace for a colleague using `bookAsUserId` or `bookAsExternalOrganizer`.
  Future<BookingResult> reserveWorkspaceForColleague({
    required String date,
    required String token,
    required String workspaceId,
    required String colleagueId,
    String? colleagueName,
    String? colleagueEmail,
  }) async {
    try {
      String currentToken = token;
      String? resolvedEmail = colleagueEmail;
      String effectiveColleagueId = colleagueId;
      final bool isExplicitExternal = colleagueId.startsWith('ext_');
      final bool hasValidUuid =
          RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(effectiveColleagueId);

      if (!hasValidUuid && !isExplicitExternal) {
        final query = (resolvedEmail != null && resolvedEmail.isNotEmpty)
            ? resolvedEmail
            : colleagueName;
        if (query != null && query.isNotEmpty) {
          try {
            final directoryUsers = await searchColleagues(currentToken, query);
            for (final u in directoryUsers) {
              if (u.id.isNotEmpty &&
                  RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(u.id)) {
                if (resolvedEmail != null &&
                    resolvedEmail.isNotEmpty &&
                    u.email.toLowerCase() == resolvedEmail.toLowerCase()) {
                  effectiveColleagueId = u.id;
                  break;
                } else if (colleagueName != null &&
                    colleagueName.isNotEmpty &&
                    u.name.toLowerCase() == colleagueName.toLowerCase()) {
                  effectiveColleagueId = u.id;
                  break;
                }
              }
            }
          } catch (_) {}
        }
      }

      final payload = <String, dynamic>{
        "workspaceId": workspaceId,
        "localDate": date,
        "timeSlot": "FullDay",
      };

      if (isExplicitExternal &&
          resolvedEmail != null &&
          resolvedEmail.isNotEmpty) {
        payload["bookAsExternalOrganizer"] = <String, dynamic>{
          "email": resolvedEmail,
          if (colleagueName != null && colleagueName.isNotEmpty)
            "displayName": colleagueName,
        };
      } else if (effectiveColleagueId.isNotEmpty &&
          !effectiveColleagueId.startsWith('ext_')) {
        payload["bookAsUserId"] = effectiveColleagueId;
      } else if (resolvedEmail != null && resolvedEmail.isNotEmpty) {
        payload["bookAsExternalOrganizer"] = <String, dynamic>{
          "email": resolvedEmail,
          if (colleagueName != null && colleagueName.isNotEmpty)
            "displayName": colleagueName,
        };
      }

      final initialResult = await _sendWithAuthRetry(
        currentToken,
        (activeToken) => _httpClient.post(
          Uri.parse("$_apiBase/bookings"),
          headers: <String, String>{
            ..._authHeaders(activeToken),
            "roomz-source-type": "1",
            "x-roomz-source-type": "1",
          },
          body: jsonEncode(payload),
        ),
      );
      currentToken = initialResult.token;
      http.Response response = initialResult.response;

      final bool isOrganizerNotFound = response.statusCode == 400 &&
          payload.containsKey("bookAsUserId") &&
          (response.body.toLowerCase().contains("organizer") ||
              response.body.toLowerCase().contains("organisateur") ||
              response.body.toLowerCase().contains("not found"));

      if (isOrganizerNotFound) {
        debugPrint(
          "🔄 Server returned 'Organizer not found' for bookAsUserId, resolving email & retrying with bookAsExternalOrganizer...",
        );
        if (resolvedEmail == null || resolvedEmail.isEmpty) {
          if (colleagueName != null && colleagueName.isNotEmpty) {
            try {
              final directoryUsers =
                  await searchColleagues(currentToken, colleagueName);
              for (final u in directoryUsers) {
                if (u.email.isNotEmpty &&
                    (u.id == colleagueId ||
                        u.name.toLowerCase() == colleagueName.toLowerCase())) {
                  resolvedEmail = u.email;
                  break;
                }
              }
            } catch (_) {}
          }
          if (resolvedEmail == null || resolvedEmail.isEmpty) {
            final myEmail = getUserEmailFromToken(currentToken);
            if (myEmail != null &&
                myEmail.contains('@') &&
                colleagueName != null &&
                colleagueName.isNotEmpty) {
              final domain = myEmail.split('@').last;
              final cleanName = colleagueName
                  .trim()
                  .toLowerCase()
                  .replaceAll(RegExp(r'\s+'), '.');
              resolvedEmail = '$cleanName@$domain';
            }
          }
        }

        final effectiveEmail =
            (resolvedEmail != null && resolvedEmail.isNotEmpty)
                ? resolvedEmail
                : (colleagueName != null && colleagueName.isNotEmpty
                    ? '${colleagueName.trim().toLowerCase().replaceAll(' ', '.')}@external.guest'
                    : 'colleague@external.guest');

        final retryPayload = Map<String, dynamic>.from(payload);
        retryPayload.remove("bookAsUserId");
        retryPayload["bookAsExternalOrganizer"] = <String, dynamic>{
          "email": effectiveEmail,
          if (colleagueName != null && colleagueName.isNotEmpty)
            "displayName": colleagueName,
        };

        final extResult = await _sendWithAuthRetry(
          currentToken,
          (activeToken) => _httpClient.post(
            Uri.parse("$_apiBase/bookings"),
            headers: <String, String>{
              ..._authHeaders(activeToken),
              "roomz-source-type": "1",
              "x-roomz-source-type": "1",
            },
            body: jsonEncode(retryPayload),
          ),
        );
        currentToken = extResult.token;
        response = extResult.response;

        if (response.statusCode != 200 && response.statusCode != 201) {
          final webResult = await _sendWithAuthRetry(
            currentToken,
            (activeToken) => _httpClient.post(
              Uri.parse("$_apiBase/bookings"),
              headers: <String, String>{
                ..._authHeaders(activeToken),
                "roomz-source-type": "MyRoomzWeb",
              },
              body: jsonEncode(retryPayload),
            ),
          );
          currentToken = webResult.token;
          response = webResult.response;
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        String? eventId;
        try {
          if (response.body.isNotEmpty) {
            final Object? decoded = jsonDecode(response.body);
            final data = _asStringMap(decoded);
            if (data != null) {
              final nestedData = _asStringMap(data['data']);
              final rawId = data['eventId']?.toString() ??
                  data['id']?.toString() ??
                  data['bookingId']?.toString() ??
                  nestedData?['eventId']?.toString() ??
                  nestedData?['id']?.toString();
              if (rawId != null && rawId.isNotEmpty) {
                eventId = rawId.contains('/') ? rawId.split('/')[1] : rawId;
              }
            }
          }
        } catch (_) {}

        final msg = colleagueName != null
            ? 'Bureau réservé pour $colleagueName !'
            : 'Bureau réservé avec succès !';
        return BookingResult.success(
          eventId: eventId,
          colleagueId: colleagueId,
          colleagueName: colleagueName,
          colleagueEmail: resolvedEmail,
          message: msg,
        );
      } else if (response.statusCode == 409) {
        final bodyLower = response.body.toLowerCase();
        final hasExplicitColleagueConflict =
            bodyLower.contains('already has a reservation') ||
                bodyLower.contains('already has a booking') ||
                bodyLower.contains('déjà une réservation') ||
                bodyLower.contains('user_already_booked') ||
                bodyLower.contains('colleague_already_booked') ||
                (bodyLower.contains('colleague') &&
                    !bodyLower.contains('workspace') &&
                    !bodyLower.contains('desk'));

        final isColleagueConflict = hasExplicitColleagueConflict ||
            ((bodyLower.contains('user') ||
                    bodyLower.contains('person') ||
                    bodyLower.contains('utilisateur')) &&
                !bodyLower.contains('workspace') &&
                !bodyLower.contains('desk') &&
                !bodyLower.contains('bureau') &&
                !bodyLower.contains('seat'));

        if (isColleagueConflict) {
          final msg = colleagueName != null
              ? '$colleagueName a déjà une réservation ce jour-là.'
              : 'Ce collègue a déjà une réservation ce jour-là.';
          return BookingResult.conflictColleague(
            message: msg,
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: resolvedEmail,
          );
        } else {
          return BookingResult.conflictDesk(
            message: 'Ce bureau est déjà réservé par quelqu\'un d\'autre.',
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: resolvedEmail,
          );
        }
      } else if (response.statusCode == 400) {
        String? serverErrorMsg;
        try {
          if (response.body.isNotEmpty) {
            final Object? decoded = jsonDecode(response.body);
            final data = _asStringMap(decoded);
            if (data != null) {
              serverErrorMsg = data['message']?.toString() ??
                  data['error_description']?.toString() ??
                  data['error']?.toString() ??
                  data['detail']?.toString() ??
                  data['title']?.toString();
            }
          }
        } catch (_) {}

        final bodyLower = (serverErrorMsg ?? response.body).toLowerCase();

        final bool isHorizonLimit = bodyLower.contains('13') ||
            bodyLower.contains('horizon') ||
            bodyLower.contains('advance') ||
            bodyLower.contains('limit');

        if (isHorizonLimit) {
          return const BookingResult(
            status: BookingStatus.invalidDate,
            message:
                "La réservation manuelle est limitée à 13 jours à l'avance.",
          );
        }

        if (bodyLower.contains('organizer not found')) {
          return BookingResult(
            status: BookingStatus.serverError,
            message:
                serverErrorMsg ?? 'Organisateur introuvable pour ce collègue.',
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: resolvedEmail,
          );
        }

        final bool isAlreadyBookedConflict =
            bodyLower.contains('already has a reservation') ||
                bodyLower.contains('already has a booking') ||
                bodyLower.contains('déjà une réservation') ||
                bodyLower.contains('user_already_booked') ||
                bodyLower.contains('conflict');

        if (isAlreadyBookedConflict) {
          return BookingResult(
            status: BookingStatus.conflictColleague,
            message: serverErrorMsg ??
                "Conflit : Vous ou ce collègue avez déjà une réservation ce jour-là.",
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: resolvedEmail,
          );
        }

        return BookingResult(
          status: BookingStatus.invalidDate,
          message: serverErrorMsg != null && serverErrorMsg.isNotEmpty
              ? serverErrorMsg
              : "Requête invalide (${response.statusCode}) : ${response.body}",
          colleagueId: colleagueId,
          colleagueName: colleagueName,
          colleagueEmail: resolvedEmail,
        );
      } else if (response.statusCode == 401) {
        _cachedAccessToken = null;
        return const BookingResult(
          status: BookingStatus.unauthorized,
          message: 'Session expirée. Reconnexion requise.',
        );
      } else if (response.statusCode == 403) {
        return const BookingResult(
          status: BookingStatus.forbidden,
          message: 'Votre profil n\'a pas les droits pour réserver pour un tiers.',
        );
      } else if (response.statusCode >= 500) {
        return BookingResult(
          status: BookingStatus.serverError,
          message: 'Erreur serveur MyRoomz (${response.statusCode}).',
        );
      } else {
        return BookingResult(
          status: BookingStatus.serverError,
          message:
              'Erreur inattendue (${response.statusCode}) : ${response.body}',
        );
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      if (e.runtimeType.toString() == 'SocketException') {
        return const BookingResult(
          status: BookingStatus.networkError,
          message:
              'Impossible de joindre les serveurs MyRoomz (réseau inaccessible).',
        );
      }
      return BookingResult(
        status: BookingStatus.networkError,
        message: 'Erreur de connexion : $e',
      );
    }
  }

  // ── Favorites & Colleague Directory (Milestone M2 - Requirement R2) ───────

  List<Colleague> _cachedHarvestedColleagues = <Colleague>[];

  /// Harvests recent colleagues/occupants from bookings and floor data.
  Future<List<Colleague>> harvestColleagues(
    String token, {
    String? floorId,
    String? date,
  }) async {
    final Map<String, Colleague> colleagueMap = <String, Colleague>{};
    String? currentUserId;
    String currentToken = token;

    // 1. Harvest from current user's bookings (/users/current/bookings)
    try {
      final result = await _sendWithAuthRetry(
        currentToken,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      currentToken = result.token;
      final response = result.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        final List<Map<String, dynamic>> bookings = data is List<Object?>
            ? _extractMapList(data)
            : (data is Map<Object?, Object?>
                ? _extractMapList(data['bookings'] ?? data['data'])
                : <Map<String, dynamic>>[]);

        for (final b in bookings) {
          final creatorMap = _asStringMap(b['creator']);
          if (currentUserId == null &&
              creatorMap != null &&
              creatorMap['id'] != null) {
            currentUserId = creatorMap['id']?.toString();
          }

          final List<Object?> candidates = <Object?>[
            b['organizer'],
            b['bookedFor'],
            b['owner'],
            b['user'],
            b['creator'],
          ];

          for (final Object? cRaw in candidates) {
            final c = _asStringMap(cRaw);
            if (c != null) {
              final id = c['id']?.toString() ?? '';
              final name =
                  c['name']?.toString() ?? c['displayName']?.toString() ?? '';
              final email =
                  c['email']?.toString() ?? c['mail']?.toString() ?? '';
              if (name.isNotEmpty &&
                  (currentUserId == null || id != currentUserId)) {
                final key =
                    id.isNotEmpty ? id : (email.isNotEmpty ? email : name);
                colleagueMap[key] = Colleague(
                  id: id.isNotEmpty
                      ? id
                      : 'harv_${email.isNotEmpty ? email : name}',
                  name: name,
                  email: email,
                  isFavorite: false,
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Exception harvesting colleagues from bookings: $e");
    }

    // 2. Harvest from floor workspaces (/floors/{floorId}/workspaces/calendars)
    try {
      final effectiveFloorId = floorId ?? await _storage.getFloorId();
      if (effectiveFloorId != null && effectiveFloorId.isNotEmpty) {
        final effectiveDate = date ?? DateHelpers.formatIsoDate(DateTime.now());
        final payload = <String, Object>{
          "availableWorkspaceOnly": false,
          "date": effectiveDate,
          "timeSlot": "FullDay",
          "tagIds": const <String>[],
          "workspaceType": "Desk",
        };
        final result = await _sendWithAuthRetry(
          currentToken,
          (activeToken) => _httpClient.post(
            Uri.parse(
              "$_apiBase/floors/$effectiveFloorId/workspaces/calendars?length=100&offset=0",
            ),
            headers: _authHeaders(activeToken)
              ..addAll(const <String, String>{
                "roomz-source-type": "MyRoomzWeb",
                "Content-Type": "application/json",
              }),
            body: jsonEncode(payload),
          ),
        );
        final response = result.response;
        if (response.statusCode == 200) {
          final Object? data = jsonDecode(response.body);
          final List<Map<String, dynamic>> items = data is List<Object?>
              ? _extractMapList(data)
              : (data is Map<Object?, Object?>
                  ? _extractMapList(
                      data['data'] ?? data['items'] ?? data['workspaces'],
                    )
                  : <Map<String, dynamic>>[]);

          for (final item in items) {
            final wsName =
                item['workspaceName']?.toString() ?? item['name']?.toString();
            final bookedTimeSlot = _asStringMap(item['bookedTimeSlot']);
            if (bookedTimeSlot != null) {
              final List<Object?> candidates = <Object?>[
                bookedTimeSlot['organizer'],
                bookedTimeSlot['bookedFor'],
                bookedTimeSlot['owner'],
                bookedTimeSlot['user'],
                bookedTimeSlot['creator'],
              ];
              for (final Object? cRaw in candidates) {
                final c = _asStringMap(cRaw);
                if (c != null) {
                  final id = c['id']?.toString() ?? '';
                  final name = c['name']?.toString() ??
                      c['displayName']?.toString() ??
                      '';
                  final email =
                      c['email']?.toString() ?? c['mail']?.toString() ?? '';
                  if (name.isNotEmpty &&
                      (currentUserId == null || id != currentUserId)) {
                    final key =
                        id.isNotEmpty ? id : (email.isNotEmpty ? email : name);
                    final existing = colleagueMap[key];
                    colleagueMap[key] = Colleague(
                      id: id.isNotEmpty
                          ? id
                          : (existing?.id ??
                              'harv_${email.isNotEmpty ? email : name}'),
                      name: name,
                      email: email,
                      deskName: wsName ?? existing?.deskName,
                      isFavorite: false,
                    );
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Exception harvesting colleagues from floor: $e");
    }

    final harvested = colleagueMap.values.toList();
    if (harvested.isNotEmpty) {
      _cachedHarvestedColleagues = harvested;
    }
    return harvested;
  }

  /// Fetches favorite colleagues from MyRoomz API (/favorites).
  Future<List<Colleague>> getFavorites(String token) async {
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.get(
          Uri.parse("$_apiBase/favorites"),
          headers: _authHeaders(activeToken)
            ..addAll(const <String, String>{"roomz-source-type": "MyRoomzWeb"}),
        ),
      );
      final response = result.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        final List<Map<String, dynamic>> rawList = data is List<Object?>
            ? _extractMapList(data)
            : (data is Map<Object?, Object?>
                ? _extractMapList(
                    data['favorites'] ??
                        data['data'] ??
                        data['users'] ??
                        data['items'],
                  )
                : <Map<String, dynamic>>[]);

        if (rawList.isNotEmpty) {
          return rawList
              .map(
                (j) => Colleague.fromJson(<String, dynamic>{
                  ...j,
                  'isFavorite': true,
                  'favoriteId': j['favoriteId'] ?? j['id'],
                }),
              )
              .toList();
        }
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("⚠️ Exception in getFavorites (/favorites): $e");
    }
    return <Colleague>[];
  }

  /// Searches for colleagues across the MyRoomz directory.
  Future<List<Colleague>> searchColleagues(String token, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return <Colleague>[];

    String currentToken = token;
    try {
      final reqResult = await _sendWithAuthRetry(
        currentToken,
        (activeToken) => _httpClient.post(
          Uri.parse("$_apiBase/search?length=30&offset=0"),
          headers: <String, String>{
            ..._authHeaders(activeToken),
            "roomz-source-type": "MyRoomzWeb",
            "Content-Type": "application/json",
          },
          body: jsonEncode(<String, String>{
            "text": trimmed,
          }),
        ),
      );
      currentToken = reqResult.token;
      final response = reqResult.response;
      if (response.statusCode == 200) {
        final Object? data = jsonDecode(response.body);
        final List<Map<String, dynamic>> list = data is List<Object?>
            ? _extractMapList(data)
            : (data is Map<Object?, Object?>
                ? _extractMapList(
                    data['users'] ??
                        data['data'] ??
                        data['items'] ??
                        data['results'],
                  )
                : <Map<String, dynamic>>[]);

        if (list.isNotEmpty) {
          return list.map(Colleague.fromJson).toList();
        }
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("⚠️ Exception in searchColleagues: $e");
    }

    // 2. Fallback: search across harvested colleagues and cached contacts
    try {
      final qLower = trimmed.toLowerCase();
      List<Colleague> pool = List<Colleague>.from(_cachedHarvestedColleagues);
      if (pool.isEmpty) {
        pool = await harvestColleagues(currentToken);
      }
      final localFavs = await _storage.getFavoriteColleagues();
      final Map<String, Colleague> allCandidates = <String, Colleague>{};
      for (final c in pool) {
        final key = c.id.isNotEmpty ? c.id : (c.email.isNotEmpty ? c.email : c.name);
        allCandidates[key] = c;
      }
      for (final c in localFavs) {
        final key = c.id.isNotEmpty ? c.id : (c.email.isNotEmpty ? c.email : c.name);
        allCandidates[key] = c;
      }

      return allCandidates.values.where((c) {
        return c.name.toLowerCase().contains(qLower) ||
            c.email.toLowerCase().contains(qLower);
      }).toList();
    } catch (e) {
      debugPrint("⚠️ Exception in searchColleagues fallback: $e");
    }

    return <Colleague>[];
  }

  // ── Server Favorites Endpoints (Hotfix 5) ──────────────────────────────────

  Future<bool> addFavorite(String token, String colleagueId) async {
    final id = await addFavoriteWithId(token, colleagueId);
    return id != null;
  }

  Future<String?> addFavoriteWithId(String token, String colleagueId) async {
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.post(
          Uri.parse("$_apiBase/favorites/$colleagueId"),
          headers: <String, String>{
            ..._authHeaders(activeToken),
            "roomz-source-type": "MyRoomzWeb",
          },
        ),
      );
      final response = result.response;
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        if (response.body.isNotEmpty) {
          try {
            final Object? data = jsonDecode(response.body);
            if (data is Map<Object?, Object?> && data['id'] != null) {
              return data['id'].toString();
            }
          } catch (_) {}
        }
        return colleagueId;
      }
      return null;
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("⚠️ Exception in addFavorite: $e");
      return null;
    }
  }

  Future<bool> removeFavorite(
    String token,
    String favoriteOrColleagueId,
  ) async {
    try {
      final result = await _sendWithAuthRetry(
        token,
        (activeToken) => _httpClient.delete(
          Uri.parse("$_apiBase/favorites/$favoriteOrColleagueId"),
          headers: <String, String>{
            ..._authHeaders(activeToken),
            "roomz-source-type": "MyRoomzWeb",
          },
        ),
      );
      final response = result.response;
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("⚠️ Exception in removeFavorite: $e");
      return false;
    }
  }

  Future<bool> deleteFavorite(String token, String favoriteOrColleagueId) =>
      removeFavorite(token, favoriteOrColleagueId);

  // ── Floor Occupancy & 2D Map (Milestone M3 - Requirement R3) ───────────────

  /// Extracts user ID from JWT access token if possible.
  String? getUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length >= 2) {
        final normalized = base64Url.normalize(parts[1]);
        final payload = utf8.decode(base64Url.decode(normalized));
        final Object? data = jsonDecode(payload);
        if (data is Map<Object?, Object?>) {
          return data['sub']?.toString() ??
              data['id']?.toString() ??
              data['userId']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Extracts user email or UPN from JWT access token if possible.
  String? getUserEmailFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length >= 2) {
        final normalized = base64Url.normalize(parts[1]);
        final payload = utf8.decode(base64Url.decode(normalized));
        final Object? data = jsonDecode(payload);
        if (data is Map<Object?, Object?>) {
          return data['email']?.toString() ??
              data['upn']?.toString() ??
              data['preferred_username']?.toString() ??
              data['unique_name']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetches all seated occupants for every desk on a given floor for [date].
  Future<Map<String, DeskOccupant>> getFloorOccupants(
    String token,
    String floorId,
    String date, {
    String? myUserId,
    String? myUserEmail,
    Map<String, String>? delegatedBookingsMap,
  }) async {
    final Map<String, DeskOccupant> occupants = <String, DeskOccupant>{};
    int offset = 0;
    const int limit = 100;
    const int maxPages = 20;
    String currentToken = token;

    final resolvedMyUserId = myUserId ?? await getCurrentUserId(currentToken);
    final resolvedMyUserEmail =
        myUserEmail ?? await getCurrentUserEmail(currentToken);

    try {
      for (int page = 0; page < maxPages; page++) {
        final payload = <String, Object>{
          "availableWorkspaceOnly": false,
          "date": date,
          "timeSlot": "FullDay",
          "tagIds": const <String>[],
          "workspaceType": "Desk",
        };

        final reqResult = await _sendWithAuthRetry(
          currentToken,
          (activeToken) => _httpClient.post(
            Uri.parse(
              "$_apiBase/floors/$floorId/workspaces/calendars?length=$limit&offset=$offset",
            ),
            headers: _authHeaders(activeToken)
              ..addAll(const <String, String>{
                "roomz-source-type": "MyRoomzWeb",
                "Content-Type": "application/json",
              }),
            body: jsonEncode(payload),
          ),
        );
        currentToken = reqResult.token;
        final response = reqResult.response;

        if (response.statusCode == 200) {
          final Object? data = jsonDecode(response.body);
          final List<Map<String, dynamic>> items = data is List<Object?>
              ? _extractMapList(data)
              : (data is Map<Object?, Object?>
                  ? _extractMapList(
                      data['data'] ?? data['items'] ?? data['workspaces'],
                    )
                  : <Map<String, dynamic>>[]);

          if (items.isEmpty) break;

          for (final item in items) {
            final status = item['status']?.toString();
            final statusLower = status?.toLowerCase();
            if (statusLower != 'reserved' &&
                statusLower != 'booked' &&
                statusLower != 'occupied') {
              continue;
            }

            Object? rawSlot =
                item['bookedTimeSlot'] ?? item['booking'] ?? item['timeSlot'];
            final rawSlotsList = _extractMapList(item['bookedTimeSlots']);
            if (rawSlot == null && rawSlotsList.isNotEmpty) {
              rawSlot = rawSlotsList.firstWhere(
                (s) => s['timeSlot']?.toString().toLowerCase() == 'fullday',
                orElse: () => rawSlotsList.first,
              );
            }
            final bookedTimeSlot = _asStringMap(rawSlot);
            if (bookedTimeSlot == null) continue;

            final creator = _asStringMap(bookedTimeSlot['creator']);
            final bookedFor = _asStringMap(bookedTimeSlot['bookedFor']);
            final user = _asStringMap(bookedTimeSlot['user']);
            final owner = _asStringMap(bookedTimeSlot['owner']);
            final organizer = _asStringMap(bookedTimeSlot['organizer']);

            String? bookedForString;
            if (bookedFor == null && bookedTimeSlot['bookedFor'] is String) {
              bookedForString = bookedTimeSlot['bookedFor'] as String;
            }

            final creatorId =
                creator?['id']?.toString() ?? creator?['userId']?.toString();
            final creatorName = creator?['name']?.toString() ??
                creator?['displayName']?.toString();
            final creatorEmail =
                creator?['email']?.toString() ?? creator?['mail']?.toString();

            final organizerId = organizer?['id']?.toString() ??
                organizer?['userId']?.toString();
            final organizerName = organizer?['name']?.toString() ??
                organizer?['displayName']?.toString();
            final organizerEmail = organizer?['email']?.toString() ??
                organizer?['mail']?.toString();

            final bool isOrganizerDelegated = creator != null &&
                organizer != null &&
                ((organizerId != null &&
                        creatorId != null &&
                        organizerId != creatorId) ||
                    (organizerEmail != null &&
                        creatorEmail != null &&
                        organizerEmail.toLowerCase() !=
                            creatorEmail.toLowerCase()) ||
                    (organizerName != null &&
                        creatorName != null &&
                        organizerName.toLowerCase() !=
                            creatorName.toLowerCase()));

            final target = bookedFor ??
                (isOrganizerDelegated ? organizer : null) ??
                user ??
                owner ??
                organizer ??
                creator;

            final occName = target?['name']?.toString() ??
                target?['displayName']?.toString() ??
                target?['fullName']?.toString() ??
                bookedForString ??
                (isOrganizerDelegated ? organizerName : null) ??
                bookedTimeSlot['userName']?.toString() ??
                bookedTimeSlot['occupantName']?.toString() ??
                item['occupantName']?.toString() ??
                '';

            if (occName.isEmpty) continue;

            final occId = target?['id']?.toString() ??
                target?['userId']?.toString() ??
                (isOrganizerDelegated ? organizerId : null);
            final occEmail = target?['email']?.toString() ??
                target?['mail']?.toString() ??
                (isOrganizerDelegated ? organizerEmail : null);

            final wsNested = _asStringMap(item['workspace']);
            final wsId = item['workspaceId']?.toString() ??
                item['id']?.toString() ??
                wsNested?['id']?.toString() ??
                wsNested?['workspaceId']?.toString() ??
                bookedTimeSlot['workspaceId']?.toString() ??
                '';

            final isDelegated =
                (bookedFor != null || bookedForString != null) ||
                    isOrganizerDelegated ||
                    (creator != null &&
                        target != null &&
                        ((occId != null &&
                                creatorId != null &&
                                occId != creatorId) ||
                            (occEmail != null &&
                                creatorEmail != null &&
                                occEmail.toLowerCase() !=
                                    creatorEmail.toLowerCase()) ||
                            (occName.isNotEmpty &&
                                creatorName != null &&
                                occName.toLowerCase() !=
                                    creatorName.toLowerCase())));

            bool inDelegatedStorage = false;
            if (delegatedBookingsMap != null && wsId.isNotEmpty) {
              final compositeKey = '$date#$wsId';
              inDelegatedStorage =
                  delegatedBookingsMap.containsKey(compositeKey) ||
                      delegatedBookingsMap[date] == wsId ||
                      (delegatedBookingsMap[date]?.startsWith('$wsId|') ??
                          false);
            }

            final bool effectiveDelegation = isDelegated || inDelegatedStorage;

            bool isCreatorMe = false;
            if (resolvedMyUserId != null && resolvedMyUserId.isNotEmpty) {
              final myIdLower = resolvedMyUserId.toLowerCase();
              if (creatorId != null && creatorId.toLowerCase() == myIdLower) {
                isCreatorMe = true;
              }
            }
            if (!isCreatorMe &&
                resolvedMyUserEmail != null &&
                resolvedMyUserEmail.isNotEmpty) {
              final myEmailLower = resolvedMyUserEmail.toLowerCase();
              if (creatorEmail != null &&
                  creatorEmail.toLowerCase() == myEmailLower) {
                isCreatorMe = true;
              }
            }

            bool isTargetMe = false;
            if (resolvedMyUserId != null && resolvedMyUserId.isNotEmpty) {
              final myIdLower = resolvedMyUserId.toLowerCase();
              if (occId != null && occId.toLowerCase() == myIdLower) {
                isTargetMe = true;
              }
            }
            if (!isTargetMe &&
                resolvedMyUserEmail != null &&
                resolvedMyUserEmail.isNotEmpty) {
              final myEmailLower = resolvedMyUserEmail.toLowerCase();
              if (occEmail != null && occEmail.toLowerCase() == myEmailLower) {
                isTargetMe = true;
              }
            }

            bool isMe = false;
            bool isDelegatedByMe = false;
            bool isDelegatedForMe = false;
            bool isDelegatedOther = false;

            if (effectiveDelegation) {
              if (isCreatorMe || inDelegatedStorage) {
                isDelegatedByMe = true;
                isMe = false;
              } else if (isTargetMe) {
                isDelegatedForMe = true;
                isMe = true;
              } else {
                isDelegatedOther = true;
                isMe = false;
              }
            } else {
              if (isTargetMe || isCreatorMe) {
                isMe = true;
              }
            }

            final bookedByName =
                effectiveDelegation ? (creatorName ?? creatorEmail) : null;

            if (wsId.isNotEmpty) {
              final occupant = DeskOccupant(
                workspaceId: wsId,
                occupantName: occName,
                occupantId: occId,
                occupantEmail: occEmail,
                isMe: isMe,
                isDelegated: effectiveDelegation,
                isDelegatedByMe: isDelegatedByMe,
                isDelegatedForMe: isDelegatedForMe,
                isDelegatedOther: isDelegatedOther,
                bookedByName: bookedByName,
              );
              occupants[wsId] = occupant;
              occupants[wsId.toLowerCase()] = occupant;
            }
          }

          if (items.length < limit) break;
          offset += limit;
        } else {
          debugPrint("⚠️ getFloorOccupants HTTP ${response.statusCode}");
          break;
        }
      }
    } catch (e) {
      OfflineStateManager.instance.reportException(e);
      debugPrint("❌ Exception in getFloorOccupants: $e");
    }

    return occupants;
  }
}
