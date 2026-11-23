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
  final List<int> days;

  const AutomationRule({
    required this.id,
    required this.siteId,
    required this.floorId,
    required this.workspaceId,
    required this.workspaceName,
    required this.days,
  });

  static List<int> normalizeDays(Iterable<int> rawDays) {
    final normalized = rawDays.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    return normalized;
  }

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final parsedDays = <int>[];
    if (rawDays is List) {
      for (final item in rawDays) {
        final parsed = item is int ? item : int.tryParse(item.toString());
        if (parsed != null && parsed >= 1 && parsed <= 7) {
          parsedDays.add(parsed);
        }
      }
    }
    final wsId = json['workspaceId']?.toString() ?? json['id']?.toString() ?? '';
    final id = json['id']?.toString();
    final wsName = json['workspaceName']?.toString();
    return AutomationRule(
      id: (id != null && id.isNotEmpty) ? id : wsId,
      siteId: json['siteId']?.toString() ?? '',
      floorId: json['floorId']?.toString() ?? '',
      workspaceId: wsId,
      workspaceName: (wsName != null && wsName.isNotEmpty) ? wsName : wsId,
      days: normalizeDays(parsedDays),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'siteId': siteId,
        'floorId': floorId,
        'workspaceId': workspaceId,
        'workspaceName': workspaceName,
        'days': normalizeDays(days),
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
      days: days != null ? normalizeDays(days) : normalizeDays(this.days),
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
        listEquals(normalizeDays(other.days), normalizeDays(days));
  }

  @override
  int get hashCode => Object.hash(
        id,
        siteId,
        floorId,
        workspaceId,
        workspaceName,
        Object.hashAll(normalizeDays(days)),
      );

  @override
  String toString() =>
      'AutomationRule(id: $id, siteId: $siteId, floorId: $floorId, workspaceId: $workspaceId, workspaceName: $workspaceName, days: $days)';
}
