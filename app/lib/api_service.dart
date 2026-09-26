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
    final today = DateTime.now().toIso8601String().split('T').first;
    
    // The GET endpoints seem to be deprecated (return 404). MyRoomzWeb now uses the POST calendars endpoint.
    // We make two requests to get both Desks and Rooms so the map has all names.
    for (final type in ["Desk", "Room", ""]) {
      try {
        final postResponse = await http.post(
          Uri.parse("$_apiBase/floors/$floorId/workspaces/calendars?length=100&offset=0"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
          body: jsonEncode({
            "availableWorkspaceOnly": false,
            "date": today,
            "timeSlot": "FullDay",
            "tagIds": [],
            if (type.isNotEmpty) "workspaceType": type
          }),
        );
        
        if (postResponse.statusCode == 200) {
          final data = jsonDecode(postResponse.body);
          final list = data['data'] as List? ?? [];
          for (var ws in list) {
            // Map the calendars schema to standard workspace schema
            final mapped = Map<String, dynamic>.from(ws);
            mapped['id'] = ws['workspaceId'] ?? ws['id'];
            mapped['isReservable'] = ws['isReservable'] ?? true;
            mapped['bookable'] = ws['bookable'] ?? true;
            mapped['isBookable'] = ws['isBookable'] ?? true;
            mapped['type'] = type.isEmpty ? (ws['workspaceType'] ?? "Desk") : type;
            allWorkspaces.add(mapped);
          }
          lastApiKeys = "POST 200 Calendars ($type)";
        } else {
           debugPrint("❌ POST $type failed: ${postResponse.statusCode}");
        }
      } catch (e) {
         debugPrint("❌ Exception fetching $type: $e");
      }
    }

    if (allWorkspaces.isNotEmpty) {
      // Remove duplicates
      final uniqueMap = {for (var ws in allWorkspaces) ws['id']: ws};
      
      // The calendars endpoint doesn't include the 'name' field, it only gives workspaceId and status!
      // We MUST fetch the GeoJSON to extract the names and merge them in.
      try {
        final features = await getFloorPlanData(token, siteId, floorId);
        for (var f in features) {
          final props = f['properties'] ?? {};
          final wsId = props['workspaceId']?.toString();
          if (wsId != null && uniqueMap.containsKey(wsId)) {
            final name = props['name']?.toString() ?? props['title']?.toString() ?? props['label']?.toString() ?? props['workspaceName']?.toString() ?? props['text']?.toString() ?? props['description']?.toString();
            if (name != null && name.isNotEmpty) {
               uniqueMap[wsId]!['name'] = name;
            }
          }
        }
      } catch (e) {
        debugPrint("❌ Failed to merge names from GeoJSON: $e");
      }
      
      return uniqueMap.values.toList();
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
  Future<({Set<String> here, Set<String> elsewhere})> getMyReservations(
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
        final Set<String> elsewhere = {};
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final dateStr = b['eventDate']?.toString().split('T').first;
          if (dateStr == null) continue;
          if (b['workspaceId'] == workspaceId) {
            here.add(dateStr);
          } else {
            elsewhere.add(dateStr);
          }
        }
        return (here: here, elsewhere: elsewhere);
      }
      debugPrint("❌ getMyReservations ${response.statusCode}: ${response.body}");
    } catch (e) {
      debugPrint("❌ Exception getMyReservations: $e");
    }
    return (here: <String>{}, elsewhere: <String>{});
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
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final bDate = b['eventDate']?.toString().split('T').first;
          if (bDate == dateStr) {
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

  /// Fetch dates where the same workspace is booked by someone ELSE.
  /// Uses the same /users/current/bookings endpoint but looks for OTHER workspaceIds
  /// sharing the same floor — we detect occupation via a separate endpoint.
  /// Simpler: just try POSTing a reservation; a 409 means occupied. 
  /// Best approach: GET /workspaces/{id}/bookings or check workspace events.
  Future<Set<String>> getWorkspaceOccupancy(String token, String workspaceId, List<String> dates) async {
    final Set<String> occupied = {};
    for (final date in dates) {
      try {
        final response = await http.get(
          Uri.parse("$_apiBase/workspaces/$workspaceId/events/$date"),
          headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // If events exist and it's not our own booking, it's occupied
          if (data != null && (data is List ? data.isNotEmpty : data['id'] != null)) {
            occupied.add(date);
          }
        }
        // 404 = no booking on that date, skip
      } catch (_) {}
    }
    return occupied;
  }

  Future<bool> cancelReservation(
      String date, String token, String workspaceId) async {
    final response = await http.delete(
      Uri.parse("$_apiBase/bookings"),
      headers: {
        ..._authHeaders(token),
        "roomz-source-type": "MyRoomzWeb",
      },
      body: jsonEncode({
        "workspaceId": workspaceId,
        "localDate": date,
        "timeSlot": "FullDay",
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint("✅ Cancelled $date");
      return true;
    } else {
      debugPrint("❌ cancelReservation ${response.statusCode} $date: ${response.body}");
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Map<String, String> _authHeaders(String token) => {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Origin": "https://my.roomz.io",
        "Referer": "https://my.roomz.io/",
      };
}
