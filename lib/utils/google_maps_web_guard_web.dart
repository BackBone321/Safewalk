import 'dart:js_util' as js_util;

bool isGoogleMapsJsLoadedImpl() {
  final global = js_util.globalThis;
  if (!js_util.hasProperty(global, 'google')) return false;
  final google = js_util.getProperty<Object>(global, 'google');
  return js_util.hasProperty(google, 'maps');
}
