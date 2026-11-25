import 'package:flutter/material.dart';
import '../models/desk_occupant.dart';
import 'mini_map_overlay.dart';
import 'workspace_map/desk_marker_widget.dart';
import 'workspace_map/floor_background_painter.dart';
import 'workspace_map/floor_geometry_cache.dart';
import 'workspace_map/map_camera_helper.dart';
import 'workspace_map/room_occupancy_stats.dart';

export 'workspace_map/room_occupancy_stats.dart' show RoomOccupancyStats;

class _CameraFramingRequest {
  final double viewW;
  final double viewH;
  final double mapWidth;
  final double mapHeight;
  final Rect? targetRect;

  const _CameraFramingRequest({
    required this.viewW,
    required this.viewH,
    required this.mapWidth,
    required this.mapHeight,
    required this.targetRect,
  });
}

class WorkspaceMapViewer extends StatefulWidget {
  final List<Map<String, dynamic>> features;
  final List<Map<String, dynamic>> workspaces;
  final List<Map<String, dynamic>> allWorkspaces;
  final String? selectedWorkspaceId;
  final String? defaultWorkspaceId;
  final double? containerHeight;
  final void Function(Map<String, dynamic> workspace) onSelected;

  // Milestone M3 Extensions
  final Map<String, DeskOccupant> occupants;
  final Set<String> favoriteIds;
  final Set<String> favoriteNamesNormalized;
  final Set<String> favoriteWorkspaceIds;
  final void Function(Map<String, dynamic> workspace, DeskOccupant occupant)?
      onOccupantTapped;
  final String? focusedRoom;
  final String? focusedWorkspaceId;
  final Set<String> pendingWorkspaceIds;
  final VoidCallback? onBackgroundTapped;
  final bool showMiniMap;
  final TransformationController? controller;

  // Evolution #4: Coloration thermique des pièces
  final bool showRoomHeatmap;
  final bool showHeatmapToggleChip;
  final ValueChanged<bool>? onToggleHeatmap;
  final Widget? bottomBar;

  static const Color heatmapGreen = RoomOccupancyStats.heatmapGreen;
  static const Color heatmapOrange = RoomOccupancyStats.heatmapOrange;
  static const Color heatmapRed = RoomOccupancyStats.heatmapRed;
  static const Color heatmapSlate = RoomOccupancyStats.heatmapSlate;

  /// Calcule le taux d'occupation : bureaux_occupés / total_bureaux
  static double calculateOccupancyRatio({
    required int occupiedDesks,
    required int totalDesks,
  }) =>
      RoomOccupancyStats.calculateOccupancyRatio(
        occupiedDesks: occupiedDesks,
        totalDesks: totalDesks,
      );

  /// Calcule le ratio de places libres : places_libres / total_bureaux
  static double calculateFreeRatio({
    required int occupiedDesks,
    required int totalDesks,
  }) =>
      RoomOccupancyStats.calculateFreeRatio(
        occupiedDesks: occupiedDesks,
        totalDesks: totalDesks,
      );

  /// Retourne la couleur thermique pastel adaptée à l'occupation de la salle :
  /// - 🟢 Verte pastel très douce (0x1822C55E) si > 65% de places libres (très calme)
  /// - 🟡 Orangée pastel douce (0x18F59E0B) si 35% à 65% libre (modérée)
  /// - 🔴 Feutrée / ardoise douce (0x18EF4444) si < 35% de places libres (presque pleine)
  static Color getRoomHeatmapColor({
    required int occupiedDesks,
    required int totalDesks,
    bool isDark = false,
  }) =>
      RoomOccupancyStats.getRoomHeatmapColor(
        occupiedDesks: occupiedDesks,
        totalDesks: totalDesks,
        isDark: isDark,
      );

  const WorkspaceMapViewer({
    super.key,
    required this.features,
    required this.workspaces,
    this.allWorkspaces = const <Map<String, dynamic>>[],
    this.selectedWorkspaceId,
    this.defaultWorkspaceId,
    this.containerHeight,
    required this.onSelected,
    this.occupants = const <String, DeskOccupant>{},
    this.favoriteIds = const <String>{},
    this.favoriteNamesNormalized = const <String>{},
    this.favoriteWorkspaceIds = const <String>{},
    this.onOccupantTapped,
    this.focusedRoom,
    this.focusedWorkspaceId,
    this.pendingWorkspaceIds = const <String>{},
    this.onBackgroundTapped,
    this.showMiniMap = true,
    this.controller,
    this.showRoomHeatmap = true,
    this.showHeatmapToggleChip = true,
    this.onToggleHeatmap,
    this.bottomBar,
  });

  @override
  State<WorkspaceMapViewer> createState() => WorkspaceMapViewerState();
}

class WorkspaceMapViewerState extends State<WorkspaceMapViewer> {
  TransformationController? _internalController;
  TransformationController get controller =>
      widget.controller ?? _internalController!;
  TransformationController get _controller => controller;

  final FloorGeometryCache _geometryCache = FloorGeometryCache();

  Size? _lastViewportSize;
  Map<String, RoomBounds> _savedRoomBounds = const <String, RoomBounds>{};
  Map<String, Rect> _savedDeskBounds = const <String, Rect>{};
  Map<String, String> _savedDeskRooms = const <String, String>{};
  Map<String, RoomOccupancyStats> _savedRoomOccupancy =
      <String, RoomOccupancyStats>{};
  bool _isInitialTransformSet = false;
  bool _isFramingCallbackScheduled = false;
  _CameraFramingRequest? _pendingFraming;
  late bool _showRoomHeatmap;

  /// Statistiques d'occupation de chaque pièce calculées sur le plan
  Map<String, RoomOccupancyStats> get roomOccupancy => _savedRoomOccupancy;

  /// Indique si la coloration thermique des pièces est active
  bool get showRoomHeatmap => _showRoomHeatmap;

  /// Bascule la coloration thermique des pièces
  void toggleHeatmap([bool? value]) {
    setState(() {
      _showRoomHeatmap = value ?? !_showRoomHeatmap;
    });
    widget.onToggleHeatmap?.call(_showRoomHeatmap);
  }

  @override
  void initState() {
    super.initState();
    _showRoomHeatmap = widget.showRoomHeatmap;
    if (widget.controller == null) {
      _internalController = TransformationController();
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkspaceMapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller == null && _internalController == null) {
        _internalController = TransformationController();
      } else if (widget.controller != null && _internalController != null) {
        _internalController!.dispose();
        _internalController = null;
      }
    }
    if (oldWidget.showRoomHeatmap != widget.showRoomHeatmap) {
      _showRoomHeatmap = widget.showRoomHeatmap;
    }
    if (oldWidget.features != widget.features) {
      _isInitialTransformSet = false;
      return;
    }
    if (oldWidget.focusedRoom != widget.focusedRoom) {
      _handleFocusedRoomChanged();
    }
    if (widget.focusedWorkspaceId != null &&
        widget.focusedWorkspaceId != oldWidget.focusedWorkspaceId) {
      _handleFocusedWorkspaceChanged();
    }
  }

  void _handleFocusedWorkspaceChanged() {
    final String? targetId = widget.focusedWorkspaceId;
    if (targetId == null || targetId.isEmpty) return;
    if (_lastViewportSize == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final String? currentId = widget.focusedWorkspaceId;
        if (currentId != null && currentId.isNotEmpty) {
          focusOnWorkspace(currentId);
        }
      });
      return;
    }
    focusOnWorkspace(targetId);
  }

  void focusOnWorkspace(String workspaceId) {
    final Size? viewport = _lastViewportSize;
    if (viewport == null) return;
    final Matrix4? nextMatrix = MapCameraHelper.computeFocusOnWorkspace(
      workspaceId: workspaceId,
      viewport: viewport,
      currentMatrix: _controller.value,
      savedDeskBounds: _savedDeskBounds,
      savedDeskRooms: _savedDeskRooms,
      savedRoomBounds: _savedRoomBounds,
    );
    if (nextMatrix != null) {
      _controller.value = nextMatrix;
    }
  }

  void _handleFocusedRoomChanged() {
    final Size? viewport = _lastViewportSize;
    final String? focused = widget.focusedRoom;
    if (viewport == null || focused == null || focused.isEmpty) return;
    final Matrix4? nextMatrix = MapCameraHelper.computeFocusedRoomMatrix(
      focusedRoom: focused,
      viewport: viewport,
      savedRoomBounds: _savedRoomBounds,
    );
    if (nextMatrix != null) {
      _controller.value = nextMatrix;
    }
  }

  void _zoomIn() {
    final Matrix4 matrix = _controller.value.clone();
    matrix.scaleByDouble(1.3, 1.3, 1.0, 1.0);
    _controller.value = matrix;
  }

  void _zoomOut() {
    final Matrix4 matrix = _controller.value.clone();
    matrix.scaleByDouble(0.77, 0.77, 1.0, 1.0);
    _controller.value = matrix;
  }

  void _scheduleCameraFraming(_CameraFramingRequest request) {
    _pendingFraming = request;
    if (_isFramingCallbackScheduled) return;
    _isFramingCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isFramingCallbackScheduled = false;
      if (!mounted) return;
      final _CameraFramingRequest? req = _pendingFraming;
      _pendingFraming = null;
      if (req == null) return;

      final String? focusedWs = widget.focusedWorkspaceId;
      final String? focusedRoom = widget.focusedRoom;
      if (focusedWs != null && focusedWs.isNotEmpty) {
        focusOnWorkspace(focusedWs);
      } else if (focusedRoom != null && focusedRoom.isNotEmpty) {
        _handleFocusedRoomChanged();
      } else {
        final Matrix4? initialMatrix = MapCameraHelper.computeInitialTransform(
          viewW: req.viewW,
          viewH: req.viewH,
          mapW: req.mapWidth,
          mapH: req.mapHeight,
          targetRect: req.targetRect,
        );
        if (initialMatrix != null) {
          _controller.value = initialMatrix;
        }
      }
    });
  }

  DeskOccupant? _findOccupant(ParsedFloorFeature feature) {
    for (final String key in feature.occupantLookupKeys) {
      final DeskOccupant? occ = widget.occupants[key];
      if (occ != null) return occ;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.features.isEmpty) {
      return const Center(child: Text('Aucun plan disponible'));
    }

    final FloorGeometrySnapshot snapshot = _geometryCache.resolve(
      features: widget.features,
      workspaces: widget.workspaces,
      allWorkspaces: widget.allWorkspaces,
    );

    if (!snapshot.hasValidBounds) {
      return const Center(child: Text('Coordonnées de la carte invalides'));
    }

    // Pré-calcul O(N) unique avant la boucle des postes
    bool hasMyConfirmedBooking = false;
    String? myDeskId;
    for (final MapEntry<String, DeskOccupant> entry
        in widget.occupants.entries) {
      if (entry.value.isMe) {
        hasMyConfirmedBooking = true;
        myDeskId = entry.key.toLowerCase();
        break;
      }
    }

    final String? selectedLower =
        widget.selectedWorkspaceId?.trim().isNotEmpty == true
            ? widget.selectedWorkspaceId!.toLowerCase()
            : null;
    final String? focusedRoomLower =
        widget.focusedRoom != null && widget.focusedRoom!.isNotEmpty
            ? widget.focusedRoom!.toLowerCase()
            : null;
    final bool checkPending =
        !hasMyConfirmedBooking && widget.pendingWorkspaceIds.isNotEmpty;

    final Map<String, int> roomOccupiedDesks = <String, int>{};
    final List<Widget> featureWidgets = <Widget>[];
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    for (final ParsedFloorFeature feature in snapshot.parsedFeatures) {
      final DeskOccupant? occupant = _findOccupant(feature);

      if (feature.countsInRoomStats &&
          occupant != null &&
          feature.roomName != null) {
        roomOccupiedDesks[feature.roomName!] =
            (roomOccupiedDesks[feature.roomName!] ?? 0) + 1;
      }

      if (feature.isPointFeature) {
        if (feature.label.isEmpty) continue;
        featureWidgets.add(
          Positioned(
            left: feature.left - 50,
            top: feature.top - 10,
            width: 100,
            child: Text(
              feature.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        continue;
      }

      final bool isInteractiveDesk =
          feature.isDesk || feature.isBookable || occupant != null;

      bool isSelected = false;
      if (selectedLower != null &&
          isInteractiveDesk &&
          feature.wsId != null &&
          feature.wsId!.trim().isNotEmpty) {
        for (final String key in feature.idLookupKeysLower) {
          if (key == selectedLower) {
            isSelected = true;
            break;
          }
        }
      }

      bool isPending = false;
      if (checkPending &&
          occupant == null &&
          (feature.isDesk || feature.isBookable) &&
          feature.wsId != null &&
          feature.wsId!.trim().isNotEmpty) {
        for (final String key in feature.idLookupKeysLower) {
          if (widget.pendingWorkspaceIds.contains(key)) {
            isPending = true;
            break;
          }
        }
      }

      final bool isMe = occupant != null && occupant.isMe;
      final bool isFavorite = (occupant != null && !isMe) &&
          ((occupant.occupantId != null &&
                  (widget.favoriteIds.contains(occupant.occupantId) ||
                      widget.favoriteIds
                          .contains(occupant.occupantId!.toLowerCase()))) ||
              widget.favoriteNamesNormalized
                  .contains(occupant.occupantName.trim().toLowerCase()) ||
              (feature.wsId != null &&
                  (widget.favoriteWorkspaceIds.contains(feature.wsId) ||
                      widget.favoriteWorkspaceIds
                          .contains(feature.wsId!.toLowerCase()))));

      final bool isRoomDimmed = focusedRoomLower != null &&
          feature.roomNameLower != null &&
          feature.roomNameLower != focusedRoomLower;

      VoidCallback? onTap;
      if (occupant != null && widget.onOccupantTapped != null) {
        onTap = () {
          final Map<String, dynamic> wsData = feature.workspace ??
              <String, dynamic>{
                'id': feature.wsId,
                'name': feature.label,
                'roomName': feature.roomName,
              };
          widget.onOccupantTapped!(wsData, occupant);
        };
      } else if (feature.isBookable) {
        onTap = () {
          widget.onSelected(feature.workspace!);
        };
      }

      featureWidgets.add(
        Positioned(
          left: feature.renderLeft,
          top: feature.renderTop,
          width: feature.renderWidth,
          height: feature.renderHeight,
          child: DeskMarkerWidget(
            label: feature.label,
            occupant: occupant,
            isSelected: isSelected,
            isMe: isMe,
            isPending: isPending,
            isFavorite: isFavorite,
            isBookable: feature.isBookable,
            isDimmed: isRoomDimmed,
            onTap: onTap,
          ),
        ),
      );
    }

    _savedRoomBounds = snapshot.roomBounds;
    _savedDeskBounds = snapshot.deskBounds;
    _savedDeskRooms = snapshot.deskRooms;
    _savedRoomOccupancy = <String, RoomOccupancyStats>{
      for (final ParsedRoomGeometry room in snapshot.rooms)
        room.name: RoomOccupancyStats(
          totalDesks: room.totalDesks,
          occupiedDesks: roomOccupiedDesks[room.name] ?? 0,
        ),
    };

    final List<Widget> roomWidgets = <Widget>[
      for (final ParsedRoomGeometry room in snapshot.rooms)
        Positioned(
          left: room.outerRect.left,
          top: room.outerRect.top,
          width: room.outerRect.width,
          height: room.outerRect.height,
          child: RoomBoxWidget(
            name: room.name,
            totalCount: room.totalDesks,
            occupiedCount: roomOccupiedDesks[room.name] ?? 0,
            showHeatmap: _showRoomHeatmap,
            isDimmed: focusedRoomLower != null &&
                room.nameLower != focusedRoomLower,
          ),
        ),
    ];

    final Rect? targetRect = MapCameraHelper.resolveInitialTargetRect(
      snapshot: snapshot,
      selectedWorkspaceId: widget.selectedWorkspaceId,
      defaultWorkspaceId: widget.defaultWorkspaceId,
      myDeskId: myDeskId,
    );
    final double mapWidth = snapshot.mapWidth;
    final double mapHeight = snapshot.mapHeight;
    final Color floorBgColor =
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewW = constraints.maxWidth;
        final double viewH = widget.containerHeight ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 450.0);

        final Size currentSize = Size(viewW, viewH);
        if (viewW > 0 && viewH > 0 && mapWidth > 0 && mapHeight > 0) {
          if (!_isInitialTransformSet || _lastViewportSize != currentSize) {
            _isInitialTransformSet = true;
            _lastViewportSize = currentSize;
            _scheduleCameraFraming(
              _CameraFramingRequest(
                viewW: viewW,
                viewH: viewH,
                mapWidth: mapWidth,
                mapHeight: mapHeight,
                targetRect: targetRect,
              ),
            );
          }
        }

        return Stack(
          children: <Widget>[
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onBackgroundTapped,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              isComplex: true,
                              willChange: false,
                              painter: FloorBackgroundPainter(
                                backgroundColor: floorBgColor,
                              ),
                            ),
                          ),
                        ),
                        ...roomWidgets,
                        ...featureWidgets,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showHeatmapToggleChip)
              Positioned(
                top: 12,
                left: 12,
                child: Material(
                  color: Colors.transparent,
                  child: FilterChip(
                    key: const ValueKey<String>('toggle_heatmap_chip'),
                    avatar: Icon(
                      Icons.thermostat_rounded,
                      size: 16,
                      color: _showRoomHeatmap
                          ? const Color(0xFFF59E0B)
                          : colorScheme.onSurfaceVariant,
                    ),
                    label: const Text(
                      'Thermique',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    selected: _showRoomHeatmap,
                    selectedColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.85),
                    onSelected: (bool val) {
                      toggleHeatmap(val);
                    },
                  ),
                ),
              ),
            if (widget.bottomBar != null) widget.bottomBar!,
            Positioned(
              bottom: 16,
              right: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FloatingActionButton.small(
                    heroTag: 'zoomIn',
                    onPressed: _zoomIn,
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoomOut',
                    onPressed: _zoomOut,
                    child: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
            if (widget.showMiniMap && mapWidth > 0 && mapHeight > 0)
              Positioned(
                bottom: 16,
                left: 16,
                child: RepaintBoundary(
                  child: MiniMapOverlay(
                    expansionAlignment: Alignment.bottomLeft,
                    transformationController: _controller,
                    viewportSize: Size(viewW, viewH),
                    mapSize: snapshot.mapSize,
                    rooms: snapshot.miniMapRooms,
                    desks: snapshot.miniMapDesks,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
