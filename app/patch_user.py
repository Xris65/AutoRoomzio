import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Map<String, String> _authHeaders(String token) => {"""
good = """  Future<String?> getCurrentUserId(String token) async {
    try {
      final response = await http.get(Uri.parse("$_apiBase/users/current"), headers: _authHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> _authHeaders(String token) => {"""

content = content.replace(bad, good)
with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)