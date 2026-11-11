import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'add_device_page.dart';
import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';
import '../utils/google_maps_web_guard.dart';
import '../services/guardian_service.dart';
import '../services/notification_service.dart';
import '../services/print_service.dart';
import '../services/system_admin_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AuthService _authService = AuthService();
  final SystemAdminService _systemAdminService = SystemAdminService();
  final NotificationService _notificationService = NotificationService();


  String _selectedFilter = 'all';
  String _searchText = '';
  int _selectedMenuIndex = 0;

  GoogleMapController? _adminMapController;
  LatLng? _lastFocusedAdminPoint;
  BitmapDescriptor? _sosMarkerIcon;
  BitmapDescriptor? _respondedMarkerIcon;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _devicesStreamSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersStreamSub;
  final Map<String, Map<String, dynamic>> _devicesById =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _devicesByPhone =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _usersByUid =
      <String, Map<String, dynamic>>{};
  final Set<String> _backfilledAdminAlertIds = <String>{};
  final Set<String> _clearedAdminAlertIds = <String>{};

  static const LatLng _defaultMapCenter = LatLng(14.5995, 120.9842);
  static final Set<Factory<OneSequenceGestureRecognizer>>
  _mapGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  final List<_AdminMenuItem> _menuItems = const [
    _AdminMenuItem('User Management', Icons.people_alt_outlined),
    _AdminMenuItem('Device Management', Icons.memory_outlined),
    _AdminMenuItem('Emergency Alerts', Icons.warning_amber_rounded),
    _AdminMenuItem('Login Activity', Icons.login_outlined),
    _AdminMenuItem('Logout', Icons.logout_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _prepareMapMarkers();
    _startLocationFallbackStreams();
  }

  @override
  void dispose() {
    _devicesStreamSub?.cancel();
    _usersStreamSub?.cancel();
    _adminMapController?.dispose();
    super.dispose();
  }

  void _startLocationFallbackStreams() {
    _devicesStreamSub = FirebaseFirestore.instance
        .collection('devices')
        .snapshots()
        .listen((snapshot) {
          _devicesById.clear();
          _devicesByPhone.clear();
          for (final doc in snapshot.docs) {
            final data = doc.data();
            _devicesById[doc.id] = data;
            final devId = (data['deviceId'] ?? '').toString().trim();
            if (devId.isNotEmpty) {
              _devicesById[devId] = data;
            }
            final phone = (data['phoneNumber'] ?? '').toString().trim();
            if (phone.isNotEmpty) {
              _devicesByPhone[phone] = data;
            }
          }
          if (mounted) setState(() {});
        }, onError: (_) {});

    _usersStreamSub = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen((snapshot) {
          _usersByUid.clear();
          for (final doc in snapshot.docs) {
            _usersByUid[doc.id] = doc.data();
          }
          if (mounted) setState(() {});
        }, onError: (_) {});
  }

  Future<Uint8List> _buildSosMarkerBytes({
    int size = 96,
    Color color = const Color(0xFFE5192B),
  }) async {
    final markerSize = size.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, markerSize, markerSize),
    );

    final center = Offset(markerSize / 2, markerSize * 0.36);
    final topRadius = markerSize * 0.28;
    final bodyColor = color;
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.22)
      ..style = PaintingStyle.fill;
    final pinPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = markerSize * 0.04;

    final shadowPath = Path()
      ..moveTo(center.dx, markerSize * 0.98)
      ..lineTo(center.dx - topRadius * 0.68, center.dy + topRadius * 0.60)
      ..lineTo(center.dx + topRadius * 0.68, center.dy + topRadius * 0.60)
      ..close();
    canvas.drawCircle(
      Offset(center.dx, center.dy + markerSize * 0.02),
      topRadius,
      shadowPaint,
    );
    canvas.drawPath(shadowPath, shadowPaint);

    final pinPath = Path()
      ..moveTo(center.dx, markerSize * 0.96)
      ..lineTo(center.dx - topRadius * 0.65, center.dy + topRadius * 0.55)
      ..lineTo(center.dx + topRadius * 0.65, center.dy + topRadius * 0.55)
      ..close();
    canvas.drawCircle(center, topRadius, pinPaint);
    canvas.drawPath(pinPath, pinPaint);
    canvas.drawCircle(center, topRadius, borderPaint);
    canvas.drawCircle(center, topRadius * 0.44, Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return Uint8List(0);
    }
    return bytes.buffer.asUint8List();
  }

  Future<void> _prepareMapMarkers() async {
    try {
      final red = await _buildSosMarkerBytes(color: const Color(0xFFE5192B));
      final dark = await _buildSosMarkerBytes(color: const Color(0xFF111827));
      if (!mounted) return;
      setState(() {
        if (red.isNotEmpty) {
          _sosMarkerIcon = BitmapDescriptor.bytes(red, width: 38, height: 38);
        }
        if (dark.isNotEmpty) {
          _respondedMarkerIcon =
              BitmapDescriptor.bytes(dark, width: 38, height: 38);
        }
      });
    } catch (_) {}
  }

  BitmapDescriptor _markerIconForStatus(String status) {
    if (status == 'responded') {
      return _respondedMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (status == 'acknowledged') {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
    if (status == 'not_resolved') {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
    return _sosMarkerIcon ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }

  bool _isSamePoint(LatLng a, LatLng b) {
    const tolerance = 0.00001;
    return (a.latitude - b.latitude).abs() <= tolerance &&
        (a.longitude - b.longitude).abs() <= tolerance;
  }

  void _focusAdminMapOnPoint(
    LatLng point, {
    double zoom = 16,
    bool force = false,
  }) {
    final controller = _adminMapController;
    if (controller == null) return;
    if (!force &&
        _lastFocusedAdminPoint != null &&
        _isSamePoint(_lastFocusedAdminPoint!, point)) {
      return;
    }
    _lastFocusedAdminPoint = point;
    try {
      controller
          .animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: point, zoom: zoom),
            ),
          )
          .catchError((_) {});
    } catch (_) {}
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.green,
      ),
    );
  }

  Map<String, dynamic> _clearedLocationPatch() => {
        'locationCleared': true,
        'location': 'Location removed',
        'locationText': 'Location removed',
        'currentLocation': FieldValue.delete(),
        'coordinates': FieldValue.delete(),
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'lat': FieldValue.delete(),
        'lng': FieldValue.delete(),
        'lon': FieldValue.delete(),
      };

  void _applyLocalLocationClear({
    required String senderUid,
    required Set<String> deviceIds,
  }) {
    void clearMap(Map<String, dynamic> data) {
      data['locationCleared'] = true;
      data['location'] = 'Location removed';
      data['locationText'] = 'Location removed';
      data.remove('currentLocation');
      data.remove('coordinates');
      data.remove('latitude');
      data.remove('longitude');
      data.remove('lat');
      data.remove('lng');
      data.remove('lon');
    }

    if (senderUid.isNotEmpty) {
      final user = _usersByUid[senderUid];
      if (user != null) clearMap(user);
    }
    for (final id in deviceIds) {
      final device = _devicesById[id];
      if (device != null) clearMap(device);
    }
    if (mounted) setState(() {});
  }

  bool _isFalseAlarmStatus(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    return data['falseAlarm'] == true ||
        status == 'false_alarm' ||
        status == 'cancelled_false_trigger';
  }

  Future<void> _collectDeviceDocIds(
    Set<String> ids,
    String lookupId,
  ) async {
    final trimmed = lookupId.trim();
    if (trimmed.isEmpty || trimmed == 'Not linked') return;
    final db = FirebaseFirestore.instance;
    final direct = await db.collection('devices').doc(trimmed).get();
    if (direct.exists) ids.add(direct.id);
    final byField = await db
        .collection('devices')
        .where('deviceId', isEqualTo: trimmed)
        .get();
    for (final doc in byField.docs) {
      ids.add(doc.id);
    }
  }

  Future<void> _collectAlerts(
    Map<String, DocumentReference<Map<String, dynamic>>> refs,
    Set<String> markedIds,
    String field,
    String value,
  ) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('emergency_alerts')
        .where(field, isEqualTo: trimmed)
        .get();
    for (final doc in snap.docs) {
      if (_isFalseAlarmStatus(doc.data())) continue;
      refs[doc.id] = doc.reference;
      markedIds.add(doc.id);
      _clearedAdminAlertIds.add(doc.id);
    }
  }

  Future<void> _removeLocationAndAlerts(String alertId) async {
    if (alertId.isEmpty || _clearedAdminAlertIds.contains(alertId)) return;
    final markedIds = <String>{alertId};
    _clearedAdminAlertIds.add(alertId);
    if (mounted) setState(() {});
    try {
      final db = FirebaseFirestore.instance;
      final alertRef = db.collection('emergency_alerts').doc(alertId);
      final snap = await alertRef.get();
      if (!snap.exists) {
        _showMessage('Done. Location and alerts removed.');
        return;
      }
      final data = snap.data() ?? <String, dynamic>{};
      if (_isFalseAlarmStatus(data)) {
        _clearedAdminAlertIds.remove(alertId);
        _showMessage(
          "Student reported this alert as a false alarm (miss-clicked device).",
        );
        return;
      }

      final senderUid =
          (data['uid'] ?? data['studentUid'] ?? '').toString().trim();
      final deviceId = (data['deviceId'] ?? '').toString().trim();
      final phone = (data['phoneNumber'] ?? '').toString().trim();
      final linkedDeviceId = senderUid.isEmpty
          ? ''
          : (_usersByUid[senderUid]?['linkedDeviceId'] ?? '').toString().trim();

      final alertRefs = <String, DocumentReference<Map<String, dynamic>>>{
        alertId: alertRef,
      };
      await _collectAlerts(alertRefs, markedIds, 'uid', senderUid);
      await _collectAlerts(alertRefs, markedIds, 'studentUid', senderUid);
      await _collectAlerts(alertRefs, markedIds, 'deviceId', deviceId);
      await _collectAlerts(alertRefs, markedIds, 'deviceId', linkedDeviceId);
      await _collectAlerts(alertRefs, markedIds, 'phoneNumber', phone);

      final deviceIds = <String>{};
      await _collectDeviceDocIds(deviceIds, deviceId);
      await _collectDeviceDocIds(deviceIds, linkedDeviceId);
      if (senderUid.isNotEmpty) {
        final byStudent = await db
            .collection('devices')
            .where('studentUid', isEqualTo: senderUid)
            .get();
        for (final doc in byStudent.docs) {
          deviceIds.add(doc.id);
        }
      }
      if (phone.isNotEmpty) {
        final byPhone = await db
            .collection('devices')
            .where('phoneNumber', isEqualTo: phone)
            .get();
        for (final doc in byPhone.docs) {
          deviceIds.add(doc.id);
        }
      }

      _applyLocalLocationClear(senderUid: senderUid, deviceIds: deviceIds);

      final writes = <void Function(WriteBatch batch)>[];
      if (senderUid.isNotEmpty) {
        final userRef = db.collection('users').doc(senderUid);
        writes.add(
          (batch) => batch.set(
            userRef,
            _clearedLocationPatch(),
            SetOptions(merge: true),
          ),
        );
      }
      for (final id in deviceIds) {
        final deviceRef = db.collection('devices').doc(id);
        writes.add(
          (batch) => batch.set(
            deviceRef,
            _clearedLocationPatch(),
            SetOptions(merge: true),
          ),
        );
      }
      for (final ref in alertRefs.values) {
        writes.add((batch) => batch.delete(ref));
      }

      var start = 0;
      while (start < writes.length) {
        final batch = db.batch();
        final end = start + 400 > writes.length ? writes.length : start + 400;
        for (var i = start; i < end; i++) {
          writes[i](batch);
        }
        await batch.commit();
        start = end;
      }

      _showMessage('Done. Location and alerts removed.');
    } catch (e) {
      _clearedAdminAlertIds.removeAll(markedIds);
      if (mounted) setState(() {});
      _showMessage('Failed to remove alert: $e', isError: true);
    }
  }

  Future<void> _handleAlertAction(String alertId, String currentStatus) async {
    final status = currentStatus.toLowerCase().trim();
    if (status == 'false_alarm' || status == 'cancelled_false_trigger') {
      _showMessage("Student reported this alert as a false alarm (miss-clicked device).");
      return;
    }
    if (status == 'resolved' ||
        status == 'responded' ||
        status == 'acknowledged' ||
        status == 'not_resolved') {
      await _removeLocationAndAlerts(alertId);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .set({
        'status': 'responded',
        'respondedAt': FieldValue.serverTimestamp(),
        'respondedBy': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        'locationCleared': false,
      }, SetOptions(merge: true));
      _showMessage('Issue responded. Marker is now dark.');
    } catch (e) {
      _showMessage('Failed to respond to alert: $e', isError: true);
    }
  }

  Widget _buildAdminMapActionChip({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  bool _isValidLatLng(double lat, double lng) {
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  LatLng? _coordinatesFromValues(dynamic latValue, dynamic lngValue) {
    final lat = _toDouble(latValue);
    final lng = _toDouble(lngValue);
    if (lat == null || lng == null) return null;
    if (!_isValidLatLng(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  LatLng? _coordinatesFromText(String text) {
    final match = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
    ).firstMatch(text);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1) ?? '');
    final lng = double.tryParse(match.group(2) ?? '');
    if (lat == null || lng == null) return null;
    if (!_isValidLatLng(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  bool _isDefaultManila(LatLng? p) {
    if (p == null) return false;
    return (p.latitude - 14.5995).abs() < 0.005 &&
        (p.longitude - 120.9842).abs() < 0.005;
  }

  String _formatLocationField(dynamic loc) {
    if (loc == null) return '-';
    if (loc is GeoPoint) {
      if (!_isValidLatLng(loc.latitude, loc.longitude)) return 'Pending GPS Fix';
      return '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}';
    }
    final text = loc.toString().trim();
    if (text.isEmpty) return '-';
    return text;
  }

  LatLng? _extractDirectCoordinatesFromMap(Map<String, dynamic> data) {
    final candidates = <LatLng>[];

    final coordinates = data['coordinates'];
    if (coordinates is GeoPoint) {
      if (_isValidLatLng(coordinates.latitude, coordinates.longitude)) {
        candidates.add(LatLng(coordinates.latitude, coordinates.longitude));
      }
    } else if (coordinates is Map) {
      final nested = _coordinatesFromValues(
        coordinates['latitude'] ?? coordinates['lat'],
        coordinates['longitude'] ?? coordinates['lng'] ?? coordinates['lon'],
      );
      if (nested != null) candidates.add(nested);
    }

    final direct = _coordinatesFromValues(
      data['latitude'] ?? data['lat'],
      data['longitude'] ?? data['lng'] ?? data['lon'],
    );
    if (direct != null) candidates.add(direct);

    final location = data['location'];
    if (location is GeoPoint) {
      if (_isValidLatLng(location.latitude, location.longitude)) {
        candidates.add(LatLng(location.latitude, location.longitude));
      }
    } else if (location is String) {
      final fromTxt = _coordinatesFromText(location);
      if (fromTxt != null) candidates.add(fromTxt);
    }

    final locationText = data['locationText'];
    if (locationText is String) {
      final fromTxt = _coordinatesFromText(locationText);
      if (fromTxt != null) candidates.add(fromTxt);
    }

    if (candidates.isEmpty) return null;
    for (final c in candidates) {
      if (!_isDefaultManila(c)) return c;
    }
    return candidates.first;
  }

  LatLng? _extractAlertCoordinates(
    Map<String, dynamic> data, {
    String? alertId,
  }) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    if ((alertId != null && _clearedAdminAlertIds.contains(alertId)) ||
        data['locationCleared'] == true ||
        data['falseAlarm'] == true ||
        status == 'false_alarm' ||
        status == 'cancelled_false_trigger' ||
        status == 'resolved') {
      return null;
    }

    final directAlertPoint = _extractDirectCoordinatesFromMap(data);

    final senderUid =
        (data['uid'] ?? data['studentUid'] ?? '').toString().trim();
    final studentData = senderUid.isNotEmpty ? _usersByUid[senderUid] : null;
    final alertDeviceId = (data['deviceId'] ?? '').toString().trim();
    final linkedDeviceId = alertDeviceId.isNotEmpty
        ? alertDeviceId
        : (studentData?['linkedDeviceId'] ?? '').toString().trim();
    final alertPhone = (data['phoneNumber'] ??
            studentData?['phoneNumber'] ??
            '')
        .toString()
        .trim();

    Map<String, dynamic>? deviceData;
    if (linkedDeviceId.isNotEmpty) {
      deviceData = _devicesById[linkedDeviceId];
    }
    if (deviceData == null && alertPhone.isNotEmpty) {
      deviceData = _devicesByPhone[alertPhone];
    }
    if (deviceData == null && senderUid.isNotEmpty) {
      for (final dev in _devicesById.values) {
        if ((dev['studentUid'] ?? '').toString().trim() == senderUid) {
          deviceData = dev;
          break;
        }
      }
    }

    final devicePoint = deviceData != null
        ? _extractDirectCoordinatesFromMap(deviceData)
        : null;
    final studentPoint = studentData != null
        ? _extractDirectCoordinatesFromMap(studentData)
        : null;

    LatLng? bestFallback;
    final deviceValid = devicePoint != null && !_isDefaultManila(devicePoint);
    final studentValid =
        studentPoint != null && !_isDefaultManila(studentPoint);

    if (deviceValid) {
      bestFallback = devicePoint;
    } else if (studentValid) {
      bestFallback = studentPoint;
    } else {
      bestFallback = devicePoint ?? studentPoint;
    }

    if (bestFallback == null) {
      for (final dev in _devicesById.values) {
        final candidate = _extractDirectCoordinatesFromMap(dev);
        if (candidate != null && !_isDefaultManila(candidate)) {
          bestFallback = candidate;
          break;
        }
      }
    }

    // Live device coordinates move the existing pin. The alert document
    // keeps the status and is only used when the tracker has no fix yet.
    final LatLng? resolved = deviceValid
        ? devicePoint
        : ((directAlertPoint != null && !_isDefaultManila(directAlertPoint))
            ? directAlertPoint
            : (bestFallback ?? directAlertPoint));

    if (alertId != null &&
        alertId.isNotEmpty &&
        !_clearedAdminAlertIds.contains(alertId) &&
        resolved != null &&
        !_isDefaultManila(resolved) &&
        (directAlertPoint == null ||
            _isDefaultManila(directAlertPoint) ||
            !_isSamePoint(directAlertPoint, resolved)) &&
        !_backfilledAdminAlertIds.contains(alertId)) {
      _backfilledAdminAlertIds.add(alertId);
      final label = _formatCoordinateValue(resolved);
      FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .set({
            'coordinates': GeoPoint(resolved.latitude, resolved.longitude),
            'location': label,
            'latitude': resolved.latitude,
            'longitude': resolved.longitude,
          }, SetOptions(merge: true))
          .catchError((_) {});
    }

    return resolved;
  }

  String _formatCoordinateValue(LatLng? value) {
    if (value == null) return 'Unknown';
    return '${value.latitude.toStringAsFixed(6)}, ${value.longitude.toStringAsFixed(6)}';
  }

  String _resolveAlertSenderName(Map<String, dynamic> data) {
    final fullName = (data['fullName'] ?? '').toString().trim();
    if (fullName.isNotEmpty) return fullName;
    final studentName = (data['studentName'] ?? '').toString().trim();
    if (studentName.isNotEmpty) return studentName;
    final userName = (data['userName'] ?? '').toString().trim();
    if (userName.isNotEmpty) return userName;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return 'Unknown sender';
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    var dt = ts.toDate().toLocal();
    if (dt.year >= 2070 || dt.year < 2024) {
      final now = DateTime.now();
      dt = DateTime(now.year, now.month, now.day, dt.hour, dt.minute);
    }
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m/$d/${dt.year} $h:$min';
  }

  Widget _buildWebMapFallback({required String contextLabel}) {
    return Container(
      color: const Color(0xFF830C0C),
      padding: const EdgeInsets.all(14),
      alignment: Alignment.centerLeft,
      child: Text(
        'Google Maps is not ready on Web.\n'
        'Set your API key in web/index.html and reload.\n'
        'Context: $contextLabel',
        style: const TextStyle(
          color: Color(0xFFFFF1B8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;
    await _logout();
  }

  Future<void> _changePasswordDialog(
    String uid,
    String userName,
    String email,
  ) async {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isLoading = false;
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: AppColors.border.withOpacity(0.5)),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHANGE PASSWORD',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 4,
                  color: AppColors.gold.withOpacity(0.9),
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                userName,
                style: const TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  color: AppColors.green,
                ),
              ),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSub,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPassCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    hintText: 'Minimum 6 characters',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.green),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.offWhite,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSub,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.green),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.offWhite,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSub,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSub),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: AppColors.goldLt,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      final newPass = newPassCtrl.text.trim();
                      final confirmPass = confirmPassCtrl.text.trim();

                      if (newPass.length < 6) {
                        _showMessage('Password must be at least 6 characters.', isError: true);
                        return;
                      }
                      if (newPass != confirmPass) {
                        _showMessage('Passwords do not match.', isError: true);
                        return;
                      }

                      setDialogState(() => isLoading = true);
                      try {
                        final callable = FirebaseFunctions.instance
                            .httpsCallable('updateUserPassword');
                        await callable.call({
                          'uid': uid,
                          'newPassword': newPass,
                        });
                        if (mounted) Navigator.pop(context);
                        _showMessage('Password updated for $userName.');
                      } on FirebaseFunctionsException catch (e) {
                        _showMessage(
                          e.message ?? 'Failed to update password.',
                          isError: true,
                        );
                      } catch (e) {
                        _showMessage('Error: $e', isError: true);
                      } finally {
                        setDialogState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.goldLt,
                      ),
                    )
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          const Positioned.fill(child: _AdminBackground()),
          // Top gradient accent bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.green, AppColors.bright, AppColors.gold],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Column(
                      children: [
                        _buildSummaryRow(),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Row(
                            children: [
                              _buildMenuPanel(),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: _buildContentArea(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          _menuItems[_selectedMenuIndex].title == 'Device Management'
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.green,
              foregroundColor: AppColors.goldLt,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddDevicePage()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text(
                'ADD DEVICE',
                style: TextStyle(letterSpacing: 2),
              ),
            )
          : null,
    );
  }

  String _getAdminGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green,
            border: Border.all(color: AppColors.gold, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withOpacity(0.18),
                blurRadius: 16,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 16,
                fontWeight: FontWeight.w300,
                color: AppColors.gold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SAFEWALK ADMIN',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 4,
                color: AppColors.goldDark,
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              _getAdminGreeting(),
              style: const TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 18,
                fontWeight: FontWeight.w300,
                color: AppColors.green,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }




  Widget _buildSummaryRow() {
    return Row(
      children: [
        _LuxurySummaryCard(
          title: 'USERS',
          icon: Icons.people_outline,
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'DEVICES',
          icon: Icons.memory_outlined,
          stream: FirebaseFirestore.instance.collection('devices').snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'ALERTS',
          icon: Icons.warning_amber_rounded,
          stream: FirebaseFirestore.instance
              .collection('emergency_alerts')
              .snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'LOGINS',
          icon: Icons.login_outlined,
          stream: FirebaseFirestore.instance
              .collection('login_logs')
              .snapshots(),
        ),
      ],
    );
  }

  Widget _buildMenuPanel() {
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Sidebar header with green gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF05412B), Color(0xFF0B2C1E)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NAVIGATION',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 4,
                      color: AppColors.gold.withOpacity(0.8),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Admin Panel',
                    style: TextStyle(
                      fontFamily: 'CormorantGaramond',
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      color: AppColors.goldLt,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _menuItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _menuItems[index];
                  final isSelected = _selectedMenuIndex == index;
                  final isLogout = item.title == 'Logout';

                  return InkWell(
                    onTap: () {
                      if (isLogout) {
                        _confirmLogout();
                      } else {
                        setState(() {
                          _selectedMenuIndex = index;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.green.withOpacity(0.07)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(
                            color: isSelected
                                ? AppColors.gold
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            color: isLogout
                                ? const Color(0xFFCB392B)
                                : isSelected
                                ? AppColors.green
                                : AppColors.textSub,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isLogout
                                    ? const Color(0xFFCB392B)
                                    : isSelected
                                    ? AppColors.green
                                    : AppColors.textMain,
                              ),
                            ),
                          ),
                          if (isSelected && !isLogout)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.gold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    final title = _menuItems[_selectedMenuIndex].title;
    switch (title) {
      case 'User Management':
        return _buildUserManagement();
      case 'Device Management':
        return _buildDeviceManagement();
      case 'Emergency Alerts':
        return _buildEmergencyAlerts();
      case 'Login Activity':
        return _buildLoginActivity();
      default:
        return _buildUserManagement();
    }
  }

  Widget _buildUserManagement() {
    return _LuxuryPanel(
      title: 'REGISTERED USERS',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No registered users found.',
                style: TextStyle(color: AppColors.textSub),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();

              final fullName = (data['fullName'] ?? 'No Name').toString();
              final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
              final role = (data['role'] ?? 'unknown').toString();
              final roleColor = role == 'admin'
                  ? const Color(0xFF7E1F14)
                  : role == 'parent'
                  ? const Color(0xFF1A4D8F)
                  : AppColors.green;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Initials Avatar
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.green,
                        border: Border.all(color: AppColors.gold, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.green.withOpacity(0.18),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontFamily: 'CormorantGaramond',
                            fontSize: 20,
                            color: AppColors.gold,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              // Role badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: roleColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: roleColor.withOpacity(0.35),
                                  ),
                                ),
                                child: Text(
                                  role.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    color: roleColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              _MiniTag(
                                label: data['email'] ?? 'No Email',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (data['phoneNumber'] ?? 'No phone number').toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSub,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Change Password button
                    Tooltip(
                      message: 'Change Password',
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.offWhite,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.lock_reset_rounded,
                            color: AppColors.goldDark,
                            size: 20,
                          ),
                          onPressed: () => _changePasswordDialog(
                            docs[index].id,
                            fullName,
                            (data['email'] ?? '').toString(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDeviceManagement() {
    return _LuxuryPanel(
      title: 'REGISTERED DEVICES',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('devices')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No devices found.',
                style: TextStyle(color: AppColors.textSub),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();

              final status = (data['status'] ?? '').toString().toLowerCase();
              final isOnline = status == 'active' || status == 'online';
              final deviceName = (data['deviceName'] ?? 'No Name').toString();

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.gold,
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.memory_rounded,
                            color: AppColors.gold,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            deviceName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                        // Status pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFFEAF7F0)
                                : AppColors.cream,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isOnline
                                  ? const Color(0xFF60CC8A)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: isOnline
                                    ? const Color(0xFF2CA86E)
                                    : AppColors.textSub,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w600,
                                  color: isOnline
                                      ? const Color(0xFF0E5B3C)
                                      : AppColors.textSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.border, Colors.transparent],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AdminInfoRow('Device ID', (data['deviceId'] ?? '-').toString()),
                    const SizedBox(height: 6),
                    _AdminInfoRow('Phone', (data['phoneNumber'] ?? '-').toString()),
                    const SizedBox(height: 6),
                    _AdminInfoRow(
                      'Location',
                      _formatLocationField(data['location'] ?? data['coordinates']),
                    ),
                    const SizedBox(height: 6),
                    _AdminInfoRow(
                      'Assigned Student',
                      data['studentName'] != null
                          ? '${data['studentName']} (${data['studentUid']})'
                          : 'Not assigned',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _editDeviceDialog(context, docs[index].id, data),
                          icon: const Icon(Icons.edit, size: 16, color: AppColors.green),
                          label: const Text(
                            'Edit',
                            style: TextStyle(
                              color: AppColors.green,
                              fontSize: 13,
                              fontFamily: 'JosefinSans',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _deleteDeviceConfirm(context, docs[index].id, deviceName),
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          label: const Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontFamily: 'JosefinSans',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _editDeviceDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final deviceIdCtrl = TextEditingController(text: (data['deviceId'] ?? '').toString());
    final deviceNameCtrl = TextEditingController(text: (data['deviceName'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (data['phoneNumber'] ?? '').toString());
    final initialLoc = _formatLocationField(data['location'] ?? data['coordinates']);
    final locationCtrl = TextEditingController(text: initialLoc == '-' ? '' : initialLoc);
    final studentUidCtrl = TextEditingController(text: (data['studentUid'] ?? '').toString());
    bool saving = false;
    bool detectingLocation = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.offWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Text(
                'Edit Device Details',
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  color: AppColors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: deviceIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Device ID',
                        labelStyle: TextStyle(color: AppColors.green, fontFamily: 'JosefinSans'),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                      ),
                      style: const TextStyle(fontFamily: 'JosefinSans'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: deviceNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Device Name',
                        labelStyle: TextStyle(color: AppColors.green, fontFamily: 'JosefinSans'),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                      ),
                      style: const TextStyle(fontFamily: 'JosefinSans'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        labelStyle: TextStyle(color: AppColors.green, fontFamily: 'JosefinSans'),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                      ),
                      style: const TextStyle(fontFamily: 'JosefinSans'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationCtrl,
                      decoration: InputDecoration(
                        labelText: 'Location (Coordinates or Address)',
                        labelStyle: const TextStyle(color: AppColors.green, fontFamily: 'JosefinSans'),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                        suffixIcon: IconButton(
                          icon: detectingLocation
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green),
                                )
                              : const Icon(Icons.my_location_rounded, color: AppColors.green, size: 20),
                          tooltip: 'Detect Exact Device Location',
                          onPressed: detectingLocation
                              ? null
                              : () async {
                                  setDialogState(() => detectingLocation = true);
                                  try {
                                    LocationPermission perm = await Geolocator.checkPermission();
                                    if (perm == LocationPermission.denied) {
                                      perm = await Geolocator.requestPermission();
                                    }
                                    if (perm != LocationPermission.denied &&
                                        perm != LocationPermission.deniedForever) {
                                      final pos = await Geolocator.getCurrentPosition(
                                        desiredAccuracy: LocationAccuracy.high,
                                        timeLimit: const Duration(seconds: 12),
                                      );
                                      locationCtrl.text =
                                          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
                                    }
                                  } catch (e) {
                                    debugPrint('Detect location error: $e');
                                  } finally {
                                    setDialogState(() => detectingLocation = false);
                                  }
                                },
                        ),
                      ),
                      style: const TextStyle(fontFamily: 'JosefinSans'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: studentUidCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Student UID (Optional)',
                        labelStyle: TextStyle(color: AppColors.green, fontFamily: 'JosefinSans'),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                      ),
                      style: const TextStyle(fontFamily: 'JosefinSans'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: AppColors.textSub, fontFamily: 'JosefinSans'),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          final newId = deviceIdCtrl.text.trim();
                          final newName = deviceNameCtrl.text.trim();
                          final newPhone = phoneCtrl.text.trim();
                          final newLoc = locationCtrl.text.trim();
                          final newStudentUid = studentUidCtrl.text.trim();

                          if (newId.isEmpty || newName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Device ID and Name cannot be empty.')),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);
                          try {
                            String? resolvedStudentName;
                            String? resolvedParentPhone;
                            String? resolvedParentUid;
                            if (newStudentUid.isNotEmpty) {
                              final studentDoc = await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(newStudentUid)
                                  .get();
                              if (!studentDoc.exists) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Student UID not found.')),
                                );
                                setDialogState(() => saving = false);
                                return;
                              }
                              final sData = studentDoc.data();
                              resolvedStudentName = (sData?['fullName'] ?? 'Student').toString();
                              
                              final pQuery = await FirebaseFirestore.instance
                                  .collection('parent_student_links')
                                  .where('studentUid', isEqualTo: newStudentUid)
                                  .where('status', isEqualTo: 'accepted')
                                  .limit(1)
                                  .get();
                              if (pQuery.docs.isNotEmpty) {
                                final pData = pQuery.docs.first.data();
                                resolvedParentPhone = (pData['parentPhone'] ?? '').toString();
                                resolvedParentUid = (pData['parentUid'] ?? '').toString();
                              }
                            }

                            final parts = newLoc.split(',');
                            double? lat;
                            double? lng;
                            if (parts.length == 2) {
                              lat = double.tryParse(parts[0].trim());
                              lng = double.tryParse(parts[1].trim());
                            }

                            final oldStudentUid = (data['studentUid'] ?? '').toString().trim();
                            final updateData = <String, dynamic>{
                              'deviceId': newId,
                              'deviceName': newName,
                              'phoneNumber': newPhone,
                              'location': newLoc,
                            };
                            if (lat != null && lng != null) {
                              updateData['latitude'] = lat;
                              updateData['longitude'] = lng;
                              updateData['coordinates'] = GeoPoint(lat, lng);
                              updateData['locationText'] = newLoc;
                              updateData['updatedAt'] = FieldValue.serverTimestamp();
                            }

                            if (newStudentUid.isNotEmpty) {
                              updateData['studentUid'] = newStudentUid;
                              updateData['studentName'] = resolvedStudentName;
                              if (resolvedParentPhone != null && resolvedParentPhone.isNotEmpty) {
                                updateData['parentPhoneNumber'] = resolvedParentPhone;
                                updateData['parentUid'] = resolvedParentUid;
                              }
                            } else {
                              updateData['studentUid'] = FieldValue.delete();
                              updateData['studentName'] = FieldValue.delete();
                              updateData['parentPhoneNumber'] = FieldValue.delete();
                              updateData['parentUid'] = FieldValue.delete();
                              updateData['guardianPhonesCsv'] = '';
                            }

                            // 1. Update the device doc
                            await FirebaseFirestore.instance
                                .collection('devices')
                                .doc(docId)
                                .update(updateData);
                            if (newStudentUid.isNotEmpty) {
                              await GuardianService().syncRecipients(newStudentUid);
                            }

                            // 2. Synchronize the student's linkedDeviceId
                            if (oldStudentUid != newStudentUid) {
                              if (oldStudentUid.isNotEmpty) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(oldStudentUid)
                                    .update({'linkedDeviceId': FieldValue.delete()});
                              }
                              if (newStudentUid.isNotEmpty) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(newStudentUid)
                                    .update({'linkedDeviceId': newId});
                              }
                            } else if (newStudentUid.isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(newStudentUid)
                                  .update({'linkedDeviceId': newId});
                            }

                            if (lat != null &&
                                lng != null &&
                                _isValidLatLng(lat, lng)) {
                              final geo = GeoPoint(lat, lng);
                              if (newStudentUid.isNotEmpty) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(newStudentUid)
                                    .set({
                                      'coordinates': geo,
                                      'location': geo,
                                      'latitude': lat,
                                      'longitude': lng,
                                      'locationText': newLoc,
                                      'lastLocationUpdate':
                                          FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));
                              }
                              final activeAlerts = await FirebaseFirestore
                                  .instance
                                  .collection('emergency_alerts')
                                  .where('status', isEqualTo: 'active')
                                  .limit(30)
                                  .get();
                              for (final alertDoc in activeAlerts.docs) {
                                final aData = alertDoc.data();
                                final aUid = (aData['uid'] ??
                                        aData['studentUid'] ??
                                        '')
                                    .toString()
                                    .trim();
                                final aDev =
                                    (aData['deviceId'] ?? '').toString().trim();
                                if ((newStudentUid.isNotEmpty &&
                                        aUid == newStudentUid) ||
                                    (newId.isNotEmpty && aDev == newId)) {
                                  await alertDoc.reference.set({
                                    'coordinates': geo,
                                    'location': newLoc,
                                    'latitude': lat,
                                    'longitude': lng,
                                  }, SetOptions(merge: true));
                                }
                              }
                            }

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Device updated successfully.')),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to update: $e')),
                            );
                          } finally {
                            setDialogState(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          'SAVE',
                          style: TextStyle(
                            fontFamily: 'JosefinSans',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteDeviceConfirm(BuildContext context, String docId, String deviceName) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.offWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Delete Device?',
            style: TextStyle(
              fontFamily: 'CormorantGaramond',
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "$deviceName"? This cannot be undone.',
            style: const TextStyle(fontFamily: 'JosefinSans', color: AppColors.green),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: AppColors.textSub, fontFamily: 'JosefinSans'),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('devices')
                      .doc(docId)
                      .delete();
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device deleted successfully.')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              },
              child: const Text(
                'DELETE',
                style: TextStyle(
                  fontFamily: 'JosefinSans',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmergencySosMap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sosDocs =
        docs.where((doc) {
          final data = doc.data();
          final type = (data['type'] ?? '').toString().toLowerCase();
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (_clearedAdminAlertIds.contains(doc.id)) return false;
          final isEmergency =
              type == 'sos' || type == 'voice_help' || type == 'emergency';
          final isActiveEmergency =
              (status == 'active' ||
                  status == 'verifying_speech' ||
                  status == 'responded' ||
                  status == 'acknowledged' ||
                  status == 'not_resolved') &&
              data['locationCleared'] != true;
          return isEmergency && isActiveEmergency;
        }).toList()..sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aStatus = (aData['status'] ?? '').toString().toLowerCase();
          final bStatus = (bData['status'] ?? '').toString().toLowerCase();
          final aIsActive = aStatus == 'active' || aStatus == 'verifying_speech';
          final bIsActive = bStatus == 'active' || bStatus == 'verifying_speech';
          if (aIsActive != bIsActive) {
            return aIsActive ? -1 : 1;
          }
          final aTs = aData['timestamp'] as Timestamp?;
          final bTs = bData['timestamp'] as Timestamp?;
          return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
            aTs?.millisecondsSinceEpoch ?? 0,
          );
        });

    final latestBySender =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in sosDocs) {
      final data = doc.data();
      final deviceId = (data['deviceId'] ?? '').toString().trim();
      final senderUid = (data['uid'] ?? data['studentUid'] ?? '').toString().trim();
      final key = deviceId.isNotEmpty
          ? deviceId
          : (senderUid.isNotEmpty ? senderUid : doc.id);
      final current = latestBySender[key];
      if (current == null) {
        latestBySender[key] = doc;
        continue;
      }
      final currentTs = current.data()['timestamp'];
      final nextTs = data['timestamp'];
      final currentMs = currentTs is Timestamp ? currentTs.millisecondsSinceEpoch : 0;
      final nextMs = nextTs is Timestamp ? nextTs.millisecondsSinceEpoch : 0;
      if (nextMs >= currentMs) {
        latestBySender[key] = doc;
      }
    }

    final markers = <Marker>{};
    final circles = <Circle>{};
    LatLng? firstPoint;
    for (final entry in latestBySender.entries) {
      final data = entry.value.data();
      final point = _extractAlertCoordinates(data, alertId: entry.value.id);
      if (point == null) continue;
      firstPoint ??= point;
      final sender = _resolveAlertSenderName(data);
      final alertStatus = (data['status'] ?? '').toString().toLowerCase();
      final isActive =
          alertStatus == 'active' || alertStatus == 'verifying_speech';
      final pointLabel = _formatCoordinateValue(point);
      final statusTitle = alertStatus == 'responded'
          ? 'Responded'
          : alertStatus == 'acknowledged'
          ? 'Acknowledged'
          : alertStatus == 'not_resolved'
          ? 'Not resolved'
          : 'SOS';
      final circleFill = alertStatus == 'responded'
          ? const Color(0x55111827)
          : alertStatus == 'acknowledged'
          ? const Color(0x55F97316)
          : alertStatus == 'not_resolved'
          ? const Color(0x557C3AED)
          : const Color(0x55CB392B);
      final circleStroke = alertStatus == 'responded'
          ? const Color(0xFF111827)
          : alertStatus == 'acknowledged'
          ? const Color(0xFFEA580C)
          : alertStatus == 'not_resolved'
          ? const Color(0xFF6D28D9)
          : const Color(0xFFCB392B);
      markers.add(
        Marker(
          markerId: MarkerId('admin-sos-${entry.key}'),
          position: point,
          anchor: const Offset(0.5, 0.98),
          draggable: true,
          onDragEnd: (newPoint) async {
            final geo = GeoPoint(newPoint.latitude, newPoint.longitude);
            final label = _formatCoordinateValue(newPoint);
            await entry.value.reference.set({
              'coordinates': geo,
              'location': label,
              'latitude': newPoint.latitude,
              'longitude': newPoint.longitude,
            }, SetOptions(merge: true));
            final senderUid =
                (data['uid'] ?? data['studentUid'] ?? '').toString().trim();
            if (senderUid.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(senderUid)
                  .set({
                    'coordinates': geo,
                    'location': geo,
                    'latitude': newPoint.latitude,
                    'longitude': newPoint.longitude,
                    'locationText': label,
                    'lastLocationUpdate': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
            }
            final devId = (data['deviceId'] ??
                    _usersByUid[senderUid]?['linkedDeviceId'] ??
                    '')
                .toString()
                .trim();
            if (devId.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('devices')
                  .doc(devId)
                  .set({
                    'coordinates': geo,
                    'location': label,
                    'latitude': newPoint.latitude,
                    'longitude': newPoint.longitude,
                    'locationText': label,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
            }
            _focusAdminMapOnPoint(newPoint, zoom: 18, force: true);
          },
          icon: _markerIconForStatus(alertStatus),
          infoWindow: InfoWindow(
            title: '$sender - $statusTitle ($pointLabel)',
            snippet: pointLabel,
            onTap: () => _handleAlertAction(entry.value.id, data['status'] ?? 'active'),
          ),
        ),
      );
      circles.add(
        Circle(
          circleId: CircleId('admin-sos-circle-${entry.key}'),
          center: point,
          radius: isActive ? 90 : 60,
          fillColor: circleFill,
          strokeColor: circleStroke,
          strokeWidth: 2,
        ),
      );
    }

    if (markers.isEmpty) {
      final seenDevices = <String>{};
      for (final dev in _devicesById.values) {
        final devId = (dev['deviceId'] ?? '').toString().trim();
        final dedupKey = devId.isEmpty ? dev.hashCode.toString() : devId;
        if (seenDevices.contains(dedupKey)) continue;
        seenDevices.add(dedupKey);
        if (dev['locationCleared'] == true) continue;

        final point = _extractDirectCoordinatesFromMap(dev);
        if (point == null || _isDefaultManila(point)) continue;
        firstPoint ??= point;
        final devName = (dev['deviceName'] ?? 'Tracker').toString();
        final studentName = (dev['studentName'] ?? '').toString().trim();
        final studentUid = (dev['studentUid'] ?? '').toString().trim();
        final title = studentName.isNotEmpty ? '$studentName ($devName)' : devName;
        final pointLabel = _formatCoordinateValue(point);
        markers.add(
          Marker(
            markerId: MarkerId('admin-dev-$dedupKey'),
            position: point,
            anchor: _sosMarkerIcon != null
                ? const Offset(0.5, 0.98)
                : const Offset(0.5, 1.0),
            draggable: true,
            onDragEnd: (newPoint) async {
              final geo = GeoPoint(newPoint.latitude, newPoint.longitude);
              final label = _formatCoordinateValue(newPoint);
              if (devId.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('devices')
                    .doc(devId)
                    .set({
                      'coordinates': geo,
                      'location': label,
                      'latitude': newPoint.latitude,
                      'longitude': newPoint.longitude,
                      'locationText': label,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
              }
              if (studentUid.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(studentUid)
                    .set({
                      'coordinates': geo,
                      'location': geo,
                      'latitude': newPoint.latitude,
                      'longitude': newPoint.longitude,
                      'locationText': label,
                      'lastLocationUpdate': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
              }
              _focusAdminMapOnPoint(newPoint, zoom: 18, force: true);
            },
            icon: _sosMarkerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: title,
              snippet: pointLabel,
            ),
          ),
        );
        circles.add(
          Circle(
            circleId: CircleId('admin-dev-circle-$dedupKey'),
            center: point,
            radius: 60,
            fillColor: const Color(0x44CB392B),
            strokeColor: const Color(0xFFCB392B),
            strokeWidth: 2,
          ),
        );
      }
    }

    final markerCount = markers.length;
    final latestData = sosDocs.isNotEmpty ? sosDocs.first.data() : null;
    final latestSender = latestData == null
        ? 'Active Device'
        : _resolveAlertSenderName(latestData);
    final latestLabel = latestData == null
        ? ''
        : _formatTimestamp(latestData['timestamp'] as Timestamp?);
    final latestPoint = latestData == null
        ? firstPoint
        : _extractAlertCoordinates(latestData, alertId: sosDocs.first.id);
    final center = firstPoint ?? latestPoint ?? _defaultMapCenter;
    final hasPoint = markerCount > 0;
    if (hasPoint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusAdminMapOnPoint(center, zoom: 18);
      });
    }
    final footerTitle = sosDocs.isNotEmpty && hasPoint
        ? 'LATEST SOS: $latestSender${latestLabel.isEmpty ? '' : ' | $latestLabel'}'
        : hasPoint
        ? 'TRACKED DEVICE LOCATION'
        : 'NO SOS LOCATION YET';
    final footerLocation = hasPoint
        ? _formatCoordinateValue(latestPoint ?? firstPoint)
        : 'Waiting for SOS coordinates';
    QueryDocumentSnapshot<Map<String, dynamic>>? actionDoc;
    var actionMs = -1;
    for (final doc in sosDocs) {
      final ts = doc.data()['timestamp'];
      final ms = ts is Timestamp ? ts.millisecondsSinceEpoch : 0;
      if (actionDoc == null || ms >= actionMs) {
        actionDoc = doc;
        actionMs = ms;
      }
    }
    final actionStatus =
        (actionDoc?.data()['status'] ?? '').toString().toLowerCase();
    final actionAlertId = actionDoc?.id ?? '';
    final mapTagColor = actionStatus == 'responded'
        ? const Color(0xFF111827)
        : actionStatus == 'acknowledged'
        ? const Color(0xFFEA580C)
        : actionStatus == 'not_resolved'
        ? const Color(0xFF6D28D9)
        : const Color(0xFF7E1F14);
    final mapTagLabel = markerCount == 0
        ? 'NO SOS MARKERS'
        : actionStatus == 'responded'
        ? 'RESPONDED'
        : actionStatus == 'acknowledged'
        ? 'ACKNOWLEDGED'
        : actionStatus == 'not_resolved'
        ? 'NOT RESOLVED'
        : markerCount > 1
        ? '$markerCount SOS MARKERS'
        : 'ACTIVE ALERT';

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              child: kIsWeb && !isGoogleMapsJsLoaded()
                  ? _buildWebMapFallback(contextLabel: 'Admin SOS Map')
                  : GoogleMap(
                      key: const ValueKey('admin-sos-map-main'),
                      initialCameraPosition: CameraPosition(
                        target: center,
                        zoom: hasPoint ? 18 : 12,
                      ),
                      mapType: MapType.normal,
                      gestureRecognizers: _mapGestureRecognizers,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      markers: markers,
                      circles: circles,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      onMapCreated: (controller) {
                        _adminMapController = controller;
                        if (hasPoint) {
                          _focusAdminMapOnPoint(
                            center,
                            zoom: 18,
                            force: true,
                          );
                        }
                      },
                    ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: mapTagColor,
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Text(
                mapTagLabel,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 9,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (markerCount > 0 && actionAlertId.isNotEmpty)
            Positioned(
              top: 14,
              right: 14,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actionStatus == 'active' ||
                      actionStatus == 'verifying_speech') ...[
                    _buildAdminMapActionChip(
                      label: 'RESPOND',
                      color: const Color(0xFF111827),
                      onTap: () =>
                          _handleAlertAction(actionAlertId, actionStatus),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _buildAdminMapActionChip(
                    label: 'DONE',
                    color: const Color(0xFF0E5B3C),
                    onTap: () => _removeLocationAndAlerts(actionAlertId),
                  ),
                ],
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.02),
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    footerTitle,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 9,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    footerLocation,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyAlerts() {
    return _LuxuryPanel(
      title: 'EMERGENCY ALERTS',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('emergency_alerts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs
              .where((doc) => !_clearedAdminAlertIds.contains(doc.id))
              .toList()
            ..sort((a, b) {
              final aData = a.data();
              final bData = b.data();
              final aStatus = (aData['status'] ?? '').toString().toLowerCase();
              final bStatus = (bData['status'] ?? '').toString().toLowerCase();
              final aIsActive = aStatus == 'active' || aStatus == 'verifying_speech';
              final bIsActive = bStatus == 'active' || bStatus == 'verifying_speech';
              if (aIsActive != bIsActive) {
                return aIsActive ? -1 : 1;
              }
              final aTs = aData['timestamp'] as Timestamp?;
              final bTs = bData['timestamp'] as Timestamp?;
              return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
                aTs?.millisecondsSinceEpoch ?? 0,
              );
            });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: _buildEmergencySosMap(docs),
              ),
              Expanded(
                child: docs.isEmpty
                    ? const Center(
                        child: Text(
                          'No emergency alerts found.',
                          style: TextStyle(color: AppColors.textSub),
                        ),
                      )
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final sender = _resolveAlertSenderName(data);
                    final resolvedAlertPoint = _extractAlertCoordinates(
                      data,
                      alertId: docs[index].id,
                    );
                    final rawLocText = _formatLocationField(data['location']);
                    final locationText =
                        (rawLocText.startsWith('0.0000') || rawLocText == '-') &&
                            resolvedAlertPoint != null
                        ? _formatCoordinateValue(resolvedAlertPoint)
                        : rawLocText;
                    final status = (data['status'] ?? 'unknown')
                        .toString()
                        .toUpperCase();
                    final timestamp = _formatTimestamp(
                      data['timestamp'] as Timestamp?,
                    );

                    final isActive = (data['status'] ?? '').toString().toLowerCase() == 'active';
                    final senderInitial = sender.isNotEmpty ? sender[0].toUpperCase() : '!';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFFFEEEC)
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFFCB392B).withOpacity(0.35)
                              : AppColors.border,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sender initials avatar
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive
                                  ? const Color(0xFFCB392B)
                                  : AppColors.green,
                              border: Border.all(
                                color: isActive
                                    ? const Color(0xFFCB392B).withOpacity(0.4)
                                    : AppColors.gold,
                                width: 1.2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                senderInitial,
                                style: const TextStyle(
                                  fontFamily: 'CormorantGaramond',
                                  fontSize: 20,
                                  color: AppColors.goldLt,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (data['message'] ?? 'Emergency Alert').toString(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isActive
                                              ? const Color(0xFF7E1F14)
                                              : AppColors.green,
                                        ),
                                      ),
                                    ),
                                    // Status badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(0xFFCB392B).withOpacity(0.12)
                                            : status.toLowerCase() == 'false_alarm'
                                            ? const Color(0xFFFEF3C7)
                                            : AppColors.cream,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isActive
                                              ? const Color(0xFFCB392B).withOpacity(0.35)
                                              : status.toLowerCase() == 'false_alarm'
                                              ? const Color(0xFFF59E0B).withOpacity(0.5)
                                              : AppColors.border,
                                        ),
                                      ),
                                      child: Text(
                                        status.toUpperCase().replaceAll('_', ' '),
                                        style: TextStyle(
                                          fontSize: 9,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? const Color(0xFFCB392B)
                                              : status.toLowerCase() == 'false_alarm'
                                              ? const Color(0xFFB45309)
                                              : AppColors.textSub,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _AdminInfoRow('Sender', sender),
                                const SizedBox(height: 4),
                                _AdminInfoRow(
                                  'Location',
                                  status.toLowerCase() == 'resolved'
                                      ? 'Removed'
                                      : locationText,
                                ),
                                const SizedBox(height: 4),
                                _AdminInfoRow('Time', timestamp),
                                if (isActive ||
                                    status.toLowerCase() == 'verifying_speech') ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _handleAlertAction(
                                            docs[index].id,
                                            data['status']?.toString() ?? 'active',
                                          ),
                                          icon: const Icon(
                                            Icons.reply_outlined,
                                            size: 14,
                                            color: Color(0xFF111827),
                                          ),
                                          label: const Text(
                                            'RESPOND',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF111827),
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            backgroundColor: const Color(0xFF111827)
                                                .withOpacity(0.08),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => _removeLocationAndAlerts(
                                            docs[index].id,
                                          ),
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                            size: 14,
                                            color: Color(0xFF0E5B3C),
                                          ),
                                          label: const Text(
                                            'DONE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0E5B3C),
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            backgroundColor: const Color(0xFF0E5B3C)
                                                .withOpacity(0.08),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (status.toLowerCase() == 'responded' ||
                                    status.toLowerCase() == 'acknowledged' ||
                                    status.toLowerCase() == 'not_resolved') ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => _removeLocationAndAlerts(
                                        docs[index].id,
                                      ),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 14,
                                        color: Color(0xFF0E5B3C),
                                      ),
                                      label: const Text(
                                        'DONE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0E5B3C),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        backgroundColor:
                                            const Color(0xFF0E5B3C).withOpacity(0.08),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (status.toLowerCase() == 'false_alarm') ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () {
                                        _showMessage(
                                          "Student reported this alert as a false alarm (miss-clicked device).",
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 14,
                                        color: Color(0xFFB45309),
                                      ),
                                      label: const Text(
                                        'FALSE ALARM (STUDENT SAFE)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFB45309),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        backgroundColor: const Color(0xFFFEF3C7),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          side: BorderSide(
                                            color: const Color(0xFFF59E0B)
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (status.toLowerCase() == 'resolved') ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => _removeLocationAndAlerts(
                                        docs[index].id,
                                      ),
                                      icon: const Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: AppColors.green,
                                      ),
                                      label: const Text(
                                        'DONE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.green,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        backgroundColor: AppColors.green.withOpacity(0.08),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginActivity() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('login_logs')
        .orderBy('timestamp', descending: true);

    if (_selectedFilter != 'all') {
      query = query.where('status', isEqualTo: _selectedFilter);
    }

    return Column(
      children: [
        _buildFilterBar(),
        const SizedBox(height: 16),
        Expanded(
          child: _LuxuryPanel(
            title: 'LOGIN RECORDS',
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final email = (doc.data()['email'] ?? '')
                      .toString()
                      .toLowerCase();
                  return email.contains(_searchText.toLowerCase());
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No login records found.',
                      style: TextStyle(color: AppColors.textSub),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final status = (data['status'] ?? '').toString();
                    final isSuccess = status == 'success';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSuccess ? AppColors.white : const Color(0xFFFFEEEC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSuccess
                              ? AppColors.border
                              : const Color(0xFFCB392B).withOpacity(0.3),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSuccess ? AppColors.green : const Color(0xFFCB392B),
                              border: Border.all(
                                color: isSuccess ? AppColors.gold : const Color(0xFFCB392B).withOpacity(0.4),
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              isSuccess ? Icons.check_rounded : Icons.close_rounded,
                              color: AppColors.goldLt,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['email'] ?? 'No Email',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.green,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSuccess
                                            ? const Color(0xFFEAF7F0)
                                            : const Color(0xFFCB392B).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isSuccess
                                              ? const Color(0xFF2CA86E).withOpacity(0.4)
                                              : const Color(0xFFCB392B).withOpacity(0.35),
                                        ),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w600,
                                          color: isSuccess
                                              ? const Color(0xFF0E5B3C)
                                              : const Color(0xFFCB392B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _MiniTag(
                                      label: 'Role: ${data['role'] ?? 'unknown'}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _AdminInfoRow('Location', (data['location'] ?? 'Unknown').toString()),
                                const SizedBox(height: 4),
                                _AdminInfoRow('Device', (data['deviceId'] ?? 'Unknown').toString()),
                                if ((data['error'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFEEEC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFCB392B).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      'Error: ${data['error']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF7E1F14),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _AdminSearchField(
              hint: 'Search email address',
              onChanged: (value) {
                setState(() => _searchText = value);
              },
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: DropdownButton<String>(
              value: _selectedFilter,
              underline: const SizedBox(),
              dropdownColor: AppColors.white,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'success', child: Text('Success')),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedFilter = value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }


}

class _AdminMenuItem {
  final String title;
  final IconData icon;

  const _AdminMenuItem(this.title, this.icon);
}

/// A compact label-value row used inside admin cards.
class _AdminInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _AdminInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSub,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMain,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}



class _LuxurySummaryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Stream<QuerySnapshot> stream;

  const _LuxurySummaryCard({
    required this.title,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            final count = snapshot.data?.docs.length ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gold top accent line
                Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    gradient: LinearGradient(
                      colors: [AppColors.green, AppColors.gold],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.gold.withOpacity(0.3),
                          ),
                        ),
                        child: Icon(icon, color: AppColors.green, size: 18),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 4,
                          color: AppColors.gold.withOpacity(0.9),
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontFamily: 'CormorantGaramond',
                          fontSize: 34,
                          fontWeight: FontWeight.w300,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LuxuryPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _LuxuryPanel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 4,
                        color: AppColors.gold.withOpacity(0.9),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _AdminSearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textSub),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: AppColors.green),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;

  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.textSub,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}



class _AdminBackground extends StatelessWidget {
  const _AdminBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AdminVinesPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _AdminVinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final vine = Paint()
      ..color = AppColors.green.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final leaf = Paint()
      ..color = AppColors.gold.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final left = Path()
      ..moveTo(w * 0.03, h)
      ..cubicTo(w * 0.03, h * 0.80, w * 0.01, h * 0.65, w * 0.05, h * 0.48)
      ..cubicTo(w * 0.08, h * 0.34, w * 0.01, h * 0.18, w * 0.06, 0);

    final right = Path()
      ..moveTo(w * 0.97, h)
      ..cubicTo(w * 0.97, h * 0.82, w * 0.99, h * 0.68, w * 0.94, h * 0.50)
      ..cubicTo(w * 0.90, h * 0.34, w * 0.98, h * 0.18, w * 0.93, 0);

    canvas.drawPath(left, vine);
    canvas.drawPath(right, vine);

    void drawLeaf(Offset center, double rx, double ry) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx, height: ry),
        leaf,
      );
    }

    drawLeaf(Offset(w * 0.035, h * 0.78), 14, 8);
    drawLeaf(Offset(w * 0.055, h * 0.58), 12, 7);
    drawLeaf(Offset(w * 0.028, h * 0.36), 13, 8);
    drawLeaf(Offset(w * 0.95, h * 0.74), 14, 8);
    drawLeaf(Offset(w * 0.93, h * 0.52), 12, 7);
    drawLeaf(Offset(w * 0.965, h * 0.30), 13, 8);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// keep same color theme used by your login page
class AppColors {
  static const white = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F5F0);
  static const cream = Color(0xFFF0EBE0);
  static const gold = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const goldLt = Color(0xFFE8D08A);
  static const green = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright = Color(0xFF2CA86E);
  static const border = Color(0x55C9A551);
  static const glass = Color(0xFFFFFFFF);
  static const shadow = Color(0x14000000);
  static const textMain = Color(0xFF1A1A1A);
  static const textSub = Color(0xFF888880);
}
