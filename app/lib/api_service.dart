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
  Future<({Set<String> here, Map<String, String> elsewhere})> getMyReservations(
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
        for (final b in bookings) {
          if (b['type'] != 'Reserved') continue;
          final dateStr = b['eventDate']?.toString().split('T').first;
          if (dateStr == null) continue;
          if (b['workspaceId'] == workspaceId) {
            here.add(dateStr);
          } else {
            final wsName = b['workspaceName']?.toString() ?? b['workspaceTitle']?.toString() ?? b['workspace']?['name']?.toString() ?? "Ailleurs";
            elsewhere[dateStr] = wsName;
          }
        }
        return (here: here, elsewhere: elsewhere);
      }
      debugPrint("❌ getMyReservations ${response.statusCode}: ${response.body}");
    } catch (e) {
      debugPrint("❌ Exception getMyReservations: $e");
    }
    return (here: <String>{}, elsewhere: <String, String>{});
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

  /// Fetch dates where the workspace is booked by someone ELSE.
  /// Uses the POST /floors/{floorId}/workspaces/calendars endpoint for each date.
  Future<Set<String>> getWorkspaceOccupancy(String token, String workspaceId, String floorId, List<String> dates) async {
    final Set<String> occupied = {};
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
                  if (item['workspaceId'] == workspaceId || item['id'] == workspaceId) {
                    // If the workspace is Reserved and the creator email doesn't match ours (or just count any reservation since we filter out 'bookedHere' later)
                    if (item['status'] == 'Reserved') {
                      occupied.add(date);
                    }
                    break;
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
