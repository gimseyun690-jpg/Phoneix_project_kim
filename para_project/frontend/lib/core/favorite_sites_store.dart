import 'package:shared_preferences/shared_preferences.dart';

enum FavoriteSiteType { registered, imported }

class FavoriteSiteEntry {
  const FavoriteSiteEntry.registered(this.registeredSiteId)
      : type = FavoriteSiteType.registered,
        importedSiteSourceId = null;

  const FavoriteSiteEntry.imported(this.importedSiteSourceId)
      : type = FavoriteSiteType.imported,
        registeredSiteId = null;

  final FavoriteSiteType type;
  final int? registeredSiteId;
  final String? importedSiteSourceId;

  String get storageKey => switch (type) {
        FavoriteSiteType.registered => 'registered:$registeredSiteId',
        FavoriteSiteType.imported => 'imported:$importedSiteSourceId',
      };

  static FavoriteSiteEntry? fromStorageKey(String value) {
    if (value.startsWith('registered:')) {
      final rawId = value.substring('registered:'.length);
      final siteId = int.tryParse(rawId);
      if (siteId == null) {
        return null;
      }
      return FavoriteSiteEntry.registered(siteId);
    }
    if (value.startsWith('imported:')) {
      final sourceId = value.substring('imported:'.length).trim();
      if (sourceId.isEmpty) {
        return null;
      }
      return FavoriteSiteEntry.imported(sourceId);
    }
    return null;
  }
}

class FavoriteSitesStore {
  static const _favoritesKey = 'favorite_sites_v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    _preferences ??= await SharedPreferences.getInstance();
    return _preferences!;
  }

  Future<List<FavoriteSiteEntry>> loadFavorites() async {
    final prefs = await _prefs();
    final rawValues = prefs.getStringList(_favoritesKey) ?? const <String>[];
    return rawValues
        .map(FavoriteSiteEntry.fromStorageKey)
        .whereType<FavoriteSiteEntry>()
        .toList(growable: false);
  }

  Future<List<FavoriteSiteEntry>> toggle(FavoriteSiteEntry entry) async {
    final favorites = (await loadFavorites()).toList(growable: true);
    final existingIndex = favorites.indexWhere(
      (item) => item.storageKey == entry.storageKey,
    );
    if (existingIndex >= 0) {
      favorites.removeAt(existingIndex);
    } else {
      favorites.insert(0, entry);
    }
    await _saveFavorites(favorites);
    return favorites;
  }

  Future<void> _saveFavorites(List<FavoriteSiteEntry> favorites) async {
    final prefs = await _prefs();
    await prefs.setStringList(
      _favoritesKey,
      favorites.map((item) => item.storageKey).toList(growable: false),
    );
  }
}
