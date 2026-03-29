import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../services/auth_services.dart';
import '../../firebase_options.dart';
import '../login_screen.dart';

String _teacherLabel(String id, Map<String, dynamic> data) {
  final name = data['name']?.toString();
  final email = data['email']?.toString();
  if (name != null && name.isNotEmpty) {
    return (email != null && email.isNotEmpty) ? '$name ($email)' : name;
  }
  return id;
}

/// Admin-only: assign subjects to teachers and build division timetables.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late TabController _tabController;

  final _subjectNameController = TextEditingController();
  String? _selectedTeacherId;

  final _divisionController = TextEditingController();
  final _timeController = TextEditingController();
  String? _scheduleSubjectId;
  String _scheduleDay = 'Monday';
  String _scheduleType = 'lecture';

  final _teacherUidController = TextEditingController();
  final _teacherNameController = TextEditingController();
  final _teacherEmailController = TextEditingController();
  final _teacherPasswordController = TextEditingController();

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectNameController.dispose();
    _divisionController.dispose();
    _timeController.dispose();
    _teacherUidController.dispose();
    _teacherNameController.dispose();
    _teacherEmailController.dispose();
    _teacherPasswordController.dispose();
    super.dispose();
  }

  Future<FirebaseApp> _adminSecondaryApp() async {
    const appName = 'admin-user-creator';
    for (final app in Firebase.apps) {
      if (app.name == appName) return app;
    }
    return Firebase.initializeApp(
      name: appName,
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<void> _createTeacherAccount() async {
    final name = _teacherNameController.text.trim();
    final email = _teacherEmailController.text.trim();
    final password = _teacherPasswordController.text.trim();
    if (name.isEmpty || email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter name, valid email and password (min 6 chars).'),
        ),
      );
      return;
    }
    try {
      final app = await _adminSecondaryApp();
      final auth = FirebaseAuth.instanceFor(app: app);
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;
      await _db.collection('users').doc(uid).set({
        'name': name,
        'email': email,
        'role': 'teacher',
      }, SetOptions(merge: true));
      if (!mounted) return;
      _teacherUidController.text = uid;
      _teacherPasswordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teacher Auth + profile created.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to create teacher account.')),
      );
    }
  }

  Future<void> _upsertTeacher() async {
    final uid = _teacherUidController.text.trim();
    final name = _teacherNameController.text.trim();
    final email = _teacherEmailController.text.trim();
    if (uid.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter teacher UID and name.')),
      );
      return;
    }

    // NOTE: This creates/updates the Firestore user profile only.
    // Creating Firebase Auth accounts requires a backend/Admin SDK.
    await _db.collection('users').doc(uid).set({
      'role': 'teacher',
      'name': name,
      if (email.isNotEmpty) 'email': email,
    }, SetOptions(merge: true));

    if (!mounted) return;
    _teacherUidController.clear();
    _teacherNameController.clear();
    _teacherEmailController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teacher saved in Firestore.')),
    );
  }

  Future<void> _deleteTeacherProfile(String uid) async {
    await _db.collection('users').doc(uid).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teacher profile removed.')),
    );
  }

  Future<void> _addSubject() async {
    final name = _subjectNameController.text.trim();
    if (name.isEmpty || _selectedTeacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter subject name and select a teacher.')),
      );
      return;
    }
    await _db.collection('subjects').add({
      'name': name,
      'teacherId': _selectedTeacherId,
    });
    if (mounted) {
      _subjectNameController.clear();
      setState(() => _selectedTeacherId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject created.')),
      );
    }
  }

  Future<void> _updateSubjectTeacher({
    required String subjectId,
    required String teacherId,
  }) async {
    await _db.collection('subjects').doc(subjectId).update({
      'teacherId': teacherId,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subject teacher updated.')),
    );
  }

  Future<void> _addScheduleRow() async {
    final division = _divisionController.text.trim();
    final time = _timeController.text.trim();
    if (_scheduleSubjectId == null || division.isEmpty || time.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select subject, division, and time.'),
        ),
      );
      return;
    }
    await _db.collection('schedule').add({
      'subjectId': _scheduleSubjectId,
      'division': division,
      'day': _scheduleDay,
      'time': time,
      'type': _scheduleType,
    });
    if (mounted) {
      _divisionController.clear();
      _timeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable slot added.')),
      );
    }
  }

  Future<void> _editScheduleRow({
    required String scheduleId,
    required Map<String, dynamic> current,
  }) async {
    final division = TextEditingController(text: current['division']?.toString() ?? '');
    final time = TextEditingController(text: current['time']?.toString() ?? '');
    String day = current['day']?.toString() ?? 'Monday';
    String type = current['type']?.toString() == 'lab' ? 'lab' : 'lecture';
    String? subjectId = current['subjectId']?.toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit slot'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _db.collection('subjects').snapshots(),
                  builder: (context, snap) {
                    final docs = (snap.data?.docs.toList() ?? [])
                      ..sort((a, b) => (a.data()['name']?.toString() ?? '')
                          .compareTo(b.data()['name']?.toString() ?? ''));
                    return DropdownButtonFormField<String>(
                      value: subjectId,
                      decoration: const InputDecoration(labelText: 'Subject'),
                      items: docs
                          .map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(d.data()['name']?.toString() ?? d.id),
                              ))
                          .toList(),
                      onChanged: (v) => subjectId = v,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: division,
                  decoration: const InputDecoration(labelText: 'Division'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: _days
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => day = v ?? day,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: time,
                  decoration: const InputDecoration(labelText: 'Time'),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'lecture', label: Text('Lecture')),
                    ButtonSegment(value: 'lab', label: Text('Lab')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => type = s.first,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    if (subjectId == null || subjectId!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a subject.')),
      );
      return;
    }

    final nextDivision = division.text.trim();
    final nextTime = time.text.trim();
    division.dispose();
    time.dispose();

    await _db.collection('schedule').doc(scheduleId).update({
      'subjectId': subjectId,
      'division': nextDivision,
      'day': day,
      'time': nextTime,
      'type': type,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Slot updated.')),
    );
  }

  Future<void> _deleteSubject(String id) async {
    await _db.collection('subjects').doc(id).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject removed.')),
      );
    }
  }

  Future<void> _deleteSchedule(String id) async {
    await _db.collection('schedule').doc(id).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slot removed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spiderman'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Subjects'),
            Tab(text: 'Timetable'),
            Tab(text: 'Teachers'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSubjectsTab(theme),
          _buildScheduleTab(theme),
          _buildTeachersTab(theme),
        ],
      ),
    );
  }

  Widget _buildSubjectsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create class (subject)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subjectNameController,
            decoration: const InputDecoration(
              labelText: 'Subject name',
              hintText: 'e.g. Data Structures',
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('users')
                .where('role', isEqualTo: 'teacher')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ));
              }
              final teachers = snap.data!.docs;
              return DropdownButtonFormField<String>(
                value: _selectedTeacherId,
                decoration: const InputDecoration(labelText: 'Teacher'),
                items: teachers
                    .map(
                      (d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          _teacherLabel(d.id, d.data()),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedTeacherId = v),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addSubject,
            icon: const Icon(Icons.add),
            label: const Text('Add subject'),
          ),
          const SizedBox(height: 28),
          Text(
            'Existing subjects',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('subjects').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) => (a.data()['name']?.toString() ?? '')
                    .compareTo(b.data()['name']?.toString() ?? ''));
              if (docs.isEmpty) {
                return Text(
                  'No subjects yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                );
              }
              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  final teacherId = data['teacherId']?.toString();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: _db
                          .collection('users')
                          .doc(teacherId ?? '__missing__')
                          .get(),
                      builder: (context, teacherSnap) {
                        final teacherName = teacherSnap.hasData &&
                                teacherSnap.data != null &&
                                teacherSnap.data!.exists
                            ? teacherSnap.data!.data()!['name']?.toString() ?? teacherId ?? '—'
                            : (teacherId ?? '—');
                        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          future: _db
                              .collection('schedule')
                              .where('subjectId', isEqualTo: doc.id)
                              .get(),
                          builder: (context, schSnap) {
                            final rows = schSnap.data?.docs ?? [];
                            final labels = <String>{};
                            for (final r in rows) {
                              final d = r.data();
                              final div = d['division']?.toString() ?? '';
                              final batch = d['batch']?.toString();
                              if (div.isEmpty && (batch == null || batch.isEmpty)) continue;
                              labels.add(batch != null && batch.isNotEmpty
                                  ? 'Div $div • Batch $batch'
                                  : 'Div $div');
                            }
                            final divisionBatchText =
                                labels.isEmpty ? 'Division/Batch: -' : labels.join(', ');
                            return ListTile(
                              title: Text(data['name']?.toString() ?? doc.id),
                              subtitle: Text(
                                'Teacher: $teacherName\n$divisionBatchText',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'delete') {
                                    await _deleteSubject(doc.id);
                                    return;
                                  }
                                  if (v == 'changeTeacher') {
                                    await _openChangeTeacherDialog(
                                      subjectId: doc.id,
                                      currentTeacherId: data['teacherId']?.toString(),
                                    );
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(
                                    value: 'changeTeacher',
                                    child: Text('Change teacher'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete subject'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add timetable slot',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('subjects').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) => (a.data()['name']?.toString() ?? '')
                    .compareTo(b.data()['name']?.toString() ?? ''));
              return DropdownButtonFormField<String>(
                value: _scheduleSubjectId,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: docs
                    .map(
                      (d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(d.data()['name']?.toString() ?? d.id),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _scheduleSubjectId = v),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _divisionController,
            decoration: const InputDecoration(
              labelText: 'Division / class',
              hintText: 'e.g. A',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _scheduleDay,
            decoration: const InputDecoration(labelText: 'Day'),
            items: _days
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _scheduleDay = v ?? 'Monday'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _timeController,
            decoration: const InputDecoration(
              labelText: 'Time',
              hintText: 'e.g. 10:00 AM – 11:00 AM',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'lecture',
                label: Text('Lecture'),
                icon: Icon(Icons.menu_book_outlined),
              ),
              ButtonSegment(
                value: 'lab',
                label: Text('Lab'),
                icon: Icon(Icons.science_outlined),
              ),
            ],
            selected: {_scheduleType},
            onSelectionChanged: (s) =>
                setState(() => _scheduleType = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addScheduleRow,
            icon: const Icon(Icons.event_available),
            label: const Text('Add slot'),
          ),
          const SizedBox(height: 28),
          Text(
            'All slots',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('schedule').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final slots = snap.data!.docs.toList()
                ..sort((a, b) {
                  final da = a.data();
                  final db = b.data();
                  final dayCmp = _days.indexOf(da['day']?.toString() ?? '') -
                      _days.indexOf(db['day']?.toString() ?? '');
                  if (dayCmp != 0) return dayCmp;
                  return (da['time']?.toString() ?? '')
                      .compareTo(db['time']?.toString() ?? '');
                });
              if (slots.isEmpty) {
                return Text(
                  'No timetable rows yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                );
              }
              return Column(
                children: slots.map((doc) {
                  final data = doc.data();
                  final sid = data['subjectId']?.toString() ?? '';
                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: _db.collection('subjects').doc(sid).get(),
                    builder: (context, subSnap) {
                      final subName = subSnap.hasData && subSnap.data!.exists
                          ? (subSnap.data!.data()!['name']?.toString() ?? sid)
                          : sid;
                      final isLab = data['type'] == 'lab';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isLab
                                ? theme.colorScheme.tertiaryContainer
                                : theme.colorScheme.primaryContainer,
                            child: Icon(
                              isLab ? Icons.science : Icons.menu_book,
                              color: isLab
                                  ? theme.colorScheme.onTertiaryContainer
                                  : theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text('$subName • Div ${data['division']}'),
                          subtitle: Text(
                            '${data['day']} • ${data['time']} • ${data['type']}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    _editScheduleRow(scheduleId: doc.id, current: data),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteSchedule(doc.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openChangeTeacherDialog({
    required String subjectId,
    required String? currentTeacherId,
  }) async {
    String? selected = currentTeacherId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change teacher'),
        content: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('users')
              .where('role', isEqualTo: 'teacher')
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Teacher'),
              items: docs
                  .map((d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(_teacherLabel(d.id, d.data())),
                      ))
                  .toList(),
              onChanged: (v) => selected = v,
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (selected == null) return;
    await _updateSubjectTeacher(subjectId: subjectId, teacherId: selected!);
  }

  Widget _buildTeachersTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create teacher account (frontend)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherNameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherEmailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherPasswordController,
            decoration: const InputDecoration(
              labelText: 'Password (min 6)',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _createTeacherAccount,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Create teacher auth'),
          ),
          const SizedBox(height: 24),
          Text(
            'Or map existing UID (Firestore only)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherUidController,
            decoration: const InputDecoration(
              labelText: 'Teacher UID',
              hintText: 'Paste existing Firebase Auth UID',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _upsertTeacher,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Save profile by UID'),
          ),
          const SizedBox(height: 28),
          Text(
            'Teachers',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('users')
                .where('role', isEqualTo: 'teacher')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) =>
                    _teacherLabel(a.id, a.data()).compareTo(_teacherLabel(b.id, b.data())));
              if (docs.isEmpty) {
                return Text(
                  'No teachers yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                );
              }
              return Column(
                children: docs.map((d) {
                  final data = d.data();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(data['name']?.toString() ?? d.id),
                      subtitle: Text(data['email']?.toString() ?? d.id),
                      trailing: IconButton(
                        tooltip: 'Remove profile',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteTeacherProfile(d.id),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
