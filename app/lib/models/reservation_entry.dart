import 'package:flutter/foundation.dart';

/// Immutable representation of a user reservation for a single ISO date.
@immutable
class ReservationEntry {
  /// Reservation date in `YYYY-MM-DD` ISO format.
  final String dateIso;

  /// Reserved workspace identifier (may be empty for legacy migrated entries).
  final String workspaceId;

  /// Human-readable workspace name.
  final String workspaceName;

  /// Optional ISO-8601 timestamp of the last local update.
  final String? updatedAt;

  const ReservationEntry({
    required this.dateIso,
    required this.workspaceId,
    required this.workspaceName,
    this.updatedAt,
  });

  /// Constructs a [ReservationEntry] from JSON, supporting both full v2 entries
  /// and legacy `{workspaceId, workspaceName}` maps.
  factory ReservationEntry.fromJson(
    String dateIso,
    Map<String, dynamic> json,
  ) {
    final String? rawUpdatedAt = json['updatedAt']?.toString();
    return ReservationEntry(
      dateIso: dateIso,
      workspaceId: json['workspaceId']?.toString() ?? '',
      workspaceName: json['workspaceName']?.toString() ?? '',
      updatedAt: (rawUpdatedAt != null && rawUpdatedAt.isNotEmpty)
          ? rawUpdatedAt
          : null,
    );
  }

  /// Serializes this entry into a JSON-compatible map (keyed externally by [dateIso]).
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  /// Converts this entry into the legacy `{workspaceId, workspaceName}` string map.
  Map<String, String> toLegacyMap() {
    return <String, String>{
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
    };
  }

  ReservationEntry copyWith({
    String? dateIso,
    String? workspaceId,
    String? workspaceName,
    String? updatedAt,
  }) {
    return ReservationEntry(
      dateIso: dateIso ?? this.dateIso,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceName: workspaceName ?? this.workspaceName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReservationEntry &&
        other.dateIso == dateIso &&
        other.workspaceId == workspaceId &&
        other.workspaceName == workspaceName &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(dateIso, workspaceId, workspaceName, updatedAt);
}
