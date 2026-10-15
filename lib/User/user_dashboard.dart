import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';
import '../utils/google_maps_web_guard.dart';

class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({super.key});

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage> {
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

  String _fullName = 'Student';
  String _email = '';
  String _phoneNumber = '';
  String _studentUid = '';
  String _avatarMood = 'happy';
  final String _activeRoute = 'Main Campus -> Dorm Block C';

  String _deviceId = 'Not linked';
  String _linkedDeviceId = '';
  String _deviceName = 'No linked device';
  String _deviceLocation = 'Unknown';
  String _deviceStatus = 'offline';
  LatLng? _deviceCoordinates;
  bool _isDetectingLocation = false;
  StreamSubscription<Position>? _positionStreamSub;
  BitmapDescriptor? _sosMarkerIcon;
  GoogleMapController? _routeMapController;
  LatLng? _nextMapFocusPoint;
  LatLng? _lastFocusedMapPoint;

  bool _alertsEnabled = true;
  bool _safeModeEnabled = true;
  bool _locationSharingEnabled = true;
  String _linkedParentUid = '';
  String _linkedParentPhone = '';
  String _linkedParentName = '';
  List<_ParentInvitation> _pendingInvitations = const [];
  bool _isLoadingInvitations = false;
  bool _isHandlingInvitation = false;
  String _invitationActionId = '';

  final List<_NavItem> _navItems = const [
    _NavItem('Map', Icons.map_outlined),
    _NavItem('Device', Icons.smartphone_outlined),
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
    final direct = _coordinatesFromValues(
      data['latitude'] ?? data['lat'],
      data['longitude'] ?? data['lng'] ?? data['lon'],
    );
    if (direct != null) return direct;

    final coordinates = data['coordinates'];
    if (coordinates is Map) {
      final nested = _coordinatesFromValues(
        coordinates['latitude'] ?? coordinates['lat'],
        coordinates['longitude'] ?? coordinates['lng'] ?? coordinates['lon'],
      );
      if (nested != null) return nested;
    }

    final location = data['location'];
    if (location is GeoPoint) {
      if (_isValidLatLng(location.latitude, location.longitude)) {
        return LatLng(location.latitude, location.longitude);
      }
    }
    if (location is String) {
      final parsed = _coordinatesFromText(location);
      if (parsed != null) return parsed;
    }

    return null;
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
        (data['status'] ?? '').toString().toLowerCase() == 'resolved' ||
        (data['status'] ?? '').toString().toLowerCase() == 'acknowledged') {
      return null;
    }

    final coordinates = data['coordinates'];
    if (coordinates is GeoPoint) {
      if (_isValidLatLng(coordinates.latitude, coordinates.longitude)) {
        return LatLng(coordinates.latitude, coordinates.longitude);
      }
    }
    if (coordinates is Map) {
      final nested = _coordinatesFromValues(
        coordinates['latitude'] ?? coordinates['lat'],
        coordinates['longitude'] ?? coordinates['lng'] ?? coordinates['lon'],
      );
      if (nested != null) return nested;
    }

    final direct = _coordinatesFromValues(
      data['latitude'] ?? data['lat'],
      data['longitude'] ?? data['lng'] ?? data['lon'],
    );
    if (direct != null) return direct;

    final location = data['location'];
    if (location is GeoPoint) {
      if (_isValidLatLng(location.latitude, location.longitude)) {
        return LatLng(location.latitude, location.longitude);
      }
    }
    if (location is String) {
      final fromTxt = _coordinatesFromText(location);
      if (fromTxt != null) return fromTxt;
    }

    // Fallback: If hardware reported (0,0) or pending fix, use student's live location!
    if (_deviceCoordinates != null && !_isDefaultManila(_deviceCoordinates)) {
      return _deviceCoordinates;
    }

    return null;
  }

  String _formatCoordinateLabel(LatLng? point) {
    if (point == null) return 'Not available';
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  String get _activeStudentUid {
    if (_studentUid.isNotEmpty) return _studentUid;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  _SosMapState _resolveSosMapState(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sosDocs =
        docs.where((doc) {
          final data = doc.data();
          final type = (data['type'] ?? '').toString().toLowerCase();
          return type == 'sos' || type == 'voice_help' || type == 'emergency';
        }).toList()..sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aStatus = (aData['status'] ?? '').toString().toLowerCase();
          final bStatus = (bData['status'] ?? '').toString().toLowerCase();
          int priority(String s) {
            if (s == 'active' || s == 'verifying_speech') return 0;
            if (s == 'acknowledged') return 1;
            return 2;
          }
          final pA = priority(aStatus);
          final pB = priority(bStatus);
          if (pA != pB) {
            return pA.compareTo(pB);
          }
          final aTs = aData['timestamp'] as Timestamp?;
          final bTs = bData['timestamp'] as Timestamp?;
          final aClientTs = aData['clientTimestamp'] as Timestamp?;
          final bClientTs = bData['clientTimestamp'] as Timestamp?;
          final aMs =
              aTs?.millisecondsSinceEpoch ??
              aClientTs?.millisecondsSinceEpoch ??
              0;
          final bMs =
              bTs?.millisecondsSinceEpoch ??
              bClientTs?.millisecondsSinceEpoch ??
              0;
          return bMs.compareTo(aMs);
        });

    if (sosDocs.isEmpty) return const _SosMapState();

    final latestDoc = sosDocs.first;
    final latest = latestDoc.data();
    final status = (latest['status'] ?? '').toString().toLowerCase();
    final isActive = status == 'active' || status == 'verifying_speech';
    final isAck = status == 'acknowledged';
    final isFalseAlarm = status == 'false_alarm' || status == 'cancelled_false_trigger';
    final isResolved = status == 'resolved';
    final isCleared = latest['locationCleared'] == true;

    // Coordinate is strictly null if false alarm, resolved, acknowledged, or location cleared
    final coordinate = (isFalseAlarm || isResolved || isCleared || isAck || !isActive)
        ? null
        : _extractAlertCoordinates(latest);

    final locationText = (latest['location'] ?? '').toString().trim();
    return _SosMapState(
      coordinate: coordinate,
      isActive: isActive,
      isAcknowledged: isAck,
      isFalseAlarm: isFalseAlarm,
      alertId: latestDoc.id,
      timestampLabel: _formatTimestamp(latest['timestamp'] as Timestamp?),
      areaLabel: locationText.isEmpty
          ? _formatCoordinateLabel(coordinate)
          : locationText,
    );
  }

  LatLng get _mapCenter => _deviceCoordinates ?? _defaultMapCenter;

  bool get _hasDeviceCoordinates => _deviceCoordinates != null;

  String get _mapCoordinateLabel {
    return _formatCoordinateLabel(_deviceCoordinates);
  }

  bool get _mobileMapLiteMode => false;

  bool _isSamePoint(LatLng a, LatLng b) {
    const tolerance = 0.00001;
    return (a.latitude - b.latitude).abs() <= tolerance &&
        (a.longitude - b.longitude).abs() <= tolerance;
  }

  void _focusRouteMapOnPoint(
    LatLng point, {
    double zoom = 16,
    bool force = false,
  }) {
    final controller = _routeMapController;
    if (controller == null) return;

    if (!force &&
        _lastFocusedMapPoint != null &&
        _isSamePoint(_lastFocusedMapPoint!, point)) {
      return;
    }

    _lastFocusedMapPoint = point;
    try {
      controller
          .animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: point, zoom: zoom),
            ),
          )
          .catchError((_) {});
    } catch (e) {
      debugPrint('Google Maps Web view not ready yet. Skipping animation: $e');
    }

    if (_nextMapFocusPoint != null &&
        _isSamePoint(_nextMapFocusPoint!, point)) {
      _nextMapFocusPoint = null;
    }
  }

  Future<Uint8List> _buildSosMarkerBytes({int size = 144}) async {
    final markerSize = size.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, markerSize, markerSize),
    );

    final center = Offset(markerSize / 2, markerSize * 0.38);
    final topRadius = markerSize * 0.22;
    final bodyColor = const Color(0xFFF21D2F);
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..style = PaintingStyle.fill;
    final pinPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;

    final shadowPath = Path()
      ..moveTo(center.dx, markerSize * 0.92)
      ..lineTo(center.dx - topRadius * 0.62, center.dy + topRadius * 0.68)
      ..lineTo(center.dx + topRadius * 0.62, center.dy + topRadius * 0.68)
      ..close();
    canvas.drawCircle(
      Offset(center.dx, center.dy + markerSize * 0.012),
      topRadius,
      shadowPaint,
    );
    canvas.drawPath(shadowPath, shadowPaint);

    final pinPath = Path()
      ..moveTo(center.dx, markerSize * 0.88)
      ..lineTo(center.dx - topRadius * 0.58, center.dy + topRadius * 0.62)
      ..lineTo(center.dx + topRadius * 0.58, center.dy + topRadius * 0.62)
      ..close();
    canvas.drawCircle(center, topRadius, pinPaint);
    canvas.drawPath(pinPath, pinPaint);
    canvas.drawCircle(center, topRadius * 0.47, Paint()..color = Colors.white);

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
      final bytes = await _buildSosMarkerBytes();
      if (bytes.isEmpty) return;
      final icon = BitmapDescriptor.fromBytes(bytes);
      if (!mounted) return;
      setState(() => _sosMarkerIcon = icon);
    } catch (_) {
      // Keep default marker fallback when custom marker generation fails.
    }
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

  Future<void> _handleAlertAction(String alertId, String currentStatus) async {
    final status = currentStatus.toLowerCase().trim();
    if (status == 'resolved') {
      _showActionSnack("The issue is already been fixed.");
      return;
    }
    if (status == 'false_alarm') {
      _showActionSnack("This alert was already marked as a false alarm.");
      return;
    }
    await _confirmAndReportFalseAlarm(alertId);
  }

  Future<void> _confirmAndReportFalseAlarm(String alertId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: AppColors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_off_outlined,
                  color: Color(0xFFB45309),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'False Alarm?',
                  style: TextStyle(
                    fontFamily: _hf,
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                    color: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Did you accidentally click your device or trigger the emergency SOS?\n\n'
            'Marking this as a False Alarm will cancel the alert and notify your parent that you are safe.',
            style: TextStyle(
              fontFamily: _bf,
              fontSize: 13,
              height: 1.5,
              color: AppColors.textMain,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'KEEP ALERT ACTIVE',
                style: TextStyle(
                  fontFamily: _bf,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSub,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB45309),
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'YES, FALSE ALARM',
                style: TextStyle(
                  fontFamily: _bf,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _reportFalseAlarm(alertId);
    }
  }

  Future<void> _reportFalseAlarm(String alertId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await _firestore.collection('emergency_alerts').doc(alertId).set({
        'status': 'false_alarm',
        'falseAlarm': true,
        'falseAlarmBy': uid,
        'falseAlarmAt': FieldValue.serverTimestamp(),
        'cancellationReason': 'Device miss-clicked by student (False alarm reported)',
        'locationCleared': true,
        'location': 'Alert cancelled (False alarm)',
        'coordinates': FieldValue.delete(),
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'lat': FieldValue.delete(),
        'lng': FieldValue.delete(),
        'lon': FieldValue.delete(),
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': uid,
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _avatarMood = 'happy';
          _nextMapFocusPoint = null;
          _lastFocusedMapPoint = null;
          if (_linkedDeviceId.isEmpty || _linkedDeviceId == 'Not linked') {
            _deviceCoordinates = null;
            _deviceLocation = 'No coordinates';
          }
        });
      }
      if (_linkedDeviceId.isNotEmpty && _linkedDeviceId != 'Not linked') {
        await _loadLinkedDevice();
      }
      _showActionSnack('Alert marked as False Alarm. Your parent has been notified that you are safe.');
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
      if (mounted) {
        setState(() {
          _avatarMood = 'happy';
          _nextMapFocusPoint = null;
          _lastFocusedMapPoint = null;
          if (_linkedDeviceId.isEmpty || _linkedDeviceId == 'Not linked') {
            _deviceCoordinates = null;
            _deviceLocation = 'Location removed';
          }
        });
      }
      if (_linkedDeviceId.isNotEmpty && _linkedDeviceId != 'Not linked') {
        await _loadLinkedDevice();
      }
      _showActionSnack("The issue is already been fixed. Location removed.");
    } catch (e) {
      _showActionSnack('Failed to resolve alert: $e', isError: true);
    }
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
    _positionStreamSub?.cancel();
    _routeMapController?.dispose();
    _profileNameCtrl.dispose();
    _profilePhoneCtrl.dispose();
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
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final settingsDoc = await _firestore
          .collection('user_settings')
          .doc(currentUser.uid)
          .get();
      if (!mounted) return;
      setState(() {
        _studentUid = currentUser.uid;
        _fullName = (userDoc.data()?['fullName'] ?? 'Student').toString();
        _email = (userDoc.data()?['email'] ?? '').toString();
        _phoneNumber = (userDoc.data()?['phoneNumber'] ?? '').toString();
        _linkedDeviceId = (userDoc.data()?['linkedDeviceId'] ?? '').toString();
        _avatarMood = (userDoc.data()?['avatarMood'] ?? 'happy').toString();
        _alertsEnabled =
            (settingsDoc.data()?['alertsEnabled'] as bool?) ?? true;
        _safeModeEnabled =
            (settingsDoc.data()?['safeModeEnabled'] as bool?) ?? true;
        _locationSharingEnabled =
            (settingsDoc.data()?['locationSharingEnabled'] as bool?) ?? true;
      });
      await _loadLinkedDevice();
      await _loadLinkedParent();
      await _loadPendingInvitations();
      if (_locationSharingEnabled &&
          (_deviceCoordinates == null || _isDefaultManila(_deviceCoordinates))) {
        await _detectDeviceExactLocation(showFeedback: false, autoCenter: true);
      }
      if (_locationSharingEnabled && _deviceCoordinates != null) {
        _startLiveLocationTracking();
      }
    } catch (e) {
      _showActionSnack('Failed to load dashboard data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLinkedDevice() async {
    if (_linkedDeviceId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _deviceId = 'Not linked';
        _deviceName = 'No linked device';
        _deviceLocation = 'Unknown';
        _deviceStatus = 'offline';
        _deviceCoordinates = null;
      });
      return;
    }

    final targetId = _linkedDeviceId.trim();
    var q = await _firestore
        .collection('devices')
        .where('deviceId', isEqualTo: targetId)
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      if (!mounted) return;
      setState(() {
        _deviceId = targetId;
        _deviceName = 'Unknown Tracker';
        _deviceLocation = 'Unknown';
        _deviceStatus = 'offline';
        _deviceCoordinates = null;
      });
      return;
    }

    final data = q.docs.first.data();
    final locationField = data['location'];
    if (!mounted) return;
    setState(() {
      _deviceId = (data['deviceId'] ?? q.docs.first.id).toString();
      _deviceName = (data['deviceName'] ?? 'Emergency Device').toString();
      _deviceLocation = locationField is GeoPoint
          ? '${locationField.latitude.toStringAsFixed(6)}, ${locationField.longitude.toStringAsFixed(6)}'
          : (locationField ?? 'Unknown').toString();
      _deviceStatus = (data['status'] ?? 'active').toString().toLowerCase();
      final parsedCoords = _extractDeviceCoordinates(data);
      if (!_isDefaultManila(parsedCoords) || _deviceCoordinates == null) {
        _deviceCoordinates = parsedCoords;
      }
    });
  }

  Future<void> _loadLinkedParent() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final normalizedStudentPhone = _normalizePhoneForLookup(_phoneNumber);
    final linkQuery = await _firestore
        .collection('parent_student_links')
        .where('studentUid', isEqualTo: currentUid)
        .limit(50)
        .get();

    var acceptedDocs = linkQuery.docs.where((doc) {
      final status = (doc.data()['status'] ?? 'accepted')
          .toString()
          .toLowerCase();
      return status == 'accepted';
    }).toList();

    if (acceptedDocs.isEmpty && normalizedStudentPhone.isNotEmpty) {
      final byPhoneQuery = await _firestore
          .collection('parent_student_links')
          .where('studentPhoneNormalized', isEqualTo: normalizedStudentPhone)
          .limit(50)
          .get();
      acceptedDocs = byPhoneQuery.docs.where((doc) {
        final status = (doc.data()['status'] ?? 'accepted')
            .toString()
            .toLowerCase();
        return status == 'accepted';
      }).toList();
    }

    if (!mounted) return;
    if (acceptedDocs.isEmpty) {
      setState(() {
        _linkedParentUid = '';
        _linkedParentPhone = '';
        _linkedParentName = '';
      });
      return;
    }

    acceptedDocs.sort((a, b) {
      final aTs = (a.data()['updatedAt'] ?? a.data()['linkedAt']) as Timestamp?;
      final bTs = (b.data()['updatedAt'] ?? b.data()['linkedAt']) as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
        aTs?.millisecondsSinceEpoch ?? 0,
      );
    });

    final link = acceptedDocs.first.data();
    final parentUid = (link['parentUid'] ?? '').toString();
    final parentPhone = (link['parentPhone'] ?? '').toString();
    String parentName = (link['parentName'] ?? '').toString();
    if (parentName.trim().isEmpty && parentUid.trim().isNotEmpty) {
      final parentDoc = await _firestore
          .collection('users')
          .doc(parentUid)
          .get();
      parentName = (parentDoc.data()?['fullName'] ?? '').toString();
    }

    if (!mounted) return;
    setState(() {
      _linkedParentUid = parentUid;
      _linkedParentPhone = parentPhone;
      _linkedParentName = parentName;
    });
  }

  Future<void> _loadPendingInvitations() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    if (mounted) setState(() => _isLoadingInvitations = true);
    try {
      final normalizedStudentPhone = _normalizePhoneForLookup(_phoneNumber);
      final byUid = await _firestore
          .collection('parent_student_invitations')
          .where('studentUid', isEqualTo: currentUid)
          .limit(50)
          .get();

      final byPhone = byUid.docs.isEmpty && normalizedStudentPhone.isNotEmpty
          ? await _firestore
                .collection('parent_student_invitations')
                .where(
                  'studentPhoneNormalized',
                  isEqualTo: normalizedStudentPhone,
                )
                .limit(50)
                .get()
          : null;

      final docs = byUid.docs.isNotEmpty
          ? byUid.docs
          : (byPhone?.docs ?? const []);

      final invitations = <_ParentInvitation>[];
      for (final doc in docs) {
        final data = doc.data();
        final status = (data['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'pending') continue;

        final parentUid = (data['parentUid'] ?? '').toString().trim();
        if (parentUid.isEmpty) continue;

        final studentUid =
            (data['studentUid'] ?? currentUid).toString().trim().isEmpty
            ? currentUid
            : (data['studentUid'] ?? currentUid).toString().trim();

        invitations.add(
          _ParentInvitation(
            id: doc.id,
            parentUid: parentUid,
            parentName: (data['parentName'] ?? 'Parent').toString().trim(),
            parentPhone: (data['parentPhone'] ?? '').toString().trim(),
            studentUid: studentUid,
            createdAt: data['createdAt'] as Timestamp?,
          ),
        );
      }

      invitations.sort((a, b) {
        return (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.createdAt?.millisecondsSinceEpoch ?? 0,
        );
      });

      if (!mounted) return;
      setState(() => _pendingInvitations = invitations);
    } catch (e) {
      _showActionSnack('Failed to load parent invitations: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingInvitations = false);
    }
  }

  Future<void> _acceptInvitation(_ParentInvitation invitation) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    final invitationStudentUid = invitation.studentUid.trim();
    final studentUid = invitationStudentUid.isEmpty
        ? (_studentUid.isEmpty ? user.uid : _studentUid)
        : invitationStudentUid;
    final parentUid = invitation.parentUid.trim();
    if (parentUid.isEmpty) {
      _showActionSnack('Invalid invitation.', isError: true);
      return;
    }

    final invitationDocId = invitation.id.trim().isEmpty
        ? '${parentUid}_$studentUid'
        : invitation.id.trim();
    final linkDocId = '${parentUid}_$studentUid';
    final parentPhone = invitation.parentPhone.trim();

    try {
      final batch = _firestore.batch();
      final invitationRef = _firestore
          .collection('parent_student_invitations')
          .doc(invitationDocId);
      batch.set(invitationRef, {
        'status': 'accepted',
        'studentUid': studentUid,
        'studentName': _fullName.trim(),
        'studentPhone': _phoneNumber.trim(),
        'studentPhoneNormalized': _normalizePhoneForLookup(_phoneNumber),
        'updatedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final linkRef = _firestore
          .collection('parent_student_links')
          .doc(linkDocId);
      batch.set(linkRef, {
        'parentUid': parentUid,
        'parentName': invitation.parentName.trim(),
        'parentPhone': parentPhone,
        'parentPhoneNormalized': _normalizePhoneForLookup(parentPhone),
        'studentUid': studentUid,
        'studentName': _fullName.trim(),
        'studentPhone': _phoneNumber.trim(),
        'studentPhoneNormalized': _normalizePhoneForLookup(_phoneNumber),
        'status': 'accepted',
        'linkedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (_linkedDeviceId.isNotEmpty) {
        final dQuery = await _firestore
            .collection('devices')
            .where('deviceId', isEqualTo: _linkedDeviceId)
            .limit(1)
            .get();
        if (dQuery.docs.isNotEmpty) {
          await _firestore
              .collection('devices')
              .doc(dQuery.docs.first.id)
              .update({
                'parentPhoneNumber': parentPhone,
                'parentUid': parentUid,
              });
        }
      }

      await _loadLinkedParent();
      await _loadPendingInvitations();
      _showActionSnack('Invitation accepted.');
    } catch (e) {
      _showActionSnack('Failed to accept invitation: $e', isError: true);
    }
  }

  Future<void> _rejectInvitation(_ParentInvitation invitation) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    final invitationStudentUid = invitation.studentUid.trim();
    final studentUid = invitationStudentUid.isEmpty
        ? (_studentUid.isEmpty ? user.uid : _studentUid)
        : invitationStudentUid;
    final parentUid = invitation.parentUid.trim();
    if (parentUid.isEmpty) {
      _showActionSnack('Invalid invitation.', isError: true);
      return;
    }
    final invitationDocId = invitation.id.trim().isEmpty
        ? '${parentUid}_$studentUid'
        : invitation.id.trim();

    try {
      await _firestore
          .collection('parent_student_invitations')
          .doc(invitationDocId)
          .set({
            'status': 'rejected',
            'studentUid': studentUid,
            'studentName': _fullName.trim(),
            'studentPhone': _phoneNumber.trim(),
            'studentPhoneNormalized': _normalizePhoneForLookup(_phoneNumber),
            'updatedAt': FieldValue.serverTimestamp(),
            'respondedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await _loadPendingInvitations();
      _showActionSnack('Invitation rejected.');
    } catch (e) {
      _showActionSnack('Failed to reject invitation: $e', isError: true);
    }
  }

  // ─── Actions ───────────────────────────────────────────────────

  Future<LatLng?> _detectDeviceExactLocation({
    bool showFeedback = true,
    bool updateFirestore = true,
    bool autoCenter = true,
  }) async {
    if (_isDetectingLocation) return _deviceCoordinates;
    if (mounted) setState(() => _isDetectingLocation = true);

    try {
      bool serviceEnabled = true;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {
        serviceEnabled = true;
      }

      if (!serviceEnabled) {
        if (showFeedback) {
          _showActionSnack(
            'Location services are turned off on your device. Please turn on GPS.',
            isError: true,
          );
        }
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (showFeedback) {
          _showActionSnack(
            'Location permission denied. Please allow location access to detect your exact position.',
            isError: true,
          );
        }
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        if (showFeedback) {
          _showActionSnack(
            'Location permission is permanently denied. Please enable it in browser / app site settings.',
            isError: true,
          );
        }
        return null;
      }

      Position? position;
      // 1. Try high accuracy
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e1) {
        debugPrint('High accuracy location attempt: $e1. Trying medium accuracy...');
        // 2. Fallback to medium accuracy
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
        } catch (e2) {
          debugPrint('Medium accuracy location attempt: $e2. Trying last known...');
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
          if (position == null) {
            if (showFeedback) {
              _showActionSnack(
                'Could not detect live GPS location. Please check device location settings.',
                isError: true,
              );
            }
            return null;
          }
        }
      }

      final exactPoint = LatLng(position.latitude, position.longitude);
      final label =
          '${exactPoint.latitude.toStringAsFixed(6)}, ${exactPoint.longitude.toStringAsFixed(6)}';

      if (!mounted) return exactPoint;

      setState(() {
        _deviceCoordinates = exactPoint;
        _deviceLocation = label;
        if (_deviceId == 'Not linked') {
          _deviceId = 'Device GPS (Active)';
          _deviceName = 'This Device (Live GPS)';
          _deviceStatus = 'active';
        }
      });

      if (autoCenter) {
        _focusRouteMapOnPoint(exactPoint, zoom: 16, force: true);
      }

      if (updateFirestore) {
        await _syncLocationToFirestore(exactPoint, label);
      }

      if (_locationSharingEnabled) {
        _startLiveLocationTracking();
      }

      if (showFeedback) {
        _showActionSnack('Exact device location detected: $label');
      }

      return exactPoint;
    } catch (e) {
      if (showFeedback) {
        _showActionSnack('Failed to detect location: $e', isError: true);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
      }
    }
  }

  void _startLiveLocationTracking() {
    _positionStreamSub?.cancel();
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (!mounted) return;
          final point = LatLng(position.latitude, position.longitude);
          final label =
              '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
          setState(() {
            _deviceCoordinates = point;
            _deviceLocation = label;
          });
          _syncLocationToFirestore(point, label);
        },
        onError: (e) {
          debugPrint('Live location stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('Failed to start location stream: $e');
    }
  }

  Future<void> _syncLocationToFirestore(LatLng point, String label) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final batch = _firestore.batch();

      final userRef = _firestore.collection('users').doc(currentUser.uid);
      batch.set(userRef, {
        'location': GeoPoint(point.latitude, point.longitude),
        'latitude': point.latitude,
        'longitude': point.longitude,
        'locationText': label,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (_linkedDeviceId.isNotEmpty && _linkedDeviceId != 'Not linked') {
        final devRef = _firestore.collection('devices').doc(_linkedDeviceId);
        batch.set(devRef, {
          'deviceId': _linkedDeviceId,
          'location': GeoPoint(point.latitude, point.longitude),
          'latitude': point.latitude,
          'longitude': point.longitude,
          'locationText': label,
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Failed to sync location to Firestore: $e');
    }
  }

  Future<LatLng?> _getCurrentPhoneLocation() async {
    final point = await _detectDeviceExactLocation(
      showFeedback: false,
      updateFirestore: true,
      autoCenter: false,
    );
    if (point == null) {
      _showActionSnack(
        'Could not get live GPS location. Using last known linked location.',
        isError: true,
      );
    }
    return point;
  }

  Future<void> _createSosAlert() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _loadLinkedParent();
      await _loadLinkedDevice();
      if (_linkedParentUid.trim().isEmpty) {
        _showActionSnack(
          'No linked parent yet. Accept a parent invitation in Profile first.',
          isError: true,
        );
        return;
      }

      final livePoint = await _getCurrentPhoneLocation();
      final mapPoint =
          livePoint ??
          _deviceCoordinates ??
          _coordinatesFromText(_deviceLocation) ??
          _mapCenter;
      final locationGeoPoint = GeoPoint(mapPoint.latitude, mapPoint.longitude);
      final locationLabel = _formatCoordinateLabel(mapPoint);

      await _firestore.collection('emergency_alerts').add({
        'uid': user.uid,
        'studentUid': user.uid,
        'fullName': _fullName,
        'email': _email,
        'phoneNumber': _phoneNumber,
        'parentUid': _linkedParentUid,
        'parentPhoneNumber': _linkedParentPhone,
        'type': 'sos',
        'severity': 'high',
        'status': 'active',
        'message': 'SOS button pressed by $_fullName.',
        'location': locationLabel,
        'coordinates': locationGeoPoint,
        'locationSource': livePoint != null ? 'phone_gps' : 'linked_device',
        'triggeredBy': 'student_dashboard',
        'clientTimestamp': Timestamp.now(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _selectedNavIndex = 0;
          _nextMapFocusPoint = mapPoint;
          _deviceCoordinates = mapPoint;
          _deviceLocation = locationLabel;
          _avatarMood = 'angry';
        });
      }
      _showActionSnack(
        livePoint != null
            ? 'SOS sent with your live phone location.'
            : 'SOS sent using your last linked location.',
      );
    } catch (e) {
      _showActionSnack('Failed to send SOS alert: $e', isError: true);
    }
  }

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
        _fullName = fullName.trim();
        _phoneNumber = phoneNumber.trim();
        _avatarMood = avatarMood;
      });
      await _loadLinkedDevice();
      await _loadLinkedParent();
      await _loadPendingInvitations();
      _showActionSnack('Profile updated.');
    } catch (e) {
      _showActionSnack('Failed to update profile: $e', isError: true);
    }
  }

  Future<void> _saveSettings({
    required bool alertsEnabled,
    required bool safeModeEnabled,
    required bool locationSharingEnabled,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _firestore.collection('user_settings').doc(uid).set({
        'alertsEnabled': alertsEnabled,
        'safeModeEnabled': safeModeEnabled,
        'locationSharingEnabled': locationSharingEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _alertsEnabled = alertsEnabled;
        _safeModeEnabled = safeModeEnabled;
        _locationSharingEnabled = locationSharingEnabled;
      });
      if (locationSharingEnabled) {
        _startLiveLocationTracking();
      } else {
        _positionStreamSub?.cancel();
      }
      _showActionSnack('Settings saved.');
    } catch (e) {
      _showActionSnack('Failed to save settings: $e', isError: true);
    }
  }

  // ─── LUXURY DIALOGS ────────────────────────────────────────────

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
            color: AppColors.gold.withOpacity(0.2),
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
                color: AppColors.green.withOpacity(0.5),
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
            color: color.withOpacity(0.8),
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

  Future<void> _showLocationDialog({
    LatLng? mapPoint,
    bool sosIsActive = false,
    String areaLabel = '',
    String sosTimestampLabel = '',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final effectivePoint = mapPoint ?? _deviceCoordinates;
            final center = effectivePoint ?? _defaultMapCenter;
            final hasPoint = effectivePoint != null;
            final focusLabel = areaLabel.isEmpty ? _deviceLocation : areaLabel;

            Widget infoTile(String label, String value) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontFamily: _bf,
                          fontSize: 9,
                          letterSpacing: 2.8,
                          color: AppColors.gold,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: _bf,
                          fontSize: 12,
                          letterSpacing: 0.4,
                          color: AppColors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.86,
              minChildSize: 0.6,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.gold,
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.gold,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'LIVE MAP',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 9,
                                  letterSpacing: 4,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Location Info',
                                style: TextStyle(
                                  fontFamily: _hf,
                                  fontSize: 32,
                                  height: 1,
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w300,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: sosIsActive
                                  ? const Color(0xFF7E1F14)
                                  : hasPoint
                                  ? const Color(0xFF0F5A3E)
                                  : const Color(0xFF6C757D),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              sosIsActive
                                  ? 'SOS ACTIVE'
                                  : hasPoint
                                  ? 'TRACKING'
                                  : 'NO COORDS',
                              style: const TextStyle(
                                fontFamily: _bf,
                                color: AppColors.white,
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 220,
                          child: kIsWeb && !isGoogleMapsJsLoaded()
                              ? _buildWebMapFallback(
                                  contextLabel: 'Student Location Sheet',
                                )
                              : GoogleMap(
                                  key: const ValueKey('sheet-map-main'),
                                  initialCameraPosition: CameraPosition(
                                    target: center,
                                    zoom: hasPoint ? 16 : 12,
                                  ),
                                  liteModeEnabled: _mobileMapLiteMode,
                                  mapType: MapType.normal,
                                  gestureRecognizers: _mapGestureRecognizers,
                                  zoomGesturesEnabled: true,
                                  scrollGesturesEnabled: true,
                                  markers: hasPoint
                                      ? {
                                          Marker(
                                            markerId: const MarkerId(
                                              'sheet-device',
                                            ),
                                            position: center,
                                            icon: sosIsActive
                                                ? (_sosMarkerIcon ??
                                                      BitmapDescriptor.defaultMarkerWithHue(
                                                        BitmapDescriptor.hueRed,
                                                      ))
                                                : BitmapDescriptor.defaultMarkerWithHue(
                                                    BitmapDescriptor.hueAzure,
                                                  ),
                                            infoWindow: InfoWindow(
                                              title: sosIsActive
                                                  ? 'SOS Location'
                                                  : _deviceName,
                                              snippet: focusLabel,
                                            ),
                                          ),
                                        }
                                      : <Marker>{},
                                  circles: hasPoint
                                      ? {
                                          Circle(
                                            circleId: const CircleId(
                                              'sheet-radius',
                                            ),
                                            center: center,
                                            radius: sosIsActive ? 90 : 45,
                                            fillColor: sosIsActive
                                                ? const Color(0x55CB392B)
                                                : const Color(0x331AA972),
                                            strokeColor: sosIsActive
                                                ? const Color(0xFFCB392B)
                                                : const Color(0xFF1AA972),
                                            strokeWidth: 2,
                                          ),
                                        }
                                      : <Circle>{},
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: true,
                                  zoomControlsEnabled: false,
                                  mapToolbarEnabled: false,
                                  compassEnabled: false,
                                  rotateGesturesEnabled: false,
                                  tiltGesturesEnabled: false,
                                  onMapCreated: (_) {},
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Google Maps live preview',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _bf,
                          fontSize: 9,
                          letterSpacing: 1,
                          color: AppColors.textSub.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 14),
                      infoTile('ROUTE', _activeRoute),
                      const SizedBox(height: 10),
                      infoTile('MAP FOCUS', focusLabel),
                      const SizedBox(height: 10),
                      infoTile(
                        'SOS STATUS',
                        sosIsActive
                            ? 'Active${sosTimestampLabel.isEmpty ? '' : ' - $sosTimestampLabel'}'
                            : 'Not active',
                      ),
                      const SizedBox(height: 10),
                      infoTile(
                        'COORDINATES',
                        _formatCoordinateLabel(effectivePoint),
                      ),
                      const SizedBox(height: 10),
                      infoTile(
                        'LOCATION SHARING',
                        _locationSharingEnabled ? 'Enabled' : 'Disabled',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              await _detectDeviceExactLocation(
                                showFeedback: true,
                                autoCenter: true,
                              );
                              if (!mounted) return;
                              setSheetState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(0.65),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.my_location_rounded,
                                    size: 15,
                                    color: AppColors.goldLt,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'DETECT EXACT GPS LOCATION',
                                    style: TextStyle(
                                      fontFamily: _bf,
                                      color: AppColors.white,
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
                );
              },
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
      actionLabel: 'DETECT GPS LOCATION',
      onAction: () async {
        await _detectDeviceExactLocation(showFeedback: true, autoCenter: true);
      },
    );
  }

  Future<void> _showLinkDeviceDialog() async {
    final deviceIdCtrl = TextEditingController(text: _linkedDeviceId);
    final deviceNameCtrl = TextEditingController(
      text: _deviceName == 'No linked device' ? '' : _deviceName,
    );
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Link Emergency Tracker',
                      style: const TextStyle(
                        fontFamily: _hf,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ENTER YOUR DEVICE ID AND NAME TO PAIR IT',
                      style: const TextStyle(
                        fontFamily: _bf,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: deviceIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Device ID (e.g., safewalk_device_001)',
                        labelStyle: TextStyle(
                          fontFamily: _bf,
                          color: AppColors.green,
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.gold),
                        ),
                      ),
                      style: const TextStyle(fontFamily: _bf),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: deviceNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Device Name (e.g., My LilyGo Board)',
                        labelStyle: TextStyle(
                          fontFamily: _bf,
                          color: AppColors.green,
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.gold),
                        ),
                      ),
                      style: const TextStyle(fontFamily: _bf),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              final dId = deviceIdCtrl.text.trim();
                              final dName = deviceNameCtrl.text.trim();
                              if (dId.isEmpty || dName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please complete both fields.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setSheetState(() => saving = true);
                              try {
                                final currentUid =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (currentUid != null) {
                                  // 1. Update student profile with linkedDeviceId
                                  await _firestore
                                      .collection('users')
                                      .doc(currentUid)
                                      .update({'linkedDeviceId': dId});

                                  // 2. Register/update device in 'devices' collection
                                  final devDocRef = _firestore
                                      .collection('devices')
                                      .doc(dId);
                                  final devDoc = await devDocRef.get();

                                  final devData = <String, dynamic>{
                                    'deviceId': dId,
                                    'deviceName': dName,
                                    'phoneNumber': _phoneNumber,
                                    'status': 'active',
                                    'studentUid': currentUid,
                                    'studentName': _fullName,
                                    'parentPhoneNumber': _linkedParentPhone,
                                    'parentUid': _linkedParentUid,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  };
                                  if (_deviceCoordinates != null) {
                                    devData['location'] = GeoPoint(
                                      _deviceCoordinates!.latitude,
                                      _deviceCoordinates!.longitude,
                                    );
                                    devData['latitude'] =
                                        _deviceCoordinates!.latitude;
                                    devData['longitude'] =
                                        _deviceCoordinates!.longitude;
                                    devData['locationText'] = _deviceLocation;
                                  }

                                  if (!devDoc.exists) {
                                    devData['location'] = devData['location'] ?? 'Unknown';
                                    devData['createdAt'] = FieldValue.serverTimestamp();
                                    await devDocRef.set(devData);
                                  } else {
                                    await devDocRef.update(devData);
                                  }

                                  setState(() {
                                    _linkedDeviceId = dId;
                                  });
                                  await _loadLinkedDevice();
                                  if (mounted) {
                                    Navigator.pop(ctx);
                                    _showActionSnack(
                                      'Device linked successfully.',
                                    );
                                  }
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to link: $e')),
                                );
                              } finally {
                                setSheetState(() => saving = false);
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Text(
                              'SAVE & LINK',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
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
                        padding: const EdgeInsets.only(bottom: 12),
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
                                  color: AppColors.gold.withOpacity(0.65),
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

  Future<void> _showAlertHistorySheet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
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
                              'EMERGENCY LOGS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            Text(
                              'Alert History',
                              style: const TextStyle(
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
                      stream:
                          (_linkedDeviceId.isEmpty ||
                              _linkedDeviceId == 'Not linked')
                          ? _firestore
                                .collection('emergency_alerts')
                                .where('uid', isEqualTo: uid)
                                .limit(100)
                                .snapshots()
                          : _firestore
                                .collection('emergency_alerts')
                                .where(
                                  Filter.or(
                                    Filter('uid', isEqualTo: uid),
                                    Filter('studentUid', isEqualTo: uid),
                                    Filter(
                                      'deviceId',
                                      isEqualTo: _linkedDeviceId,
                                    ),
                                  ),
                                )
                                .limit(100)
                                .snapshots(),
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
                        final docs = snapshot.data!.docs.toList()
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
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 48,
                                  color: AppColors.gold.withOpacity(0.4),
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
                            final isActive = status == 'active';
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isActive
                                      ? const Color(
                                          0xFFCB392B,
                                        ).withOpacity(0.35)
                                      : AppColors.border,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
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
                                  if (isActive) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Material(
                                        color: const Color(0xFFB45309),
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () => _confirmAndReportFalseAlarm(docs[i].id),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.gold.withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.notifications_off_outlined,
                                                  color: AppColors.white,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'FALSE ALARM (MISS-CLICKED)',
                                                  style: TextStyle(
                                                    fontFamily: _bf,
                                                    color: AppColors.white,
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
                                  if (status.toLowerCase() == 'acknowledged') ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Material(
                                            color: const Color(0xFFB45309),
                                            borderRadius: BorderRadius.circular(8),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () => _confirmAndReportFalseAlarm(docs[i].id),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: AppColors.gold.withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Text(
                                                  'FALSE ALARM',
                                                  style: TextStyle(
                                                    fontFamily: _bf,
                                                    color: AppColors.white,
                                                    letterSpacing: 2,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Material(
                                            color: const Color(0xFFCB392B),
                                            borderRadius: BorderRadius.circular(8),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () => _resolveAlertDone(docs[i].id),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: AppColors.gold.withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Text(
                                                  'RESOLVE (DONE)',
                                                  style: TextStyle(
                                                    fontFamily: _bf,
                                                    color: AppColors.white,
                                                    letterSpacing: 2,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (status.toLowerCase() == 'false_alarm') ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Material(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () {
                                            _showActionSnack("This alert was marked as a false alarm (miss-clicked device).");
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
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
      ..text = _fullName
      ..selection = TextSelection.collapsed(offset: _fullName.length);
    _profilePhoneCtrl
      ..text = _phoneNumber
      ..selection = TextSelection.collapsed(offset: _phoneNumber.length);

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
                                    TextSpan(text: 'Personal\n'),
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
                                    color: AppColors.border.withOpacity(0.5),
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
                                        color: AppColors.gold.withOpacity(0.8),
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _email.isEmpty ? 'Not set' : _email,
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
                                        color: AppColors.textSub.withOpacity(
                                          0.6,
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
                                          color: AppColors.gold.withOpacity(
                                            0.65,
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

  Future<void> _changeRoleToParent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          title: const Text('Change Role to Parent'),
          content: const Text(
            'Are you sure you want to change your account role to Parent? This will unlink you from all current parent links. You will be logged out to apply changes.',
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
          'role': 'parent',
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
            top: -70,
            left: -30,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(0.07),
              ),
            ),
          ),
          Positioned(
            top: 140,
            right: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green.withOpacity(0.05),
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
        return _buildDeviceTab();
      case 2:
        return _buildAlertsTab();
      case 3:
        return _buildProfileTab();
      case 0:
      default:
        return _buildMapTab();
    }
  }


  Widget _buildMapTab() {
    final Stream<QuerySnapshot<Map<String, dynamic>>>? mapAlertsStream =
        _activeStudentUid.isEmpty
        ? null
        : (_linkedDeviceId.isEmpty || _linkedDeviceId == 'Not linked')
        ? _firestore
              .collection('emergency_alerts')
              .where('uid', isEqualTo: _activeStudentUid)
              .limit(60)
              .snapshots()
        : _firestore
              .collection('emergency_alerts')
              .where(
                Filter.or(
                  Filter('uid', isEqualTo: _activeStudentUid),
                  Filter('studentUid', isEqualTo: _activeStudentUid),
                  Filter('deviceId', isEqualTo: _linkedDeviceId),
                ),
              )
              .limit(60)
              .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: mapAlertsStream,
      builder: (context, snapshot) {
        final docs =
            snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final sosState = _resolveSosMapState(docs);
        final isEmergency = sosState.isActive || sosState.isAcknowledged;
        final hasLinkedDevice =
            _linkedDeviceId.isNotEmpty && _linkedDeviceId != 'Not linked';

        // When emergency is active, focus on the SOS coordinates.
        // When not in emergency (e.g. false alarm or resolved), only show location if there is an active linked device.
        final mapPoint = isEmergency
            ? (sosState.coordinate ?? _nextMapFocusPoint ?? _deviceCoordinates)
            : (_deviceCoordinates ??
                (hasLinkedDevice && _deviceStatus != 'offline'
                    ? _deviceCoordinates
                    : null));

        final hasPoint = mapPoint != null;
        if (sosState.coordinate != null && _nextMapFocusPoint != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _nextMapFocusPoint = null);
          });
        }
        final trackingLabel = sosState.isActive
            ? 'SOS active'
            : isEmergency
            ? 'Finding child'
            : hasPoint
            ? 'Active'
            : 'Safe / Standby';
        final fallbackAreaLabel =
            _deviceLocation.trim().isEmpty ||
                _deviceLocation.trim().toLowerCase() == 'unknown'
            ? _formatCoordinateLabel(mapPoint)
            : _deviceLocation;
        final mapAreaLabel = isEmergency
            ? (sosState.areaLabel.isEmpty ? fallbackAreaLabel : sosState.areaLabel)
            : (hasPoint ? fallbackAreaLabel : 'Safe (Standby mode)');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(),
            if (sosState.isActive || sosState.isAcknowledged) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFF59E0B),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFB45309),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sosState.isActive
                                    ? 'EMERGENCY SOS IS ACTIVE'
                                    : 'EMERGENCY SOS (ACKNOWLEDGED)',
                                style: const TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Miss-clicked the device? Cancel it as a false alarm.',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 11,
                                  color: const Color(0xFF78350F).withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: const Color(0xFFB45309),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (sosState.alertId.isNotEmpty) {
                              _confirmAndReportFalseAlarm(sosState.alertId);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'FALSE ALARM (CANCEL ALERT)',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 11,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildSectionLabel('LIVE MAP'),
            const SizedBox(height: 10),
            _buildRouteCard(
              mapPoint: mapPoint,
              sosIsActive: sosState.isActive,
              areaLabel: mapAreaLabel,
              alertId: sosState.alertId,
            ),
            const SizedBox(height: 14),
            _buildDashboardPanel(
              title: 'Map Overview',
              subtitle: 'LOCATION TRACKING',
              children: [
                _buildDeviceRow(
                  'Coordinates',
                  hasPoint
                      ? _formatCoordinateLabel(mapPoint)
                      : 'No active marker',
                ),
                const SizedBox(height: 8),
                _buildDeviceRow('Tracking', trackingLabel),
                const SizedBox(height: 8),
                _buildDeviceRow('Map Focus', mapAreaLabel),
                const SizedBox(height: 8),
                _buildDeviceRow('Device', _deviceName),
                if (sosState.isActive || sosState.isAcknowledged) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPanelAction(
                        label: 'FALSE ALARM',
                        onTap: () async {
                          if (sosState.alertId.isNotEmpty) {
                            await _confirmAndReportFalseAlarm(sosState.alertId);
                          }
                        },
                      ),
                      _buildPanelAction(
                        label: 'ALERT HISTORY',
                        onTap: _showAlertHistorySheet,
                        isPrimary: false,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('DEVICE'),
        const SizedBox(height: 10),
        _buildDeviceCard(),
        const SizedBox(height: 14),
        _buildDashboardPanel(
          title: 'Connection Status',
          subtitle: 'EMERGENCY DEVICE',
          children: [
            _buildDeviceRow('Device Name', _deviceName),
            const SizedBox(height: 8),
            _buildDeviceRow('Device ID', _deviceId),
            const SizedBox(height: 8),
            _buildDeviceRow('Status', _deviceStatus.toUpperCase()),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'GPS Sharing',
              _locationSharingEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPanelAction(
                  label: 'VIEW DETAILS',
                  onTap: _showDeviceDialog,
                ),
                _buildPanelAction(
                  label: _deviceId == 'Not linked'
                      ? 'LINK DEVICE'
                      : 'CHANGE DEVICE',
                  onTap: _showLinkDeviceDialog,
                  isPrimary: _deviceId == 'Not linked',
                ),
                _buildPanelAction(
                  label: 'REFRESH',
                  onTap: _loadLinkedDevice,
                  isPrimary: false,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('ALERT CENTER'),
        const SizedBox(height: 10),
        if (uid != null) _buildInlineAlertHistory(uid),
      ],
    );
  }

  Widget _buildInlineAlertHistory(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: (_linkedDeviceId.isEmpty || _linkedDeviceId == 'Not linked')
          ? _firestore
                .collection('emergency_alerts')
                .where('uid', isEqualTo: uid)
                .limit(100)
                .snapshots()
          : _firestore
                .collection('emergency_alerts')
                .where(
                  Filter.or(
                    Filter('uid', isEqualTo: uid),
                    Filter('studentUid', isEqualTo: uid),
                    Filter('deviceId', isEqualTo: _linkedDeviceId),
                  ),
                )
                .limit(100)
                .snapshots(),
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
        final docs = snapshot.data!.docs.toList()
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
                    color: AppColors.gold.withOpacity(0.4),
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
            final isActive = status == 'active';
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFCB392B).withOpacity(0.35)
                      : AppColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
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
                  if (isActive) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: const Color(0xFFB45309),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _confirmAndReportFalseAlarm(docs[i].id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.notifications_off_outlined,
                                  color: AppColors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'FALSE ALARM (MISS-CLICKED)',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: AppColors.white,
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
                  if (status.toLowerCase() == 'acknowledged') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: const Color(0xFFB45309),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _confirmAndReportFalseAlarm(docs[i].id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.gold.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'FALSE ALARM',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: AppColors.white,
                                    letterSpacing: 2,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Material(
                            color: const Color(0xFFCB392B),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _resolveAlertDone(docs[i].id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.gold.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'RESOLVE (DONE)',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: AppColors.white,
                                    letterSpacing: 2,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (status.toLowerCase() == 'false_alarm') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            _showActionSnack("This alert was marked as a false alarm (miss-clicked device).");
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
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

  Widget _buildProfileTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('PROFILE'),
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
            border: Border.all(color: AppColors.gold.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withOpacity(0.2),
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
                _fullName,
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
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: Text(
                  'STUDENT',
                  style: TextStyle(
                    fontFamily: _bf,
                    color: AppColors.goldLt,
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildDashboardPanel(
          title: _fullName,
          subtitle: 'STUDENT ACCOUNT',
          children: [
            _buildDeviceRow(
              'Student UID',
              _studentUid.isEmpty ? 'Unavailable' : _studentUid,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow('Email', _email.isEmpty ? '-' : _email),
            const SizedBox(height: 8),
            _buildDeviceRow('Phone', _phoneNumber.isEmpty ? '-' : _phoneNumber),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Linked Device',
              _deviceId == 'Not linked' ? 'Not linked' : _deviceName,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow('Current Route', _activeRoute),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Name',
              _linkedParentName.isEmpty ? 'Not linked' : _linkedParentName,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Phone',
              _linkedParentPhone.isEmpty ? 'Not linked' : _linkedParentPhone,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Pending Invitations',
              _pendingInvitations.length.toString(),
            ),
            const SizedBox(height: 14),
            _buildPanelAction(label: 'EDIT PROFILE', onTap: _showProfileDialog),
          ],
        ),
        const SizedBox(height: 18),
        _buildSectionLabel('PARENT INVITATIONS'),
        const SizedBox(height: 10),
        _buildParentInvitationsSection(),
        const SizedBox(height: 20),
        _buildSectionLabel('DANGER ZONE'),
        const SizedBox(height: 10),
        _buildSessionSecuritySection(),
      ],
    );
  }

  Widget _buildParentInvitationsSection() {
    return _buildDashboardPanel(
      title: 'Parent Invitations',
      subtitle: 'INCOMING GUARDIAN CONNECTIONS',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PENDING REQUESTS',
              style: TextStyle(
                fontFamily: _bf,
                fontSize: 9,
                letterSpacing: 3,
                color: AppColors.gold,
                fontWeight: FontWeight.w400,
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '${_pendingInvitations.length} Pending',
                    style: const TextStyle(
                      fontFamily: _bf,
                      fontSize: 9,
                      letterSpacing: 1,
                      color: AppColors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _isLoadingInvitations ? null : _loadPendingInvitations,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _isLoadingInvitations
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: AppColors.gold,
                              strokeWidth: 1.5,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: AppColors.green,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingInvitations)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(
                color: AppColors.gold,
                strokeWidth: 2,
              ),
            ),
          )
        else if (_pendingInvitations.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 20,
                  color: AppColors.gold.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'No pending invitations right now. When a parent invites you, it will appear here.',
                    style: TextStyle(
                      fontFamily: _bf,
                      fontSize: 11,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: _pendingInvitations.map((invite) {
              final isBusy =
                  _isHandlingInvitation && _invitationActionId == invite.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              invite.parentName.isEmpty
                                  ? 'Parent'
                                  : invite.parentName,
                              style: const TextStyle(
                                fontFamily: _bf,
                                color: AppColors.green,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'INVITATION',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 8,
                                letterSpacing: 1,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        invite.parentPhone.isEmpty
                            ? 'No phone provided'
                            : invite.parentPhone,
                        style: const TextStyle(
                          fontFamily: _bf,
                          color: AppColors.textSub,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Received ${_formatTimestamp(invite.createdAt)}',
                        style: const TextStyle(
                          fontFamily: _bf,
                          color: AppColors.textSub,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isBusy
                                  ? null
                                  : () async {
                                      setState(() {
                                        _isHandlingInvitation = true;
                                        _invitationActionId = invite.id;
                                      });
                                      try {
                                        await _rejectInvitation(invite);
                                      } finally {
                                        if (mounted) {
                                          setState(() {
                                            _isHandlingInvitation = false;
                                            _invitationActionId = '';
                                          });
                                        }
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSub,
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              child: isBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.gold,
                                      ),
                                    )
                                  : const Text(
                                      'REJECT',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isBusy
                                  ? null
                                  : () async {
                                      setState(() {
                                        _isHandlingInvitation = true;
                                        _invitationActionId = invite.id;
                                      });
                                      try {
                                        await _acceptInvitation(invite);
                                      } finally {
                                        if (mounted) {
                                          setState(() {
                                            _isHandlingInvitation = false;
                                            _invitationActionId = '';
                                          });
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.green,
                                foregroundColor: AppColors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              child: isBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.gold,
                                      ),
                                    )
                                  : const Text(
                                      'ACCEPT',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
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
                onTap: _changeRoleToParent,
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
                    'CHANGE ROLE TO PARENT',
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
            color: Colors.black.withOpacity(0.05),
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

  Widget _buildPanelAction({
    required String label,
    required Future<void> Function() onTap,
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
                  ? AppColors.gold.withOpacity(0.45)
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
        border: Border.all(color: AppColors.gold.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withOpacity(0.25),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.green,
                  border: Border.all(color: AppColors.gold, width: 1.4),
                ),
                child: Center(
                  child: Text(
                    'SW',
                    style: TextStyle(
                      fontFamily: _hf,
                      color: AppColors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
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
                    'STUDENT',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold.withOpacity(0.7),
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
              color: AppColors.white.withOpacity(0.7),
              fontSize: 13,
              letterSpacing: 1,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _fullName,
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
                label: _locationSharingEnabled ? 'GPS Active' : 'GPS Paused',
                dotColor: _locationSharingEnabled
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
                label: _safeModeEnabled ? 'Safe Mode On' : 'Safe Mode Off',
                dotColor: _safeModeEnabled
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard({
    LatLng? mapPoint,
    bool sosIsActive = false,
    String areaLabel = '',
    String alertId = '',
  }) {
    final effectivePoint = mapPoint ?? _deviceCoordinates;
    final center = effectivePoint ?? _defaultMapCenter;
    final hasPoint = effectivePoint != null;
    final focusLabel = areaLabel.isEmpty ? _deviceLocation : areaLabel;
    final requestedFocusPoint = _nextMapFocusPoint ?? effectivePoint;
    if (requestedFocusPoint != null && (sosIsActive || hasPoint)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusRouteMapOnPoint(requestedFocusPoint, zoom: hasPoint ? 16 : 12);
      });
    }
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                  ? _buildWebMapFallback(contextLabel: 'Student Route Card')
                  : GoogleMap(
                      key: const ValueKey('route-map-main'),
                      initialCameraPosition: CameraPosition(
                        target: center,
                        zoom: hasPoint ? 16 : 12,
                      ),
                      liteModeEnabled: _mobileMapLiteMode,
                      mapType: MapType.normal,
                      gestureRecognizers: _mapGestureRecognizers,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      markers: hasPoint
                          ? {
                              Marker(
                                markerId: const MarkerId('route-device'),
                                position: center,
                                icon: sosIsActive
                                    ? (_sosMarkerIcon ??
                                          BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueRed,
                                          ))
                                    : BitmapDescriptor.defaultMarkerWithHue(
                                        BitmapDescriptor.hueAzure,
                                      ),
                                infoWindow: InfoWindow(
                                  title: sosIsActive
                                      ? 'SOS Location'
                                      : _deviceName,
                                  snippet: focusLabel,
                                ),
                              ),
                            }
                          : <Marker>{},
                      circles: hasPoint
                          ? {
                              Circle(
                                circleId: const CircleId('route-radius'),
                                center: center,
                                radius: sosIsActive ? 90 : 45,
                                fillColor: sosIsActive
                                    ? const Color(0x55CB392B)
                                    : const Color(0x331AA972),
                                strokeColor: sosIsActive
                                    ? const Color(0xFFCB392B)
                                    : const Color(0xFF1AA972),
                                strokeWidth: 2,
                              ),
                            }
                          : <Circle>{},
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      onMapCreated: (controller) {
                        _routeMapController = controller;
                        final focusPoint = _nextMapFocusPoint ?? effectivePoint;
                        if (focusPoint != null && (sosIsActive || hasPoint)) {
                          _focusRouteMapOnPoint(
                            focusPoint,
                            zoom: hasPoint ? 16 : 12,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sosIsActive
                    ? const Color(0xFF7E1F14)
                    : const Color(0xFF0E5B3C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.gold.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                sosIsActive ? 'SOS MAP' : 'LIVE MAP',
                style: TextStyle(
                  fontFamily: _bf,
                  color: AppColors.gold,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sosIsActive
                    ? const Color(0xFF7E1F14)
                    : hasPoint
                    ? const Color(0xFF0F5A3E)
                    : const Color(0xFF6C757D),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 7,
                    color: sosIsActive
                        ? const Color(0xFFFF9F9F)
                        : hasPoint
                        ? const Color(0xFF5DF0A0)
                        : const Color(0xFFF6D38E),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    sosIsActive
                        ? 'SOS ACTIVE'
                        : hasPoint
                        ? 'TRACKING'
                        : 'STANDBY',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.white,
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 48,
            right: 14,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isDetectingLocation
                    ? null
                    : () => _detectDeviceExactLocation(
                        showFeedback: true,
                        autoCenter: true,
                      ),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.gold.withOpacity(0.8),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDetectingLocation)
                        const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.goldLt,
                            ),
                          ),
                        )
                      else
                        const Icon(
                          Icons.my_location_rounded,
                          size: 12,
                          color: AppColors.goldLt,
                        ),
                      const SizedBox(width: 5),
                      Text(
                        _isDetectingLocation ? 'LOCATING...' : 'LOCATE ME',
                        style: const TextStyle(
                          fontFamily: _bf,
                          color: AppColors.goldLt,
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (sosIsActive && alertId.isNotEmpty)
            Positioned(
              top: 84,
              right: 14,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _confirmAndReportFalseAlarm(alertId),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCB392B),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'CLEAR SOS',
                          style: TextStyle(
                            fontFamily: _bf,
                            color: Colors.white,
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
                    Colors.black.withOpacity(0.02),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE ROUTE',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold,
                      fontSize: 9,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _activeRoute,
                    style: const TextStyle(
                      fontFamily: _bf,
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasPoint
                        ? (sosIsActive
                              ? 'SOS pinned at ${_formatCoordinateLabel(effectivePoint)}'
                              : '$_deviceName at ${_formatCoordinateLabel(effectivePoint)}')
                        : 'Waiting for device coordinates. Tap "LOCATE ME" to detect.',
                    style: const TextStyle(
                      fontFamily: _bf,
                      color: Color(0xFFE8ECE9),
                      fontSize: 10,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sosIsActive ? focusLabel : 'Google Maps tracking view',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 9,
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
                colors: [AppColors.gold.withOpacity(0.3), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard() {
    final isLinked = _deviceId != 'Not linked';
    final isOnline = _deviceStatus == 'active' || _deviceStatus == 'online';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device',
                      style: TextStyle(
                        fontFamily: _hf,
                        color: AppColors.green,
                        fontSize: 36,
                        height: 1,
                        fontWeight: FontWeight.w300,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      'Connection',
                      style: TextStyle(
                        fontFamily: _hf,
                        color: AppColors.goldDark,
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isLinked
                          ? 'Your emergency device is linked to this account.'
                          : 'No emergency device linked yet.',
                      style: TextStyle(
                        fontFamily: _bf,
                        color: AppColors.textSub,
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: isOnline
                          ? const Color(0xFF60CC8A)
                          : const Color(0xFFFF7F7F),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontFamily: _bf,
                        color: AppColors.green,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.border,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildDeviceRow('Device Name', _deviceName),
          const SizedBox(height: 8),
          _buildDeviceRow('Device ID', _deviceId),
          const SizedBox(height: 8),
          _buildDeviceRow('Location', _deviceLocation),
          const SizedBox(height: 8),
          _buildDeviceRow(
            'GPS Sharing',
            _locationSharingEnabled ? 'Enabled' : 'Disabled',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _isDetectingLocation
                    ? null
                    : () => _detectDeviceExactLocation(
                        showFeedback: true,
                        autoCenter: true,
                      ),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.green,
                      width: 1.2,
                    ),
                    color: AppColors.offWhite,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isDetectingLocation)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.green,
                          ),
                        )
                      else
                        const Icon(
                          Icons.gps_fixed_rounded,
                          size: 16,
                          color: AppColors.green,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isDetectingLocation
                            ? 'DETECTING DEVICE GPS...'
                            : 'DETECT EXACT LOCATION',
                        style: const TextStyle(
                          fontFamily: _bf,
                          color: AppColors.green,
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _showDeviceDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                  ),
                  child: Text(
                    'VIEW DEVICE',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.white,
                      fontSize: 11,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w400,
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

  Widget _buildDeviceRow(String label, String value) {
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

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.06),
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
                                    ? AppColors.green.withOpacity(0.1)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: selected
                                    ? Border.all(
                                        color: AppColors.gold.withOpacity(0.3),
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

class _ParentInvitation {
  final String id;
  final String parentUid;
  final String parentName;
  final String parentPhone;
  final String studentUid;
  final Timestamp? createdAt;

  const _ParentInvitation({
    required this.id,
    required this.parentUid,
    required this.parentName,
    required this.parentPhone,
    required this.studentUid,
    required this.createdAt,
  });
}

class _SosMapState {
  final LatLng? coordinate;
  final bool isActive;
  final bool isAcknowledged;
  final bool isFalseAlarm;
  final String alertId;
  final String timestampLabel;
  final String areaLabel;

  const _SosMapState({
    this.coordinate,
    this.isActive = false,
    this.isAcknowledged = false,
    this.isFalseAlarm = false,
    this.alertId = '',
    this.timestampLabel = '',
    this.areaLabel = '',
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
        border: Border.all(color: AppColors.gold.withOpacity(0.25), width: 0.8),
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
      bg = const Color(0xFFCB392B).withOpacity(0.1);
      border = const Color(0xFFCB392B).withOpacity(0.3);
      text = const Color(0xFFCB392B);
    } else if (isFalse) {
      bg = const Color(0xFFFEF3C7);
      border = const Color(0xFFF59E0B).withOpacity(0.5);
      text = const Color(0xFFB45309);
    } else if (isResolved) {
      bg = AppColors.green.withOpacity(0.1);
      border = AppColors.green.withOpacity(0.3);
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
                    color: AppColors.border.withOpacity(0.6),
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
                      color: AppColors.textSub.withOpacity(0.45),
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
