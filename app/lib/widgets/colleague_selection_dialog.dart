import 'dart:async';
import 'package:flutter/material.dart';
import '../models/colleague.dart';
import '../storage_service.dart';
import '../api_service.dart';

/// Modal dialog allowing users to pick a colleague for desk reservation.
/// Features local favorites filtering, debounced remote directory search,
/// star toggling, and a confirmation prompt before reservation.
class ColleagueSelectionDialog extends StatefulWidget {
  final String date;
  final String? deskName;
  final StorageService? storageService;
  final RoomzApiService? apiService;
  final ValueChanged<Colleague>? onColleagueSelected;
  final bool isManagementMode;

  const ColleagueSelectionDialog({
    super.key,
    required this.date,
    this.deskName,
    this.storageService,
    this.apiService,
    this.onColleagueSelected,
    this.isManagementMode = false,
  });

  @override
  State<ColleagueSelectionDialog> createState() => _ColleagueSelectionDialogState();
}

class _ColleagueSelectionDialogState extends State<ColleagueSelectionDialog> {
  late final StorageService _storage = widget.storageService ?? StorageService();
  late final RoomzApiService _api = widget.apiService ?? RoomzApiService();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Colleague> _favorites = [];
  List<Colleague> _filteredFavorites = [];
  List<Colleague> _remoteResults = [];

  bool _isLoadingFavorites = true;
  bool _isRemoteSearching = false;
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoadingFavorites = true);
    try {
      final favs = await _storage.getFavoriteColleagues();
      if (mounted && favs.isNotEmpty) {
        setState(() {
          _favorites = favs;
          _filteredFavorites = List.from(favs);
        });
      }

      // Query remote API for favorites (Requirement Bug 1 Fix)
      String? token = await _api.refreshMyToken();
      token ??= await _storage.getRefreshToken();
      if (token != null && token.isNotEmpty) {
        final remoteFavs = await _api.getFavorites(token);
        if (mounted && remoteFavs.isNotEmpty) {
          final Map<String, Colleague> map = {};
          for (final f in _favorites) {
            final key = f.id.isNotEmpty ? f.id : (f.email.isNotEmpty ? f.email : f.name);
            map[key] = f;
          }
          for (final rf in remoteFavs) {
            final key = rf.id.isNotEmpty ? rf.id : (rf.email.isNotEmpty ? rf.email : rf.name);
            if (!map.containsKey(key)) {
              final newFav = rf.copyWith(isFavorite: true);
              map[key] = newFav;
              await _storage.addFavoriteColleague(newFav);
            }
          }
          final merged = map.values.toList();
          setState(() {
            _favorites = merged;
            _filteredFavorites = _searchQuery.isEmpty
                ? List.from(merged)
                : _favorites.where((c) {
                    final qLower = _searchQuery.toLowerCase();
                    return c.name.toLowerCase().contains(qLower) ||
                        c.email.toLowerCase().contains(qLower);
                  }).toList();
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingFavorites = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _searchQuery) return;
    _searchQuery = query;

    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _filteredFavorites = List.from(_favorites);
        _remoteResults = [];
        _isRemoteSearching = false;
      });
      return;
    }

    // 1. Instant local filter
    final qLower = query.toLowerCase();
    final localMatches = _favorites.where((c) {
      final nameMatch = c.name.toLowerCase().contains(qLower);
      final emailMatch = c.email.toLowerCase().contains(qLower);
      return nameMatch || emailMatch;
    }).toList();

    setState(() {
      _filteredFavorites = localMatches;
    });

    // 2. Debounced remote directory search (300ms)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performRemoteSearch(query);
    });
  }

  Future<void> _performRemoteSearch(String query) async {
    if (!mounted || query.isEmpty) return;

    setState(() => _isRemoteSearching = true);

    try {
      String? token = await _api.refreshMyToken();
      token ??= await _storage.getRefreshToken();
      if (token != null && token.isNotEmpty) {
        final results = await _api.searchColleagues(token, query);
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _remoteResults = results;
            _isRemoteSearching = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isRemoteSearching = false);
  }

  bool _isColleagueFavorite(Colleague colleague) {
    return _favorites.any((c) =>
        (colleague.id.isNotEmpty && c.id == colleague.id) ||
        (colleague.email.isNotEmpty && c.email.isNotEmpty && c.email.toLowerCase() == colleague.email.toLowerCase()) ||
        (colleague.name.isNotEmpty && c.name.isNotEmpty && c.name.toLowerCase() == colleague.name.toLowerCase()));
  }

  Future<void> _toggleFavorite(Colleague colleague) async {
    final isFav = _isColleagueFavorite(colleague);
    String? token = await _api.refreshMyToken();
    token ??= await _storage.getRefreshToken();

    // Find existing favorite record if present to retrieve its favoriteId
    final existingFav = _favorites.cast<Colleague?>().firstWhere(
      (c) =>
          c != null &&
          ((colleague.id.isNotEmpty && c.id == colleague.id) ||
           (colleague.email.isNotEmpty && c.email.isNotEmpty && c.email.toLowerCase() == colleague.email.toLowerCase()) ||
           (colleague.name.isNotEmpty && c.name.isNotEmpty && c.name.toLowerCase() == colleague.name.toLowerCase())),
      orElse: () => null,
    );

    if (isFav) {
      final deleteTargetId = existingFav?.favoriteId ?? colleague.favoriteId ?? colleague.id;
      if (token != null && token.isNotEmpty && deleteTargetId.isNotEmpty) {
        await _api.deleteFavorite(token, deleteTargetId);
      }
      if (colleague.id.isNotEmpty) {
        await _storage.removeFavoriteColleague(colleague.id);
      }
      if (existingFav != null && existingFav.id.isNotEmpty && existingFav.id != colleague.id) {
        await _storage.removeFavoriteColleague(existingFav.id);
      }
      if (colleague.email.isNotEmpty) {
        await _storage.removeFavoriteColleague(colleague.email);
      }
      await _storage.removeFavoriteColleague(colleague.name);
      _favorites.removeWhere((c) =>
          (colleague.id.isNotEmpty && c.id == colleague.id) ||
          (existingFav != null && existingFav.id.isNotEmpty && c.id == existingFav.id) ||
          (colleague.email.isNotEmpty && c.email.isNotEmpty && c.email.toLowerCase() == colleague.email.toLowerCase()) ||
          (colleague.name.isNotEmpty && c.name.isNotEmpty && c.name.toLowerCase() == colleague.name.toLowerCase()));
    } else {
      String? newFavId;
      if (token != null && token.isNotEmpty && colleague.id.isNotEmpty) {
        newFavId = await _api.addFavoriteWithId(token, colleague.id);
      }
      final updated = Colleague(
        id: colleague.id,
        name: colleague.name,
        email: colleague.email,
        isFavorite: true,
        deskName: colleague.deskName,
        roomName: colleague.roomName,
        avatarUrl: colleague.avatarUrl,
        favoriteId: newFavId ?? colleague.favoriteId,
      );
      await _storage.addFavoriteColleague(updated);
      _favorites.add(updated);
    }

    if (_searchQuery.isNotEmpty) {
      final qLower = _searchQuery.toLowerCase();
      _filteredFavorites = _favorites.where((c) {
        return c.name.toLowerCase().contains(qLower) ||
            c.email.toLowerCase().contains(qLower);
      }).toList();
    } else {
      _filteredFavorites = List.from(_favorites);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showAddColleagueDialog(BuildContext context, {String initialName = ''}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: initialName);
    final emailCtrl = TextEditingController();
    bool saveAsFavorite = true;

    final created = await showDialog<Colleague>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.person_add_alt_1_rounded,
                      color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Nouveau collègue',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Renseignez le nom et l\'email pour effectuer la réservation au nom de ce collègue.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom et prénom *',
                          hintText: 'Ex: Marie Curie',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Veuillez saisir un nom';
                          }
                          if (value.trim().length < 2) {
                            return 'Le nom doit comporter au moins 2 caractères';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Adresse email *',
                          hintText: 'Ex: marie.curie@entreprise.fr',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "L'adresse email est requise";
                          }
                          final email = value.trim();
                          final emailRegex = RegExp(r'^[\w\.\-]+@[\w\.\-]+\.[a-zA-Z]{2,}$');
                          if (!emailRegex.hasMatch(email)) {
                            return 'Veuillez saisir une adresse email valide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: saveAsFavorite,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ajouter à mes collègues favoris',
                            style: TextStyle(fontSize: 13)),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setDialogState(() {
                            saveAsFavorite = val ?? true;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ANNULER'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      final email = emailCtrl.text.trim();
                      final name = nameCtrl.text.trim();
                      final id = 'ext_${DateTime.now().millisecondsSinceEpoch}';
                      final colleague = Colleague(
                        id: id,
                        name: name,
                        email: email,
                        isFavorite: saveAsFavorite,
                      );
                      Navigator.pop(ctx, colleague);
                    }
                  },
                  child: const Text('CONTINUER'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      if (created.isFavorite) {
        await _toggleFavorite(created);
      }
      if (!widget.isManagementMode) {
        _onColleagueTapped(created);
      }
    }
  }

  Future<void> _onColleagueTapped(Colleague colleague) async {
    if (widget.isManagementMode) {
      await _toggleFavorite(colleague);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('Confirmer la réservation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Voulez-vous réserver ce bureau pour ce collègue ?'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 18, color: Colors.purple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(colleague.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ],
                  ),
                  if (colleague.email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(colleague.email,
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('Date : ${widget.date}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (widget.deskName != null && widget.deskName!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.desk, size: 16, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text('Bureau : ${widget.deskName}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRMER'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.onColleagueSelected?.call(colleague);
      Navigator.of(context).pop(colleague);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: (MediaQuery.of(context).size.height * 0.85).clamp(300.0, 620.0),
          minWidth: 280,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.isManagementMode
                          ? (isDark ? Colors.amber.shade900.withValues(alpha: 0.4) : Colors.amber.shade50)
                          : (isDark ? Colors.purple.shade900.withValues(alpha: 0.4) : Colors.purple.shade50),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isManagementMode ? Icons.star_rounded : Icons.group_add_outlined,
                      color: widget.isManagementMode
                          ? (isDark ? Colors.amber.shade300 : Colors.amber.shade800)
                          : (isDark ? Colors.purple.shade300 : Colors.purple.shade800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isManagementMode ? 'Mes collègues favoris' : 'Réserver pour un collègue',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.isManagementMode
                              ? 'Recherchez et gérez vos collègues favoris'
                              : '${widget.date}${widget.deskName != null ? ' • ${widget.deskName}' : ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar
              TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  hintText: 'Rechercher un collègue...',
                  hintStyle: const TextStyle(fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : (_isRemoteSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Button to add outside colleague (Requirement Bug 2 & 3 Fix)
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(widget.isManagementMode ? 'Ajouter un collègue' : 'Nouveau collègue (hors liste)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showAddColleagueDialog(context, initialName: _searchQuery),
              ),
              const SizedBox(height: 8),

              // List Content
              Expanded(
                child: _buildListContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListContent() {
    if (_isLoadingFavorites) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasQuery = _searchQuery.isNotEmpty;

    if (!hasQuery) {
      // Display Favorites Only
      if (_favorites.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_outline_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text('Aucun collègue favori',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Recherchez un collègue par son nom ci-dessus\nou ajoutez un nouveau collègue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Ajouter un collègue'),
                onPressed: () => _showAddColleagueDialog(context),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        shrinkWrap: true,
        itemCount: _favorites.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final colleague = _favorites[index];
          return _buildColleagueTile(colleague, isFavorite: true);
        },
      );
    }

    // Query active: combine filtered favorites + remote directory results
    final totalResults = _filteredFavorites.length + _remoteResults.length;

    if (totalResults == 0 && _isRemoteSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Recherche dans l\'annuaire...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (totalResults == 0 && !_isRemoteSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Aucun résultat pour « $_searchQuery »',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text('Ajouter « $_searchQuery » et réserver'),
              onPressed: () => _showAddColleagueDialog(context, initialName: _searchQuery),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (_filteredFavorites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 4.0),
            child: Text('Favoris (${_filteredFavorites.length})',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          ..._filteredFavorites.map((c) => _buildColleagueTile(c, isFavorite: _isColleagueFavorite(c))),
        ],
        if (_remoteResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 4.0),
            child: Text('Résultats de recherche (${_remoteResults.where((c) => !_isColleagueFavorite(c)).length})',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600)),
          ),
          ..._remoteResults.where((c) => !_isColleagueFavorite(c)).map((c) => _buildColleagueTile(c, isFavorite: false)),
        ],
      ],
    );
  }

  Widget _buildColleagueTile(Colleague colleague, {required bool isFavorite}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Text(colleague.initials,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      title: Text(colleague.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: colleague.email.isNotEmpty
          ? Text(colleague.email,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing: IconButton(
        icon: Icon(
          isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          color: isFavorite ? Colors.amber : Colors.grey,
        ),
        tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
        onPressed: () => _toggleFavorite(colleague),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () => _onColleagueTapped(colleague),
    );
  }
}
