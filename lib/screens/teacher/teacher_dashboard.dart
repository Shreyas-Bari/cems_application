import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'start_session_screen.dart';
import '../../services/auth_services.dart';
import '../login_screen.dart';

class TeacherDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const TeacherDashboard({super.key, required this.userData});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _schedule = [];
  List<Map<String, dynamic>> _sessionStats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    await Future.wait([
      _fetchSchedule(),
      _fetchSessionStats(),
    ]);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchSchedule() async {
    final teacherId = widget.userData['uid'];

    final subjectsSnap = await _db
        .collection('subjects')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    List<String> subjectIds =
        subjectsSnap.docs.map((doc) => doc.id).toList();

    if (subjectIds.isEmpty) return;

    List<Map<String, dynamic>> scheduleList = [];

    for (String subjectId in subjectIds) {
      final scheduleSnap = await _db
          .collection('schedule')
          .where('subjectId', isEqualTo: subjectId)
          .get();

      for (var doc in scheduleSnap.docs) {
        final data = doc.data();
        final subjectDoc =
            await _db.collection('subjects').doc(subjectId).get();
        final subjectName = subjectDoc.exists
            ? subjectDoc.data()!['name']
            : 'Unknown Subject';

        scheduleList.add({
          'subject': subjectName,
          'day': data['day'],
          'time': data['time'],
          'type': data['type'],
          'division': data['division'],
        });
      }
    }

    const dayOrder = [
      'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday'
    ];
    scheduleList.sort((a, b) =>
        dayOrder.indexOf(a['day']) - dayOrder.indexOf(b['day']));

    _schedule = scheduleList;
  }

  Future<void> _fetchSessionStats() async {
    final teacherId = widget.userData['uid'];

    final sessionsSnap = await _db
        .collection('sessions')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    Map<String, Map<String, dynamic>> statsMap = {};

    for (var doc in sessionsSnap.docs) {
      final data = doc.data();
      final subjectId = data['subjectId'];

      if (!statsMap.containsKey(subjectId)) {
        final subjectDoc =
            await _db.collection('subjects').doc(subjectId).get();
        final subjectName = subjectDoc.exists
            ? subjectDoc.data()!['name']
            : 'Unknown Subject';

        statsMap[subjectId] = {
          'name': subjectName,
          'subjectId': subjectId,
          'division': data['division'],
          'lectures': 0,
          'labs': 0,
        };
      }

      if (data['type'] == 'lecture') {
        statsMap[subjectId]!['lectures'] += 1;
      } else if (data['type'] == 'lab') {
        statsMap[subjectId]!['labs'] += 1;
      }
    }

    _sessionStats = statsMap.values.toList();
  }

  /// Lecture vs lab attendance % per student for one division.
  Future<List<Map<String, dynamic>>> _fetchStudentAttendance(
      String division) async {
    final studentsSnap = await _db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('division', isEqualTo: division)
        .get();

    final sessionsSnap = await _db
        .collection('sessions')
        .where('division', isEqualTo: division)
        .get();

    final lectureSessionIds = <String>[];
    final labSessionIds = <String>[];
    for (final d in sessionsSnap.docs) {
      final t = d.data()['type']?.toString();
      if (t == 'lab') {
        labSessionIds.add(d.id);
      } else {
        lectureSessionIds.add(d.id);
      }
    }

    final List<Map<String, dynamic>> studentStats = [];

    for (var studentDoc in studentsSnap.docs) {
      final studentData = studentDoc.data();
      final studentId = studentDoc.id;

      int lecturePresent = 0;
      for (final sessionId in lectureSessionIds) {
        final attendanceSnap = await _db
            .collection('attendance')
            .where('sessionId', isEqualTo: sessionId)
            .where('studentId', isEqualTo: studentId)
            .where('status', isEqualTo: true)
            .limit(1)
            .get();
        if (attendanceSnap.docs.isNotEmpty) lecturePresent++;
      }

      int labPresent = 0;
      for (final sessionId in labSessionIds) {
        final attendanceSnap = await _db
            .collection('attendance')
            .where('sessionId', isEqualTo: sessionId)
            .where('studentId', isEqualTo: studentId)
            .where('status', isEqualTo: true)
            .limit(1)
            .get();
        if (attendanceSnap.docs.isNotEmpty) labPresent++;
      }

      final lecTot = lectureSessionIds.length;
      final labTot = labSessionIds.length;
      final lecPct = lecTot == 0 ? 0.0 : (lecturePresent / lecTot) * 100;
      final labPct = labTot == 0 ? 0.0 : (labPresent / labTot) * 100;
      final overallTot = lecTot + labTot;
      final overallPresent = lecturePresent + labPresent;
      final overallPct =
          overallTot == 0 ? 0.0 : (overallPresent / overallTot) * 100;

      studentStats.add({
        'name': studentData['name'],
        'lecturePresent': lecturePresent,
        'lectureTotal': lecTot,
        'labPresent': labPresent,
        'labTotal': labTot,
        'lecturePct': lecPct,
        'labPct': labPct,
        'overallPct': overallPct,
      });
    }

    studentStats.sort((a, b) => (a['overallPct'] as double)
        .compareTo(b['overallPct'] as double));

    return studentStats;
  }

  void _openSession(String subjectId, String subjectName, String division,
      String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StartSessionScreen(
          teacherId: widget.userData['uid'],
          subjectId: subjectId,
          subjectName: subjectName,
          division: division,
          type: type,
        ),
      ),
    );
  }

  Widget _sessionTypeButtons(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _openSession(
                  item['subjectId'] as String,
                  item['name'] as String,
                  item['division'] as String,
                  'lecture',
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Lecture'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _openSession(
                  item['subjectId'] as String,
                  item['name'] as String,
                  item['division'] as String,
                  'lab',
                ),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Lab'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  foregroundColor: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Start a session for the QR students will scan.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final divisions = <String>{};
    for (final s in _sessionStats) {
      final d = s['division']?.toString();
      if (d != null && d.isNotEmpty) divisions.add(d);
    }
    final divisionList = divisions.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.userData['name']}'),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => _isLoading = true);
                await _fetchData();
                setState(() => _isLoading = false);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sessions conducted',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_sessionStats.isEmpty)
                      Text(
                        'No sessions yet. Start a lecture or lab below.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else
                      ..._sessionStats.map((item) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'] as String,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Division ${item['division']}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Chip(
                                      avatar: const Icon(Icons.menu_book,
                                          size: 18),
                                      label:
                                          Text('${item['lectures']} lectures'),
                                    ),
                                    Chip(
                                      avatar: const Icon(Icons.science,
                                          size: 18),
                                      label: Text('${item['labs']} labs'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _sessionTypeButtons(item),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    Text(
                      'Weekly schedule',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_schedule.isEmpty)
                      Text(
                        'No schedule entries. Ask admin to add your subjects.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else
                      ..._schedule.map((item) {
                        final isLab = item['type'] == 'lab';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
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
                            title: Text(item['subject'] as String),
                            subtitle: Text(
                              '${item['day']} • ${item['time']} • Div ${item['division']}',
                            ),
                            trailing: Chip(
                              label: Text(isLab ? 'Lab' : 'Lecture'),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    Text(
                      'Student attendance',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lecture and lab percentages are shown separately.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (divisionList.isEmpty)
                      Text(
                        'No division data yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      )
                    else
                      ...divisionList.map((div) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FilledButton.icon(
                            icon: const Icon(Icons.groups_outlined),
                            label: Text('Division $div — view attendance'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            onPressed: () async {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) =>
                                    const Center(child: CircularProgressIndicator()),
                              );

                              final students =
                                  await _fetchStudentAttendance(div);

                              if (context.mounted) Navigator.pop(context);

                              if (!context.mounted) return;

                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                builder: (_) => DraggableScrollableSheet(
                                  expand: false,
                                  initialChildSize: 0.65,
                                  maxChildSize: 0.95,
                                  builder: (_, controller) => Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Division $div',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Lecture vs lab breakdown',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: ListView.builder(
                                            controller: controller,
                                            itemCount: students.length,
                                            itemBuilder: (_, index) {
                                              final s = students[index];
                                              final overall =
                                                  s['overallPct'] as double;
                                              final lecPct =
                                                  s['lecturePct'] as double;
                                              final labPct =
                                                  s['labPct'] as double;
                                              final lecTot =
                                                  s['lectureTotal'] as int;
                                              final labTot =
                                                  s['labTotal'] as int;
                                              final isLow = overall < 75;
                                              final name = s['name']
                                                      ?.toString() ??
                                                  '?';
                                              return ListTile(
                                                leading: CircleAvatar(
                                                  backgroundColor: isLow
                                                      ? theme.colorScheme.error
                                                      : theme
                                                          .colorScheme.primary,
                                                  child: Text(
                                                    name.isNotEmpty
                                                        ? name[0]
                                                        : '?',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                                title: Text(name),
                                                subtitle: Text(
                                                  'Lec: ${s['lecturePresent']}/$lecTot (${lecPct.toStringAsFixed(0)}%) '
                                                  '• Lab: ${s['labPresent']}/$labTot (${labPct.toStringAsFixed(0)}%)',
                                                ),
                                                isThreeLine: true,
                                                trailing: Text(
                                                  '${overall.toStringAsFixed(1)}%',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: isLow
                                                        ? theme
                                                            .colorScheme.error
                                                        : theme.colorScheme
                                                            .primary,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}
