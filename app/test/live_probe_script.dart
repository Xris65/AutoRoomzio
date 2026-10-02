import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const loginUrl = "https://login.roomz.io/connect/token";
  const clientId = "my-roomz";
  const scope = "openid profile email identityServer-api my-roomz-api offline_access";
  const refreshToken = "7518602B9680173A79B732CB066516A6F9546DC8BEC08068B038D3F958B04A92-1";

  final tokenResp = await http.post(
    Uri.parse(loginUrl),
    body: {
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
      "client_id": clientId,
      "scope": scope,
    },
  );

  if (tokenResp.statusCode != 200) {
    print("FATAL: Refresh token failed: ${tokenResp.body}");
    exit(1);
  }

  final tokenData = jsonDecode(tokenResp.body);
  final token = tokenData['access_token'] as String;
  final newRefreshToken = tokenData['refresh_token'] as String?;

  // Save new refresh token if rotated
  if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
    print("Token rotated! New refresh token available.");
  }

  final headers = {
    "Authorization": "Bearer $token",
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Origin": "https://my.roomz.io",
    "Referer": "https://my.roomz.io/",
    "roomz-source-type": "MyRoomzWeb",
  };

  const api = "https://api.my.roomz.io";
  const orgId = "3b0ce737-a6cd-4a6b-b543-09b879fa1655";
  const siteId = "86f52773-595d-4ad4-dd94-08de536ceae5";
  const floorId = "ca9b458a-2c84-4285-3f25-08de536d0906";
  const myUserId = "a2221459-c00e-40c2-891f-25a9c470094f";

  print("=== 1. VERIFY /users/current/bookings ===");
  final bResp = await http.get(Uri.parse("$api/users/current/bookings"), headers: headers);
  print("Status: ${bResp.statusCode}");
  if (bResp.statusCode == 200) {
    print("Body: ${bResp.body.length > 500 ? bResp.body.substring(0, 500) + '...' : bResp.body}");
  }

  final candidates = [
    // Direct user / directory search endpoints
    "GET $api/users",
    "GET $api/users?search=kristo",
    "GET $api/users?q=kristo",
    "GET $api/users?filter=kristo",
    "GET $api/users?search=dhima",
    "GET $api/users/search?q=kristo",
    "GET $api/users/search?search=kristo",
    "GET $api/users/search?query=kristo",
    "GET $api/directory/users",
    "GET $api/directory/search?query=kristo",
    "GET $api/directory/search?q=kristo",
    "GET $api/directory?query=kristo",
    "GET $api/search/users?query=kristo",
    "GET $api/search/users?q=kristo",
    "GET $api/search/users?term=kristo",
    "GET $api/search?query=kristo",
    "GET $api/search?q=kristo",
    "GET $api/colleagues",
    "GET $api/colleagues?search=kristo",

    // Organization-scoped endpoints
    "GET $api/organizations/$orgId/users",
    "GET $api/organizations/$orgId/users?search=kristo",
    "GET $api/organizations/$orgId/colleagues",
    "GET $api/organizations/$orgId/directory",
    "GET $api/organizations/users",
    "GET $api/organization/users",
    "GET $api/tenants/$orgId/users",

    // Building / Floor scoped user endpoints
    "GET $api/buildings/$siteId/users",
    "GET $api/buildings/$siteId/colleagues",
    "GET $api/floors/$floorId/users",
    "GET $api/floors/$floorId/colleagues",

    // Favorites endpoints
    "GET $api/users/current/favorites",
    "GET $api/users/$myUserId/favorites",
    "GET $api/favorites",
    "GET $api/favorites/users",

    // Other user endpoints
    "GET $api/users/$myUserId",
    "GET $api/users/$myUserId/bookings",
  ];

  print("\n=== 2. PROBING CANDIDATE DIRECTORY & USER ENDPOINTS ===");
  for (final c in candidates) {
    final parts = c.split(" ");
    final method = parts[0];
    final url = parts[1];
    try {
      final res = await (method == "GET" 
          ? http.get(Uri.parse(url), headers: headers)
          : http.post(Uri.parse(url), headers: headers));
      print("[$method] $url -> ${res.statusCode} (Length: ${res.body.length})");
      if (res.statusCode != 404 && res.statusCode != 405) {
        print("   >>> Content (${res.statusCode}): ${res.body.length > 300 ? res.body.substring(0, 300) + '...' : res.body}");
      }
    } catch (e) {
      print("[$method] $url -> EXCEPTION: $e");
    }
  }

  // Also probe POST search endpoints
  final postCandidates = [
    "$api/users/search",
    "$api/directory/search",
    "$api/search/users",
    "$api/organizations/$orgId/users/search",
  ];

  print("\n=== 3. PROBING POST SEARCH ENDPOINTS ===");
  for (final url in postCandidates) {
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({"query": "kristo", "search": "kristo", "term": "kristo"}),
      );
      print("[POST] $url -> ${res.statusCode} (Length: ${res.body.length})");
      if (res.statusCode != 404 && res.statusCode != 405) {
        print("   >>> Content (${res.statusCode}): ${res.body.length > 300 ? res.body.substring(0, 300) + '...' : res.body}");
      }
    } catch (e) {
      print("[POST] $url -> EXCEPTION: $e");
    }
  }
}
