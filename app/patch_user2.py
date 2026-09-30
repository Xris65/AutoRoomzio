import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<String?> getCurrentUserId(String token) async {
    try {
      final response = await http.get(Uri.parse("$_apiBase/users/current"), headers: _authHeaders(token));"""
good = """  Future<String?> getCurrentUserId(String token) async {
    try {
      final response = await http.get(Uri.parse("$_apiBase/users/current"), headers: _authHeaders(token)..addAll({"roomz-source-type": "MyRoomzWeb"}));"""

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)