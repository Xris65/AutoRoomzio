import 'package:flutter/foundation.dart';

/// Represents a colleague in AutoRoomzio for delegated reservations (R2)
/// and 2D floor map occupant visualization (R3).
@immutable
class Colleague {
  final String id;
  final String name;
  final String email;
  final bool isFavorite;
  final String? deskName;
  final String? roomName;
  final String? avatarUrl;
  final String? favoriteId;

  const Colleague({
    required this.id,
    required this.name,
    this.email = '',
    this.isFavorite = false,
    this.deskName,
    this.roomName,
    this.avatarUrl,
    this.favoriteId,
  });

  /// Calculates two-letter initials (e.g. "Jean Dupont" -> "JD", "Alice" -> "A").
  /// Returns "?" if the name is empty or only whitespace.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final first = parts[0];
      return first.isNotEmpty ? first[0].toUpperCase() : '?';
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Deserializes a Colleague from JSON, supporting standard formats and
  /// MyRoomz API variations (e.g. displayName, photo, mail).
  factory Colleague.fromJson(Map<String, dynamic> json) {
    final rawUserId = json['userId']?.toString() ??
        json['user']?['id']?.toString() ??
        json['targetUserId']?.toString();

    final resolvedId = rawUserId ?? json['id']?.toString() ?? '';
    final favId = json['favoriteId']?.toString();

    return Colleague(
      id: resolvedId,
      name: json['name']?.toString() ??
          json['displayName']?.toString() ??
          json['fullName']?.toString() ??
          json['user']?['name']?.toString() ??
          json['user']?['displayName']?.toString() ??
          'Collègue',
      email: json['email']?.toString() ??
          json['mail']?.toString() ??
          json['user']?['email']?.toString() ??
          '',
      isFavorite: json['isFavorite'] == true ||
          json['favorite'] == true ||
          (json['favoriteId'] != null && json['favoriteId'].toString().isNotEmpty),
      deskName: json['deskName']?.toString() ?? json['workspaceName']?.toString(),
      roomName: json['roomName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString() ?? json['photo']?.toString(),
      favoriteId: favId,
    );
  }

  /// Serializes the Colleague into a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'isFavorite': isFavorite,
        if (deskName != null) 'deskName': deskName,
        if (roomName != null) 'roomName': roomName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (favoriteId != null) 'favoriteId': favoriteId,
      };

  /// Returns a copy of this Colleague with the given fields replaced by new values.
  Colleague copyWith({
    String? id,
    String? name,
    String? email,
    bool? isFavorite,
    String? deskName,
    String? roomName,
    String? avatarUrl,
    String? favoriteId,
  }) {
    return Colleague(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      isFavorite: isFavorite ?? this.isFavorite,
      deskName: deskName ?? this.deskName,
      roomName: roomName ?? this.roomName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      favoriteId: favoriteId ?? this.favoriteId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Colleague &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          email == other.email &&
          isFavorite == other.isFavorite &&
          deskName == other.deskName &&
          roomName == other.roomName &&
          avatarUrl == other.avatarUrl &&
          favoriteId == other.favoriteId;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        email,
        isFavorite,
        deskName,
        roomName,
        avatarUrl,
        favoriteId,
      );

  @override
  String toString() =>
      'Colleague(id: $id, name: $name, email: $email, isFavorite: $isFavorite, deskName: $deskName, roomName: $roomName, favoriteId: $favoriteId)';
}
