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

  /// Fetch workspaces on a given floor.
  Future<List<Map<String, dynamic>>> getWorkspaces(String token, String floorId) async {
    final response = await http.get(
      Uri.parse("$_apiBase/floors/$floorId/workspaces/all?length=100&offset=0"),
      headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return List<Map<String, dynamic>>.from(data['data'] ?? []);
    }
    debugPrint("❌ getWorkspaces ${response.statusCode}: ${response.body}");
    return [];
  }

  // ── Reservations ─────────────────────────────────────────────────────────

  Future<bool> isAlreadyReserved(
      String date, String token, String floorId, String workspaceId) async {
    final response = await http.post(
      Uri.parse("$_apiBase/floors/$floorId/workspaces/calendars?length=100&offset=0"),
      headers: _authHeaders(token),
      body: jsonEncode({
        "availableWorkspaceOnly": false,
        "date": date,
        "timeSlot": "FullDay",
        "tagIds": [],
      }),
    );
    if (response.statusCode == 200) {
      final workspaces = List.from(jsonDecode(response.body)['data'] ?? []);
      for (var ws in workspaces) {
        if (ws['workspaceId'] == workspaceId) {
          return ws['status'] != "Available";
        }
      }
      return false;
    }
    debugPrint("❌ isAlreadyReserved ${response.statusCode}: ${response.body}");
    return false;
  }

  Future<void> reserveWorkspace(
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
    if (response.statusCode == 200) {
      debugPrint("✅ Booked $date");
    } else if (response.statusCode == 409) {
      debugPrint("⚠️ Already booked $date");
    } else {
      debugPrint("❌ reserveWorkspace ${response.statusCode} $date: ${response.body}");
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
