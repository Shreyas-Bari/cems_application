import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_services.dart';
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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectNameController.dispose();
    _divisionController.dispose();
    _timeController.dispose();
    super.dispose();
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
        title: const Text('Admin'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Subjects'),
            Tab(text: 'Timetable'),
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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(data['name']?.toString() ?? doc.id),
                      subtitle: Text('Teacher: ${data['teacherId'] ?? '—'}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteSubject(doc.id),
                      ),
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
                          ? (subSnap.data!.data()!['name'] ?? sid)
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
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteSchedule(doc.id),
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
}
