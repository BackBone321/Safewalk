import 'google_maps_web_guard_stub.dart'
    if (dart.library.html) 'google_maps_web_guard_web.dart';

bool isGoogleMapsJsLoaded() => isGoogleMapsJsLoadedImpl();
