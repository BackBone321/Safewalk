import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';
import '../utils/google_maps_web_guard.dart';
import 'guardian_contacts_panel.dart';

class ParentDashboardPage extends StatefulWidget {
  const ParentDashboardPage({super.key});

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  int _selectedNavIndex = 0;
  static const String _hf = 'CormorantGaramond';
  static const String _bf = 'JosefinSans';
  static const LatLng _defaultMapCenter = LatLng(14.5995, 120.9842);
  static final Set<Factory<OneSequenceGestureRecognizer>>
  _mapGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isProfileSheetOpen = false;

  final TextEditingController _profileNameCtrl = TextEditingController();
  final TextEditingController _profilePhoneCtrl = TextEditingController();
  final TextEditingController _inviteStudentUidCtrl = TextEditingController();
  final TextEditingController _inviteStudentPhoneCtrl = TextEditingController();
  bool _isSendingInvite = false;

  String _parentName = 'Parent';
  String _parentEmail = '';
  String _parentPhone = '';
  String _parentUid = '';
  String _avatarMood = 'happy';
  List<_LinkedStudent> _linkedStudents = const [];

  String _childUid = '';
  String _childName = 'Student';
  String _childPhone = '';
  String _childRoute = 'Main Campus -> Dorm Block C';
  bool _childSessionActive = false;
  double _childDistanceKm = 1.2;

  String _deviceId = 'Not linked';
  String _deviceName = 'No linked device';
  String _deviceLocation = 'Unknown';
  String _deviceStatus = 'offline';
  LatLng? _childDeviceCoordinates;
  BitmapDescriptor? _sosMarkerIcon;
  BitmapDescriptor? _ackMarkerIcon;
  BitmapDescriptor? _unresolvedMarkerIcon;
  BitmapDescriptor? _respondedMarkerIcon;
  GoogleMapController? _parentMapController;
  LatLng? _lastFocusedParentMapPoint;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _childUserStreamSub;
  StreamSubscription<dynamic>? _childDeviceStreamSub;
  Map<String, dynamic> _latestChildDocData = const {};
  Map<String, dynamic> _latestDeviceDocData = const {};

  bool _alertsEnabled = true;
  bool _smsAlertsEnabled = true;
  bool _emailAlertsEnabled = true;

  bool get _mobileMapLiteMode => false;

  final List<_NavItem> _navItems = const [
    _NavItem('Child', Icons.shield_outlined),
    _NavItem('Alerts', Icons.notifications_none_rounded),
    _NavItem('Profile', Icons.person_outline),
  ];

  // ─── Helpers ──────────────────────────────────────────────────

  String _normalizePhoneForLookup(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+|-'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    return cleaned;
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

  LatLng? _extractDeviceCoordinates(Map<String, dynamic> data) {
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

    final location = data['location'] ?? data['currentLocation'];
    if (location is GeoPoint) {
      if (_isValidLatLng(location.latitude, location.longitude)) {
        candidates.add(LatLng(location.latitude, location.longitude));
      }
    } else if (location is String) {
      final parsed = _coordinatesFromText(location);
      if (parsed != null) candidates.add(parsed);
    }

    final locationText = data['locationText'];
    if (locationText is String) {
      final parsedText = _coordinatesFromText(locationText);
      if (parsedText != null) candidates.add(parsedText);
    }

    final direct = _coordinatesFromValues(
      data['latitude'] ?? data['lat'],
      data['longitude'] ?? data['lng'] ?? data['lon'],
    );
    if (direct != null) candidates.add(direct);

    if (candidates.isEmpty) return null;
    for (final c in candidates) {
      if (!_isDefaultManila(c)) return c;
    }
    return candidates.first;
  }

  bool _isDefaultManila(LatLng? p) {
    if (p == null) return false;
    return (p.latitude - 14.5995).abs() < 0.005 &&
        (p.longitude - 120.9842).abs() < 0.005;
  }

  LatLng? _extractAlertCoordinates(Map<String, dynamic> data) {
    if (data['locationCleared'] == true ||
        data['falseAlarm'] == true ||
        (data['status'] ?? '').toString().toLowerCase() == 'false_alarm' ||
        (data['status'] ?? '').toString().toLowerCase() == 'cancelled_false_trigger' ||
        (data['status'] ?? '').toString().toLowerCase() == 'resolved') {
      return null;
    }

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

    LatLng? rawAlertPoint;
    for (final c in candidates) {
      if (!_isDefaultManila(c)) {
        rawAlertPoint = c;
        break;
      }
    }

    if (rawAlertPoint != null) return rawAlertPoint;
    if (_childDeviceCoordinates != null &&
        !_isDefaultManila(_childDeviceCoordinates)) {
      return _childDeviceCoordinates;
    }
    return candidates.isNotEmpty ? candidates.first : _childDeviceCoordinates;
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
      ..color = Colors.black.withValues(alpha: 0.22)
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
      final orange = await _buildSosMarkerBytes(color: const Color(0xFFF97316));
      final violet = await _buildSosMarkerBytes(color: const Color(0xFF7C3AED));
      final dark = await _buildSosMarkerBytes(color: const Color(0xFF111827));
      if (!mounted) return;
      setState(() {
        if (red.isNotEmpty) {
          _sosMarkerIcon = BitmapDescriptor.bytes(red, width: 38, height: 38);
        }
        if (orange.isNotEmpty) {
          _ackMarkerIcon = BitmapDescriptor.bytes(orange, width: 38, height: 38);
        }
        if (violet.isNotEmpty) {
          _unresolvedMarkerIcon = BitmapDescriptor.bytes(
            violet,
            width: 38,
            height: 38,
          );
        }
        if (dark.isNotEmpty) {
          _respondedMarkerIcon = BitmapDescriptor.bytes(
            dark,
            width: 38,
            height: 38,
          );
        }
      });
    } catch (_) {}
  }

  bool _isOpenSosStatus(String status) {
    return status == 'active' ||
        status == 'verifying_speech' ||
        status == 'responded' ||
        status == 'acknowledged' ||
        status == 'not_resolved';
  }

  String _stableStudentKey(Map<String, dynamic> data) {
    final deviceId = (data['deviceId'] ?? '').toString().trim();
    if (deviceId.isNotEmpty && deviceId != 'Not linked') return deviceId;
    final uid = (data['studentUid'] ?? data['uid'] ?? '').toString().trim();
    return uid;
  }

  int _alertTimeMs(Map<String, dynamic> data) {
    final ts = data['timestamp'];
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    final client = data['clientTimestamp'];
    if (client is Timestamp) return client.millisecondsSinceEpoch;
    return 0;
  }

  bool _alertIsSelectedChild(Map<String, dynamic> data) {
    final uid = (data['studentUid'] ?? data['uid'] ?? '').toString().trim();
    final deviceId = (data['deviceId'] ?? '').toString().trim();
    if (_childUid.isNotEmpty && uid == _childUid) return true;
    if (_deviceId.isNotEmpty &&
        _deviceId != 'Not linked' &&
        deviceId == _deviceId) {
      return true;
    }
    return false;
  }

  BitmapDescriptor _markerIconForStatus(String status) {
    if (status == 'responded') {
      return _respondedMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (status == 'acknowledged') {
      return _ackMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
    if (status == 'not_resolved') {
      return _unresolvedMarkerIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
    return _sosMarkerIcon ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }

  LatLng get _childMapCenter => _childDeviceCoordinates ?? _defaultMapCenter;

  bool _isSamePoint(LatLng a, LatLng b) {
    const tolerance = 0.00001;
    return (a.latitude - b.latitude).abs() <= tolerance &&
        (a.longitude - b.longitude).abs() <= tolerance;
  }

  void _focusParentMapOnPoint(
    LatLng point, {
    double zoom = 16,
    bool force = false,
  }) {
    final controller = _parentMapController;
    if (controller == null) return;
    if (!force &&
        _lastFocusedParentMapPoint != null &&
        _isSamePoint(_lastFocusedParentMapPoint!, point)) {
      return;
    }
    _lastFocusedParentMapPoint = point;
    try {
      controller
          .animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: point, zoom: zoom),
            ),
          )
          .catchError((_) {});
    } catch (e) {
      debugPrint('Parent Google Map not ready yet: $e');
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    var dt = ts.toDate().toLocal();
    // Correct year 2070 or corrupted modem RTC default epoch (1970 mapped to 2070):
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

  String _formatCoordinateValue(LatLng? value) {
    if (value == null) return 'No SOS location yet';
    return '${value.latitude.toStringAsFixed(6)}, ${value.longitude.toStringAsFixed(6)}';
  }

  Map<String, String> get _linkedStudentNamesByUid {
    final map = <String, String>{};
    for (final student in _linkedStudents) {
      final uid = student.uid.trim();
      if (uid.isEmpty) continue;
      map[uid] = student.name.trim().isEmpty ? 'Student' : student.name.trim();
    }
    return map;
  }

  String _resolveStudentNameFromAlert(
    Map<String, dynamic> data, {
    required Map<String, String> linkedNameByUid,
  }) {
    final explicit = (data['fullName'] ?? data['studentName'] ?? '')
        .toString()
        .trim();
    if (explicit.isNotEmpty) return explicit;

    final uid = (data['uid'] ?? data['studentUid'] ?? '').toString().trim();
    if (uid.isEmpty) return _childName;

    // Search in _linkedStudents for a child matching uid or deviceId
    for (final child in _linkedStudents) {
      if (child.uid == uid ||
          (child.deviceId.isNotEmpty && child.deviceId == uid)) {
        return child.name;
      }
    }

    return linkedNameByUid[uid] ?? _childName;
  }

  Future<void> _switchActiveChild(String childUid) async {
    final targetUid = childUid.trim();
    if (targetUid.isEmpty || targetUid == _childUid) return;
    try {
      await _loadChildData(targetUid);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('user_settings').doc(uid).set({
          'childUid': targetUid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      _showActionSnack('Failed to switch child: $e', isError: true);
    }
  }

  void _showActionSnack(String label, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          label,
          style: const TextStyle(fontFamily: _bf, letterSpacing: 0.5),
        ),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await _firestore.collection('emergency_alerts').doc(alertId).set({
        'status': 'acknowledged',
        'ackBy': uid,
        'ackAt': FieldValue.serverTimestamp(),
        'locationCleared': false,
      }, SetOptions(merge: true));
      _showActionSnack('Alert acknowledged. Marker is now orange.');
    } catch (e) {
      _showActionSnack('Failed to acknowledge alert: $e', isError: true);
    }
  }

  Future<void> _markAlertNotResolved(String alertId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await _firestore.collection('emergency_alerts').doc(alertId).set({
        'status': 'not_resolved',
        'notResolvedBy': uid,
        'notResolvedAt': FieldValue.serverTimestamp(),
        'locationCleared': false,
      }, SetOptions(merge: true));
      _showActionSnack('Student not found yet. Marker is now violet.');
    } catch (e) {
      _showActionSnack('Failed to update alert: $e', isError: true);
    }
  }

  Future<void> _resolveAlertDone(String alertId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await _firestore.collection('emergency_alerts').doc(alertId).set({
        'status': 'resolved',
        'resolvedBy': uid,
        'resolvedAt': FieldValue.serverTimestamp(),
        'locationCleared': true,
        'location': 'Location removed',
        'coordinates': FieldValue.delete(),
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'lat': FieldValue.delete(),
        'lng': FieldValue.delete(),
        'lon': FieldValue.delete(),
      }, SetOptions(merge: true));
      _showActionSnack('Done. Location marker removed from the map.');
    } catch (e) {
      _showActionSnack('Failed to resolve alert: $e', isError: true);
    }
  }

  Widget _buildAlertStatusActions(String alertId, String status) {
    final normalized = status.toLowerCase().trim();
    final isActive =
        normalized == 'active' || normalized == 'verifying_speech';
    if (isActive) {
      return _buildFullWidthStatusButton(
        label: 'ACKNOWLEDGE',
        color: AppColors.green,
        onTap: () => _acknowledgeAlert(alertId),
      );
    }
    if (normalized == 'acknowledged' ||
        normalized == 'not_resolved' ||
        normalized == 'responded') {
      return Column(
        children: [
          _buildFullWidthStatusButton(
            label: 'DONE',
            color: const Color(0xFFCB392B),
            onTap: () => _resolveAlertDone(alertId),
          ),
          if (normalized == 'acknowledged') ...[
            const SizedBox(height: 8),
            _buildFullWidthStatusButton(
              label: 'NOT RESOLVED',
              color: const Color(0xFF6D28D9),
              onTap: () => _markAlertNotResolved(alertId),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFullWidthStatusButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: _bf,
                color: Colors.white,
                letterSpacing: 3,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
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
          fontFamily: _bf,
          color: Color(0xFFFFF1B8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ─── Data Loading ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _prepareMapMarkers();
    _loadDashboard();
  }

  @override
  void dispose() {
    _childUserStreamSub?.cancel();
    _childDeviceStreamSub?.cancel();
    _parentMapController?.dispose();
    _profileNameCtrl.dispose();
    _profilePhoneCtrl.dispose();
    _inviteStudentUidCtrl.dispose();
    _inviteStudentPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }
    try {
      final parentDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final settingsDoc = await _firestore
          .collection('user_settings')
          .doc(currentUser.uid)
          .get();
      final parentData = parentDoc.data() ?? <String, dynamic>{};
      final parentPhone = (parentData['phoneNumber'] ?? '').toString();
      final normalizedParentPhone = _normalizePhoneForLookup(parentPhone);
      if (!mounted) return;
      setState(() {
        _parentUid = currentUser.uid;
        _parentName = (parentData['fullName'] ?? 'Parent').toString();
        _parentEmail = (parentData['email'] ?? '').toString();
        _parentPhone = parentPhone;
        _avatarMood = (parentData['avatarMood'] ?? 'happy').toString();
        _alertsEnabled =
            (settingsDoc.data()?['alertsEnabled'] as bool?) ?? true;
        _smsAlertsEnabled =
            (settingsDoc.data()?['smsAlertsEnabled'] as bool?) ?? true;
        _emailAlertsEnabled =
            (settingsDoc.data()?['emailAlertsEnabled'] as bool?) ?? true;
      });

      var linkedStudents = await _fetchLinkedStudents(
        parentUid: currentUser.uid,
        normalizedParentPhone: normalizedParentPhone,
      );
      if (linkedStudents.isEmpty) {
        final configuredUid = (settingsDoc.data()?['childUid'] ?? '')
            .toString()
            .trim();
        final device = await _findChildDevice(
          childUid: configuredUid,
          childDeviceId: '',
          rawPhone: '',
        );
        if (device != null) {
          final data = device.data;
          final studentUid = (data['studentUid'] ?? configuredUid)
              .toString()
              .trim();
          final deviceId = (data['deviceId'] ?? device.id).toString();
          var studentName = (data['studentName'] ?? 'Student').toString();
          var studentPhone = '';
          if (studentUid.isNotEmpty) {
            final studentDoc = await _firestore
                .collection('users')
                .doc(studentUid)
                .get();
            if (studentDoc.exists) {
              studentName = (studentDoc.data()?['fullName'] ?? studentName)
                  .toString();
              studentPhone = (studentDoc.data()?['phoneNumber'] ?? '')
                  .toString();
            }
          }
          linkedStudents = [
            _LinkedStudent(
              uid: studentUid.isNotEmpty ? studentUid : device.id,
              name: studentName.trim().isEmpty ? 'Student' : studentName,
              phone: studentPhone,
              deviceId: deviceId,
            ),
          ];
        }
      }
      if (!mounted) return;
      setState(() => _linkedStudents = linkedStudents);

      String configuredChildUid = (settingsDoc.data()?['childUid'] ?? '')
          .toString()
          .trim();
      final hasConfiguredChild = linkedStudents.any(
        (student) => student.uid == configuredChildUid,
      );
      if (!hasConfiguredChild) {
        configuredChildUid = linkedStudents.isNotEmpty
            ? linkedStudents.first.uid
            : '';
      }

      if (configuredChildUid.isNotEmpty) {
        await _loadChildData(configuredChildUid);
      } else if (mounted) {
        setState(() {
          _childUid = '';
          _childName = 'Student';
          _childPhone = '';
          _childRoute = 'Main Campus -> Dorm Block C';
          _childSessionActive = false;
          _childDistanceKm = 0;
          _deviceId = 'Not linked';
          _deviceName = 'No linked device';
          _deviceLocation = 'Unknown';
          _deviceStatus = 'offline';
          _childDeviceCoordinates = null;
        });
      }
    } catch (e) {
      _showActionSnack('Failed to load parent dashboard: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<_LinkedStudent>> _fetchLinkedStudents({
    required String parentUid,
    required String normalizedParentPhone,
  }) async {
    if (parentUid.trim().isEmpty) return const [];

    final byUid = await _firestore
        .collection('parent_student_links')
        .where('parentUid', isEqualTo: parentUid)
        .limit(100)
        .get();

    final byPhone = byUid.docs.isEmpty && normalizedParentPhone.isNotEmpty
        ? await _firestore
              .collection('parent_student_links')
              .where('parentPhoneNormalized', isEqualTo: normalizedParentPhone)
              .limit(100)
              .get()
        : null;

    final docs = byUid.docs.isNotEmpty
        ? byUid.docs
        : (byPhone?.docs ?? const []);
    final uniqueByStudentUid = <String, _LinkedStudent>{};

    for (final doc in docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'accepted').toString().toLowerCase();
      if (status != 'accepted') continue;

      final studentUid = (data['studentUid'] ?? '').toString().trim();
      if (studentUid.isEmpty) continue;

      final studentDoc = await _firestore
          .collection('users')
          .doc(studentUid)
          .get();

      var studentName = (data['studentName'] ?? '').toString().trim();
      var studentPhone = (data['studentPhone'] ?? '').toString().trim();
      String studentDeviceId = '';

      if (studentDoc.exists) {
        studentDeviceId = (studentDoc.data()?['linkedDeviceId'] ?? '')
            .toString()
            .trim();
        if (studentName.isEmpty) {
          studentName = (studentDoc.data()?['fullName'] ?? 'Student')
              .toString()
              .trim();
        }
        if (studentPhone.isEmpty) {
          studentPhone = (studentDoc.data()?['phoneNumber'] ?? '')
              .toString()
              .trim();
        }
      }

      uniqueByStudentUid[studentUid] = _LinkedStudent(
        uid: studentUid,
        name: studentName.isEmpty ? 'Student' : studentName,
        phone: studentPhone,
        deviceId: studentDeviceId,
      );
    }

    final result = uniqueByStudentUid.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> _sendStudentInvitation({required String studentUid}) async {
    final parentUid = FirebaseAuth.instance.currentUser?.uid;
    if (parentUid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }

    final targetUid = studentUid.trim();
    if (targetUid.isEmpty) {
      _showActionSnack('Enter a Student UID or phone number.', isError: true);
      return;
    }

    final studentDoc = await _firestore
        .collection('users')
        .doc(targetUid)
        .get();
    if (!studentDoc.exists) {
      _showActionSnack('Student account not found.', isError: true);
      return;
    }
    final role = (studentDoc.data()?['role'] ?? '').toString().toLowerCase();
    if (role != 'student') {
      _showActionSnack('That UID is not a student account.', isError: true);
      return;
    }

    final linkId = '${parentUid}_$targetUid';
    final linkDoc = await _firestore
        .collection('parent_student_links')
        .doc(linkId)
        .get();
    final linkStatus = (linkDoc.data()?['status'] ?? 'accepted')
        .toString()
        .toLowerCase();
    if (linkDoc.exists && linkStatus == 'accepted') {
      _showActionSnack('Student is already linked to your account.');
      return;
    }

    final studentData = studentDoc.data() ?? <String, dynamic>{};
    final studentName = (studentData['fullName'] ?? 'Student').toString();
    final studentPhone = (studentData['phoneNumber'] ?? '').toString();
    final parentPhone = _parentPhone.trim();

    await _firestore.collection('parent_student_invitations').doc(linkId).set({
      'parentUid': parentUid,
      'parentName': _parentName.trim(),
      'parentPhone': parentPhone,
      'parentPhoneNormalized': _normalizePhoneForLookup(parentPhone),
      'studentUid': targetUid,
      'studentName': studentName,
      'studentPhone': studentPhone,
      'studentPhoneNormalized': _normalizePhoneForLookup(studentPhone),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _showActionSnack('Invitation sent to $studentName.');
  }

  Future<void> _handleSendInvitationInProfile() async {
    final enteredUid = _inviteStudentUidCtrl.text.trim();
    final enteredPhone = _inviteStudentPhoneCtrl.text.trim();
    if (enteredUid.isEmpty && enteredPhone.isEmpty) {
      _showActionSnack('Enter a valid student UID or phone number.', isError: true);
      return;
    }

    setState(() => _isSendingInvite = true);
    try {
      String targetUid = enteredUid;
      if (targetUid.isEmpty && enteredPhone.isNotEmpty) {
        targetUid = await _resolveStudentUidFromPhone(enteredPhone);
      }

      if (targetUid.isEmpty) {
        _showActionSnack('Student account not found with that phone number.', isError: true);
        return;
      }

      await _sendStudentInvitation(studentUid: targetUid);
      _inviteStudentUidCtrl.clear();
      _inviteStudentPhoneCtrl.clear();
      await _loadDashboard();
    } finally {
      if (mounted) {
        setState(() => _isSendingInvite = false);
      }
    }
  }

  void _applyResolvedChildAndDeviceState({
    required String childUid,
    required Map<String, dynamic> childData,
    Map<String, dynamic>? deviceData,
    String? deviceDocId,
  }) {
    if (!mounted) return;
    final childName = (childData['fullName'] ?? 'Student').toString();
    final childPhone = (childData['phoneNumber'] ?? '').toString();
    final childDeviceId = (childData['linkedDeviceId'] ?? '').toString().trim();

    final deviceCoords = deviceData != null
        ? _extractDeviceCoordinates(deviceData)
        : null;
    final studentCoords = _extractDeviceCoordinates(childData);

    final deviceValid = deviceCoords != null && !_isDefaultManila(deviceCoords);
    final studentValid =
        studentCoords != null && !_isDefaultManila(studentCoords);

    LatLng? bestCoords;
    bool useStudentSource = false;
    if (deviceValid) {
      bestCoords = deviceCoords;
    } else if (studentValid) {
      bestCoords = studentCoords;
      useStudentSource = true;
    } else {
      bestCoords = deviceCoords ?? studentCoords;
      useStudentSource = deviceCoords == null && studentCoords != null;
    }

    final prevCoords = _childDeviceCoordinates;
    setState(() {
      _childUid = childUid;
      _childName = childName;
      _childPhone = childPhone;

      if (deviceData != null) {
        _deviceId = (deviceData['deviceId'] ?? deviceDocId ?? childDeviceId)
            .toString();
        _deviceName = (deviceData['deviceName'] ?? 'Emergency Device')
            .toString();
        _deviceStatus = (deviceData['status'] ?? 'active')
            .toString()
            .toLowerCase();
      } else {
        _deviceId = childDeviceId.isNotEmpty
            ? childDeviceId
            : 'Student Device (Live)';
        _deviceName = childDeviceId.isNotEmpty
            ? 'Unknown Tracker'
            : '${childName.isNotEmpty ? childName : 'Student'}\'s Phone';
        _deviceStatus = bestCoords != null ? 'active' : 'offline';
      }

      _childDeviceCoordinates = bestCoords;
      if (bestCoords != null && !_isDefaultManila(bestCoords)) {
        _deviceLocation = _formatCoordinateValue(bestCoords);
      } else if (useStudentSource || deviceData == null) {
        final userLocField =
            childData['location'] ?? childData['currentLocation'];
        _deviceLocation = userLocField is GeoPoint
            ? '${userLocField.latitude.toStringAsFixed(6)}, ${userLocField.longitude.toStringAsFixed(6)}'
            : (childData['locationText'] ?? userLocField ?? 'Unknown')
                  .toString();
      } else {
        final locationField = deviceData['location'];
        _deviceLocation = locationField is GeoPoint
            ? '${locationField.latitude.toStringAsFixed(6)}, ${locationField.longitude.toStringAsFixed(6)}'
            : (deviceData['locationText'] ?? locationField ?? 'Unknown')
                  .toString();
      }
    });

    if (_childDeviceCoordinates != null &&
        (prevCoords == null ||
            !_isSamePoint(prevCoords, _childDeviceCoordinates!))) {
      _focusParentMapOnPoint(_childDeviceCoordinates!, zoom: 18);
    }
  }

  void _subscribeToChildRealtimeLocation({
    required String childUid,
    required String childDeviceId,
    required String rawPhone,
    String? directDeviceDocId,
  }) {
    _childUserStreamSub?.cancel();
    _childDeviceStreamSub?.cancel();

    _childUserStreamSub = _firestore
        .collection('users')
        .doc(childUid)
        .snapshots()
        .listen((docSnap) {
          if (!docSnap.exists || docSnap.data() == null) return;
          _latestChildDocData = docSnap.data()!;
          final updatedDevId = (_latestChildDocData['linkedDeviceId'] ?? '')
              .toString()
              .trim();
          _applyResolvedChildAndDeviceState(
            childUid: childUid,
            childData: _latestChildDocData,
            deviceData: _latestDeviceDocData.isEmpty
                ? null
                : _latestDeviceDocData,
          );
          if (updatedDevId.isNotEmpty && updatedDevId != childDeviceId) {
            _subscribeToChildRealtimeLocation(
              childUid: childUid,
              childDeviceId: updatedDevId,
              rawPhone: rawPhone,
            );
          }
        }, onError: (e) {
          debugPrint('Parent child user stream error: $e');
        });

    final resolvedDocId = (directDeviceDocId != null && directDeviceDocId.isNotEmpty)
        ? directDeviceDocId
        : null;

    if (resolvedDocId != null) {
      _childDeviceStreamSub = _firestore
          .collection('devices')
          .doc(resolvedDocId)
          .snapshots()
          .listen((docSnap) {
            if (!docSnap.exists || docSnap.data() == null) {
              if (childDeviceId.isNotEmpty && childDeviceId != resolvedDocId) {
                _listenForDeviceByField(
                  childUid: childUid,
                  childDeviceId: childDeviceId,
                  rawPhone: rawPhone,
                );
              }
              return;
            }
            _latestDeviceDocData = docSnap.data()!;
            _applyResolvedChildAndDeviceState(
              childUid: childUid,
              childData: _latestChildDocData,
              deviceData: _latestDeviceDocData,
              deviceDocId: docSnap.id,
            );
          }, onError: (e) {
            debugPrint('Parent child device doc stream error: $e');
            _listenForDeviceByField(
              childUid: childUid,
              childDeviceId: childDeviceId,
              rawPhone: rawPhone,
            );
          });
    } else {
      _listenForDeviceByField(
        childUid: childUid,
        childDeviceId: childDeviceId,
        rawPhone: rawPhone,
      );
    }
  }

  void _listenForDeviceByField({
    required String childUid,
    required String childDeviceId,
    required String rawPhone,
  }) {
    _childDeviceStreamSub?.cancel();
    final Query<Map<String, dynamic>> devQuery;
    if (childDeviceId.isNotEmpty) {
      devQuery = _firestore
          .collection('devices')
          .where('deviceId', isEqualTo: childDeviceId)
          .limit(1);
    } else if (childUid.isNotEmpty) {
      devQuery = _firestore
          .collection('devices')
          .where('studentUid', isEqualTo: childUid)
          .limit(1);
    } else if (rawPhone.isNotEmpty) {
      devQuery = _firestore
          .collection('devices')
          .where('phoneNumber', isEqualTo: rawPhone)
          .limit(1);
    } else if (_parentUid.isNotEmpty) {
      devQuery = _firestore
          .collection('devices')
          .where('parentUid', isEqualTo: _parentUid)
          .limit(1);
    } else {
      return;
    }

    _childDeviceStreamSub = devQuery.snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;
      _latestDeviceDocData = snap.docs.first.data();
      _applyResolvedChildAndDeviceState(
        childUid: childUid,
        childData: _latestChildDocData,
        deviceData: _latestDeviceDocData,
        deviceDocId: snap.docs.first.id,
      );
    }, onError: (e) {
      debugPrint('Parent child device stream error: $e');
    });
  }

  Future<({String id, Map<String, dynamic> data})?> _findChildDevice({
    required String childUid,
    required String childDeviceId,
    required String rawPhone,
  }) async {
    Future<({String id, Map<String, dynamic> data})?> firstOf(
      Query<Map<String, dynamic>> query,
    ) async {
      final snap = await query.limit(1).get();
      if (snap.docs.isEmpty) return null;
      return (id: snap.docs.first.id, data: snap.docs.first.data());
    }

    if (childDeviceId.isNotEmpty) {
      final byField = await firstOf(
        _firestore
            .collection('devices')
            .where('deviceId', isEqualTo: childDeviceId),
      );
      if (byField != null) return byField;
      final direct = await _firestore
          .collection('devices')
          .doc(childDeviceId)
          .get();
      if (direct.exists && direct.data() != null) {
        return (id: direct.id, data: direct.data()!);
      }
    }

    if (childUid.isNotEmpty) {
      final byStudent = await firstOf(
        _firestore
            .collection('devices')
            .where('studentUid', isEqualTo: childUid),
      );
      if (byStudent != null) return byStudent;
    }

    final normalizedPhone = _normalizePhoneForLookup(rawPhone);
    if (rawPhone.isNotEmpty) {
      final byPhone = await firstOf(
        _firestore
            .collection('devices')
            .where('phoneNumber', isEqualTo: rawPhone),
      );
      if (byPhone != null) return byPhone;
    }
    if (normalizedPhone.isNotEmpty && normalizedPhone != rawPhone) {
      final byNorm = await firstOf(
        _firestore
            .collection('devices')
            .where('phoneNumber', isEqualTo: normalizedPhone),
      );
      if (byNorm != null) return byNorm;
    }

    final parentUid = _parentUid.trim().isNotEmpty
        ? _parentUid.trim()
        : (FirebaseAuth.instance.currentUser?.uid ?? '');
    if (parentUid.isNotEmpty) {
      final byParent = await firstOf(
        _firestore.collection('devices').where('parentUid', isEqualTo: parentUid),
      );
      if (byParent != null) return byParent;
    }

    final fallback = await _firestore
        .collection('devices')
        .doc('safewalk_device_001')
        .get();
    if (fallback.exists && fallback.data() != null) {
      return (id: fallback.id, data: fallback.data()!);
    }
    return null;
  }

  Future<void> _loadChildData(String childUid) async {
    final childDoc = await _firestore.collection('users').doc(childUid).get();
    final childData = childDoc.data() ?? <String, dynamic>{};
    _latestChildDocData = childData;
    _latestDeviceDocData = const {};
    final childPhone = (childData['phoneNumber'] ?? '').toString();
    final rawPhone = childPhone.trim();
    final childDeviceId = (childData['linkedDeviceId'] ?? '').toString().trim();
    final resolvedDevice = await _findChildDevice(
      childUid: childUid,
      childDeviceId: childDeviceId,
      rawPhone: rawPhone,
    );

    Map<String, dynamic>? resolvedDeviceData;
    String? resolvedDeviceDocId;
    if (resolvedDevice != null) {
      resolvedDeviceData = resolvedDevice.data;
      resolvedDeviceDocId = resolvedDevice.id;
      _latestDeviceDocData = resolvedDeviceData;
    }

    final walkQuery = await _firestore
        .collection('walk_sessions')
        .where('uid', isEqualTo: childUid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (!mounted) return;
    setState(() {
      if (walkQuery.docs.isNotEmpty) {
        final walkData = walkQuery.docs.first.data();
        _childSessionActive = true;
        _childRoute = (walkData['route'] ?? _childRoute).toString();
        _childDistanceKm =
            (walkData['distanceKm'] as num?)?.toDouble() ?? _childDistanceKm;
      } else {
        _childSessionActive = false;
      }
    });

    _applyResolvedChildAndDeviceState(
      childUid: childUid,
      childData: childData,
      deviceData: resolvedDeviceData,
      deviceDocId: resolvedDeviceDocId,
    );

    final trackedDeviceId = childDeviceId.isNotEmpty
        ? childDeviceId
        : (resolvedDeviceData?['deviceId'] ?? '').toString();
    _subscribeToChildRealtimeLocation(
      childUid: childUid,
      childDeviceId: trackedDeviceId,
      rawPhone: rawPhone,
      directDeviceDocId: resolvedDeviceDocId,
    );
  }

  Future<String> _resolveStudentUidFromPhone(String inputPhone) async {
    final rawPhone = inputPhone.trim();
    if (rawPhone.isEmpty) return '';
    final normalizedPhone = _normalizePhoneForLookup(rawPhone);

    var query = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('phoneNumber', isEqualTo: rawPhone)
        .limit(1)
        .get();

    if (query.docs.isEmpty && normalizedPhone != rawPhone) {
      query = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
    }

    if (query.docs.isEmpty) return '';
    return query.docs.first.id;
  }

  // ─── Save Methods ──────────────────────────────────────────────

  Future<void> _saveProfile(
    String fullName,
    String phoneNumber,
    String avatarMood,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _firestore.collection('users').doc(uid).set({
        'fullName': fullName.trim(),
        'phoneNumber': phoneNumber.trim(),
        'avatarMood': avatarMood,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _parentName = fullName.trim();
        _parentPhone = phoneNumber.trim();
        _avatarMood = avatarMood;
      });
      _showActionSnack('Profile updated.');
    } catch (e) {
      _showActionSnack('Failed to update profile: $e', isError: true);
    }
  }

  Future<void> _saveSettings({
    required bool alertsEnabled,
    required bool smsAlertsEnabled,
    required bool emailAlertsEnabled,
    required String childUid,
    String childPhoneNumber = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _firestore.collection('user_settings').doc(uid).set({
        'alertsEnabled': alertsEnabled,
        'smsAlertsEnabled': smsAlertsEnabled,
        'emailAlertsEnabled': emailAlertsEnabled,
        'childUid': childUid.trim(),
        'childPhoneNumber': childPhoneNumber.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _alertsEnabled = alertsEnabled;
        _smsAlertsEnabled = smsAlertsEnabled;
        _emailAlertsEnabled = emailAlertsEnabled;
      });
      final resolvedChildUid = childUid.trim();
      if (resolvedChildUid.isNotEmpty && resolvedChildUid != _childUid) {
        await _loadChildData(resolvedChildUid);
      } else if (resolvedChildUid.isEmpty) {
        setState(() {
          _childUid = '';
          _childName = 'Student';
          _childPhone = '';
          _childSessionActive = false;
          _childDistanceKm = 0;
          _deviceId = 'Not linked';
          _deviceName = 'No linked device';
          _deviceLocation = 'Unknown';
          _deviceStatus = 'offline';
          _childDeviceCoordinates = null;
        });
      }
      _showActionSnack('Settings saved.');
    } catch (e) {
      _showActionSnack('Failed to save settings: $e', isError: true);
    }
  }

  // ─── LUXURY SHEETS ─────────────────────────────────────────────

  Future<void> _showChildStatusDialog() async {
    if (_linkedStudents.isEmpty) {
      _showActionSnack('No linked student account found.', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx2, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.gold,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.gold,
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: AppColors.gold,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ALL LINKED CHILDREN | STATUS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const Text(
                              'Child Status',
                              style: TextStyle(
                                fontFamily: _hf,
                                fontSize: 26,
                                height: 1,
                                color: AppColors.green,
                                fontWeight: FontWeight.w300,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.gold, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                      itemCount: _linkedStudents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final student = _linkedStudents[i];
                        return _StudentStatusCard(
                          student: student,
                          isSelected: student.uid == _childUid,
                          onTap: () {
                            Navigator.pop(ctx);
                            _switchActiveChild(student.uid);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDeviceDialog() async {
    await _showLuxuryInfoSheet(
      title: 'Device Connection',
      subtitle: 'LINKED DEVICE',
      icon: Icons.smartphone_rounded,
      rows: [
        _InfoRow('Device Name', _deviceName),
        _InfoRow('Device ID', _deviceId),
        _InfoRow('Location', _deviceLocation),
        _InfoRow('Status', _deviceStatus.toUpperCase()),
      ],
      actionLabel: 'REFRESH',
      onAction: () async {
        if (_childUid.isNotEmpty) await _loadChildData(_childUid);
        _showActionSnack('Device status refreshed.');
      },
    );
  }

  Future<void> _showLuxuryInfoSheet({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<_InfoRow> rows,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.offWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.gold,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.gold, width: 1),
                          ),
                          child: Icon(icon, color: AppColors.gold, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: _hf,
                                fontSize: 28,
                                height: 1,
                                color: AppColors.green,
                                fontWeight: FontWeight.w300,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.gold, Colors.transparent],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...rows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.label,
                                style: const TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  row.value,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (actionLabel != null && onAction != null)
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: AppColors.green,
                          child: InkWell(
                            onTap: () async {
                              Navigator.pop(ctx);
                              await onAction();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.gold.withValues(alpha: 0.65),
                                ),
                              ),
                              child: Text(
                                actionLabel,
                                style: const TextStyle(
                                  fontFamily: _bf,
                                  color: AppColors.white,
                                  letterSpacing: 4,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Text(
                          'CLOSE',
                          style: TextStyle(
                            fontFamily: _bf,
                            fontSize: 9,
                            letterSpacing: 3,
                            color: AppColors.textSub,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _guardianAlertStream(
    String parentUid,
    List<String> deviceIds,
  ) {
    if (parentUid.trim().isEmpty &&
        _linkedStudents.isEmpty &&
        deviceIds.every((id) => id.trim().isEmpty)) {
      return null;
    }
    // Same read the student and admin dashboards use. Filtering happens
    // afterwards so a tracker alert still shows when parentUid was not
    // written on the document.
    return _firestore
        .collection('emergency_alerts')
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots();
  }

  bool _doesAlertMatchParent(Map<String, dynamic> data) {
    final parentUid = _parentUid.trim().isNotEmpty
        ? _parentUid.trim()
        : (FirebaseAuth.instance.currentUser?.uid ?? '');
    final docUid = (data['uid'] ?? '').toString().trim();
    final docStudentUid = (data['studentUid'] ?? '').toString().trim();
    final docDeviceId = (data['deviceId'] ?? '').toString().trim();
    final docParentUid = (data['parentUid'] ?? '').toString().trim();
    final triggeredBy = (data['triggeredBy'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final linkedUids = <String>{
      for (final student in _linkedStudents)
        if (student.uid.trim().isNotEmpty) student.uid.trim(),
      if (_childUid.trim().isNotEmpty) _childUid.trim(),
    };
    final linkedDevices = <String>{
      for (final student in _linkedStudents)
        if (student.deviceId.trim().isNotEmpty &&
            student.deviceId.trim() != 'Not linked')
          student.deviceId.trim(),
    };
    final activeDevice = _deviceId.trim();
    if (activeDevice.isNotEmpty &&
        activeDevice != 'Not linked' &&
        !activeDevice.startsWith('Student Device') &&
        !activeDevice.startsWith('Device GPS')) {
      linkedDevices.add(activeDevice);
    }

    if (parentUid.isNotEmpty &&
        (docParentUid == parentUid ||
            _recipientUidsOf(data).contains(parentUid))) {
      return true;
    }
    if (docUid.isNotEmpty &&
        (linkedUids.contains(docUid) || linkedDevices.contains(docUid))) {
      return true;
    }
    if (docStudentUid.isNotEmpty &&
        (linkedUids.contains(docStudentUid) ||
            linkedDevices.contains(docStudentUid))) {
      return true;
    }
    if (docDeviceId.isNotEmpty &&
        (linkedDevices.contains(docDeviceId) ||
            linkedUids.contains(docDeviceId))) {
      return true;
    }

    const hardwareId = 'safewalk_device_001';
    final isHardwareAlert =
        docDeviceId == hardwareId ||
        docUid == hardwareId ||
        docStudentUid == hardwareId ||
        triggeredBy == 'iot_device';
    return isHardwareAlert && linkedUids.isNotEmpty;
  }

  Set<String> _recipientUidsOf(Map<String, dynamic> data) {
    final raw = data['recipientUids'];
    if (raw is! Iterable) return const <String>{};
    return raw.map((value) => value.toString()).toSet();
  }

  Widget _buildGuardianManagement() {
    final students = _linkedStudents.where((student) => student.uid.trim().isNotEmpty).toList();
    if (students.isEmpty) {
      return const GuardianContactsPanel(studentUid: '');
    }
    final selected = students.any((student) => student.uid == _childUid)
        ? _childUid
        : students.first.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (students.length > 1) ...[
          DropdownButtonFormField<String>(
            key: ValueKey<String>(selected),
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Student',
              labelStyle: TextStyle(fontFamily: _bf),
            ),
            items: students
                .map(
                  (student) => DropdownMenuItem<String>(
                    value: student.uid,
                    child: Text(
                      student.name.trim().isEmpty ? student.uid : student.name,
                      style: const TextStyle(fontFamily: _bf),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _switchActiveChild(value);
            },
          ),
          const SizedBox(height: 12),
        ],
        GuardianContactsPanel(studentUid: selected),
      ],
    );
  }

  Future<void> _showAlertHistorySheet() async {
    if (_linkedStudents.isEmpty) {
      _showActionSnack('No linked student account found.', isError: true);
      return;
    }
    final parentUidForAlerts = _parentUid.isEmpty
        ? FirebaseAuth.instance.currentUser?.uid ?? ''
        : _parentUid;
    final linkedNameByUid = _linkedStudentNamesByUid;
    final linkedDeviceIds = _linkedStudents
        .map((s) => s.deviceId.trim())
        .where((id) => id.isNotEmpty && id != 'Not linked')
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx2, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.gold,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.gold,
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.history,
                            color: AppColors.gold,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ALL LINKED CHILDREN | ALERTS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const Text(
                              'Alert History',
                              style: TextStyle(
                                fontFamily: _hf,
                                fontSize: 26,
                                height: 1,
                                color: AppColors.green,
                                fontWeight: FontWeight.w300,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.gold, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _guardianAlertStream(
                        parentUidForAlerts,
                        linkedDeviceIds,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Failed to load alerts: ${snapshot.error}',
                              style: const TextStyle(fontFamily: _bf),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.gold,
                            ),
                          );
                        }
                        final docs =
                            snapshot.data!.docs
                                .where(
                                  (doc) => _doesAlertMatchParent(doc.data()),
                                )
                                .toList()..sort((a, b) {
                              final aData = a.data();
                              final bData = b.data();
                              final aStatus = (aData['status'] ?? '').toString().toLowerCase();
                              final bStatus = (bData['status'] ?? '').toString().toLowerCase();
                              final aIsActive = aStatus == 'active' || aStatus == 'verifying_speech';
                              final bIsActive = bStatus == 'active' || bStatus == 'verifying_speech';
                              if (aIsActive != bIsActive) {
                                return aIsActive ? -1 : 1; // ACTIVE on top
                              }
                              final aTs = aData['timestamp'] as Timestamp?;
                              final bTs = bData['timestamp'] as Timestamp?;
                              return (bTs?.millisecondsSinceEpoch ?? 0)
                                  .compareTo(aTs?.millisecondsSinceEpoch ?? 0);
                            });
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 48,
                                  color: AppColors.gold.withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No alerts found.',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: AppColors.textSub,
                                    fontSize: 13,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final data = docs[i].data();
                            final status = (data['status'] ?? 'unknown')
                                .toString();
                            final message = (data['message'] ?? 'No details')
                                .toString();
                            final timestamp = data['timestamp'] as Timestamp?;
                            final isActive = status == 'active' ||
                                status == 'verifying_speech';
                            final childName = _resolveStudentNameFromAlert(
                              data,
                              linkedNameByUid: linkedNameByUid,
                            );
                            final alertCoordinate = _extractAlertCoordinates(
                              data,
                            );
                            final locationText = alertCoordinate != null
                                ? _formatCoordinateValue(alertCoordinate)
                                : (data['location'] ?? '').toString().trim();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isActive
                                      ? const Color(
                                          0xFFCB392B,
                                        ).withValues(alpha: 0.35)
                                      : AppColors.border,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? const Color(0xFFFFEEEC)
                                              : AppColors.cream,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.warning_amber_rounded,
                                          size: 17,
                                          color: isActive
                                              ? const Color(0xFFCB392B)
                                              : AppColors.textSub,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: const TextStyle(
                                            fontFamily: _bf,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: AppColors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Child: $childName',
                                    style: TextStyle(
                                      fontFamily: _bf,
                                      fontSize: 10,
                                      letterSpacing: 1.2,
                                      color: AppColors.textSub,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (locationText.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      status.toLowerCase() == 'resolved'
                                          ? 'SOS Location: Removed'
                                          : 'SOS Location: $locationText',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                        color: AppColors.textSub,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _AlertBadge(
                                        label: status.toUpperCase(),
                                        isActive: isActive,
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatTimestamp(timestamp),
                                        style: TextStyle(
                                          fontFamily: _bf,
                                          fontSize: 10,
                                          letterSpacing: 1,
                                          color: AppColors.textSub,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isActive ||
                                      status.toLowerCase() == 'acknowledged' ||
                                      status.toLowerCase() == 'not_resolved' ||
                                      status.toLowerCase() == 'responded') ...[
                                    const SizedBox(height: 10),
                                    _buildAlertStatusActions(docs[i].id, status),
                                  ],
                                  if (status.toLowerCase() == 'false_alarm' ||
                                      status.toLowerCase() ==
                                          'cancelled_false_trigger') ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Material(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          onTap: () {
                                            _showActionSnack(
                                              "Student reported this alert as a false alarm (miss-clicked device).",
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFFF59E0B)
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 14,
                                                  color: Color(0xFFB45309),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'FALSE ALARM REPORTED (SAFE)',
                                                  style: TextStyle(
                                                    fontFamily: _bf,
                                                    color: const Color(0xFFB45309),
                                                    letterSpacing: 2,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (status.toLowerCase() == 'resolved') ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Material(
                                        color: AppColors.green.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () {
                                            _showActionSnack("The issue is already been fixed.");
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.green
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.check_circle,
                                                  size: 14,
                                                  color: AppColors.green,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'DONE (FIXED)',
                                                  style: TextStyle(
                                                    fontFamily: _bf,
                                                    color: AppColors.green,
                                                    letterSpacing: 2,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── LUXURY PROFILE SHEET ──────────────────────────────────────

  Future<void> _showProfileDialog() async {
    if (_isProfileSheetOpen || !mounted) return;
    _isProfileSheetOpen = true;
    _profileNameCtrl
      ..text = _parentName
      ..selection = TextSelection.collapsed(offset: _parentName.length);
    _profilePhoneCtrl
      ..text = _parentPhone
      ..selection = TextSelection.collapsed(offset: _parentPhone.length);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          bool isSaving = false;
          String localMood = _avatarMood;
          return StatefulBuilder(
            builder: (context, setSheet) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                AppColors.gold,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EDIT PROFILE',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 9,
                                  letterSpacing: 4,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 6),
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontFamily: _hf,
                                    fontSize: 34,
                                    height: 1.05,
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  children: [
                                    TextSpan(text: 'Parent\n'),
                                    TextSpan(
                                      text: 'Information',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.goldDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              Center(
                                child: _RobotAvatar(mood: localMood, size: 84),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: ['happy', 'angry', 'heart_eyes'].map((
                                  m,
                                ) {
                                  return IconButton(
                                    onPressed: () =>
                                        setSheet(() => localMood = m),
                                    icon: Icon(
                                      Icons.circle,
                                      color: localMood == m
                                          ? AppColors.gold
                                          : AppColors.border,
                                      size: 16,
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  'PARENT / GUARDIAN',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 9,
                                    letterSpacing: 4,
                                    color: AppColors.textSub,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                height: 1,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.gold,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Email read-only
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cream,
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(
                                    color: AppColors.border.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'EMAIL ADDRESS',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 9,
                                        letterSpacing: 4,
                                        color: AppColors.gold.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _parentEmail.isEmpty
                                          ? 'Not set'
                                          : _parentEmail,
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                        color: AppColors.textSub,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Read-only · Contact admin to change',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 9,
                                        letterSpacing: 1,
                                        color: AppColors.textSub.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              _DashLuxuryField(
                                label: 'FULL NAME',
                                hint: 'Enter your full name',
                                controller: _profileNameCtrl,
                              ),
                              const SizedBox(height: 20),

                              _DashLuxuryField(
                                label: 'PHONE NUMBER',
                                hint: 'e.g. 09XXXXXXXXX',
                                controller: _profilePhoneCtrl,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 32),

                              // Save button
                              SizedBox(
                                width: double.infinity,
                                child: Material(
                                  color: AppColors.green,
                                  child: InkWell(
                                    onTap: isSaving
                                        ? null
                                        : () async {
                                            setSheet(() => isSaving = true);
                                            await _saveProfile(
                                              _profileNameCtrl.text,
                                              _profilePhoneCtrl.text,
                                              localMood,
                                            );
                                            if (sheetCtx.mounted) {
                                              Navigator.pop(sheetCtx);
                                            }
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.gold.withValues(
                                            alpha: 0.65,
                                          ),
                                        ),
                                      ),
                                      child: isSaving
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.gold,
                                              ),
                                            )
                                          : Text(
                                              'SAVE CHANGES',
                                              style: TextStyle(
                                                fontFamily: _bf,
                                                color: AppColors.white,
                                                letterSpacing: 4,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(sheetCtx),
                                  child: Text(
                                    'CANCEL',
                                    style: TextStyle(
                                      fontFamily: _bf,
                                      fontSize: 9,
                                      letterSpacing: 3,
                                      color: AppColors.textSub,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _isProfileSheetOpen = false;
    }
  }



  Future<void> _onBottomNavTap(int index) async {
    setState(() => _selectedNavIndex = index);
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

  Future<void> _logout() async {
    try {
      await _authService.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _changeRoleToStudent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          title: const Text('Change Role to Student'),
          content: const Text(
            'Are you sure you want to change your account role to Student? This will unlink you from all current student accounts. You will be logged out to apply changes.',
          ),
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

    if (confirmed != true) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('users').doc(uid).update({
          'role': 'student',
        });
        await _firestore.collection('user_settings').doc(uid).delete();
      }
      await _logout();
    } catch (e) {
      _showActionSnack('Failed to change role: $e', isError: true);
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.offWhite,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Top accent bar
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: _buildCurrentTabContent(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_selectedNavIndex) {
      case 1:
        return _buildAlertsTab();
      case 2:
        return _buildProfileTab();
      case 0:
      default:
        return _buildChildTab();
    }
  }

  Widget _buildChildTab() {
    final parentUidForAlerts = _parentUid.isEmpty
        ? FirebaseAuth.instance.currentUser?.uid ?? ''
        : _parentUid;
    final linkedNameByUid = _linkedStudentNamesByUid;
    final linkedDeviceIds = _linkedStudents
        .map((s) => s.deviceId.trim())
        .where((id) => id.isNotEmpty && id != 'Not linked')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('CHILD LOCATION'),
        if (_linkedStudents.length > 1) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _linkedStudents.map((student) {
                final selected = student.uid == _childUid;
                final shortUid = student.uid.length > 6
                    ? student.uid.substring(0, 6)
                    : student.uid;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${student.name} - $shortUid',
                      style: TextStyle(
                        fontFamily: _bf,
                        fontSize: 10,
                        color: selected ? AppColors.white : AppColors.green,
                      ),
                    ),
                    selected: selected,
                    onSelected: (v) {
                      if (!v) return;
                      _switchActiveChild(student.uid);
                    },
                    selectedColor: AppColors.green,
                    backgroundColor: AppColors.white,
                    side: BorderSide(
                      color: selected
                          ? AppColors.gold.withValues(alpha: 0.6)
                          : AppColors.border,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _buildChildMapCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('SOS LOCATION'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: 'Child SOS',
          subtitle: 'LOCATION WHERE SOS WAS SENT',
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _guardianAlertStream(
                parentUidForAlerts,
                linkedDeviceIds,
              ),
              builder: (context, snapshot) {
                String sosStatus = 'NO SOS YET';
                String sosTime = '-';
                String sosLocation = 'No SOS location yet';
                String sosSender = 'No sender yet';
                String latestAlertId = '';
                String latestAlertRawStatus = '';

                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  final docs =
                      snapshot.data!.docs.where((doc) {
                        final data = doc.data();
                        final alertType = (data['type'] ?? '')
                            .toString()
                            .toLowerCase();
                        final isEmergency =
                            alertType == 'sos' ||
                            alertType == 'voice_help' ||
                            alertType == 'emergency';
                        return isEmergency && _doesAlertMatchParent(data);
                      }).toList()..sort((a, b) {
                        final aData = a.data();
                        final bData = b.data();
                        final aStatus = (aData['status'] ?? '').toString().toLowerCase();
                        final bStatus = (bData['status'] ?? '').toString().toLowerCase();
                        int priority(String s) {
                          if (s == 'active' || s == 'verifying_speech') return 0;
                          if (s == 'responded' ||
                              s == 'acknowledged' ||
                              s == 'not_resolved') {
                            return 1;
                          }
                          return 2;
                        }
                        final pA = priority(aStatus);
                        final pB = priority(bStatus);
                        if (pA != pB) {
                          return pA.compareTo(pB);
                        }
                        final aTs = aData['timestamp'] as Timestamp?;
                        final bTs = bData['timestamp'] as Timestamp?;
                        return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
                          aTs?.millisecondsSinceEpoch ?? 0,
                        );
                      });

                  if (docs.isNotEmpty) {
                    final latest = docs.first.data();
                    latestAlertId = docs.first.id;
                    final latestSosCoordinate = _extractAlertCoordinates(
                      latest,
                    );
                    sosSender = _resolveStudentNameFromAlert(
                      latest,
                      linkedNameByUid: linkedNameByUid,
                    );
                    final fallbackLocation = (latest['location'] ?? '')
                        .toString()
                        .trim();
                    final latestStatus = (latest['status'] ?? '')
                        .toString()
                        .toLowerCase();
                    latestAlertRawStatus = latestStatus;
                    final isActive =
                        latestStatus == 'active' ||
                        latestStatus == 'verifying_speech';
                    final isAck = latestStatus == 'acknowledged';
                    final isResolved = latestStatus == 'resolved';
                    final isFalseAlarm =
                        latestStatus == 'false_alarm' ||
                        latestStatus == 'cancelled_false_trigger';

                    if (isActive) {
                      sosStatus = 'ACTIVE';
                      sosLocation = latestSosCoordinate != null
                          ? _formatCoordinateValue(latestSosCoordinate)
                          : fallbackLocation.isEmpty
                          ? 'No SOS location yet'
                          : fallbackLocation;
                    } else if (isAck) {
                      sosStatus = 'ACKNOWLEDGED';
                      sosLocation = latestSosCoordinate != null
                          ? _formatCoordinateValue(latestSosCoordinate)
                          : fallbackLocation.isEmpty
                          ? 'Tracking child...'
                          : fallbackLocation;
                    } else if (latestStatus == 'not_resolved') {
                      sosStatus = 'NOT RESOLVED';
                      sosLocation = latestSosCoordinate != null
                          ? _formatCoordinateValue(latestSosCoordinate)
                          : fallbackLocation.isEmpty
                          ? 'Still searching...'
                          : fallbackLocation;
                    } else if (latestStatus == 'responded') {
                      sosStatus = 'ADMIN RESPONDED';
                      sosLocation = latestSosCoordinate != null
                          ? _formatCoordinateValue(latestSosCoordinate)
                          : fallbackLocation.isEmpty
                          ? 'Admin responded...'
                          : fallbackLocation;
                    } else if (isResolved) {
                      sosStatus = 'RESOLVED';
                      sosLocation = 'Location removed (Issue fixed)';
                    } else if (isFalseAlarm) {
                      sosStatus = 'FALSE ALARM (CHILD SAFE)';
                      sosLocation = 'Child cancelled - miss clicked device';
                    } else {
                      sosStatus = 'NO SOS YET';
                      sosLocation = 'No SOS location yet';
                    }
                    sosTime = _formatTimestamp(
                      latest['timestamp'] as Timestamp?,
                    );
                  }
                }

                return Column(
                  children: [
                    _buildDashboardRow('SOS Sent By', sosSender),
                    const SizedBox(height: 8),
                    _buildDashboardRow('SOS Status', sosStatus),
                    const SizedBox(height: 8),
                    _buildDashboardRow('Last SOS Time', sosTime),
                    const SizedBox(height: 8),
                    _buildDashboardRow('SOS Location', sosLocation),
                    if (_linkedStudents.length > 1) ...[
                      const SizedBox(height: 8),
                      _buildDashboardRow(
                        'Connected Children',
                        _linkedStudents.length.toString(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPanelAction(
                            label: 'ALERT HISTORY',
                            onTap: _showAlertHistorySheet,
                          ),
                          if (latestAlertId.isNotEmpty) ...[
                            if (latestAlertRawStatus == 'active' ||
                                latestAlertRawStatus == 'verifying_speech')
                              _buildPanelAction(
                                label: 'ACKNOWLEDGE',
                                onTap: () => _acknowledgeAlert(latestAlertId),
                              )
                            else if (latestAlertRawStatus == 'acknowledged') ...[
                              _buildPanelAction(
                                label: 'DONE',
                                onTap: () => _resolveAlertDone(latestAlertId),
                              ),
                              _buildPanelAction(
                                label: 'NOT RESOLVED',
                                onTap: () => _markAlertNotResolved(latestAlertId),
                              ),
                            ] else if (latestAlertRawStatus == 'not_resolved' ||
                                latestAlertRawStatus == 'responded')
                              _buildPanelAction(
                                label: 'DONE',
                                onTap: () => _resolveAlertDone(latestAlertId),
                              )
                            else if (latestAlertRawStatus == 'false_alarm' ||
                                latestAlertRawStatus == 'cancelled_false_trigger')
                              _buildPanelAction(
                                label: 'FALSE ALARM (SAFE)',
                                onTap: () async => _showActionSnack(
                                  "Student reported this alert as a false alarm (miss-clicked device).",
                                ),
                              )
                            else if (latestAlertRawStatus == 'resolved')
                              _buildPanelAction(
                                label: 'DONE (FIXED)',
                                onTap: () async => _showActionSnack(
                                  "The issue is already been fixed.",
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('ALERTS'),
        const SizedBox(height: 10),
        _buildInlineAlertHistory(),
      ],
    );
  }

  Widget _buildInlineAlertHistory() {
    if (_linkedStudents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text(
            'No linked student account found.',
            style: const TextStyle(fontFamily: _bf),
          ),
        ),
      );
    }
    final parentUidForAlerts = _parentUid.isEmpty
        ? FirebaseAuth.instance.currentUser?.uid ?? ''
        : _parentUid;
    final linkedNameByUid = _linkedStudentNamesByUid;
    final linkedDeviceIds = _linkedStudents
        .map((s) => s.deviceId.trim())
        .where((id) => id.isNotEmpty && id != 'Not linked')
        .toList();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _guardianAlertStream(parentUidForAlerts, linkedDeviceIds),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Failed to load alerts: ${snapshot.error}',
                style: const TextStyle(fontFamily: _bf),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(color: AppColors.gold),
            ),
          );
        }
        final docs =
            snapshot.data!.docs
                .where((doc) => _doesAlertMatchParent(doc.data()))
                .toList()..sort((a, b) {
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
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No alerts found.',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.textSub,
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 20),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final status = (data['status'] ?? 'unknown').toString();
            final message = (data['message'] ?? 'No details').toString();
            final timestamp = data['timestamp'] as Timestamp?;
            final isActive = status == 'active' ||
                status == 'verifying_speech';
            final childName = _resolveStudentNameFromAlert(
              data,
              linkedNameByUid: linkedNameByUid,
            );
            final alertCoordinate = _extractAlertCoordinates(data);
            final locationText = alertCoordinate != null
                ? _formatCoordinateValue(alertCoordinate)
                : (data['location'] ?? '').toString().trim();
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFCB392B).withValues(alpha: 0.35)
                      : AppColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFFFEEEC)
                              : AppColors.cream,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: isActive
                              ? const Color(0xFFCB392B)
                              : AppColors.textSub,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            fontFamily: _bf,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Child: $childName',
                    style: TextStyle(
                      fontFamily: _bf,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: AppColors.textSub,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (locationText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      status.toLowerCase() == 'resolved'
                          ? 'SOS Location: Removed'
                          : 'SOS Location: $locationText',
                      style: TextStyle(
                        fontFamily: _bf,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: AppColors.textSub,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _AlertBadge(
                        label: status.toUpperCase(),
                        isActive: isActive,
                      ),
                      const Spacer(),
                      Text(
                        _formatTimestamp(timestamp),
                        style: TextStyle(
                          fontFamily: _bf,
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.textSub,
                        ),
                      ),
                    ],
                  ),
                  if (isActive ||
                      status.toLowerCase() == 'acknowledged' ||
                      status.toLowerCase() == 'not_resolved' ||
                      status.toLowerCase() == 'responded') ...[
                    const SizedBox(height: 10),
                    _buildAlertStatusActions(docs[i].id, status),
                  ],
                  if (status.toLowerCase() == 'false_alarm' ||
                      status.toLowerCase() == 'cancelled_false_trigger') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            _showActionSnack(
                              "Student reported this alert as a false alarm (miss-clicked device).",
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 14,
                                  color: Color(0xFFB45309),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'FALSE ALARM REPORTED (SAFE)',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: const Color(0xFFB45309),
                                    letterSpacing: 2,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (status.toLowerCase() == 'resolved') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: AppColors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            _showActionSnack("The issue is already been fixed.");
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.green.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: AppColors.green,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'DONE (FIXED)',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: AppColors.green,
                                    letterSpacing: 2,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChildMapCard() {
    final parentUidForAlerts = _parentUid.isEmpty
        ? FirebaseAuth.instance.currentUser?.uid ?? ''
        : _parentUid;
    final linkedNameByUid = _linkedStudentNamesByUid;
    final linkedDeviceIds = _linkedStudents
        .map((s) => s.deviceId.trim())
        .where((id) => id.isNotEmpty && id != 'Not linked')
        .toList();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _guardianAlertStream(parentUidForAlerts, linkedDeviceIds),
      builder: (context, snapshot) {
        final sosDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          sosDocs.addAll(
            snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final alertType = (data['type'] ?? '').toString().toLowerCase();
              final status = (data['status'] ?? '').toString().toLowerCase();
              final isEmergency =
                  alertType == 'sos' ||
                  alertType == 'voice_help' ||
                  alertType == 'emergency' ||
                  alertType == 'sos_update' ||
                  alertType == 'voice_help_update';
              final isOpen =
                  _isOpenSosStatus(status) && data['locationCleared'] != true;
              return isEmergency && isOpen && _doesAlertMatchParent(data);
            }),
          );
          sosDocs.sort((a, b) {
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
        }

        final latestSosData = sosDocs.isNotEmpty ? sosDocs.first.data() : null;
        final latestSosAlertId = sosDocs.isNotEmpty ? sosDocs.first.id : '';
        final latestSosPoint = latestSosData == null
            ? null
            : _extractAlertCoordinates(latestSosData);
        final latestSosSender = latestSosData == null
            ? _childName
            : _resolveStudentNameFromAlert(
                latestSosData,
                linkedNameByUid: linkedNameByUid,
              );
        final latestSosLabel = latestSosData == null
            ? ''
            : _formatTimestamp(latestSosData['timestamp'] as Timestamp?);
        final latestSosStatus = (latestSosData?['status'] ?? '')
            .toString()
            .toLowerCase();
        final latestSosLocationText = latestSosPoint != null
            ? _formatCoordinateValue(latestSosPoint)
            : (latestSosData?['location'] ?? '').toString().trim().isEmpty
            ? 'No SOS location yet'
            : (latestSosData?['location'] ?? '').toString().trim();

        final latestByChild =
            <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final doc in sosDocs) {
          final data = doc.data();
          final childKey = _stableStudentKey(data);
          if (childKey.isEmpty) continue;
          final current = latestByChild[childKey];
          if (current == null ||
              _alertTimeMs(data) >= _alertTimeMs(current.data())) {
            latestByChild[childKey] = doc;
          }
        }

        final markers = <Marker>{};
        final circles = <Circle>{};
        var sosMarkersWithPoint = 0;
        LatLng? firstSosMarkerPoint;
        latestByChild.forEach((childKey, doc) {
          final data = doc.data();
          // Keep the pin on the coordinates the device sent with this help
          // request. The saved child profile can be the phone or an older fix.
          final point = _extractAlertCoordinates(data);
          if (point == null) return;
          firstSosMarkerPoint ??= point;
          final sender = _resolveStudentNameFromAlert(
            data,
            linkedNameByUid: linkedNameByUid,
          );
          final alertStatus = (data['status'] ?? '').toString().toLowerCase();
          final pointLabel = _formatCoordinateValue(point);
          final statusLabel = alertStatus == 'responded'
              ? 'Admin responded'
              : alertStatus == 'acknowledged'
              ? 'Acknowledged'
              : alertStatus == 'not_resolved'
              ? 'Not resolved'
              : 'Active alert';
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
          final markerId = _alertIsSelectedChild(data)
              ? 'child-location'
              : 'child-$childKey';

          markers.add(
            Marker(
              markerId: MarkerId(markerId),
              position: point,
              anchor: const Offset(0.5, 0.98),
              icon: _markerIconForStatus(alertStatus),
              infoWindow: InfoWindow(
                title: '$sender - $statusLabel',
                snippet: pointLabel,
              ),
            ),
          );

          circles.add(
            Circle(
              circleId: CircleId('sos-radius-$markerId'),
              center: point,
              radius: 90,
              fillColor: circleFill,
              strokeColor: circleStroke,
              strokeWidth: 2,
            ),
          );
          sosMarkersWithPoint += 1;
        });

        final hasSosPoints = sosMarkersWithPoint > 0;

        final mapPoint = hasSosPoints
            ? (latestSosPoint ?? firstSosMarkerPoint)
            : (_childDeviceCoordinates ?? latestSosPoint);
        final center = mapPoint ?? _childMapCenter;
        final hasPoint = mapPoint != null;
        if (hasPoint) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _focusParentMapOnPoint(center, zoom: 18);
          });
        }

        final tagLabel = hasSosPoints
            ? (sosMarkersWithPoint > 1
                  ? '$sosMarkersWithPoint SOS MARKERS'
                  : latestSosStatus == 'responded'
                  ? 'ADMIN RESPONDED'
                  : latestSosStatus == 'acknowledged'
                  ? 'ACKNOWLEDGED'
                  : latestSosStatus == 'not_resolved'
                  ? 'NOT RESOLVED'
                  : 'SOS LOCATION')
            : hasPoint
            ? 'NO ACTIVE ALERT'
            : 'NO LOCATION YET';
        final tagColor = latestSosStatus == 'responded'
            ? const Color(0xFF111827)
            : latestSosStatus == 'acknowledged'
            ? const Color(0xFF9A3412)
            : latestSosStatus == 'not_resolved'
            ? const Color(0xFF5B21B6)
            : hasSosPoints
            ? const Color(0xFF7E1F14)
            : const Color(0xFF0E5B3C);
        final footerTitle = hasSosPoints
            ? (latestSosStatus == 'responded'
                ? 'ADMIN RESPONDED - $latestSosSender${latestSosLabel.isEmpty ? '' : ' | $latestSosLabel'}'
                : latestSosStatus == 'acknowledged'
                ? 'ACKNOWLEDGED - $latestSosSender${latestSosLabel.isEmpty ? '' : ' | $latestSosLabel'}'
                : latestSosStatus == 'not_resolved'
                ? 'NOT RESOLVED - $latestSosSender${latestSosLabel.isEmpty ? '' : ' | $latestSosLabel'}'
                : 'SOS FROM $latestSosSender${latestSosLabel.isEmpty ? '' : ' | $latestSosLabel'}')
            : 'NO ALERT MARKER';
        final footerLocation = hasSosPoints
            ? latestSosLocationText
            : 'Marker appears when a help request is sent';

        return Container(
          height: 240,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: kIsWeb && !isGoogleMapsJsLoaded()
                      ? _buildWebMapFallback(
                          contextLabel: 'Parent Child Tracking Card',
                        )
                      : GoogleMap(
                          key: const ValueKey('parent-map-main'),
                          initialCameraPosition: CameraPosition(
                            target: center,
                            zoom: hasPoint ? 18 : 12,
                          ),
                          liteModeEnabled: _mobileMapLiteMode,
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
                            _parentMapController = controller;
                            if (hasPoint) {
                              _focusParentMapOnPoint(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    tagLabel,
                    style: const TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold,
                      fontSize: 9,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (hasSosPoints && latestSosAlertId.isNotEmpty)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () {
                            if (latestSosStatus == 'active' ||
                                latestSosStatus == 'verifying_speech') {
                              _acknowledgeAlert(latestSosAlertId);
                            } else if (latestSosStatus == 'acknowledged' ||
                                latestSosStatus == 'not_resolved' ||
                                latestSosStatus == 'responded') {
                              _resolveAlertDone(latestSosAlertId);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: latestSosStatus == 'responded'
                                  ? const Color(0xFF111827)
                                  : latestSosStatus == 'acknowledged'
                                  ? const Color(0xFFEA580C)
                                  : latestSosStatus == 'not_resolved'
                                  ? const Color(0xFF6D28D9)
                                  : const Color(0xFFCB392B),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  (latestSosStatus == 'active' ||
                                          latestSosStatus ==
                                              'verifying_speech')
                                      ? 'ACKNOWLEDGE'
                                      : 'DONE',
                                  style: const TextStyle(
                                    fontFamily: _bf,
                                    color: Colors.white,
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (latestSosStatus == 'acknowledged') ...[
                        const SizedBox(height: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () =>
                                _markAlertNotResolved(latestSosAlertId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6D28D9),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              child: const Text(
                                'NOT RESOLVED',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  color: Colors.white,
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                Positioned(
                  top: 14,
                  right: 14,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _loadDashboard(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.8),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: AppColors.goldLt,
                              size: 13,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'REFRESH',
                              style: TextStyle(
                                fontFamily: _bf,
                                color: AppColors.goldLt,
                                fontSize: 9,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        footerTitle,
                        style: const TextStyle(
                          fontFamily: _bf,
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
                          fontFamily: _bf,
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
      },
    );
  }

  Widget _buildProfileTab() {
    final linkedPreview = _linkedStudents.isEmpty
        ? 'None'
        : _linkedStudents.take(3).map((student) => student.name).join(', ') +
              (_linkedStudents.length > 3
                  ? ' +${_linkedStudents.length - 3} more'
                  : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('PARENT PROFILE'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF05412B), Color(0xFF042D1F)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _RobotAvatar(mood: _avatarMood, size: 72),
              const SizedBox(height: 14),
              Text(
                _parentName,
                style: TextStyle(
                  fontFamily: _hf,
                  color: AppColors.white,
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'PARENT / GUARDIAN',
                  style: TextStyle(
                    fontFamily: _bf,
                    color: AppColors.goldLt,
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.people_outline,
                      color: AppColors.gold,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_linkedStudents.length} Student${_linkedStudents.length == 1 ? '' : 's'} Linked',
                      style: TextStyle(
                        fontFamily: _bf,
                        color: AppColors.goldLt,
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildDashboardPanel(
          title: _parentName,
          subtitle: 'ACCOUNT DETAILS',
          children: [
            _buildDashboardRow(
              'Email',
              _parentEmail.isEmpty ? '-' : _parentEmail,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Phone',
              _parentPhone.isEmpty ? '-' : _parentPhone,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Connected Students',
              _linkedStudents.length.toString(),
            ),
            const SizedBox(height: 8),
            _buildDashboardRow('Student List', linkedPreview),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student',
              _childName.isEmpty ? 'Not set' : _childName,
            ),
            const SizedBox(height: 14),
            _buildPanelAction(label: 'EDIT PROFILE', onTap: _showProfileDialog),
          ],
        ),
        const SizedBox(height: 18),
        _buildSectionLabel('LINK YOUR CHILD'),
        const SizedBox(height: 10),
        _buildLinkChildFeature(),
        const SizedBox(height: 18),
        _buildSectionLabel('GUARDIANS'),
        const SizedBox(height: 10),
        _buildGuardianManagement(),
        const SizedBox(height: 20),
        _buildSectionLabel('DANGER ZONE'),
        const SizedBox(height: 10),
        _buildSessionSecuritySection(),
      ],
    );
  }

  Widget _buildSessionSecuritySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFCB392B).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACCOUNT',
            style: TextStyle(
              fontFamily: _bf,
              color: const Color(0xFFCB392B).withValues(alpha: 0.7),
              fontSize: 9,
              letterSpacing: 3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Session & Security',
            style: TextStyle(
              fontFamily: _hf,
              color: const Color(0xFF7E1F14),
              fontSize: 26,
              height: 1,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFCB392B).withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: const Color(0xFFCB392B),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _confirmLogout,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFCB392B).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'LOG OUT',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.white,
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _changeRoleToStudent,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFCB392B).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'CHANGE ROLE TO STUDENT',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: const Color(0xFFCB392B),
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkChildFeature() {
    return _buildDashboardPanel(
      title: 'Link Your Child',
      subtitle: 'CONNECTED STUDENTS & INVITATIONS',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LINKED STUDENTS',
              style: TextStyle(
                fontFamily: _bf,
                fontSize: 9,
                letterSpacing: 3,
                color: AppColors.gold,
                fontWeight: FontWeight.w400,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                '${_linkedStudents.length} Connected',
                style: const TextStyle(
                  fontFamily: _bf,
                  fontSize: 9,
                  letterSpacing: 1,
                  color: AppColors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_linkedStudents.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'No linked students yet. Send an invitation below to connect your child.',
              style: TextStyle(
                fontFamily: _bf,
                fontSize: 11,
                color: AppColors.textSub,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _linkedStudents.map((student) {
              final isSelected = student.uid == _childUid;
              final shortUid = student.uid.length > 6
                  ? student.uid.substring(0, 6)
                  : student.uid;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle : Icons.person_outline,
                      size: 13,
                      color: isSelected ? AppColors.white : AppColors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${student.name} - $shortUid',
                      style: TextStyle(
                        fontFamily: _bf,
                        fontSize: 10,
                        color: isSelected ? AppColors.white : AppColors.green,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                onSelected: (_) => _switchActiveChild(student.uid),
                selectedColor: AppColors.green,
                backgroundColor: AppColors.white,
                side: BorderSide(
                  color: isSelected
                      ? AppColors.gold.withValues(alpha: 0.8)
                      : AppColors.border,
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 18),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        const Text(
          'INVITE STUDENT',
          style: TextStyle(
            fontFamily: _bf,
            fontSize: 9,
            letterSpacing: 3,
            color: AppColors.gold,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter student UID or phone number to link your child to this dashboard.',
          style: TextStyle(
            fontFamily: _bf,
            fontSize: 10,
            color: AppColors.textSub,
          ),
        ),
        const SizedBox(height: 12),
        _DashLuxuryField(
          label: 'STUDENT UID',
          hint: 'Enter student UID',
          controller: _inviteStudentUidCtrl,
        ),
        const SizedBox(height: 12),
        _DashLuxuryField(
          label: 'OR STUDENT PHONE NUMBER',
          hint: 'Example: +63 9XXXXXXXXX or 09XXXXXXXXX',
          controller: _inviteStudentPhoneCtrl,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 8),
        const Text(
          'Student must accept this invitation from their dashboard.',
          style: TextStyle(
            fontFamily: _bf,
            fontSize: 10,
            color: AppColors.textSub,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              onTap: _isSendingInvite ? null : _handleSendInvitationInProfile,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.65),
                  ),
                ),
                child: _isSendingInvite
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 14, color: AppColors.goldLt),
                          SizedBox(width: 8),
                          Text(
                            'SEND INVITATION',
                            style: TextStyle(
                              fontFamily: _bf,
                              fontSize: 11,
                              letterSpacing: 3,
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildDashboardPanel({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.goldDark,
              fontSize: 9,
              letterSpacing: 3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontFamily: _hf,
              color: AppColors.green,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.border, Colors.transparent],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDashboardRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.textSub,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: _bf,
                color: AppColors.green,
                fontSize: 11,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelAction({
    required String label,
    required dynamic Function() onTap,
    bool isPrimary = true,
  }) {
    return Material(
      color: isPrimary ? AppColors.green : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPrimary
                  ? AppColors.gold.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: _bf,
              color: isPrimary ? AppColors.white : AppColors.green,
              fontSize: 10,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _getDynamicGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05412B), Color(0xFF042D1F)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RobotAvatar(mood: _avatarMood, size: 40),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SafeWalk',
                    style: TextStyle(
                      fontFamily: _hf,
                      color: AppColors.white,
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text(
                    'PARENT / GUARDIAN',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold.withValues(alpha: 0.7),
                      fontSize: 9,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _RobotAvatar(mood: _avatarMood, size: 42),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _getDynamicGreeting(),
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.white.withValues(alpha: 0.7),
              fontSize: 13,
              letterSpacing: 1,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _parentName,
            style: TextStyle(
              fontFamily: _hf,
              color: AppColors.gold,
              fontSize: 44,
              height: 1,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: _childSessionActive
                    ? 'Student Online'
                    : 'Student Offline',
                dotColor: _childSessionActive
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
              _StatusPill(
                label: _deviceId == 'Not linked'
                    ? 'Device Unlinked'
                    : 'Device Linked',
                dotColor: _deviceId == 'Not linked'
                    ? const Color(0xFFFF7F7F)
                    : AppColors.goldLt,
              ),
              _StatusPill(
                label: _alertsEnabled ? 'Alerts Enabled' : 'Alerts Paused',
                dotColor: _alertsEnabled
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _RobotAvatar({required String mood, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.35),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A5E3D), Color(0xFF0B2C1E)],
        ),
        border: Border.all(color: AppColors.gold, width: size > 50 ? 2 : 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.2),
            blurRadius: size > 50 ? 14 : 10,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.75,
            height: size * 0.55,
            decoration: BoxDecoration(
              color: const Color(0xFF041C12),
              borderRadius: BorderRadius.circular(size * 0.15),
              border: Border.all(
                color: AppColors.green.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: size * 0.1,
                  left: size * 0.1,
                  right: size * 0.1,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildRobotEye(mood, size),
                      _buildRobotEye(mood, size),
                    ],
                  ),
                ),
                Positioned(
                  bottom: size * 0.1,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildRobotMouth(mood, size)),
                ),
                if (mood == 'angry')
                  Positioned(
                    top: size * 0.05,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Transform.rotate(
                          angle: 0.3,
                          child: Container(
                            width: size * 0.2,
                            height: size * 0.04,
                            color: const Color(0xFFCB392B),
                          ),
                        ),
                        Transform.rotate(
                          angle: -0.3,
                          child: Container(
                            width: size * 0.2,
                            height: size * 0.04,
                            color: const Color(0xFFCB392B),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRobotEye(String mood, double size) {
    if (mood == 'heart_eyes') {
      return Icon(
        Icons.favorite,
        color: const Color(0xFFFF4B4B),
        size: size * 0.25,
      );
    }
    final color = mood == 'angry' ? const Color(0xFFCB392B) : AppColors.gold;
    return Container(
      width: size * 0.15,
      height: size * 0.15,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.8),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildRobotMouth(String mood, double size) {
    final width = size * 0.3;
    final height = size * 0.12;
    if (mood == 'angry') {
      return Container(
        width: width,
        height: size * 0.04,
        color: const Color(0xFFCB392B),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.gold, width: size * 0.03),
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(size * 0.3),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: _bf,
            color: AppColors.textSub,
            fontSize: 9,
            letterSpacing: 4,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.gold.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gold gradient accent top line
          Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.gold,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_navItems.length, (index) {
                  final item = _navItems[index];
                  final selected = index == _selectedNavIndex;
                  return Expanded(
                    child: InkWell(
                      onTap: () => _onBottomNavTap(index),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.green.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: selected
                                    ? Border.all(
                                        color: AppColors.gold.withValues(
                                          alpha: 0.3,
                                        ),
                                        width: 0.5,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                item.icon,
                                size: 20,
                                color: selected
                                    ? AppColors.green
                                    : const Color(0xFFA6A49D),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontFamily: _bf,
                                color: selected
                                    ? AppColors.green
                                    : const Color(0xFFA6A49D),
                                fontSize: 9,
                                letterSpacing: 1,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────────────────────────

class _LinkedStudent {
  final String uid;
  final String name;
  final String phone;
  final String deviceId;

  const _LinkedStudent({
    required this.uid,
    required this.name,
    required this.phone,
    required this.deviceId,
  });
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

// ─────────────────────────────────────────────────────────────────
//  Reusable Widgets
// ─────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final Color dotColor;
  const _StatusPill({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF164837),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: dotColor, size: 6),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'JosefinSans',
              color: Color(0xFFEAF2ED),
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  const _AlertBadge({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final upper = label.toUpperCase();
    final isFalse = upper.contains('FALSE');
    final isResolved = upper.contains('RESOLVED');

    Color bg = AppColors.cream;
    Color border = AppColors.border;
    Color text = AppColors.textSub;

    if (isActive) {
      bg = const Color(0xFFCB392B).withValues(alpha: 0.1);
      border = const Color(0xFFCB392B).withValues(alpha: 0.3);
      text = const Color(0xFFCB392B);
    } else if (isFalse) {
      bg = const Color(0xFFFEF3C7);
      border = const Color(0xFFF59E0B).withValues(alpha: 0.5);
      text = const Color(0xFFB45309);
    } else if (isResolved) {
      bg = AppColors.green.withValues(alpha: 0.1);
      border = AppColors.green.withValues(alpha: 0.3);
      text = AppColors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: TextStyle(
          fontFamily: 'JosefinSans',
          fontSize: 9,
          letterSpacing: 2,
          color: text,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Luxury Input Field (matches login page style)
// ─────────────────────────────────────────────────────────────────

class _DashLuxuryField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;

  const _DashLuxuryField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<_DashLuxuryField> createState() => _DashLuxuryFieldState();
}

class _DashLuxuryFieldState extends State<_DashLuxuryField>
    with SingleTickerProviderStateMixin {
  late AnimationController _lineAnim;
  late Animation<double> _lineWidth;

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _lineWidth = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _lineAnim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _lineAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) =>
          hasFocus ? _lineAnim.forward() : _lineAnim.reverse(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              fontFamily: 'JosefinSans',
              fontSize: 9,
              letterSpacing: 4,
              color: AppColors.gold,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  keyboardType: widget.keyboardType,
                  obscureText: false,
                  style: const TextStyle(
                    fontFamily: 'JosefinSans',
                    fontSize: 14,
                    letterSpacing: 1,
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w300,
                  ),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      fontFamily: 'JosefinSans',
                      color: AppColors.textSub.withValues(alpha: 0.45),
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _lineWidth,
                  builder: (_, __) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _lineWidth.value,
                      child: Container(height: 1.2, color: AppColors.gold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



class _StudentStatusCard extends StatelessWidget {
  final _LinkedStudent student;
  final bool isSelected;
  final VoidCallback? onTap;

  const _StudentStatusCard({
    required this.student,
    this.isSelected = false,
    this.onTap,
  });

  String _normalizePhoneForLookup(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+|-'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final rawPhone = student.phone.trim();
    final normalizedPhone = _normalizePhoneForLookup(rawPhone);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('devices').limit(50).snapshots(),
      builder: (context, deviceSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('walk_sessions')
              .where('uid', isEqualTo: student.uid)
              .where('status', isEqualTo: 'active')
              .limit(1)
              .snapshots(),
          builder: (context, walkSnapshot) {
            Map<String, dynamic>? deviceData;
            if (deviceSnapshot.hasData) {
              final docs = deviceSnapshot.data!.docs;
              QueryDocumentSnapshot<Map<String, dynamic>>? matched;
              for (final doc in docs) {
                final data = doc.data();
                final devId = (data['deviceId'] ?? doc.id).toString().trim();
                final ownerUid = (data['studentUid'] ?? '').toString().trim();
                if (student.deviceId.trim().isNotEmpty &&
                    (devId == student.deviceId.trim() ||
                        doc.id == student.deviceId.trim())) {
                  matched = doc;
                  break;
                }
                if (ownerUid.isNotEmpty && ownerUid == student.uid) {
                  matched = doc;
                  break;
                }
              }
              if (matched == null && rawPhone.isNotEmpty) {
                for (final doc in docs) {
                  final phone = (doc.data()['phoneNumber'] ?? '')
                      .toString()
                      .trim();
                  if (phone.isEmpty) continue;
                  if (phone == rawPhone ||
                      _normalizePhoneForLookup(phone) == normalizedPhone) {
                    matched = doc;
                    break;
                  }
                }
              }
              if (matched == null) {
                for (final doc in docs) {
                  if (doc.id == 'safewalk_device_001' ||
                      (doc.data()['deviceId'] ?? '').toString() ==
                          'safewalk_device_001') {
                    matched = doc;
                    break;
                  }
                }
              }
              deviceData = matched?.data();
            }

            final hasWalk =
                walkSnapshot.hasData && walkSnapshot.data!.docs.isNotEmpty;
            final walkData = hasWalk
                ? walkSnapshot.data!.docs.first.data()
                : null;

            final deviceStatus = (deviceData?['status'] ?? 'offline')
                .toString()
                .toLowerCase();
            final isOnline =
                deviceStatus == 'active' || deviceStatus == 'online';

            final activeRoute = hasWalk
                ? (walkData?['route'] ?? 'Active Route').toString()
                : 'No active route';
            final distanceKm = hasWalk
                ? (walkData?['distanceKm'] as num?)?.toDouble() ?? 0.0
                : 0.0;

            final locationField = deviceData?['location'];
            final coordinates = deviceData?['coordinates'];
            final latitude = deviceData?['latitude'];
            final longitude = deviceData?['longitude'];
            String locationStr = 'Unknown';
            if (coordinates is GeoPoint) {
              locationStr =
                  '${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)}';
            } else if (latitude is num &&
                longitude is num &&
                (latitude.abs() > 0.0001 || longitude.abs() > 0.0001)) {
              locationStr =
                  '${latitude.toDouble().toStringAsFixed(6)}, ${longitude.toDouble().toStringAsFixed(6)}';
            } else if (locationField is GeoPoint) {
              locationStr =
                  '${locationField.latitude.toStringAsFixed(6)}, ${locationField.longitude.toStringAsFixed(6)}';
            } else if (deviceData?['locationText'] != null &&
                deviceData!['locationText'].toString().trim().isNotEmpty) {
              locationStr = deviceData['locationText'].toString();
            } else if (locationField != null &&
                locationField.toString().trim().isNotEmpty) {
              locationStr = locationField.toString();
            }

            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.gold
                        : (isOnline
                              ? AppColors.green.withValues(alpha: 0.35)
                              : AppColors.border),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFFE8F5E9)
                                : AppColors.cream,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.person,
                            size: 17,
                            color: isOnline
                                ? AppColors.green
                                : AppColors.textSub,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.name.toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'JosefinSans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.green,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                isOnline ? 'ONLINE' : 'OFFLINE',
                                style: TextStyle(
                                  fontFamily: 'JosefinSans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: isOnline
                                      ? AppColors.green
                                      : AppColors.textSub,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 10),
                    _buildDetailRow('Route', activeRoute),
                    const SizedBox(height: 6),
                    _buildDetailRow('Location', locationStr),
                    if (hasWalk) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow(
                        'Distance',
                        '${distanceKm.toStringAsFixed(1)} km',
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'JosefinSans',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSub,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'JosefinSans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
        ),
      ],
    );
  }
}
