import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class RoomzApiService {
  final StorageService _storage = StorageService();

  // 1. Refresh Token
  Future<String?> refreshMyToken() async {
    final oldRefreshToken = await _storage.getRefreshToken();
    if (oldRefreshToken == null || oldRefreshToken.isEmpty) return null;

    final url = Uri.parse("https://login.roomz.io/connect/token");
    final response = await http.post(url, body: {
      "grant_type": "refresh_token",
      "refresh_token": oldRefreshToken,
      "client_id": "my-roomz",
      "scope": "openid profile email identityServer-api my-roomz-api offline_access"
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newRefreshToken = data['refresh_token'];
      final accessToken = data['access_token'];
      
      // Save the new refresh token securely
      await _storage.saveRefreshToken(newRefreshToken);
      return accessToken;
    } else {
      debugPrint("❌ Error refreshing token: ${response.statusCode}");
      return null;
    }
  }

  // 2. Check if Already Reserved
  Future<bool> isAlreadyReserved(String date, String token, String floorId, String workspaceId) async {
    final url = Uri.parse("https://api.my.roomz.io/floors/$floorId/workspaces/calendars?length=100&offset=0");
    
    final payload = {
      "availableWorkspaceOnly": false,
      "date": date,
      "timeSlot": "FullDay",
      "tagIds": []
    };

    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Origin": "https://my.roomz.io",
      "Referer": "https://my.roomz.io/"
    };

    try {
      final response = await http.post(url, headers: headers, body: jsonEncode(payload));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final workspaces = data['data'] as List;
        
        for (var ws in workspaces) {
          if (ws['workspaceId'] == workspaceId) {
            final status = ws['status'];
            return status != "Available";
          }
        }
        return false;
      } else {
        debugPrint("❌ Error ${response.statusCode}: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("🔥 Crash: $e");
      return false;
    }
  }

  // 3. Make Reservation
  Future<void> reserveWorkspace(String date, String token, String workspaceId) async {
    final url = Uri.parse("https://api.my.roomz.io/bookings");
    
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
      "Accept": "application/json",
      "roomz-source-type": "1", 
      "x-roomz-source-type": "1",
      "Origin": "https://my.roomz.io",
      "Referer": "https://my.roomz.io/"
    };

    final payload = {
      "workspaceId": workspaceId,
      "localDate": date,
      "timeSlot": "FullDay",
    };

    try {
      final response = await http.post(url, headers: headers, body: jsonEncode(payload));
      if (response.statusCode == 200) {
        debugPrint("✅ Success for $date!");
      } else if (response.statusCode == 409) {
        debugPrint("⚠️ Already reserved or conflict for $date.");
      } else {
        debugPrint("❌ Error ${response.statusCode} for $date: ${response.body}");
      }
    } catch (e) {
      debugPrint("🔥 Script error: $e");
    }
  }
}
