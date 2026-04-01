import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ParaglidingMapViewType { satellite, standard }

extension ParaglidingMapViewTypeLabel on ParaglidingMapViewType {
  String get storageValue => switch (this) {
        ParaglidingMapViewType.satellite => 'satellite',
        ParaglidingMapViewType.standard => 'standard',
      };

  String get label => switch (this) {
        ParaglidingMapViewType.satellite => '위성',
        ParaglidingMapViewType.standard => '일반',
      };

  String get urlTemplate => switch (this) {
        ParaglidingMapViewType.satellite =>
          'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        ParaglidingMapViewType.standard =>
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      };

  String get attributionText => switch (this) {
        ParaglidingMapViewType.satellite =>
          'Esri, Maxar, Earthstar Geographics',
        ParaglidingMapViewType.standard => 'OpenStreetMap contributors',
      };

  static ParaglidingMapViewType fromStorageValue(String? value) {
    return ParaglidingMapViewType.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => ParaglidingMapViewType.satellite,
    );
  }
}

class MapViewPreferenceStore {
  static const _storageKey = 'paragliding_map_view_type_v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    _preferences ??= await SharedPreferences.getInstance();
    return _preferences!;
  }

  Future<ParaglidingMapViewType> load() async {
    final prefs = await _prefs();
    return ParaglidingMapViewTypeLabel.fromStorageValue(
      prefs.getString(_storageKey),
    );
  }

  Future<void> save(ParaglidingMapViewType type) async {
    final prefs = await _prefs();
    await prefs.setString(_storageKey, type.storageValue);
  }
}

TileLayer buildParaglidingTileLayer(ParaglidingMapViewType type) {
  return TileLayer(
    urlTemplate: type.urlTemplate,
    userAgentPackageName: 'com.phoneix.paragliding',
    maxZoom: 19,
  );
}

TextSourceAttribution buildParaglidingAttribution(
  ParaglidingMapViewType type,
) {
  return TextSourceAttribution(type.attributionText);
}
