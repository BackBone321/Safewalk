import 'package:flutter/material.dart';

import '../login_dashboard/login_page.dart';
import '../models/guardian_contact.dart';
import '../services/guardian_service.dart';

/// Add, edit, and delete the guardian contacts notified on an emergency alert.
class GuardianContactsPanel extends StatefulWidget {
  const GuardianContactsPanel({super.key, required this.studentUid});

  final String studentUid;

  @override
  State<GuardianContactsPanel> createState() => _GuardianContactsPanelState();
}

class _GuardianContactsPanelState extends State<GuardianContactsPanel> {
  static const String _hf = 'CormorantGaramond';
  static const String _bf = 'JosefinSans';

  final GuardianService _guardians = GuardianService();
  String _busyId = '';

  Future<void> _openForm({GuardianContact? existing}) async {
    final studentUid = widget.studentUid.trim();
    if (studentUid.isEmpty) return;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phoneNumber ?? '');
    var relationship = GuardianService.relationships.contains(existing?.relationship)
        ? existing!.relationship
        : 'Guardian';
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.offWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                existing == null ? 'Add guardian' : 'Edit guardian',
                style: const TextStyle(
                  fontFamily: _hf,
                  color: AppColors.green,
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        labelStyle: TextStyle(fontFamily: _bf),
                      ),
                      style: const TextStyle(fontFamily: _bf),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        labelStyle: TextStyle(fontFamily: _bf),
                      ),
                      style: const TextStyle(fontFamily: _bf),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: relationship,
                      decoration: const InputDecoration(
                        labelText: 'Relationship',
                        labelStyle: TextStyle(fontFamily: _bf),
                      ),
                      items: GuardianService.relationships
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value,
                                style: const TextStyle(fontFamily: _bf),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() => relationship = value);
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.textSub,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            if (existing == null) {
                              await _guardians.addGuardian(
                                studentUid: studentUid,
                                name: nameCtrl.text,
                                phoneNumber: phoneCtrl.text,
                                relationship: relationship,
                              );
                            } else {
                              await _guardians.updateGuardian(
                                studentUid: studentUid,
                                guardianId: existing.id,
                                name: nameCtrl.text,
                                phoneNumber: phoneCtrl.text,
                                relationship: relationship,
                              );
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            _showNotice(
                              existing == null
                                  ? 'Guardian added. They will be notified on the next alert.'
                                  : 'Guardian updated.',
                            );
                          } catch (e) {
                            setDialogState(() => saving = false);
                            _showNotice(_readableError(e), isError: true);
                          }
                        },
                  child: Text(
                    saving ? 'SAVING...' : 'SAVE',
                    style: const TextStyle(
                      fontFamily: _bf,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _confirmDelete(GuardianContact contact) async {
    final studentUid = widget.studentUid.trim();
    if (studentUid.isEmpty || _busyId.isNotEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.offWhite,
          title: const Text(
            'Remove guardian?',
            style: TextStyle(fontFamily: _hf, color: AppColors.green),
          ),
          content: Text(
            '${contact.name} (${contact.phoneNumber}) will no longer receive emergency alerts.',
            style: const TextStyle(fontFamily: _bf, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'KEEP',
                style: TextStyle(fontFamily: _bf, color: AppColors.textSub),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCB392B),
                foregroundColor: AppColors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'DELETE',
                style: TextStyle(fontFamily: _bf),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _busyId = contact.id);
    try {
      await _guardians.deleteGuardian(
        studentUid: studentUid,
        guardianId: contact.id,
      );
      _showNotice('Guardian removed.');
    } catch (e) {
      _showNotice(_readableError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  void _showNotice(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFCB392B) : AppColors.green,
      ),
    );
  }

  String _readableError(Object error) {
    final text = error.toString();
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final studentUid = widget.studentUid.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EMERGENCY CONTACTS',
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.goldDark,
              fontSize: 9,
              letterSpacing: 3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Guardians',
            style: TextStyle(
              fontFamily: _hf,
              color: AppColors.green,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add, edit, or remove people who should be contacted. A help or SOS alert is sent to every saved guardian.',
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.textSub,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          if (studentUid.isEmpty)
            const Text(
              'Select a student before managing guardians.',
              style: TextStyle(fontFamily: _bf, color: AppColors.textSub),
            )
          else
            StreamBuilder<List<GuardianContact>>(
              stream: _guardians.watchGuardians(studentUid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Could not load guardians: ${snapshot.error}',
                    style: const TextStyle(fontFamily: _bf, fontSize: 12),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.gold,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }
                final contacts = snapshot.data!;
                final atLimit = contacts.length >= GuardianContact.maxPerStudent;
                return Column(
                  children: [
                    if (contacts.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.offWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'No guardians yet. Add a name and phone number so alerts have someone to reach.',
                          style: TextStyle(
                            fontFamily: _bf,
                            fontSize: 12,
                            color: AppColors.textSub,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ...contacts.map((contact) {
                        final busy = _busyId == contact.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            decoration: BoxDecoration(
                              color: AppColors.offWhite,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact.name,
                                        style: const TextStyle(
                                          fontFamily: _bf,
                                          color: AppColors.green,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        contact.phoneNumber,
                                        style: const TextStyle(
                                          fontFamily: _bf,
                                          color: AppColors.textMain,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        contact.relationship,
                                        style: const TextStyle(
                                          fontFamily: _bf,
                                          color: AppColors.textSub,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit guardian',
                                  onPressed: busy ? null : () => _openForm(existing: contact),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: AppColors.green,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete guardian',
                                  onPressed: busy ? null : () => _confirmDelete(contact),
                                  icon: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.gold,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.delete_outline,
                                          color: Color(0xFFCB392B),
                                          size: 20,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: atLimit ? null : () => _openForm(),
                        icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                        label: Text(
                          atLimit
                              ? 'GUARDIAN LIMIT REACHED'
                              : 'ADD GUARDIAN',
                          style: const TextStyle(
                            fontFamily: _bf,
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
