import 'package:cloud_firestore/cloud_firestore.dart';

class BackupResult {
  final String backupId;
  final int totalDocuments;

  const BackupResult({required this.backupId, required this.totalDocuments});
}

class SystemAdminService {
  SystemAdminService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const List<String> defaultCollections = [
    'users',
    'devices',
    'emergency_alerts',
    'login_logs',
    'sms_logs',
    'email_logs',
  ];

  Future<Map<String, dynamic>> generateSystemReport({
    List<String> collections = defaultCollections,
  }) async {
    final counts = <String, int>{};
    for (final collection in collections) {
      final snapshot = await _firestore.collection(collection).get();
      counts[collection] = snapshot.docs.length;
    }

    final latestLogins = await _firestore
        .collection('login_logs')
        .orderBy('timestamp', descending: true)
        .limit(40)
        .get();

    final failedLogins = latestLogins.docs
        .where((doc) => (doc.data()['status'] ?? '').toString() == 'failed')
        .take(10)
        .map((doc) => _serializeMap(doc.data()))
        .toList();

    final latestAlerts = await _firestore
        .collection('emergency_alerts')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();

    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'counts': counts,
      'failedLoginSamples': failedLogins,
      'recentAlerts': latestAlerts.docs
          .map((doc) => _serializeMap(doc.data()))
          .toList(),
    };
  }

  Future<String> saveGeneratedReport(Map<String, dynamic> report) async {
    final ref = await _firestore.collection('system_reports').add({
      ...report,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<BackupResult> createBackupSnapshot({
    List<String> collections = defaultCollections,
  }) async {
    final backupRef = _firestore.collection('system_backups').doc();

    await backupRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtIso': DateTime.now().toUtc().toIso8601String(),
      'collections': collections,
      'status': 'running',
      'totalDocuments': 0,
    });

    var totalDocuments = 0;

    for (final collection in collections) {
      final snapshot = await _firestore.collection(collection).get();

      for (final doc in snapshot.docs) {
        totalDocuments += 1;
        await backupRef.collection('documents').add({
          'collection': collection,
          'sourceId': doc.id,
          'data': _serializeMap(doc.data()),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await backupRef.set({
      'status': 'completed',
      'totalDocuments': totalDocuments,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return BackupResult(backupId: backupRef.id, totalDocuments: totalDocuments);
  }

  static String formatReportAsText(Map<String, dynamic> report) {
    final buffer = StringBuffer();
    final generatedAt = (report['generatedAt'] ?? '').toString();
    final counts = Map<String, dynamic>.from(
      (report['counts'] as Map?) ?? const {},
    );
    final failedLoginSamples = List<Map<String, dynamic>>.from(
      (report['failedLoginSamples'] as List?)?.map(
            (item) => Map<String, dynamic>.from(item as Map),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final recentAlerts = List<Map<String, dynamic>>.from(
      (report['recentAlerts'] as List?)?.map(
            (item) => Map<String, dynamic>.from(item as Map),
          ) ??
          const <Map<String, dynamic>>[],
    );

    buffer.writeln('SAFEWALK SYSTEM REPORT');
    buffer.writeln('Generated At (UTC): $generatedAt');
    buffer.writeln('');
    buffer.writeln('COUNTS');
    counts.forEach((key, value) {
      buffer.writeln('- $key: $value');
    });

    buffer.writeln('');
    buffer.writeln('RECENT FAILED LOGINS');
    if (failedLoginSamples.isEmpty) {
      buffer.writeln('- None');
    } else {
      for (final sample in failedLoginSamples) {
        buffer.writeln(
          '- ${sample['loginInput'] ?? 'unknown'} | '
          'reason: ${sample['reason'] ?? 'n/a'}',
        );
      }
    }

    buffer.writeln('');
    buffer.writeln('RECENT ALERTS');
    if (recentAlerts.isEmpty) {
      buffer.writeln('- None');
    } else {
      for (final alert in recentAlerts) {
        buffer.writeln(
          '- ${alert['userName'] ?? alert['email'] ?? 'unknown'} | '
          'status: ${alert['status'] ?? 'n/a'}',
        );
      }
    }

    return buffer.toString();
  }

  Map<String, dynamic> _serializeMap(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    input.forEach((key, value) {
      output[key] = _serializeValue(value);
    });
    return output;
  }

  dynamic _serializeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is DocumentReference) {
      return value.path;
    }
    if (value is List) {
      return value.map(_serializeValue).toList();
    }
    if (value is Map) {
      final mapped = <String, dynamic>{};
      value.forEach((key, item) {
        mapped[key.toString()] = _serializeValue(item);
      });
      return mapped;
    }
    return value;
  }
}
