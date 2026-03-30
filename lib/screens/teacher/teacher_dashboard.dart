import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'start_session_screen.dart';
import '../../services/auth_services.dart';
import '../login_screen.dart';
import '../../widgets/schedule_card.dart';

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
  int _tabIndex = 0;

  String _baseSubjectName(String name) {
    final n = name.trim();
    final lower = n.toLowerCase();
    if (lower.endsWith(' lab')) {
      return n.substring(0, n.length - 4).trim();
    }
    return n;
  }

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
          'subject': _baseSubjectName(subjectName),
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
    final subjectsSnap = await _db
        .collection('subjects')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    final subjectIds = subjectsSnap.docs.map((d) => d.id).toSet();
    if (subjectIds.isEmpty) {
      _sessionStats = [];
      return;
    }

    final subjectNameMap = <String, String>{};
    for (final doc in subjectsSnap.docs) {
      final raw = doc.data()['name']?.toString() ?? 'Unknown Subject';
      subjectNameMap[doc.id] = _baseSubjectName(raw);
    }

    final scheduleSnap = await _db.collection('schedule').get();
    final sessionsSnap = await _db
        .collection('sessions')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    final statsMap = <String, Map<String, dynamic>>{};

    for (final sch in scheduleSnap.docs) {
      final data = sch.data();
      final subjectId = data['subjectId']?.toString();
      final division = data['division']?.toString();
      if (subjectId == null || !subjectIds.contains(subjectId)) continue;
      if (division == null || division.isEmpty) continue;
      final baseName = subjectNameMap[subjectId] ?? 'Unknown Subject';
      final key = '$baseName|$division';
      statsMap.putIfAbsent(
        key,
        () => {
          'name': baseName,
          'lectureSubjectId': null,
          'labSubjectId': null,
          'subjectIds': <String>{},
          'division': division,
          'lectures': 0,
          'labs': 0,
          'hasLectureSlot': false,
          'hasLabSlot': false,
        },
      );
      final t = data['type']?.toString() == 'lab' ? 'lab' : 'lecture';
      (statsMap[key]!['subjectIds'] as Set<String>).add(subjectId);
      if (t == 'lab') {
        statsMap[key]!['hasLabSlot'] = true;
        statsMap[key]!['labSubjectId'] ??= subjectId;
      } else {
        statsMap[key]!['hasLectureSlot'] = true;
        statsMap[key]!['lectureSubjectId'] ??= subjectId;
      }
    }

    for (final ses in sessionsSnap.docs) {
      final data = ses.data();
      final subjectId = data['subjectId']?.toString();
      final division = data['division']?.toString();
      if (subjectId == null || !subjectIds.contains(subjectId)) continue;
      if (division == null || division.isEmpty) continue;
      final baseName = subjectNameMap[subjectId] ?? 'Unknown Subject';
      final key = '$baseName|$division';
      if (!statsMap.containsKey(key)) continue;
      final t = data['type']?.toString() == 'lab' ? 'lab' : 'lecture';
      if (t == 'lab') {
        statsMap[key]!['labs'] += 1;
      } else {
        statsMap[key]!['lectures'] += 1;
      }
    }

    _sessionStats = statsMap.values.toList()
      ..sort((a, b) {
        final nameCmp = (a['name']?.toString() ?? '')
            .compareTo(b['name']?.toString() ?? '');
        if (nameCmp != 0) return nameCmp;
        return (a['division']?.toString() ?? '')
            .compareTo(b['division']?.toString() ?? '');
      });
  }

  /// Lecture vs lab attendance % per student for one subject in a division,
  /// scoped to this teacher only.
  Future<List<Map<String, dynamic>>> _fetchStudentAttendanceForSubject({
    required String division,
    required Set<String> subjectIds,
  }) async {
    final studentsSnap = await _db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('division', isEqualTo: division)
        .get();

    final allSessions = await _db
        .collection('sessions')
        .where('division', isEqualTo: division)
        .where('teacherId', isEqualTo: widget.userData['uid'])
        .get();
    final sessions = allSessions.docs.where((d) {
      final sid = d.data()['subjectId']?.toString() ?? '';
      return subjectIds.contains(sid);
    }).toList();

    final lectureSessionIds = <String>[];
    final labSessionIds = <String>[];
    for (final d in sessions) {
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

      studentStats.add({
        'name': studentData['name'],
        'lecturePresent': lecturePresent,
        'lectureTotal': lecTot,
        'labPresent': labPresent,
        'labTotal': labTot,
        'lecturePct': lecPct,
        'labPct': labPct,
      });
    }

    studentStats.sort((a, b) =>
        (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));

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
    final hasLecture = item['hasLectureSlot'] == true;
    final hasLab = item['hasLabSlot'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: hasLecture
                    ? () => _openSession(
                          (item['lectureSubjectId'] ??
                              item['labSubjectId']) as String,
                          item['name'] as String,
                          item['division'] as String,
                          'lecture',
                        )
                    : null,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Lecture'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: hasLab
                    ? () => _openSession(
                          (item['labSubjectId'] ??
                              item['lectureSubjectId']) as String,
                          item['name'] as String,
                          item['division'] as String,
                          'lab',
                        )
                    : null,
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
          hasLecture || hasLab
              ? 'Start a session for the QR students will scan.'
              : 'No lecture/lab slots assigned by admin for this subject/division.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openSubjectAttendanceSheet(
            subjectIds:
                (item['subjectIds'] as Set<String>).toSet(),
            subjectName: item['name'] as String,
            division: item['division'] as String,
          ),
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('View attendance'),
        ),
      ],
    );
  }

  Future<void> _openSubjectAttendanceSheet({
    required Set<String> subjectIds,
    required String subjectName,
    required String division,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final students = await _fetchStudentAttendanceForSubject(
      division: division,
      subjectIds: subjectIds,
    );

    if (context.mounted) Navigator.pop(context);
    if (!context.mounted) return;

    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subjectName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Division $division • lecture & lab separately',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: students.isEmpty
                    ? Center(
                        child: Text(
                          'No students found.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: students.length,
                        itemBuilder: (_, index) {
                          final s = students[index];
                          final name = s['name']?.toString() ?? '?';
                          final lecP = s['lecturePresent'] as int;
                          final lecT = s['lectureTotal'] as int;
                          final labP = s['labPresent'] as int;
                          final labT = s['labTotal'] as int;
                          final lecPct = s['lecturePct'] as double;
                          final labPct = s['labPct'] as double;
                          final overallPct = ((lecP + labP) / (lecT + labT))*100;
                          final color = _attendanceColor(overallPct, theme);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color,
                              child: Text(
                                name.isNotEmpty ? name[0] : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(name),
                            subtitle: Text(
                              'Lecture: $lecP/$lecT (${lecPct.toStringAsFixed(0)}%)  •  '
                              'Lab: $labP/$labT (${labPct.toStringAsFixed(0)}%)',
                            ),
                            isThreeLine: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            trailing: Text(
                              '${overallPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
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
  }

  Color _attendanceColor(double pct, ThemeData theme) {
    if (pct >= 75) return Colors.green;
    if (pct >= 60) return const Color(0xFFE0A800);
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = <Widget>[
      _dashboardSection(theme),
      _timetableSection(theme),
      _profileSection(theme),
    ];
    final titles = ['Dashboard', 'Weekly timetable', 'Profile'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tabIndex]),
        actions: [
          if (_tabIndex != 2)
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => setState(() => _tabIndex = 2),
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
              child: IndexedStack(index: _tabIndex, children: pages),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), label: 'Timetable'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _dashboardSection(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      children: [
        if (_sessionStats.isEmpty)
          Text(
            'No subject/division setup found. Ask admin to assign schedule.',
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
                          avatar: const Icon(Icons.menu_book, size: 18),
                          label: Text('${item['lectures']} lectures'),
                        ),
                        Chip(
                          avatar: const Icon(Icons.science, size: 18),
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
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _timetableSection(ThemeData theme) {
  const dayOrder = [
    'Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday'
  ];

  // Group schedule by day
  final Map<String, List<Map<String, dynamic>>> grouped = {};
  for (final item in _schedule) {
    final day = item['day'] as String;
    grouped.putIfAbsent(day, () => []).add(item);
  }

  // Sort days by dayOrder
  final sortedDays = grouped.keys.toList()
    ..sort((a, b) => dayOrder.indexOf(a) - dayOrder.indexOf(b));

  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16.0),
    children: [
      if (_schedule.isEmpty)
        Text(
          'No schedule entries. Ask admin to add your subjects.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        )
      else
        ...sortedDays.expand((day) {
          final items = grouped[day]!;
          return [
            // Day header
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                day,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            // Tiles for that day
            ...items.map((item) {
              final isLab = item['type'] == 'lab';
              return ScheduleCard(
                title: isLab
                    ? '${item['subject']} Lab'
                    : item['subject'] as String,
                time: item['time']?.toString() ?? '',
                subtitle:
                    'Div ${item['division']} • ${isLab ? 'Lab' : 'Lecture'}',
                isLab: isLab,
              );
            }),
          ];
        }),
    ],
  );
}

  Widget _profileSection(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.userData['name']?.toString() ?? 'Teacher',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userData['email']?.toString() ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Change'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              await AuthService().signOut();
              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ),
      ],
    );
  }
}
