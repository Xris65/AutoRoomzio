import 'package:flutter/foundation.dart';

/// Represents an independent weekly automation rule associating a specific
/// desk/workspace with a sorted list of weekdays (1 = Monday .. 7 = Sunday).
@immutable
class AutomationRule {
  final String id;
  final String siteId;
  final String floorId;
  final String workspaceId;
  final String workspaceName;
  final List<int> _days;

  const AutomationRule({
    required this.id,
    required this.siteId,
    required this.floorId,
    required this.workspaceId,
    required this.workspaceName,
    required this._days,
  });

  /// Unmodifiable view of configured weekdays, preventing external cache mutation.
  List<int> get days => List<int>.unmodifiable(_days);

  static List<int> normalizeDays(Iterable<int> rawDays) {
    final normalized = rawDays.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    return List<int>.unmodifiable(normalized);
  }

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    final Object? rawDays = json['days'];
    final parsedDays = <int>[];
    if (rawDays is List<Object?>) {
      for (final Object? item in rawDays) {
        final parsed =
            item is int ? item : (item != null ? int.tryParse(item.toString()) : null);
        if (parsed != null && parsed >= 1 && parsed <= 7) {
          parsedDays.add(parsed);
        }
      }
    }
    final wsId =
        json['workspaceId']?.toString() ?? json['id']?.toString() ?? '';
    final id = json['id']?.toString();
    final wsName = json['workspaceName']?.toString();
    return AutomationRule(
      id: (id != null && id.isNotEmpty) ? id : wsId,
      siteId: json['siteId']?.toString() ?? '',
      floorId: json['floorId']?.toString() ?? '',
      workspaceId: wsId,
      workspaceName: (wsName != null && wsName.isNotEmpty) ? wsName : wsId,
      days: List<int>.unmodifiable(normalizeDays(parsedDays)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'siteId': siteId,
        'floorId': floorId,
        'workspaceId': workspaceId,
        'workspaceName': workspaceName,
        'days': normalizeDays(_days),
      };

  AutomationRule copyWith({
    String? id,
    String? siteId,
    String? floorId,
    String? workspaceId,
    String? workspaceName,
    List<int>? days,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      floorId: floorId ?? this.floorId,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceName: workspaceName ?? this.workspaceName,
      days: List<int>.unmodifiable(
        days != null ? normalizeDays(days) : normalizeDays(_days),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AutomationRule &&
        other.id == id &&
        other.siteId == siteId &&
        other.floorId == floorId &&
        other.workspaceId == workspaceId &&
        other.workspaceName == workspaceName &&
        listEquals(normalizeDays(other._days), normalizeDays(_days));
  }

  @override
  int get hashCode => Object.hash(
        id,
        siteId,
        floorId,
        workspaceId,
        workspaceName,
        Object.hashAll(normalizeDays(_days)),
      );

  @override
  String toString() =>
      'AutomationRule(id: $id, siteId: $siteId, floorId: $floorId, workspaceId: $workspaceId, workspaceName: $workspaceName, days: $days)';
}
