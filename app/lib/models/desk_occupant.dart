import 'package:flutter/foundation.dart';

/// Represents a seated person on a desk workspace for a given date.
/// Used for 2D map visualization (Milestone M3 - Requirement R3).
@immutable
class DeskOccupant {
  final String workspaceId;
  final String occupantName;
  final String? occupantId;
  final String? occupantEmail;
  final bool isMe;
  final bool isDelegated;
  final bool isDelegatedByMe;
  final bool isDelegatedForMe;
  final bool isDelegatedOther;
  final String? bookedByName;

  const DeskOccupant({
    required this.workspaceId,
    required this.occupantName,
    this.occupantId,
    this.occupantEmail,
    this.isMe = false,
    bool isDelegated = false,
    this.isDelegatedByMe = false,
    this.isDelegatedForMe = false,
    bool? isDelegatedOther,
    this.bookedByName,
  })  : isDelegated = isDelegated || isDelegatedByMe || isDelegatedForMe || (isDelegatedOther == true),
        isDelegatedOther = isDelegatedOther ??
            ((isDelegated || isDelegatedByMe || isDelegatedForMe) &&
                !isDelegatedByMe &&
                !isDelegatedForMe);

  /// Extracts two-letter initials from [occupantName] for avatar display.
  String get initials {
    final trimmed = occupantName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final first = parts[0];
      return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Formats the mandatory occupant name format: "LASTNAME F."
  /// e.g. "Jean Dupont" -> "DUPONT J."
  String get formattedDisplayName {
    final trimmed = occupantName.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0].toUpperCase();
    final lastName = parts.last.toUpperCase();
    final firstInitial = parts.first[0].toUpperCase();
    return '$lastName $firstInitial.';
  }

  /// Formats a readable short name (e.g. "Sophie G." or "Bob N.")
  String get shortName {
    final trimmed = occupantName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return trimmed;
    final first = parts.first;
    final lastInitial = parts.last[0].toUpperCase();
    return '$first $lastInitial.';
  }

  /// Deserializes a [DeskOccupant] from JSON.
  factory DeskOccupant.fromJson(Map<String, dynamic> json) {
    final rawDelegated = json['isDelegated'] == true;
    final isDelegatedByMe = json['isDelegatedByMe'] == true;
    final isDelegatedForMe = json['isDelegatedForMe'] == true;
    final isDelegatedOther = json['isDelegatedOther'] == true ||
        (rawDelegated && !isDelegatedByMe && !isDelegatedForMe);
    return DeskOccupant(
      workspaceId: json['workspaceId']?.toString() ?? '',
      occupantName: json['occupantName']?.toString() ??
          json['name']?.toString() ??
          json['displayName']?.toString() ??
          json['fullName']?.toString() ??
          'Occupant',
      occupantId: json['occupantId']?.toString() ?? json['id']?.toString() ?? json['userId']?.toString(),
      occupantEmail: json['occupantEmail']?.toString() ?? json['email']?.toString() ?? json['mail']?.toString(),
      isMe: json['isMe'] == true,
      isDelegated: rawDelegated || isDelegatedByMe || isDelegatedForMe || isDelegatedOther,
      isDelegatedByMe: isDelegatedByMe,
      isDelegatedForMe: isDelegatedForMe,
      isDelegatedOther: isDelegatedOther,
      bookedByName: json['bookedByName']?.toString(),
    );
  }

  /// Serializes the [DeskOccupant] into a JSON-encodable map.
  Map<String, dynamic> toJson() => {
        'workspaceId': workspaceId,
        'occupantName': occupantName,
        if (occupantId != null) 'occupantId': occupantId,
        if (occupantEmail != null) 'occupantEmail': occupantEmail,
        'isMe': isMe,
        'isDelegated': isDelegated,
        'isDelegatedByMe': isDelegatedByMe,
        'isDelegatedForMe': isDelegatedForMe,
        'isDelegatedOther': isDelegatedOther,
        if (bookedByName != null) 'bookedByName': bookedByName,
      };

  DeskOccupant copyWith({
    String? workspaceId,
    String? occupantName,
    String? occupantId,
    String? occupantEmail,
    bool? isMe,
    bool? isDelegated,
    bool? isDelegatedByMe,
    bool? isDelegatedForMe,
    bool? isDelegatedOther,
    String? bookedByName,
  }) {
    return DeskOccupant(
      workspaceId: workspaceId ?? this.workspaceId,
      occupantName: occupantName ?? this.occupantName,
      occupantId: occupantId ?? this.occupantId,
      occupantEmail: occupantEmail ?? this.occupantEmail,
      isMe: isMe ?? this.isMe,
      isDelegated: isDelegated ?? this.isDelegated,
      isDelegatedByMe: isDelegatedByMe ?? this.isDelegatedByMe,
      isDelegatedForMe: isDelegatedForMe ?? this.isDelegatedForMe,
      isDelegatedOther: isDelegatedOther ?? this.isDelegatedOther,
      bookedByName: bookedByName ?? this.bookedByName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeskOccupant &&
        other.workspaceId == workspaceId &&
        other.occupantName == occupantName &&
        other.occupantId == occupantId &&
        other.occupantEmail == occupantEmail &&
        other.isMe == isMe &&
        other.isDelegated == isDelegated &&
        other.isDelegatedByMe == isDelegatedByMe &&
        other.isDelegatedForMe == isDelegatedForMe &&
        other.isDelegatedOther == isDelegatedOther &&
        other.bookedByName == bookedByName;
  }

  @override
  int get hashCode => Object.hash(
        workspaceId,
        occupantName,
        occupantId,
        occupantEmail,
        isMe,
        isDelegated,
        isDelegatedByMe,
        isDelegatedForMe,
        isDelegatedOther,
        bookedByName,
      );

  @override
  String toString() =>
      'DeskOccupant(workspaceId: $workspaceId, occupantName: $occupantName, occupantId: $occupantId, isMe: $isMe, isDelegated: $isDelegated, isDelegatedByMe: $isDelegatedByMe, isDelegatedForMe: $isDelegatedForMe, isDelegatedOther: $isDelegatedOther, bookedByName: $bookedByName)';
}
