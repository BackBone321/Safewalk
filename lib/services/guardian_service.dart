import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/guardian_contact.dart';
import 'notification_service.dart';

/// Add, edit, and delete guardian contacts, and fan an alert out to all of them.
class GuardianService {
  GuardianService({
    FirebaseFirestore? firestore,
    NotificationService? notifications,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _notifications = notifications ?? NotificationService();

  final FirebaseFirestore _firestore;
  final NotificationService _notifications;

  static const List<String> relationships = <String>[
    'Parent',
    'Mother',
    'Father',
    'Guardian',
    'Relative',
    'Teacher',
    'Neighbor',
    'Other',
  ];

  CollectionReference<Map<String, dynamic>> _guardians(String studentUid) {
    return _firestore
        .collection('users')
        .doc(studentUid)
        .collection('guardians');
  }

  Stream<List<GuardianContact>> watchGuardians(String studentUid) {
    final uid = studentUid.trim();
    if (uid.isEmpty) return Stream<List<GuardianContact>>.value(const []);
    return _guardians(uid).snapshots().map((snapshot) {
      final contacts = snapshot.docs.map(GuardianContact.fromDoc).toList();
      contacts.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return contacts;
    });
  }

  Future<void> addGuardian({
    required String studentUid,
    required String name,
    required String phoneNumber,
    required String relationship,
  }) {
    return _saveGuardian(
      studentUid: studentUid,
      name: name,
      phoneNumber: phoneNumber,
      relationship: relationship,
    );
  }

  Future<void> updateGuardian({
    required String studentUid,
    required String guardianId,
    required String name,
    required String phoneNumber,
    required String relationship,
  }) {
    return _saveGuardian(
      studentUid: studentUid,
      guardianId: guardianId,
      name: name,
      phoneNumber: phoneNumber,
      relationship: relationship,
    );
  }

  Future<void> deleteGuardian({
    required String studentUid,
    required String guardianId,
  }) async {
    final uid = studentUid.trim();
    final id = guardianId.trim();
    if (uid.isEmpty || id.isEmpty) {
      throw StateError('Missing guardian.');
    }
    await _guardians(uid).doc(id).delete();
    await syncRecipients(uid);
  }

  Future<AlertAudience> resolveAudience(String studentUid) async {
    final uid = studentUid.trim();
    if (uid.isEmpty) return AlertAudience.empty;

    final guardianSnap = await _guardians(uid).get();
    final guardians = guardianSnap.docs.map(GuardianContact.fromDoc).toList();

    final linkSnap = await _firestore
        .collection('parent_student_links')
        .where('studentUid', isEqualTo: uid)
        .limit(50)
        .get();

    final contacts = <Map<String, dynamic>>[];
    final phones = <String>[];
    final seenPhones = <String>{};
    final recipientUids = <String>[];
    final seenUids = <String>{};
    String primaryParentUid = '';
    String primaryParentPhone = '';
    String primaryParentName = '';

    void addPhone(String raw) {
      final normalized = GuardianPhone.normalize(raw);
      if (!GuardianPhone.isValid(raw) || seenPhones.contains(normalized)) {
        return;
      }
      if (phones.length >= GuardianContact.maxPerStudent) return;
      seenPhones.add(normalized);
      phones.add(raw.trim());
    }

    void addUid(String parentUid) {
      final cleaned = parentUid.trim();
      if (cleaned.isEmpty || seenUids.contains(cleaned)) return;
      seenUids.add(cleaned);
      recipientUids.add(cleaned);
    }

    final acceptedLinks = linkSnap.docs.where((doc) {
      final status = (doc.data()['status'] ?? 'accepted')
          .toString()
          .toLowerCase();
      return status == 'accepted';
    }).toList();

    acceptedLinks.sort((a, b) {
      final aTs = (a.data()['updatedAt'] ?? a.data()['linkedAt']) as Timestamp?;
      final bTs = (b.data()['updatedAt'] ?? b.data()['linkedAt']) as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
        aTs?.millisecondsSinceEpoch ?? 0,
      );
    });

    for (final doc in acceptedLinks) {
      final data = doc.data();
      final parentUid = (data['parentUid'] ?? '').toString();
      final parentPhone = (data['parentPhone'] ?? '').toString();
      final parentName = (data['parentName'] ?? 'Parent').toString();
      addUid(parentUid);
      if (parentPhone.trim().isNotEmpty) {
        contacts.add(<String, dynamic>{
          'id': 'parent:$parentUid',
          'name': parentName.trim().isEmpty ? 'Parent' : parentName.trim(),
          'phoneNumber': parentPhone.trim(),
          'phoneNormalized': GuardianPhone.normalize(parentPhone),
          'relationship': 'Parent',
          'parentUid': parentUid,
          'source': 'parent_link',
        });
        addPhone(parentPhone);
      }
      if (primaryParentUid.isEmpty && parentUid.trim().isNotEmpty) {
        primaryParentUid = parentUid.trim();
        primaryParentPhone = parentPhone.trim();
        primaryParentName = parentName.trim();
      }
    }

    for (final guardian in guardians) {
      if (seenPhones.contains(guardian.phoneNormalized)) continue;
      contacts.add(guardian.toAlertMap());
      addPhone(guardian.phoneNumber);
    }

    return AlertAudience(
      contacts: contacts,
      phones: phones,
      phonesCsv: phones.join(','),
      recipientUids: recipientUids,
      primaryParentUid: primaryParentUid,
      primaryParentPhone: primaryParentPhone,
      primaryParentName: primaryParentName,
    );
  }

  /// Copy the phone list onto the student profile and linked devices.
  ///
  /// The tracker reads `devices/{id}.guardianPhonesCsv` and texts every number.
  Future<void> syncRecipients(String studentUid) async {
    final uid = studentUid.trim();
    if (uid.isEmpty) return;
    try {
      final audience = await resolveAudience(uid);
      final guardianOnly = audience.contacts
          .where((contact) => contact['source'] == 'guardian')
          .map(
            (contact) => <String, dynamic>{
              'id': contact['id'] ?? '',
              'name': contact['name'] ?? '',
              'phoneNumber': contact['phoneNumber'] ?? '',
              'relationship': contact['relationship'] ?? 'Guardian',
            },
          )
          .toList();

      await _firestore.collection('users').doc(uid).set({
        'guardianContacts': guardianOnly,
        'guardianPhonesCsv': audience.phonesCsv,
        'guardianCount': guardianOnly.length,
        'guardiansUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final deviceSnap = await _firestore
          .collection('devices')
          .where('studentUid', isEqualTo: uid)
          .get();
      if (deviceSnap.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in deviceSnap.docs) {
        final patch = <String, dynamic>{
          'guardianPhonesCsv': audience.phonesCsv,
          'guardiansUpdatedAt': FieldValue.serverTimestamp(),
        };
        if (audience.primaryParentUid.isNotEmpty) {
          patch['parentUid'] = audience.primaryParentUid;
        }
        if (audience.primaryParentPhone.isNotEmpty) {
          patch['parentPhoneNumber'] = audience.primaryParentPhone;
        }
        batch.set(doc.reference, patch, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
      // A failed mirror must not block saving the guardian itself.
    }
  }

  Future<SmsBroadcastResult> notifyAudience({
    required AlertAudience audience,
    required String message,
    String triggeredBy = 'emergency_alert',
    String? alertId,
  }) {
    return _notifications.broadcastSms(
      phoneNumbers: audience.phones,
      message: message,
      triggeredBy: triggeredBy,
      alertId: alertId,
    );
  }

  Map<String, dynamic> alertFields(AlertAudience audience) {
    return <String, dynamic>{
      if (audience.primaryParentUid.isNotEmpty)
        'parentUid': audience.primaryParentUid,
      if (audience.primaryParentPhone.isNotEmpty)
        'parentPhoneNumber': audience.primaryParentPhone,
      'guardianContacts': audience.contacts,
      'guardianPhones': audience.phones,
      'guardianPhonesCsv': audience.phonesCsv,
      'recipientUids': audience.recipientUids,
      'notifiedGuardianCount': audience.phones.length,
      'clientHandlesSms': true,
      'broadcastStatus': 'pending',
    };
  }

  Future<void> _saveGuardian({
    required String studentUid,
    required String name,
    required String phoneNumber,
    required String relationship,
    String? guardianId,
  }) async {
    final uid = studentUid.trim();
    final cleanedName = name.trim();
    final cleanedPhone = phoneNumber.trim();
    final cleanedRelationship = relationships.contains(relationship)
        ? relationship
        : 'Guardian';
    if (uid.isEmpty) {
      throw StateError('Missing student account.');
    }
    if (cleanedName.isEmpty || cleanedName.length > 60) {
      throw StateError('Enter a guardian name (60 characters or fewer).');
    }
    if (!GuardianPhone.isValid(cleanedPhone)) {
      throw StateError('Enter a valid phone number.');
    }

    final normalized = GuardianPhone.normalize(cleanedPhone);
    final col = _guardians(uid);
    final existing = await col.get();
    final duplicate = existing.docs.where((doc) {
      if (guardianId != null && doc.id == guardianId) return false;
      final saved = (doc.data()['phoneNormalized'] ?? '').toString();
      final fallback = GuardianPhone.normalize(
        (doc.data()['phoneNumber'] ?? '').toString(),
      );
      return saved == normalized || fallback == normalized;
    });
    if (duplicate.isNotEmpty) {
      throw StateError('That phone number is already saved.');
    }
    if (guardianId == null &&
        existing.docs.length >= GuardianContact.maxPerStudent) {
      throw StateError(
        'You can save up to ${GuardianContact.maxPerStudent} guardians.',
      );
    }

    final payload = <String, dynamic>{
      'studentUid': uid,
      'name': cleanedName,
      'phoneNumber': cleanedPhone,
      'phoneNormalized': normalized,
      'relationship': cleanedRelationship,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (guardianId == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await col.add(payload);
    } else {
      await col.doc(guardianId).set(payload, SetOptions(merge: true));
    }
    await syncRecipients(uid);
  }
}
