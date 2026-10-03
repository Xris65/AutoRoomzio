import 'package:flutter/material.dart';
import '../models/desk_occupant.dart';

class _RoomBounds {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;
  void addRect(double left, double top, double width, double height) {
    if (left < minX) minX = left;
    if (top < minY) minY = top;
    if (left + width > maxX) maxX = left + width;
    if (top + height > maxY) maxY = top + height;
  }
}

class WorkspaceMapViewer extends StatefulWidget {
  final List<Map<String, dynamic>> features;
  final List<Map<String, dynamic>> workspaces;
  final List<Map<String, dynamic>> allWorkspaces;
  final String? selectedWorkspaceId;
  final String? defaultWorkspaceId;
  final double? containerHeight;
  final Function(Map<String, dynamic> workspace) onSelected;

  // Milestone M3 Extensions
  final Map<String, DeskOccupant> occupants;
  final Set<String> favoriteIds;
  final Set<String> favoriteNamesNormalized;
  final Set<String> favoriteWorkspaceIds;
  final Function(Map<String, dynamic> workspace, DeskOccupant occupant)? onOccupantTapped;
  final String? focusedRoom;

  const WorkspaceMapViewer({
    super.key,
    required this.features,
    required this.workspaces,
    this.allWorkspaces = const [],
    this.selectedWorkspaceId,
    this.defaultWorkspaceId,
    this.containerHeight,
    required this.onSelected,
    this.occupants = const {},
    this.favoriteIds = const {},
    this.favoriteNamesNormalized = const {},
    this.favoriteWorkspaceIds = const {},
    this.onOccupantTapped,
    this.focusedRoom,
  });

  @override
  State<WorkspaceMapViewer> createState() => _WorkspaceMapViewerState();
}

class _WorkspaceMapViewerState extends State<WorkspaceMapViewer> {
  final TransformationController _controller = TransformationController();
  // Track the last viewport size we initialized for — reinit if size changes
  Size? _lastViewportSize;
  double _lastMapWidth = 0.0;
  double _lastMapHeight = 0.0;
  Map<String, _RoomBounds> _savedRoomBounds = {};
  bool _isInitialTransformSet = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkspaceMapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedRoom != widget.focusedRoom) {
      _handleFocusedRoomChanged();
    }
  }

  void _handleFocusedRoomChanged() {
    if (_lastViewportSize == null) return;
    final viewW = _lastViewportSize!.width;
    final viewH = _lastViewportSize!.height;

    if (widget.focusedRoom == null || widget.focusedRoom!.isEmpty) {
      if (_lastMapWidth > 0 && _lastMapHeight > 0) {
        _initTransform(viewW, viewH, _lastMapWidth, _lastMapHeight, null);
      }
      return;
    }

    _RoomBounds? bounds = _savedRoomBounds[widget.focusedRoom];
    if (bounds == null) {
      for (final entry in _savedRoomBounds.entries) {
        if (entry.key.toLowerCase() == widget.focusedRoom!.toLowerCase()) {
          bounds = entry.value;
          break;
        }
      }
    }

    if (bounds != null && bounds.minX != double.infinity) {
      final targetRect = Rect.fromLTRB(
        bounds.minX - 28,
        bounds.minY - 36,
        bounds.maxX + 28,
        bounds.maxY + 36,
      );
      _frameTargetRect(viewW, viewH, targetRect);
    }
  }

  void _zoomIn() {
    final matrix = _controller.value.clone();
    matrix.scaleByDouble(1.3, 1.3, 1.0, 1.0);
    _controller.value = matrix;
  }

  void _zoomOut() {
    final matrix = _controller.value.clone();
    matrix.scaleByDouble(0.77, 0.77, 1.0, 1.0);
    _controller.value = matrix;
  }

  /// Recursively extracts all [x, y] leaf coordinate pairs from a GeoJSON
  /// coordinates array, regardless of nesting depth (Point/LineString/Polygon/
  /// MultiPolygon etc.).
  void _extractBounds(List coords, void Function(double x, double y) cb) {
    if (coords.isEmpty) return;
    if (coords[0] is num) {
      if (coords.length >= 2) {
        cb((coords[0] as num).toDouble(), (coords[1] as num).toDouble());
      }
    } else {
      for (final item in coords) {
        if (item is List) _extractBounds(item, cb);
      }
    }
  }

  void _initTransform(double viewW, double viewH, double mapW, double mapH, Rect? targetRect) {
    if (mapW <= 0 || mapH <= 0 || viewW <= 0 || viewH <= 0) return;

    // Use a comfortable, legible scale so desks (~72px) and occupant names are immediately readable.
    // Scale 1.0 represents the exact architectural design scale with clear legible text.
    final double scale;
    double targetCx;
    double targetCy;

    if (targetRect != null && targetRect.width > 0 && targetRect.height > 0) {
      final fitScale = (viewW * 0.75) / targetRect.width;
      scale = fitScale.clamp(0.85, 1.25);
      targetCx = targetRect.left + targetRect.width / 2;
      targetCy = targetRect.top + targetRect.height / 2;
    } else {
      // Smart Zoom-to-Fit fallback when default desk is not on current floor
      final scaleX = (viewW * 0.90) / mapW;
      final scaleY = (viewH * 0.85) / mapH;
      final fitScale = (scaleX < scaleY ? scaleX : scaleY);
      scale = fitScale.clamp(0.60, 1.25);
      targetCx = mapW / 2;
      targetCy = mapH / 2;
    }

    final dx = (viewW / 2) - (targetCx * scale);
    final dy = (viewH / 2) - (targetCy * scale);

    final m = Matrix4.identity()
      ..setTranslationRaw(dx, dy, 0.0)
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale);

    _controller.value = m;
  }

  void _frameTargetRect(double viewW, double viewH, Rect targetRect) {
    if (targetRect.width <= 0 || targetRect.height <= 0 || viewW <= 0 || viewH <= 0) return;
    final scaleX = viewW / targetRect.width;
    final scaleY = viewH / targetRect.height;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.5, 2.5) * 0.90;

    final targetCx = targetRect.left + targetRect.width / 2;
    final targetCy = targetRect.top + targetRect.height / 2;
    final dx = (viewW / 2) - (targetCx * scale);
    final dy = (viewH / 2) - (targetCy * scale);

    final m = Matrix4.identity()
      ..setTranslationRaw(dx, dy, 0.0)
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale);

    _controller.value = m;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.features.isEmpty) {
      return const Center(child: Text("Aucun plan disponible"));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        // If containerHeight is provided, use it; otherwise fill available height
        final viewH = widget.containerHeight ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 450.0);

        // ── 1. Compute overall bounding box & coordinate scaling factor ───────
        double minX = double.infinity, minY = double.infinity;
        double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
        double totalDeskWidth = 0.0;
        int deskCount = 0;

        for (final feature in widget.features) {
          final coords = feature['geometry']?['coordinates'] as List?;
          if (coords == null || coords.isEmpty) continue;
          double fMinX = double.infinity, fMinY = double.infinity;
          double fMaxX = double.negativeInfinity, fMaxY = double.negativeInfinity;
          _extractBounds(coords, (x, y) {
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
            if (x < fMinX) fMinX = x;
            if (y < fMinY) fMinY = y;
            if (x > fMaxX) fMaxX = x;
            if (y > fMaxY) fMaxY = y;
          });
          final props = feature['properties'] ?? {};
          final isDesk = props['workspaceType'] == 'Desk';
          if (isDesk && fMinX != double.infinity && (fMaxX - fMinX) > 0) {
            totalDeskWidth += (fMaxX - fMinX);
            deskCount++;
          }
        }

        if (minX == double.infinity) {
          return const Center(child: Text("Coordonnées de la carte invalides"));
        }

        // Target desk width is ~72.0px. Scale coordinates proportionally so desks are large
        // and spacious (~68-76px wide, ~44-52px high) and never collide with neighbors.
        final avgDeskWidth = deskCount > 0 ? (totalDeskWidth / deskCount) : 32.0;
        final coordScale = avgDeskWidth > 0 ? (72.0 / avgDeskWidth).clamp(1.0, 3.5) : 2.0;

        const padding = 40.0;

        // ── 3. Build the feature widgets ─────────────────────────────────────
        final Map<String, _RoomBounds> roomBounds = {};
        final List<Widget> featureWidgets = [];

        // Build quick lookup maps
        final wsMap = {
          for (var w in widget.workspaces)
            if (w['id'] != null) w['id'].toString().toLowerCase(): w
        };
        final allWsMap = {
          for (var w in widget.allWorkspaces)
            if (w['id'] != null) w['id'].toString().toLowerCase(): w
        };

        for (final feature in widget.features) {
          final props = feature['properties'] ?? {};
          final wsId = (props['workspaceId']?.toString() ??
                  props['roomId']?.toString() ??
                  props['id']?.toString())
              ?.toLowerCase();
          final isDesk = props['workspaceType'] == 'Desk';
          final workspace = wsMap[wsId];
          final isBookable = workspace != null;
          final isSelected = widget.selectedWorkspaceId != null &&
              widget.selectedWorkspaceId?.toLowerCase() == wsId;

          final coords = feature['geometry']?['coordinates'] as List?;
          if (coords == null || coords.isEmpty) continue;

          double fMinX = double.infinity, fMinY = double.infinity;
          double fMaxX = double.negativeInfinity, fMaxY = double.negativeInfinity;
          _extractBounds(coords, (x, y) {
            if (x < fMinX) fMinX = x;
            if (y < fMinY) fMinY = y;
            if (x > fMaxX) fMaxX = x;
            if (y > fMaxY) fMaxY = y;
          });
          if (fMinX == double.infinity) continue;

          final left = (fMinX - minX) * coordScale + padding;
          final top = (fMinY - minY) * coordScale + padding;
          final width = (fMaxX - fMinX) * coordScale;
          final height = (fMaxY - fMinY) * coordScale;

          // Check occupant and favorite status (Milestone M3)
          final occupant = widget.occupants[wsId] ??
              (wsId != null ? widget.occupants[wsId.toLowerCase()] : null);

          // For desks: ensure positive padding/gap between neighboring desks so they never collide
          double renderWidth = width;
          double renderHeight = height;
          double renderLeft = left;
          double renderTop = top;

          if (isDesk || isBookable || occupant != null) {
            const deskGap = 1.5;
            if (width > deskGap * 2 && height > deskGap * 2) {
              renderWidth = width - deskGap * 2;
              renderHeight = height - deskGap * 2;
              renderLeft = left + deskGap;
              renderTop = top + deskGap;
            }
          }

          // Label & room determination
          String label = '';
          String? roomName;
          final propName = props['name']?.toString() ??
              props['title']?.toString() ??
              props['label']?.toString() ??
              props['workspaceName']?.toString() ??
              props['text']?.toString() ??
              props['description']?.toString();

          if (workspace != null) {
            final name = workspace['name']?.toString() ?? propName ?? '';
            final parts = name.split('-');
            label = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : name;
            final lastDash = name.lastIndexOf('-');
            if (lastDash > 0 && lastDash < name.length - 1) {
              final suffix = name.substring(lastDash + 1);
              roomName = (suffix.length <= 4 && !suffix.contains(' '))
                  ? name.substring(0, lastDash)
                  : name;
            } else {
              roomName = name;
            }
            if (roomName.isNotEmpty) {
              roomBounds
                  .putIfAbsent(roomName, () => _RoomBounds())
                  .addRect(renderLeft, renderTop, renderWidth, renderHeight);
            }
          } else if (!isDesk) {
            final roomWs = wsId != null ? allWsMap[wsId] : null;
            label = roomWs?['name']?.toString() ??
                propName ??
                (wsId != null ? 'Err: $wsId' : '');
          }

          // Point features (no area) → just a label
          if (width == 0 && height == 0) {
            if (label.isEmpty) continue;
            featureWidgets.add(Positioned(
              left: left - 50,
              top: top - 10,
              width: 100,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ));
            continue;
          }

          final isMe = occupant != null && occupant.isMe;

          final isFavorite = (occupant != null && !isMe) &&
              ((occupant.occupantId != null &&
                      (widget.favoriteIds.contains(occupant.occupantId) ||
                       widget.favoriteIds.contains(occupant.occupantId!.toLowerCase()))) ||
               widget.favoriteNamesNormalized.contains(occupant.occupantName.trim().toLowerCase()) ||
               (wsId != null &&
                   (widget.favoriteWorkspaceIds.contains(wsId) ||
                    widget.favoriteWorkspaceIds.contains(wsId.toLowerCase()))));

          final isDark = Theme.of(context).brightness == Brightness.dark;

          Color bgColor;
          Color textColor;
          Color borderColor;
          double borderWidth;
          List<BoxShadow>? boxShadow;

          if (isSelected) {
            bgColor = Theme.of(context).colorScheme.primary;
            textColor = Theme.of(context).colorScheme.onPrimary;
            borderColor = Theme.of(context).colorScheme.onPrimary;
            borderWidth = 2.5;
            boxShadow = [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                blurRadius: 6.0,
                spreadRadius: 1.0,
              ),
            ];
          } else if (isFavorite) {
            // Frank / Bold Gold/Amber for favorite colleague
            bgColor = isDark ? const Color(0xFFD97706) : const Color(0xFFFBBF24);
            textColor = isDark ? Colors.white : const Color(0xFF78350F);
            borderColor = isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);
            borderWidth = 2.5;
            boxShadow = [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.45 : 0.55),
                blurRadius: 6.0,
                spreadRadius: 1.5,
              ),
            ];
          } else if (isMe) {
            // Frank / Bold Green for personal desk
            bgColor = isDark ? const Color(0xFF15803D) : const Color(0xFF22C55E);
            textColor = Colors.white;
            borderColor = isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534);
            borderWidth = 2.5;
            boxShadow = [
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: isDark ? 0.4 : 0.5),
                blurRadius: 6.0,
                spreadRadius: 1.5,
              ),
            ];
          } else if (occupant != null) {
            // Frank / Bold Gray for other occupied desks
            bgColor = isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1);
            textColor = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1E293B);
            borderColor = isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8);
            borderWidth = 1.5;
          } else if (isBookable) {
            // Frank / Clear Blue for available/bookable desks
            bgColor = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE);
            textColor = isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E40AF);
            borderColor = isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD);
            borderWidth = 1.5;
          } else {
            bgColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
            textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
            borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
            borderWidth = 1.0;
          }

          // Room dimming when a room filter is active
          final isRoomDimmed = widget.focusedRoom != null &&
              widget.focusedRoom!.isNotEmpty &&
              roomName != null &&
              roomName.toLowerCase() != widget.focusedRoom!.toLowerCase();

          // Build clean desk content: prominent occupant name in "LASTNAME F." format (no icons)
          Widget deskContent;
          if (occupant != null) {
            final displayName = occupant.formattedDisplayName.isNotEmpty
                ? occupant.formattedDisplayName
                : occupant.occupantName.toUpperCase();
            deskContent = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      displayName,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9,
                            color: textColor.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );

          } else {
            deskContent = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          Widget deskWidget = GestureDetector(
            onTap: () {
              if (occupant != null && widget.onOccupantTapped != null) {
                final wsData = workspace ?? {
                  'id': wsId,
                  'name': label,
                  'roomName': ?roomName,
                };
                widget.onOccupantTapped!(wsData, occupant);
              } else if (isBookable) {
                widget.onSelected(workspace);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: boxShadow,
              ),
              alignment: Alignment.center,
              child: deskContent,
            ),
          );

          if (isRoomDimmed) {
            deskWidget = Opacity(opacity: 0.25, child: deskWidget);
          }

          featureWidgets.add(Positioned(
            left: renderLeft,
            top: renderTop,
            width: renderWidth,
            height: renderHeight,
            child: deskWidget,
          ));
        }

        _savedRoomBounds = roomBounds;

        // ── 4. Room group outlines ────────────────────────────────────────────
        final List<Widget> roomWidgets = [];
        roomBounds.forEach((name, bounds) {
          if (bounds.minX == double.infinity) return;
          final isRoomDimmed = widget.focusedRoom != null &&
              widget.focusedRoom!.isNotEmpty &&
              name.toLowerCase() != widget.focusedRoom!.toLowerCase();

          Widget roomBox = Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1.5),
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context)
                  .colorScheme
                  .surface
                  .withValues(alpha: 0.55),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 2, left: 4, right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );

          if (isRoomDimmed) {
            roomBox = Opacity(opacity: 0.25, child: roomBox);
          }

          final rLeft = bounds.minX - 16.0;
          final rTop = bounds.minY - 28.0; // room header space
          final rWidth = (bounds.maxX - bounds.minX) + 32.0;
          final rHeight = (bounds.maxY - bounds.minY) + 44.0;

          roomWidgets.add(Positioned(
            left: rLeft,
            top: rTop,
            width: rWidth,
            height: rHeight,
            child: roomBox,
          ));
        });

        // ── 5. Dynamically expand total bounding box across ALL rooms and desks
        double calculatedMaxX = (maxX - minX) * coordScale + padding * 2;
        double calculatedMaxY = (maxY - minY) * coordScale + padding * 2;

        for (final bounds in roomBounds.values) {
          if (bounds.minX == double.infinity) continue;
          final rightEdge = bounds.maxX + 16.0 + padding;
          final bottomEdge = bounds.maxY + 16.0 + padding;
          if (rightEdge > calculatedMaxX) calculatedMaxX = rightEdge;
          if (bottomEdge > calculatedMaxY) calculatedMaxY = bottomEdge;
        }

        // Strictly equal to the canvas bounds without inflating height to the entire screen
        final mapWidth = calculatedMaxX + 24.0;
        final mapHeight = calculatedMaxY + 24.0;
        _lastMapWidth = mapWidth;
        _lastMapHeight = mapHeight;

        // Locate selected or default workspace rect, personal desk, or enclosing room
        Rect? targetRect;
        String? targetDeskId = (widget.selectedWorkspaceId ?? widget.defaultWorkspaceId)?.toLowerCase();
        if (targetDeskId == null || targetDeskId.isEmpty) {
          for (final entry in widget.occupants.entries) {
            if (entry.value.isMe) {
              targetDeskId = entry.key.toLowerCase();
              break;
            }
          }
        }

        if (targetDeskId != null && targetDeskId.isNotEmpty) {
          // 1. Identify desk name and enclosing room
          final targetWs = wsMap[targetDeskId] ?? allWsMap[targetDeskId];
          String? deskName = targetWs?['name']?.toString();
          String? targetRoomName;

          if (deskName == null) {
            for (final feature in widget.features) {
              final props = feature['properties'] ?? {};
              final wsId = (props['workspaceId']?.toString() ??
                      props['roomId']?.toString() ??
                      props['id']?.toString())
                  ?.toLowerCase();
              if (wsId == targetDeskId) {
                deskName = props['name']?.toString() ?? props['workspaceName']?.toString();
                break;
              }
            }
          }

          if (deskName != null) {
            final lastDash = deskName.lastIndexOf('-');
            if (lastDash > 0 && lastDash < deskName.length - 1) {
              final suffix = deskName.substring(lastDash + 1);
              targetRoomName = (suffix.length <= 4 && !suffix.contains(' '))
                  ? deskName.substring(0, lastDash)
                  : deskName;
            } else {
              targetRoomName = deskName;
            }
          }

          // 2. Prioritize centering directly on the enclosing ROOM bounds
          if (targetRoomName != null && roomBounds.containsKey(targetRoomName)) {
            final bounds = roomBounds[targetRoomName]!;
            if (bounds.minX != double.infinity) {
              targetRect = Rect.fromLTRB(
                bounds.minX - 16.0,
                bounds.minY - 28.0,
                bounds.maxX + 16.0,
                bounds.maxY + 16.0,
              );
            }
          }

          // 3. Fallback to individual desk bounds if room bounds not found
          if (targetRect == null) {
            for (final feature in widget.features) {
              final props = feature['properties'] ?? {};
              final wsId = (props['workspaceId']?.toString() ??
                      props['roomId']?.toString() ??
                      props['id']?.toString())
                  ?.toLowerCase();
              if (wsId == targetDeskId) {
                final coords = feature['geometry']?['coordinates'] as List?;
                if (coords != null && coords.isNotEmpty) {
                  double fMinX = double.infinity, fMinY = double.infinity;
                  double fMaxX = double.negativeInfinity, fMaxY = double.negativeInfinity;
                  _extractBounds(coords, (x, y) {
                    if (x < fMinX) fMinX = x;
                    if (y < fMinY) fMinY = y;
                    if (x > fMaxX) fMaxX = x;
                    if (y > fMaxY) fMaxY = y;
                  });
                  if (fMinX != double.infinity) {
                    targetRect = Rect.fromLTWH(
                      (fMinX - minX) * coordScale + padding,
                      (fMinY - minY) * coordScale + padding,
                      (fMaxX - fMinX) * coordScale,
                      (fMaxY - fMinY) * coordScale,
                    );
                  }
                }
                break;
              }
            }
          }
        }

        // Initialize transformation controller immediately on first layout
        final currentSize = Size(viewW, viewH);
        if (viewW > 0 && viewH > 0 && mapWidth > 0 && mapHeight > 0) {
          if (!_isInitialTransformSet) {
            _isInitialTransformSet = true;
            _lastViewportSize = currentSize;
            if (widget.focusedRoom != null && widget.focusedRoom!.isNotEmpty) {
              _handleFocusedRoomChanged();
            } else {
              _initTransform(viewW, viewH, mapWidth, mapHeight, targetRect);
            }
          } else if (_lastViewportSize != currentSize) {
            _lastViewportSize = currentSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (widget.focusedRoom != null && widget.focusedRoom!.isNotEmpty) {
                _handleFocusedRoomChanged();
              } else {
                _initTransform(viewW, viewH, mapWidth, mapHeight, targetRect);
              }
            });
          }
        }

        // ── 6. InteractiveViewer wrapping the positioned stack ────────────────
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.1,
                maxScale: 5.0,
                child: SizedBox(
                  width: mapWidth,
                  height: mapHeight,
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    child: Stack(
                      children: [...roomWidgets, ...featureWidgets],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: "zoomIn",
                    onPressed: _zoomIn,
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: "zoomOut",
                    onPressed: _zoomOut,
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
