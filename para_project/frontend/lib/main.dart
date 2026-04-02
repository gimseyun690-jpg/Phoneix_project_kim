import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app.dart';
import 'core/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final supportsMapbox =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (supportsMapbox && AppConfig.hasMapboxAccessToken) {
    MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);
  }
  runApp(const ParaglidingApp());
}
