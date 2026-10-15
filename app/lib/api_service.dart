import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models/colleague.dart';
import 'models/booking_result.dart';
import 'models/desk_occupant.dart';
import 'storage_service.dart';
import 'token_crypto.dart';
import 'utils/delegation_display_helper.dart';

class RoomzApiService {
  final StorageService _storage;
  final http.Client? _customClient;

  http.Client get _client => _customClient ?? http.Client();

  RoomzApiService({StorageService? storage, http.Client? client})
      : _storage = storage ?? StorageService(),
        _customClient = client;

  static String get _loginUrl => kIsWeb ? "https://roomzioproxy.krisdhim2.workers.dev/https://login.roomz.io/connect/token" : "https://login.roomz.io/connect/token";
  static String get _apiBase => kIsWeb ? "https://roomzioproxy.krisdhim2.workers.dev/https://api.my.roomz.io" : "https://api.my.roomz.io";
  static const String _clientId = "my-roomz";
  static const String _scope =
      "openid profile email identityServer-api my-roomz-api offline_access";

  /// Callback invoked when a session expires (HTTP 401).
  static VoidCallback? onSessionExpired;

  String? _cachedAccessToken;
  Future<String?>? _inFlightTokenRefresh;

  /// Central handler when an HTTP 401 or token refresh failure is encountered.
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

  // ── Authentication ──────────────────────────────────────────────────────

  static const String defaultAuthWorkerUrl = "https://roomzauth.krisdhim2.workers.dev";

  /// Initial login with email + password via Cloudflare PKCE Worker (AES-256 encrypted payload).
  /// Returns access token or null.
  Future<String?> login(String email, String password, {String? workerUrl}) async {
    final targetUrl = (workerUrl != null && workerUrl.trim().isNotEmpty)
        ? workerUrl.trim()
        : defaultAuthWorkerUrl;

    final rawJson = jsonEncode({
      "email": email.trim(),
      "password": password,
      "ts": DateTime.now().millisecondsSinceEpoch,
    });
    final encryptedPayload = TokenCryptoService.encryptToken(rawJson);

    final response = await _client.post(
      Uri.parse(targetUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "payload": encryptedPayload,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['refresh_token'] != null) {
        await _storage.saveRefreshToken(data['refresh_token'].toString());
      }
      final token = data['access_token']?.toString();
      _cachedAccessToken = token;
      return token;
    } else {
      debugPrint("❌ Login failed ${response.statusCode}: ${response.body}");
      return null;
    }
  }

  /// Refresh access token using stored refresh token with mutex and caching.
  Future<String?> refreshMyToken({bool force = false}) async {
    if (!force && _cachedAccessToken != null && _cachedAccessToken!.isNotEmpty) {
      return _cachedAccessToken;
    }
    if (_inFlightTokenRefresh != null) {
      return _inFlightTokenRefresh;
    }
    _inFlightTokenRefresh = _performRefreshMyToken();
    try {
      return await _inFlightTokenRefresh;
    } finally {
      _inFlightTokenRefresh = null;
    }
  }

  Future<String?> _performRefreshMyToken() async {
    try {
      final oldRefreshToken = await _storage.getRefreshToken();
      if (oldRefreshToken == null || oldRefreshToken.isEmpty) return null;

      final response = await _client.post(
        Uri.parse(_loginUrl),
        body: {
          "grant_type": "refresh_token",
          "refresh_token": oldRefreshToken,
          "client_id": _clientId,
          "scope": _scope,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data['refresh_token'] != null) {
            await _storage.saveRefreshToken(data['refresh_token']);
          }
          final newAccessToken = data['access_token']?.toString();
          _cachedAccessToken = newAccessToken;
          return newAccessToken;
        }
      } else {
        debugPrint("❌ Token refresh failed ${response.statusCode}");
        if (response.statusCode == 401 || response.statusCode == 400 || response.statusCode == 403) {
          _cachedAccessToken = null;
          await handleSessionExpired();
        }
      }
    } catch (e) {
      debugPrint("❌ Exception in refreshMyToken: $e");
    }
    return null;
  }

  // ── Discovery ────────────────────────────────────────────────────────────

  /// Fetch the list of buildings (sites).
  Future<List<Map<String, dynamic>>> getSites(String token) async {
    final response = await _client.get(
      Uri.parse("$_apiBase/buildings"),
      headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
    );
    _checkAuthResponse(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return List<Map<String, dynamic>>.from(data['data'] ?? []);
    }
    debugPrint("❌ getSites ${response.statusCode}: ${response.body}");
    return [];
  }

  /// Fetch floors for a given building.
  Future<List<Map<String, dynamic>>> getFloors(String token, String siteId) async {
    final response = await _client.get(
      Uri.parse("$_apiBase/buildings/$siteId/floors"),
      headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
    );
    _checkAuthResponse(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return List<Map<String, dynamic>>.from(data['data'] ?? []);
    }
    debugPrint("❌ getFloors ${response.statusCode}: ${response.body}");
    return [];
  }

  // Debug variable to store API keys
  static String lastApiKeys = "";

  /// Fetch ALL workspaces on a given floor (unfiltered).
  Future<List<Map<String, dynamic>>> getAllWorkspaces(String token, String siteId, String floorId) async {
    final List<Map<String, dynamic>> allWorkspaces = [];
    int offset = 0;
    final int limit = 100;
    
    try {
      while (true) {
        final url = "$_apiBase/floors/$floorId/workspaces/all?length=$limit&offset=$offset";
        final response = await _client.get(
          Uri.parse(url),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        _checkAuthResponse(response);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          lastApiKeys = "GET 200 /workspaces/all";
          
          final list = data is List
              ? List<Map<String, dynamic>>.from(data)
              : List<Map<String, dynamic>>.from(
                  data['data'] ?? data['workspaces'] ?? data['items'] ?? data['results'] ?? data['value'] ?? []);
                  
          allWorkspaces.addAll(list);
          
          if (list.length < limit) break; // Reached the end
          offset += limit;
        } else {
          debugPrint("❌ GET /workspaces/all failed: ${response.statusCode}");
          break; // Stop on error
        }
      }
    } catch (e) {
      debugPrint("❌ Exception fetching /workspaces/all: $e");
    }

    if (allWorkspaces.isNotEmpty) {
      // Normalize schema
      for (var ws in allWorkspaces) {
        ws['id'] = ws['workspaceId'] ?? ws['id'];
        ws['name'] = ws['name'] ?? ws['title'] ?? ws['label'] ?? ws['workspaceName'] ?? ws['id'];
        ws['type'] = ws['workspaceType'] ?? ws['type'] ?? "Desk";
      }
      return allWorkspaces;
    }

    lastApiKeys = "ERR: 404 everywhere";
    return [];
  }

  /// Fetch only bookable (desk) workspaces — filters from getAllWorkspaces.
  Future<List<Map<String, dynamic>>> getWorkspaces(String token, String siteId, String floorId) async {
    final all = await getAllWorkspaces(token, siteId, floorId);
    return all.where((ws) {
      if (ws['isReservable'] == false) return false;
      if (ws['bookable'] == false) return false;
      if (ws['isBookable'] == false) return false;
      if (ws['type'] == 'Room') return false;
      if (ws['type'] == 1) return false;
      return true;
    }).toList();
  }

  /// Fetch floor plan GeoJSON data for 2D map.
  Future<List<Map<String, dynamic>>> getFloorPlanData(String token, String siteId, String floorId) async {
    try {
      final response = await _client.get(
        Uri.parse("$_apiBase/buildings/$siteId/floors/$floorId/data"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      _checkAuthResponse(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['features'] != null) {
          return List<Map<String, dynamic>>.from(data['features']);
        }
      }
      debugPrint("❌ getFloorPlanData ${response.statusCode}: ${response.body}");
    } catch (e) {
      debugPrint("❌ Exception getFloorPlanData: $e");
    }
    return [];
  }

  // ── Reservations ─────────────────────────────────────────────────────────



  Future<bool> reserveWorkspace(
      String date, String token, String workspaceId) async {
    final response = await _client.post(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "1",
        "x-roomz-source-type": "1",
      },
      body: jsonEncode({
        "workspaceId": workspaceId,
        "localDate": date,
        "timeSlot": "FullDay",
      }),
    );
    _checkAuthResponse(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      debugPrint("✅ Booked $date");
      return true;
    } else if (response.statusCode == 409) {
      debugPrint("⚠️ Conflict (Already booked by someone else) $date");
      return false;
    } else if (response.statusCode == 400) {
      debugPrint("⚠️ Not available (already booked elsewhere or unavailable) $date");
      return false;
    } else {
      debugPrint("❌ reserveWorkspace ${response.statusCode} $date: ${response.body}");
      return false;
    }
  }

  /// Fetch the user's own bookings.
  /// Returns a record with:
  ///   - `here`: dates booked at the given workspaceId
  ///   - `elsewhere`: dates booked at ANY other workspace (same user, different desk)
  Future<({Set<String> here, Map<String, String> elsewhere, Map<String, String> delegated, String? myUserId})> getMyReservations(
        String token, String workspaceId) async {
      try {
        final response = await _client.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        _checkAuthResponse(response);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final bookings = data['bookings'] as List? ?? [];
          final Set<String> here = {};
          final Map<String, String> elsewhere = {};
          final Map<String, String> delegated = {};
          
          String? foundUserId;
            for (final b in bookings) {
              if (foundUserId == null && b['creator'] != null && b['creator']['id'] != null) {
                foundUserId = b['creator']['id']?.toString();
              }
            if (b['type'] != 'Reserved') continue;
            final dateStr = b['eventDate']?.toString().split('T').first;
            if (dateStr == null) continue;
            
            // Check if it's delegated
            bool isDelegated = false;
            final creator = b['creator'] ?? b['bookedBy'];
            final organizer = b['organizer'];
            final bookedFor = b['bookedFor'] ?? b['user'];
            String targetName = "Quelqu'un";
            String? creatorDisplayName;
            if (creator is Map) {
              creatorDisplayName = creator['name']?.toString() ?? creator['displayName']?.toString();
            } else if (creator is String) {
              creatorDisplayName = creator;
            }
            
            if (bookedFor != null) {
              isDelegated = true;
              if (bookedFor is Map) {
                targetName = bookedFor['name'] ?? bookedFor['displayName'] ?? targetName;
              } else if (bookedFor is String) {
                targetName = bookedFor;
              }
            } else if (creator != null && organizer != null) {
               final creatorId = creator['id'];
               final orgId = organizer['id'];
               final creatorEmail = creator['email']?.toString().toLowerCase();
               final orgEmail = organizer['email']?.toString().toLowerCase();
               final creatorName = creator['name'];
               final orgName = organizer['name'] ?? organizer['displayName'];

               if (creatorId != null && orgId != null && creatorId != orgId) {
                  isDelegated = true;
                  targetName = orgName ?? targetName;
               } else if (creatorEmail != null && orgEmail != null && creatorEmail != orgEmail) {
                  isDelegated = true;
                  targetName = orgName ?? organizer['email'] ?? targetName;
               } else if (creatorName != null && orgName != null && creatorName != orgName) {
                  isDelegated = true;
                  targetName = orgName;
               }
            }
            
            final wsName = b['workspaceName']?.toString() ?? b['workspaceTitle']?.toString() ?? b['workspace']?['name']?.toString() ?? "Ailleurs";
            
            if (isDelegated) {
               final wsId = b['workspaceId']?.toString() ?? '';
               // Always use the real desk name (workspaceName from API) as location
               final location = wsName;
               // eventId in API has format "workspaceId/eventUUID" — extract just the UUID part
               final rawEventId = b['eventId']?.toString() ?? '';
               final evId = rawEventId.contains('/') ? rawEventId.split('/')[1] : rawEventId;
               final orgId = organizer?['id']?.toString() ?? organizer?['email']?.toString() ?? '';
               final cName = creatorDisplayName ?? '';
               final entryVal = '$wsId|$targetName|$location|$evId|$orgId|$cName';
               // If multiple delegated reservations exist for this day, prioritize matching current workspaceId
               if (!delegated.containsKey(dateStr) || wsId.toLowerCase() == workspaceId.toLowerCase()) {
                 delegated[dateStr] = entryVal;
               }
            } else if (b['workspaceId'] == workspaceId) {
              here.add(dateStr);
            } else {
              elsewhere[dateStr] = wsName;
            }
          }
          return (here: here, elsewhere: elsewhere, delegated: delegated, myUserId: foundUserId);
        }
        debugPrint("❌ getMyReservations ${response.statusCode}");
      } catch (e) {
        debugPrint("❌ Exception getMyReservations: $e");
      }
      return (here: <String>{}, elsewhere: <String, String>{}, delegated: <String, String>{}, myUserId: null);
    }

  /// Finds a booking on a specific date (any workspace) and cancels it.
  /// Optionally targets a specific [workspaceId], [forUserId], or [eventId] so other
  /// bookings on the same date (e.g. multi-delegation) are never mistakenly deleted.
  Future<bool> cancelBookingByDate(String token, String dateStr, {String? workspaceId, String? forUserId, String? eventId}) async {
    try {
      final response = await _client.get(
        Uri.parse("$_apiBase/users/current/bookings"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      _checkAuthResponse(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bookings = data['bookings'] as List? ?? [];
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          if (bDate != dateStr) continue;

          final bWsId = b['workspaceId']?.toString() ??
              b['workspace']?['id']?.toString() ??
              b['workspace']?['workspaceId']?.toString();

          // Target strictly the requested workspace if provided
          if (workspaceId != null && workspaceId.isNotEmpty) {
            if (bWsId != null && bWsId.toLowerCase() != workspaceId.toLowerCase()) {
              continue;
            }
          }

          final bCreator = b['creator'];
          final bOrganizer = b['organizer'];
          final bBookedFor = b['bookedFor'];
          bool isDelegatedBooking = false;
          if (bBookedFor != null) {
            isDelegatedBooking = true;
          } else if (bCreator != null && bOrganizer != null) {
            if (bCreator['id'] != null && bOrganizer['id'] != null) {
              isDelegatedBooking = bCreator['id'] != bOrganizer['id'];
            } else if (bCreator['email'] != null && bOrganizer['email'] != null) {
              isDelegatedBooking = bCreator['email'] != bOrganizer['email'];
            } else if (bCreator['name'] != null && bOrganizer['name'] != null) {
              isDelegatedBooking = bCreator['name'] != bOrganizer['name'];
            }
          }

          if (forUserId != null && forUserId.isNotEmpty) {
            if (!isDelegatedBooking) continue;
            final orgId = bOrganizer?['id']?.toString();
            final orgEmail = bOrganizer?['email']?.toString() ?? bOrganizer?['mail']?.toString();
            final orgName = bOrganizer?['name']?.toString() ?? bOrganizer?['displayName']?.toString();
            final targetUserId = forUserId.toLowerCase();
            final matchesDelegate = (orgId != null && orgId.toLowerCase() == targetUserId) ||
                (orgEmail != null && orgEmail.toLowerCase() == targetUserId) ||
                (orgName != null && orgName.toLowerCase() == targetUserId);
            if ((orgId != null || orgEmail != null || orgName != null) && !matchesDelegate) {
              continue;
            }
          } else if (workspaceId == null || workspaceId.isEmpty) {
            if (isDelegatedBooking) continue; // Skip delegation, we want to cancel personal booking
          }

          final targetWsId = bWsId ?? workspaceId;
          final bEventId = eventId ?? b['eventId']?.toString() ?? b['id']?.toString();
          if (targetWsId != null && targetWsId.isNotEmpty) {
            return await cancelReservation(dateStr, token, targetWsId, eventId: bEventId, forUserId: forUserId);
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Exception cancelBookingByDate: $e");
    }
    return false;
  }

  /// Fetch dates where the workspace is booked by someone ELSE.
  /// Uses the POST /floors/{floorId}/workspaces/calendars endpoint for each date.
  Future<({Map<String, String> occupiedByOthers, Map<String, String> delegatedBookings, Set<String> delegatedHere, Set<String> delegatedElsewhere})> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates, String? myUserId, Map<String, String> elsewhereMap) async {
    final Map<String, String> occupied = {};
    final Map<String, String> delegated = {};
    final Set<String> delegatedHere = {};
    final Set<String> delegatedElsewhere = {};
    final client = _customClient ?? http.Client(); // Use custom client if provided (testing), else persistent client
    try {
      // Execute in parallel chunks of 15 to avoid overwhelming the server
      for (int i = 0; i < dates.length; i += 15) {
        final chunk = dates.skip(i).take(15);
        await Future.wait(chunk.map((date) async {
          try {
            final payload = {
              "availableWorkspaceOnly": false,
              "date": date,
              "timeSlot": "FullDay",
              "tagIds": [],
              "workspaceType": "Desk"
            };
            final response = await client.post(
              Uri.parse("$_apiBase/floors/$floorId/workspaces/calendars?length=100&offset=0"),
              headers: _authHeaders(token)..addAll({
                "roomz-source-type": "MyRoomzWeb",
                "Content-Type": "application/json"
              }),
              body: jsonEncode(payload)
            );
            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final items = data['data'] ?? data['items'] ?? data['workspaces'] ?? data;
              if (items is List) {
                for (final item in items) {
                    final isMyDesk = (item['workspaceId'] == workspaceId || item['id'] == workspaceId);
                    
                    if (item['status'] == 'Reserved') {
                      final bookedTimeSlot = item['bookedTimeSlot'];
                      if (bookedTimeSlot != null) {
                        final creator = bookedTimeSlot['creator'] ?? bookedTimeSlot['bookedBy'];
                        final organizer = bookedTimeSlot['organizer'];
                        final bookedFor = bookedTimeSlot['bookedFor'] ?? bookedTimeSlot['user'] ?? bookedTimeSlot['owner'];
                        
                        bool isDelegated = false;
                        String delegateName = "Quelqu'un";
                        
                        final creatorId = creator?['id']?.toString() ?? creator?['userId']?.toString();
                        final creatorName = creator?['name']?.toString() ?? creator?['displayName']?.toString() ?? (creator is String ? creator : null);
                        final creatorEmail = creator?['email']?.toString().toLowerCase();
                        
                        final organizerId = organizer?['id']?.toString() ?? organizer?['userId']?.toString();
                        final organizerName = organizer?['name']?.toString() ?? organizer?['displayName']?.toString() ?? (organizer is String ? organizer : null) ?? organizer?['email']?.toString();
                        final organizerEmail = organizer?['email']?.toString().toLowerCase();
                        
                        final bool isCreatorMe = myUserId != null && creatorId != null && creatorId == myUserId;
                        
                        if (isCreatorMe) {
                          if (bookedFor != null) {
                            isDelegated = true;
                            final targetName = bookedFor is Map ? (bookedFor['name'] ?? bookedFor['displayName'] ?? 'Collègue') : bookedFor.toString();
                            final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                            final location = isMyDesk ? 'Mon bureau' : (elsewhereMap[date] ?? item['workspaceName']?.toString() ?? item['name']?.toString() ?? 'Autre bureau');
                            final evId = bookedTimeSlot['eventId']?.toString() ?? bookedTimeSlot['id']?.toString() ?? '';
                            final orgId = (bookedFor is Map ? bookedFor['id']?.toString() : null) ?? "";
                            final cName = creatorName ?? 'vous';
                            delegateName = "$wsId|$targetName|$location|$evId|$orgId|$cName";
                          } else if (organizer != null) {
                            final bool diff = (organizerId != null && creatorId != organizerId) ||
                                (organizerEmail != null && creatorEmail != null && organizerEmail != creatorEmail) ||
                                (organizerName != null && creatorName != null && organizerName.toLowerCase() != creatorName.toLowerCase());
                            if (diff) {
                              isDelegated = true;
                              final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                              final location = isMyDesk ? 'Mon bureau' : (elsewhereMap[date] ?? item['workspaceName']?.toString() ?? item['name']?.toString() ?? 'Autre bureau');
                              final evId = bookedTimeSlot['eventId']?.toString() ?? bookedTimeSlot['id']?.toString() ?? '';
                              final orgId = organizerId ?? organizerEmail ?? "";
                              final cName = creatorName ?? 'vous';
                              delegateName = "$wsId|${organizerName ?? 'Quelqu\'un'}|$location|$evId|$orgId|$cName";
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
                           // Don't mark as occupied by others if it's actually booked by US
                           if (creator == null || creatorId != myUserId) {
                             final occupantLabel = DelegationDisplayHelper.extractReservationOccupant(
                               Map<String, dynamic>.from(bookedTimeSlot),
                               myUserId: myUserId,
                             );
                             occupied[date] = occupantLabel;
                           }
                        }
                      }
                    }
                  }
              }
            }
          } catch (_) {}
        }));
      }
    } finally {
      client.close();
    }
    return (occupiedByOthers: occupied, delegatedBookings: delegated, delegatedHere: delegatedHere, delegatedElsewhere: delegatedElsewhere);
  }

  Future<bool> cancelReservation(
      String date, String token, String workspaceId, {String? eventId, String? forUserId}) async {
    // In case caller passes workspaceId and date swapped
    String effectiveDate = date;
    String effectiveWorkspaceId = workspaceId;
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(date) && dateRegex.hasMatch(workspaceId)) {
      effectiveDate = workspaceId;
      effectiveWorkspaceId = date;
    }

    String? foundBookingId;
    // If we already have the exact eventId from the calendar, use it!
    if (eventId != null && eventId.isNotEmpty) {
      final cleanEventId = eventId.contains('/') ? eventId.split('/')[1] : eventId;
      debugPrint("⚠️ Try 0: DELETE /bookings/$cleanEventId");
      final delResp = await _client.delete(
        Uri.parse("$_apiBase/bookings/$cleanEventId"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      _checkAuthResponse(delResp);
      if (delResp.statusCode == 200 || delResp.statusCode == 204) {
        debugPrint("✅ Cancelled by eventId: $cleanEventId");
        return true;
      }
      debugPrint("❌ Try 0 FAILED: ${delResp.statusCode} - ${delResp.body}");
      foundBookingId = cleanEventId;
    }

    // First, try to find the exact booking ID from /users/current/bookings
    try {
      final getResp = await _client.get(
        Uri.parse("$_apiBase/users/current/bookings"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      _checkAuthResponse(getResp);
      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        debugPrint("🔥 BOOKINGS DUMP: ${getResp.body}");
        final bookings = data['bookings'] as List? ?? [];
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          if (bDate != effectiveDate) continue;

          final bWsId = b['workspaceId']?.toString() ??
              b['workspace']?['id']?.toString() ??
              b['workspace']?['workspaceId']?.toString() ??
              b['id']?.toString();

          // CRITICAL: Strictly target the matching workspace ID (case-insensitive)
          if (effectiveWorkspaceId.isNotEmpty && bWsId != null &&
              bWsId.toLowerCase() != effectiveWorkspaceId.toLowerCase()) {
            continue;
          }

          // Determine if this is a delegated booking (organizer != creator or bookedFor present)
          // NOTE: organizer may have no 'id' field (external/guest accounts) — fall back to email/name comparison
          final bCreator = b['creator'];
          final bOrganizer = b['organizer'];
          final bBookedFor = b['bookedFor'];
          bool isDelegatedBooking = false;
          if (bBookedFor != null) {
            isDelegatedBooking = true;
          } else if (bCreator != null && bOrganizer != null) {
            if (bCreator['id'] != null && bOrganizer['id'] != null) {
              isDelegatedBooking = bCreator['id'] != bOrganizer['id'];
            } else if (bCreator['email'] != null && bOrganizer['email'] != null) {
              isDelegatedBooking = bCreator['email'] != bOrganizer['email'];
            } else if (bCreator['name'] != null && bOrganizer['name'] != null) {
              isDelegatedBooking = bCreator['name'] != bOrganizer['name'];
            }
          }

          // If forUserId is set → we want to cancel a delegation → skip personal bookings
          // If forUserId is NOT set → we want to cancel a personal booking → skip delegations
          if (forUserId != null && forUserId.isNotEmpty) {
            if (!isDelegatedBooking) continue; // skip personal, we want delegation
            final orgId = bOrganizer?['id']?.toString();
            final orgEmail = bOrganizer?['email']?.toString() ?? bOrganizer?['mail']?.toString();
            final orgName = bOrganizer?['name']?.toString() ?? bOrganizer?['displayName']?.toString();
            final bookedForId = bBookedFor is Map ? bBookedFor['id']?.toString() : null;
            final bookedForEmail = bBookedFor is Map ? (bBookedFor['email']?.toString() ?? bBookedFor['mail']?.toString()) : null;
            final bookedForName = bBookedFor is Map ? bBookedFor['name']?.toString() : (bBookedFor is String ? bBookedFor : null);

            final targetUserId = forUserId.toLowerCase();
            final matchesDelegate = (orgId != null && orgId.toLowerCase() == targetUserId) ||
                (orgEmail != null && orgEmail.toLowerCase() == targetUserId) ||
                (orgName != null && orgName.toLowerCase() == targetUserId) ||
                (bookedForId != null && bookedForId.toLowerCase() == targetUserId) ||
                (bookedForEmail != null && bookedForEmail.toLowerCase() == targetUserId) ||
                (bookedForName != null && bookedForName.toString().toLowerCase() == targetUserId);

            if ((orgId != null || orgEmail != null || orgName != null || bookedForId != null || bookedForEmail != null) && !matchesDelegate) {
              continue;
            }
          } else {
            if (isDelegatedBooking) continue; // skip delegation, we want personal
          }

          foundBookingId = b['eventId']?.toString() ?? b['id']?.toString() ?? b['bookingId']?.toString();
          if (foundBookingId != null && foundBookingId.contains('/')) {
            foundBookingId = foundBookingId.split('/')[1];
          }
          if (foundBookingId != null) {
            debugPrint("⚠️ Try 1: DELETE /bookings/$foundBookingId (delegated=$isDelegatedBooking, ws=$bWsId)");
            final delResp = await _client.delete(
              Uri.parse("$_apiBase/bookings/$foundBookingId"),
              headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
            );
            _checkAuthResponse(delResp);
            if (delResp.statusCode == 200 || delResp.statusCode == 204) {
              debugPrint("✅ Cancelled by URL ID: $foundBookingId");
              return true;
            }
            debugPrint("❌ Try 1 FAILED: ${delResp.statusCode} - ${delResp.body}");
            break; // Targeted the specific booking, do not loop to other bookings!
          }
        }
      }
    } catch (_) {}
    
    // Fallback to body-based DELETE, injecting the ID if found
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
    
    debugPrint("⚠️ Falling back to body DELETE. Payload: $payload");
    
    var response = await _client.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode(payload),
    );
    _checkAuthResponse(response);
    
    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    }
    
    // If it still fails, try one more endpoint format that some versions of the API use
    if (foundBookingId != null) {
       debugPrint("⚠️ Try 3: DELETE /users/current/bookings/$foundBookingId");
       final altResponse = await _client.delete(
         Uri.parse("$_apiBase/users/current/bookings/$foundBookingId"),
         headers: {
           ..._authHeaders(token),
           "roomz-source-type": "MyRoomzWeb",
         },
       );
       _checkAuthResponse(altResponse);
       if (altResponse.statusCode == 200 || altResponse.statusCode == 204) {
         return true;
       }
       debugPrint("❌ Try 3 FAILED: ${altResponse.statusCode} - ${altResponse.body}");
    }

    debugPrint("❌ cancelReservation FAILED (Fallback body): ${response.statusCode} - ${response.body}");
    return false;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String?> getCurrentUserId(String token) async {
    final fromJwt = getUserIdFromToken(token);
    if (fromJwt != null && fromJwt.isNotEmpty) return fromJwt;
    try {
      final response = await _client.get(
        Uri.parse("$_apiBase/users/current"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      _checkAuthResponse(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
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
      final response = await _client.get(
        Uri.parse("$_apiBase/users/current"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      _checkAuthResponse(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          return data['email']?.toString() ?? data['mail']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> _authHeaders(String token) => {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Origin": "https://my.roomz.io",
        "Referer": "https://my.roomz.io/",
      };

  // ── Colleague Reservation Flow (Milestone M2 - Requirement R2) ───────────

  /// Reserves a workspace for a colleague using `forUserId`.
  /// Returns a typed [BookingResult] with the extracted event UUID,
  /// or specialized conflict/error statuses and user-friendly messages.
  Future<BookingResult> reserveWorkspaceForColleague({
    required String date,
    required String token,
    required String workspaceId,
    required String colleagueId,
    String? colleagueName,
    String? colleagueEmail,
  }) async {
    try {
      String effectiveColleagueId = colleagueId;
      final bool isExplicitExternal = colleagueId.startsWith('ext_');
      final bool hasValidUuid = RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(effectiveColleagueId);

      // If not an explicit external guest and not yet a UUID, resolve from directory
      if (!hasValidUuid && !isExplicitExternal) {
        final query = (colleagueEmail != null && colleagueEmail.isNotEmpty)
            ? colleagueEmail
            : colleagueName;
        if (query != null && query.isNotEmpty) {
          try {
            final directoryUsers = await searchColleagues(token, query);
            for (final u in directoryUsers) {
              if (u.id.isNotEmpty && RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(u.id)) {
                if (colleagueEmail != null &&
                    colleagueEmail.isNotEmpty &&
                    u.email.toLowerCase() == colleagueEmail.toLowerCase()) {
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

      if (isExplicitExternal && colleagueEmail != null && colleagueEmail.isNotEmpty) {
        payload["bookAsExternalOrganizer"] = <String, dynamic>{
          "email": colleagueEmail,
          if (colleagueName != null && colleagueName.isNotEmpty)
            "displayName": colleagueName,
        };
      } else if (effectiveColleagueId.isNotEmpty && !effectiveColleagueId.startsWith('ext_')) {
        payload["bookAsUserId"] = effectiveColleagueId;
      } else if (colleagueEmail != null && colleagueEmail.isNotEmpty) {
        payload["bookAsExternalOrganizer"] = <String, dynamic>{
          "email": colleagueEmail,
          if (colleagueName != null && colleagueName.isNotEmpty)
            "displayName": colleagueName,
        };
      }

      var response = await _client.post(
        Uri.parse("$_apiBase/bookings"),
        headers: {
          ..._authHeaders(token),
          "roomz-source-type": "1",
          "x-roomz-source-type": "1",
        },
        body: jsonEncode(payload),
      );

      // If server returns 400 with "Organizer not found" and we used bookAsUserId,
      // resolve email if missing and retry with bookAsExternalOrganizer
      final bool isOrganizerNotFound = response.statusCode == 400 &&
          payload.containsKey("bookAsUserId") &&
          (response.body.toLowerCase().contains("organizer") ||
           response.body.toLowerCase().contains("organisateur") ||
           response.body.toLowerCase().contains("not found"));

      if (isOrganizerNotFound) {
        debugPrint("🔄 Server returned 'Organizer not found' for bookAsUserId, resolving email & retrying with bookAsExternalOrganizer...");
        if (colleagueEmail == null || colleagueEmail.isEmpty) {
          if (colleagueName != null && colleagueName.isNotEmpty) {
            try {
              final directoryUsers = await searchColleagues(token, colleagueName);
              for (final u in directoryUsers) {
                if (u.email.isNotEmpty && (u.id == colleagueId || u.name.toLowerCase() == colleagueName.toLowerCase())) {
                  colleagueEmail = u.email;
                  break;
                }
              }
            } catch (_) {}
          }
          if (colleagueEmail == null || colleagueEmail.isEmpty) {
            final myEmail = getUserEmailFromToken(token);
            if (myEmail != null && myEmail.contains('@') && colleagueName != null && colleagueName.isNotEmpty) {
              final domain = myEmail.split('@').last;
              final cleanName = colleagueName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '.');
              colleagueEmail = '$cleanName@$domain';
            }
          }
        }

        final effectiveEmail = (colleagueEmail != null && colleagueEmail.isNotEmpty)
            ? colleagueEmail
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

        response = await _client.post(
          Uri.parse("$_apiBase/bookings"),
          headers: {
            ..._authHeaders(token),
            "roomz-source-type": "1",
            "x-roomz-source-type": "1",
          },
          body: jsonEncode(retryPayload),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          // Also try with MyRoomzWeb source type header
          response = await _client.post(
            Uri.parse("$_apiBase/bookings"),
            headers: {
              ..._authHeaders(token),
              "roomz-source-type": "MyRoomzWeb",
            },
            body: jsonEncode(retryPayload),
          );
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        String? eventId;
        try {
          if (response.body.isNotEmpty) {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
              final rawId = data['eventId']?.toString() ??
                  data['id']?.toString() ??
                  data['bookingId']?.toString() ??
                  data['data']?['eventId']?.toString() ??
                  data['data']?['id']?.toString();
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
          colleagueEmail: colleagueEmail,
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
            (bodyLower.contains('colleague') && !bodyLower.contains('workspace') && !bodyLower.contains('desk'));

        final isColleagueConflict = hasExplicitColleagueConflict ||
            ((bodyLower.contains('user') || bodyLower.contains('person') || bodyLower.contains('utilisateur')) &&
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
            colleagueEmail: colleagueEmail,
          );
        } else {
          return BookingResult.conflictDesk(
            message: 'Ce bureau est déjà réservé par quelqu\'un d\'autre.',
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: colleagueEmail,
          );
        }
      } else if (response.statusCode == 400) {
        String? serverErrorMsg;
        try {
          if (response.body.isNotEmpty) {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
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
            message: "La réservation manuelle est limitée à 13 jours à l'avance.",
          );
        }

        if (bodyLower.contains('organizer not found')) {
          return BookingResult(
            status: BookingStatus.serverError,
            message: serverErrorMsg ?? 'Organisateur introuvable pour ce collègue.',
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: colleagueEmail,
          );
        }

        final bool isAlreadyBookedConflict = bodyLower.contains('already has a reservation') ||
            bodyLower.contains('already has a booking') ||
            bodyLower.contains('déjà une réservation') ||
            bodyLower.contains('user_already_booked') ||
            bodyLower.contains('conflict');

        if (isAlreadyBookedConflict) {
          return BookingResult(
            status: BookingStatus.conflictColleague,
            message: serverErrorMsg ?? "Conflit : Vous ou ce collègue avez déjà une réservation ce jour-là.",
            colleagueId: colleagueId,
            colleagueName: colleagueName,
            colleagueEmail: colleagueEmail,
          );
        }

        return BookingResult(
          status: BookingStatus.invalidDate,
          message: serverErrorMsg != null && serverErrorMsg.isNotEmpty
              ? serverErrorMsg
              : "Requête invalide (${response.statusCode}) : ${response.body}",
          colleagueId: colleagueId,
          colleagueName: colleagueName,
          colleagueEmail: colleagueEmail,
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
          message: 'Erreur inattendue (${response.statusCode}) : ${response.body}',
        );
      }
    } on SocketException catch (_) {
      return const BookingResult(
        status: BookingStatus.networkError,
        message: 'Impossible de joindre les serveurs MyRoomz (réseau inaccessible).',
      );
    } catch (e) {
      return BookingResult(
        status: BookingStatus.networkError,
        message: 'Erreur de connexion : $e',
      );
    }
  }

  // ── Favorites & Colleague Directory (Milestone M2 - Requirement R2) ───────

  List<Colleague> _cachedHarvestedColleagues = [];

  /// Harvests recent colleagues/occupants from bookings and floor data.
  /// Ensures directory and favorites discovery even when /users or /favorites
  /// endpoints are restricted or empty.
  Future<List<Colleague>> harvestColleagues(String token, {String? floorId, String? date}) async {
    final Map<String, Colleague> colleagueMap = {};
    String? currentUserId;

    // 1. Harvest from current user's bookings (/users/current/bookings)
    try {
      final response = await _client.get(
        Uri.parse("$_apiBase/users/current/bookings"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bookings = data['bookings'] as List? ?? (data is List ? data : []);
        for (final b in bookings) {
          if (b is! Map) continue;
          if (currentUserId == null && b['creator'] is Map && b['creator']['id'] != null) {
            currentUserId = b['creator']['id']?.toString();
          }

          final candidates = [
            b['organizer'],
            b['bookedFor'],
            b['owner'],
            b['user'],
            b['creator'],
          ];

          for (final c in candidates) {
            if (c != null && c is Map) {
              final id = c['id']?.toString() ?? '';
              final name = c['name']?.toString() ?? c['displayName']?.toString() ?? '';
              final email = c['email']?.toString() ?? c['mail']?.toString() ?? '';
              if (name.isNotEmpty && (currentUserId == null || id != currentUserId)) {
                final key = id.isNotEmpty ? id : (email.isNotEmpty ? email : name);
                colleagueMap[key] = Colleague(
                  id: id.isNotEmpty ? id : 'harv_${email.isNotEmpty ? email : name}',
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
        final effectiveDate = date ?? DateTime.now().toIso8601String().split('T').first;
        final payload = {
          "availableWorkspaceOnly": false,
          "date": effectiveDate,
          "timeSlot": "FullDay",
          "tagIds": [],
          "workspaceType": "Desk"
        };
        final response = await _client.post(
          Uri.parse("$_apiBase/floors/$effectiveFloorId/workspaces/calendars?length=100&offset=0"),
          headers: _authHeaders(token)..addAll({
            "roomz-source-type": "MyRoomzWeb",
            "Content-Type": "application/json"
          }),
          body: jsonEncode(payload),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = data['data'] ?? data['items'] ?? data['workspaces'] ?? (data is List ? data : []);
          if (items is List) {
            for (final item in items) {
              if (item is! Map) continue;
              final wsName = item['workspaceName']?.toString() ?? item['name']?.toString();
              final bookedTimeSlot = item['bookedTimeSlot'];
              if (bookedTimeSlot != null && bookedTimeSlot is Map) {
                final candidates = [
                  bookedTimeSlot['organizer'],
                  bookedTimeSlot['bookedFor'],
                  bookedTimeSlot['owner'],
                  bookedTimeSlot['user'],
                  bookedTimeSlot['creator'],
                ];
                for (final c in candidates) {
                  if (c != null && c is Map) {
                    final id = c['id']?.toString() ?? '';
                    final name = c['name']?.toString() ?? c['displayName']?.toString() ?? '';
                    final email = c['email']?.toString() ?? c['mail']?.toString() ?? '';
                    if (name.isNotEmpty && (currentUserId == null || id != currentUserId)) {
                      final key = id.isNotEmpty ? id : (email.isNotEmpty ? email : name);
                      final existing = colleagueMap[key];
                      colleagueMap[key] = Colleague(
                        id: id.isNotEmpty ? id : (existing?.id ?? 'harv_${email.isNotEmpty ? email : name}'),
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

  /// Fetches favorite colleagues from MyRoomz API.
  /// Tries `/users/current/favorites`, `/favorites`, and as a reliable fallback,
  /// harvests recent colleagues/occupants so favorites are NEVER empty if colleagues exist.
  Future<List<Colleague>> getFavorites(String token) async {
    // 1. Try /users/current/favorites
    try {
      final response = await _client.get(
        Uri.parse("$_apiBase/users/current/favorites"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data['favorites'] ?? data['data'] ?? data['users'] ?? data['items'] ?? []);
        if (list is List && list.isNotEmpty) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((j) => Colleague.fromJson({
                    ...j,
                    'isFavorite': true,
                    'favoriteId': j['favoriteId'] ?? j['id'],
                  }))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("⚠️ Exception in getFavorites (/users/current/favorites): $e");
    }

    // 2. Try /favorites
    try {
      final response = await _client.get(
        Uri.parse("$_apiBase/favorites"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data['favorites'] ?? data['data'] ?? data['users'] ?? data['items'] ?? []);
        if (list is List && list.isNotEmpty) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((j) => Colleague.fromJson({
                    ...j,
                    'isFavorite': true,
                    'favoriteId': j['favoriteId'] ?? j['id'],
                  }))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("⚠️ Exception in getFavorites (/favorites): $e");
    }

    // 3. Fallback: harvest recent colleagues/occupants from floor data or bookings
    try {
      final harvested = await harvestColleagues(token);
      if (harvested.isNotEmpty) {
        return harvested.map((c) => c.copyWith(isFavorite: true)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ Exception in getFavorites fallback harvesting: $e");
    }

    return [];
  }

  /// Searches for colleagues across the MyRoomz directory.
  /// Gracefully returns empty list on empty query or API error.
  Future<List<Colleague>> searchColleagues(String token, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final response = await _client.post(
        Uri.parse("$_apiBase/search?length=30&offset=0"),
        headers: {
          ..._authHeaders(token),
          "roomz-source-type": "MyRoomzWeb",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "text": trimmed,
        }),
      );
      _checkAuthResponse(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List
            ? data
            : (data['users'] ?? data['data'] ?? data['items'] ?? data['results'] ?? []);
        if (list is List) {
          final results = list
              .whereType<Map<String, dynamic>>()
              .map((j) => Colleague.fromJson(j))
              .toList();
          if (results.isNotEmpty) return results;
        }
      }
    } catch (e) {
      debugPrint("⚠️ Exception in searchColleagues: $e");
    }

    // 2. Fallback: search across harvested colleagues and cached contacts
    try {
      final qLower = trimmed.toLowerCase();
      List<Colleague> pool = List.from(_cachedHarvestedColleagues);
      if (pool.isEmpty) {
        pool = await harvestColleagues(token);
      }
      final localFavs = await _storage.getFavoriteColleagues();
      final Map<String, Colleague> allCandidates = {};
      for (final c in pool) {
        final key = c.id.isNotEmpty ? c.id : (c.email.isNotEmpty ? c.email : c.name);
        allCandidates[key] = c;
      }
      for (final c in localFavs) {
        final key = c.id.isNotEmpty ? c.id : (c.email.isNotEmpty ? c.email : c.name);
        allCandidates[key] = c;
      }

      final matches = allCandidates.values.where((c) {
        return c.name.toLowerCase().contains(qLower) ||
            c.email.toLowerCase().contains(qLower);
      }).toList();

      return matches;
    } catch (e) {
      debugPrint("⚠️ Exception in searchColleagues fallback: $e");
    }

    return [];
  }

  // ── Server Favorites Endpoints (Hotfix 5) ──────────────────────────────────

  /// Adds a colleague to favorites on MyRoomz server.
  /// POST https://api.my.roomz.io/favorites/{colleagueId}
  Future<bool> addFavorite(String token, String colleagueId) async {
    final id = await addFavoriteWithId(token, colleagueId);
    return id != null;
  }

  /// Adds a colleague to favorites and returns the server favorite ID if present.
  Future<String?> addFavoriteWithId(String token, String colleagueId) async {
    try {
      final response = await _client.post(
        Uri.parse("$_apiBase/favorites/$colleagueId"),
        headers: {
          ..._authHeaders(token),
          "roomz-source-type": "MyRoomzWeb",
        },
      );
      _checkAuthResponse(response);
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        if (response.body.isNotEmpty) {
          try {
            final data = jsonDecode(response.body);
            if (data is Map && data['id'] != null) {
              return data['id'].toString();
            }
          } catch (_) {}
        }
        return colleagueId;
      }
      return null;
    } catch (e) {
      debugPrint("⚠️ Exception in addFavorite: $e");
      return null;
    }
  }

  /// Removes a colleague from favorites on MyRoomz server.
  /// DELETE https://api.my.roomz.io/favorites/{favoriteOrColleagueId}
  Future<bool> removeFavorite(String token, String favoriteOrColleagueId) async {
    try {
      final response = await _client.delete(
        Uri.parse("$_apiBase/favorites/$favoriteOrColleagueId"),
        headers: {
          ..._authHeaders(token),
          "roomz-source-type": "MyRoomzWeb",
        },
      );
      _checkAuthResponse(response);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("⚠️ Exception in removeFavorite: $e");
      return false;
    }
  }

  /// Alias for removeFavorite. Accepts either favoriteId or colleagueId.
  Future<bool> deleteFavorite(String token, String favoriteOrColleagueId) =>
      removeFavorite(token, favoriteOrColleagueId);

  // ── Floor Occupancy & 2D Map (Milestone M3 - Requirement R3) ───────────────

  /// Extracts user ID from JWT access token if possible.
  String? getUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length >= 2) {
        var normalized = base64Url.normalize(parts[1]);
        final payload = utf8.decode(base64Url.decode(normalized));
        final data = jsonDecode(payload);
        if (data is Map) {
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
        var normalized = base64Url.normalize(parts[1]);
        final payload = utf8.decode(base64Url.decode(normalized));
        final data = jsonDecode(payload);
        if (data is Map) {
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
  /// Returns a map of DeskOccupant keyed by lowercase workspaceId and exact workspaceId.
  Future<Map<String, DeskOccupant>> getFloorOccupants(
    String token,
    String floorId,
    String date, {
    String? myUserId,
    String? myUserEmail,
    Map<String, String>? delegatedBookingsMap,
  }) async {
    final Map<String, DeskOccupant> occupants = {};
    int offset = 0;
    const int limit = 100;

    final resolvedMyUserId = myUserId ?? await getCurrentUserId(token);
    final resolvedMyUserEmail = myUserEmail ?? await getCurrentUserEmail(token);

    try {
      while (true) {
        final payload = {
          "availableWorkspaceOnly": false,
          "date": date,
          "timeSlot": "FullDay",
          "tagIds": [],
          "workspaceType": "Desk",
        };

        final response = await _client.post(
          Uri.parse("$_apiBase/floors/$floorId/workspaces/calendars?length=$limit&offset=$offset"),
          headers: _authHeaders(token)..addAll({
            "roomz-source-type": "MyRoomzWeb",
            "Content-Type": "application/json",
          }),
          body: jsonEncode(payload),
        );
        _checkAuthResponse(response);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = data['data'] ?? data['items'] ?? data['workspaces'] ?? (data is List ? data : []);
          if (items is! List || items.isEmpty) break;

          for (final item in items) {
            if (item is! Map) continue;
            final status = item['status']?.toString();
            final statusLower = status?.toLowerCase();
            if (statusLower != 'reserved' && statusLower != 'booked' && statusLower != 'occupied') {
              continue;
            }

            dynamic rawSlot = item['bookedTimeSlot'] ??
                item['booking'] ??
                item['timeSlot'];
            if (rawSlot == null && item['bookedTimeSlots'] is List && (item['bookedTimeSlots'] as List).isNotEmpty) {
              final list = (item['bookedTimeSlots'] as List).whereType<Map>().toList();
              if (list.isNotEmpty) {
                rawSlot = list.firstWhere(
                  (s) => s['timeSlot']?.toString().toLowerCase() == 'fullday',
                  orElse: () => list.first,
                );
              }
            }
            if (rawSlot == null || rawSlot is! Map) continue;

            final bookedTimeSlot = Map<String, dynamic>.from(rawSlot);

            Map<String, dynamic>? getMap(dynamic val) =>
                val is Map<String, dynamic> ? val : (val is Map ? Map<String, dynamic>.from(val) : null);

            final creator = getMap(bookedTimeSlot['creator']);
            final bookedFor = getMap(bookedTimeSlot['bookedFor']);
            final user = getMap(bookedTimeSlot['user']);
            final owner = getMap(bookedTimeSlot['owner']);
            final organizer = getMap(bookedTimeSlot['organizer']);

            String? bookedForString;
            if (bookedFor == null && bookedTimeSlot['bookedFor'] is String) {
              bookedForString = bookedTimeSlot['bookedFor'] as String;
            }

            final creatorId = creator?['id']?.toString() ?? creator?['userId']?.toString();
            final creatorName = creator?['name']?.toString() ?? creator?['displayName']?.toString();
            final creatorEmail = creator?['email']?.toString() ?? creator?['mail']?.toString();

            final organizerId = organizer?['id']?.toString() ?? organizer?['userId']?.toString();
            final organizerName = organizer?['name']?.toString() ?? organizer?['displayName']?.toString();
            final organizerEmail = organizer?['email']?.toString() ?? organizer?['mail']?.toString();

            final bool isOrganizerDelegated = creator != null && organizer != null &&
                ((organizerId != null && creatorId != null && organizerId != creatorId) ||
                 (organizerEmail != null && creatorEmail != null && organizerEmail.toLowerCase() != creatorEmail.toLowerCase()) ||
                 (organizerName != null && creatorName != null && organizerName.toLowerCase() != creatorName.toLowerCase()));

            // Hierarchy of occupant resolution:
            // 1. bookedFor (explicit delegate/colleague target)
            // 2. organizer if differs from creator (delegated booking for external or colleague)
            // 3. user
            // 4. owner
            // 5. organizer
            // 6. creator
            final target = bookedFor ?? (isOrganizerDelegated ? organizer : null) ?? user ?? owner ?? organizer ?? creator;

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

            final occId = target?['id']?.toString() ?? target?['userId']?.toString() ?? (isOrganizerDelegated ? organizerId : null);
            final occEmail = target?['email']?.toString() ?? target?['mail']?.toString() ?? (isOrganizerDelegated ? organizerEmail : null);

            final wsId = item['workspaceId']?.toString() ??
                item['id']?.toString() ??
                item['workspace']?['id']?.toString() ??
                item['workspace']?['workspaceId']?.toString() ??
                bookedTimeSlot['workspaceId']?.toString() ??
                '';

            final isDelegated = (bookedFor != null || bookedForString != null) ||
                isOrganizerDelegated ||
                (creator != null && target != null &&
                    ((occId != null && creatorId != null && occId != creatorId) ||
                     (occEmail != null && creatorEmail != null && occEmail.toLowerCase() != creatorEmail.toLowerCase()) ||
                     (occName.isNotEmpty && creatorName != null && occName.toLowerCase() != creatorName.toLowerCase())));

            bool inDelegatedStorage = false;
            if (delegatedBookingsMap != null && wsId.isNotEmpty) {
              final compositeKey = '$date#$wsId';
              inDelegatedStorage = delegatedBookingsMap.containsKey(compositeKey) ||
                  delegatedBookingsMap[date] == wsId ||
                  (delegatedBookingsMap[date]?.startsWith('$wsId|') ?? false);
            }

            final bool effectiveDelegation = isDelegated || inDelegatedStorage;

            bool isCreatorMe = false;
            if (resolvedMyUserId != null && resolvedMyUserId.isNotEmpty) {
              final myIdLower = resolvedMyUserId.toLowerCase();
              if (creatorId != null && creatorId.toLowerCase() == myIdLower) {
                isCreatorMe = true;
              }
            }
            if (!isCreatorMe && resolvedMyUserEmail != null && resolvedMyUserEmail.isNotEmpty) {
              final myEmailLower = resolvedMyUserEmail.toLowerCase();
              if (creatorEmail != null && creatorEmail.toLowerCase() == myEmailLower) {
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
            if (!isTargetMe && resolvedMyUserEmail != null && resolvedMyUserEmail.isNotEmpty) {
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

            final bookedByName = effectiveDelegation
                ? (creatorName ?? creatorEmail)
                : null;

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
              // Ensure all desks for this occupant are preserved in the dictionary
              occupants[wsId] = occupant;
              occupants[wsId.toLowerCase()] = occupant;
            }
          }

          if (items.length < limit) break;
          offset += limit;
        } else {
          debugPrint("⚠️ getFloorOccupants HTTP ${response.statusCode}: ${response.body}");
          break;
        }
      }
    } catch (e) {
      debugPrint("❌ Exception in getFloorOccupants: $e");
    }

    return occupants;
  }
}
