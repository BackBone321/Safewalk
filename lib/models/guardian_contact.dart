import 'package:cloud_firestore/cloud_firestore.dart';

/// One emergency contact saved for a student.
///
/// Stored at `users/{studentUid}/guardians/{id}`.
class GuardianContact {
  static const int maxPerStudent = 12;

  final String id;
  final String name;
  final String phoneNumber;
  final String phoneNormalized;
  final String relationship;

  const GuardianContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.phoneNormalized,
    required this.relationship,
  });

  factory GuardianContact.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final phone = (data['phoneNumber'] ?? '').toString();
    return GuardianContact(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      phoneNumber: phone,
      phoneNormalized: (data['phoneNormalized'] ?? GuardianPhone.normalize(phone))
          .toString(),
      relationship: (data['relationship'] ?? 'Guardian').toString(),
    );
  }

  Map<String, dynamic> toAlertMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'phoneNormalized': phoneNormalized,
      'relationship': relationship,
      'source': 'guardian',
    };
  }
}

/// People who must be told when this student triggers help.
class AlertAudience {
  final List<Map<String, dynamic>> contacts;
  final List<String> phones;
  final String phonesCsv;
  final List<String> recipientUids;
  final String primaryParentUid;
  final String primaryParentPhone;
  final String primaryParentName;

  const AlertAudience({
    required this.contacts,
    required this.phones,
    required this.phonesCsv,
    required this.recipientUids,
    required this.primaryParentUid,
    required this.primaryParentPhone,
    required this.primaryParentName,
  });

  static const empty = AlertAudience(
    contacts: <Map<String, dynamic>>[],
    phones: <String>[],
    phonesCsv: '',
    recipientUids: <String>[],
    primaryParentUid: '',
    primaryParentPhone: '',
    primaryParentName: '',
  );

  bool get isEmpty => phones.isEmpty && recipientUids.isEmpty;

  int get contactCount => contacts.length;
}

/// Shared phone cleanup so the app, device CSV, and cloud function match.
class GuardianPhone {
  static String normalize(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    if (cleaned.startsWith('9') && cleaned.length == 10) {
      return '+63$cleaned';
    }
    return cleaned;
  }

  static bool isValid(String raw) {
    final normalized = normalize(raw);
    return RegExp(r'^\+?[0-9]{10,15}$').hasMatch(normalized);
  }
}
