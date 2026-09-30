import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class RoomzApiService {
  final StorageService _storage = StorageService();

  static const String _loginUrl = "https://login.roomz.io/connect/token";
  static const String _apiBase = "https://api.my.roomz.io";
  static const String _clientId = "my-roomz";
  static const String _scope =
      "openid profile email identityServer-api my-roomz-api offline_access";

  // ── Authentication ──────────────────────────────────────────────────────

  /// Initial login with email + password. Returns access token or null.
  Future<String?> login(String email, String password) async {
    final response = await http.post(
      Uri.parse(_loginUrl),
      body: {
        "grant_type": "password",
        "username": email,
        "password": password,
        "client_id": _clientId,
        "scope": _scope,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.saveRefreshToken(data['refresh_token']);
      return data['access_token'];
    } else {
      debugPrint("❌ Login failed ${response.statusCode}: ${response.body}");
      return null;
    }
  }

  /// Refresh access token using stored refresh token.
  Future<String?> refreshMyToken() async {
    final oldRefreshToken = await _storage.getRefreshToken();
    if (oldRefreshToken == null || oldRefreshToken.isEmpty) return null;

    final response = await http.post(
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
      await _storage.saveRefreshToken(data['refresh_token']);
      return data['access_token'];
    } else {
      debugPrint("❌ Token refresh failed ${response.statusCode}");
      return null;
    }
  }

  // ── Discovery ────────────────────────────────────────────────────────────

  /// Fetch the list of buildings (sites).
  Future<List<Map<String, dynamic>>> getSites(String token) async {
    final response = await http.get(
      Uri.parse("$_apiBase/buildings"),
      headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
    );
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
    final response = await http.get(
      Uri.parse("$_apiBase/buildings/$siteId/floors"),
      headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
    );
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
        final response = await http.get(
          Uri.parse(url),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        
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
      final response = await http.get(
        Uri.parse("$_apiBase/buildings/$siteId/floors/$floorId/data"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
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
    final response = await http.post(
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
        final response = await http.get(
          Uri.parse("$_apiBase/users/current/bookings"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
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
            final creator = b['creator'];
            final organizer = b['organizer'];
            String targetName = "Quelqu'un";
            
            if (creator != null && organizer != null) {
               if (creator['id'] != null && organizer['id'] != null && creator['id'] != organizer['id']) {
                  isDelegated = true;
                  targetName = organizer['name'] ?? targetName;
               } else if (creator['name'] != null && organizer['name'] != null && creator['name'] != organizer['name']) {
                  isDelegated = true;
                  targetName = organizer['name'];
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
               final orgId = organizer?['id']?.toString() ?? '';
               delegated[dateStr] = '$wsId|$targetName|$location|$evId|$orgId';
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
  Future<bool> cancelBookingByDate(String token, String dateStr) async {
    try {
      final response = await http.get(
        Uri.parse("$_apiBase/users/current/bookings"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bookings = data['bookings'] as List? ?? [];
        String? foundUserId;
            for (final b in bookings) {
              if (foundUserId == null && b['creator'] != null && b['creator']['id'] != null) {
                foundUserId = b['creator']['id']?.toString();
              }
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          if (bDate == dateStr) {
            final bCreator = b['creator'];
            final bOrganizer = b['organizer'];
            bool isDelegatedBooking = false;
            if (bCreator != null && bOrganizer != null) {
              if (bCreator['id'] != null && bOrganizer['id'] != null) {
                isDelegatedBooking = bCreator['id'] != bOrganizer['id'];
              } else if (bCreator['email'] != null && bOrganizer['email'] != null) {
                isDelegatedBooking = bCreator['email'] != bOrganizer['email'];
              } else if (bCreator['name'] != null && bOrganizer['name'] != null) {
                isDelegatedBooking = bCreator['name'] != bOrganizer['name'];
              }
            }
            if (isDelegatedBooking) continue; // Skip delegation, we want to cancel the personal booking

            final wsId = b['workspaceId']?.toString();
            if (wsId != null) {
              return await cancelReservation(dateStr, token, wsId);
            }
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
    final client = http.Client(); // Use a persistent client to reuse TCP/TLS connections
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
                        final creator = bookedTimeSlot['creator'];
                        final organizer = bookedTimeSlot['organizer'];
                        
                        bool isDelegated = false;
                        String delegateName = "Quelqu'un";
                        
                        if (creator != null && organizer != null && myUserId != null && creator['id'] == myUserId) {
                           final organizerName = organizer['name'];
                           final creatorName = creator['name'];
                           if (organizerName != null && organizerName != creatorName) {
                              isDelegated = true;
                              final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;
                              final location = isMyDesk ? 'Mon bureau' : (elsewhereMap[date] ?? item['workspaceName']?.toString() ?? item['name']?.toString() ?? 'Autre bureau');
                              final evId = bookedTimeSlot['eventId']?.toString() ?? bookedTimeSlot['id']?.toString() ?? '';
                              final orgId = organizer['id']?.toString() ?? "";
                              delegateName = "${wsId}|${organizerName}|${location}|${evId}|${orgId}";
                           }
                        }
                        
                        if (isDelegated) {
                           delegated[date] = delegateName;
                           if (isMyDesk) delegatedHere.add(date);
                           else delegatedElsewhere.add(date);
                        } else if (isMyDesk) {
                           String name = "Quelqu'un d'autre";
                           if (bookedTimeSlot['owner'] != null && bookedTimeSlot['owner']['name'] != null) {
                             name = bookedTimeSlot['owner']['name'];
                           } else if (bookedTimeSlot['user'] != null && bookedTimeSlot['user']['name'] != null) {
                             name = bookedTimeSlot['user']['name'];
                           } else if (bookedTimeSlot['bookedFor'] != null && bookedTimeSlot['bookedFor']['name'] != null) {
                             name = bookedTimeSlot['bookedFor']['name'];
                           } else if (creator != null) {
                             name = creator['name'] ?? name;
                           }
                           
                           // Don't mark as occupied by others if it's actually booked by US
                           if (creator == null || creator['id'] != myUserId) {
                             occupied[date] = name;
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
    String? foundBookingId;
    // If we already have the exact eventId from the calendar, use it!
    if (eventId != null && eventId.isNotEmpty) {
      debugPrint("⚠️ Try 0: DELETE /bookings/$eventId");
      final delResp = await http.delete(
        Uri.parse("$_apiBase/bookings/$eventId"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (delResp.statusCode == 200 || delResp.statusCode == 204) {
        debugPrint("✅ Cancelled by eventId: $eventId");
        return true;
      }
      debugPrint("❌ Try 0 FAILED: ${delResp.statusCode} - ${delResp.body}");
      foundBookingId = eventId;
    }

    // First, try to find the exact booking ID from /users/current/bookings
    try {
      final getResp = await http.get(
        Uri.parse("$_apiBase/users/current/bookings"),
        headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
      );
      if (getResp.statusCode == 200) {
        final data = jsonDecode(getResp.body);
        debugPrint("🔥 BOOKINGS DUMP: ${getResp.body}");
        final bookings = data['bookings'] as List? ?? [];
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          final bWsId = b['workspaceId']?.toString() ?? b['workspace']?['id']?.toString();
          if (bDate != date || bWsId != workspaceId) continue;

          // Determine if this is a delegated booking (organizer != creator)
          // NOTE: organizer may have no 'id' field (external/guest accounts) — fall back to email/name comparison
          final bCreator = b['creator'];
          final bOrganizer = b['organizer'];
          bool isDelegatedBooking = false;
          if (bCreator != null && bOrganizer != null) {
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
          } else {
            if (isDelegatedBooking) continue; // skip delegation, we want personal
          }

          foundBookingId = b['eventId']?.toString() ?? b['id']?.toString();
          if (foundBookingId != null && foundBookingId!.contains('/')) foundBookingId = foundBookingId!.split('/')[1];
          if (foundBookingId != null) {
            debugPrint("⚠️ Try 1: DELETE /bookings/$foundBookingId (delegated=$isDelegatedBooking)");
            final delResp = await http.delete(
              Uri.parse("$_apiBase/bookings/$foundBookingId"),
              headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
            );
            if (delResp.statusCode == 200 || delResp.statusCode == 204) {
              debugPrint("✅ Cancelled by URL ID: $foundBookingId");
              return true;
            }
            debugPrint("❌ Try 1 FAILED: ${delResp.statusCode} - ${delResp.body}");
          }
        }
      }
    } catch (_) {}
    
    // Fallback to body-based DELETE, injecting the ID if found
    final payload = {
      "workspaceId": workspaceId,
      "localDate": date,
      "timeSlot": "FullDay",
    };
    if (foundBookingId != null && foundBookingId.isNotEmpty) {
      payload["id"] = foundBookingId;
    }
    if (forUserId != null && forUserId.isNotEmpty) {
      payload["forUserId"] = forUserId;
    }
    
    debugPrint("⚠️ Falling back to body DELETE. Payload: $payload");
    
    var response = await http.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode(payload),
    );
    
    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    }
    
    // If it still fails, try one more endpoint format that some versions of the API use
    if (foundBookingId != null) {
       debugPrint("⚠️ Try 3: DELETE /users/current/bookings/$foundBookingId");
       final altResponse = await http.delete(
         Uri.parse("$_apiBase/users/current/bookings/$foundBookingId"),
         headers: {
           ..._authHeaders(token),
           "roomz-source-type": "MyRoomzWeb",
         },
       );
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
    try {
      final response = await http.get(Uri.parse("$_apiBase/users/current"), headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id']?.toString();
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
}
