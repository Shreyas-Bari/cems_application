import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'scan_attendance_screen.dart';
import '../../services/auth_services.dart';
import '../login_screen.dart';
import '../../widgets/schedule_card.dart';

class StudentDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const StudentDashboard({super.key, required this.userData});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _schedule = [];
  List<Map<String, dynamic>> _attendanceRows = [];
  bool _isLoading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    await Future.wait([
      _fetchSchedule(),
      _fetchAttendance(),
    ]);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchSchedule() async {
    final division = widget.userData['division'];

    final scheduleSnap = await _db
        .collection('schedule')
        .where('division', isEqualTo: division)
        .get();

    List<Map<String, dynamic>> scheduleList = [];

    for (var doc in scheduleSnap.docs) {
      final data = doc.data();
      final subjectDoc =
          await _db.collection('subjects').doc(data['subjectId']).get();
      final subjectName = subjectDoc.exists
          ? subjectDoc.data()!['name']
          : 'Unknown Subject';

      scheduleList.add({
        'subject': subjectName,
        'day': data['day'],
        'time': data['time'],
        'type': data['type'],
      });
    }

    const dayOrder = [
      'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday'
    ];
    scheduleList.sort((a, b) =>
        dayOrder.indexOf(a['day']) - dayOrder.indexOf(b['day']));

    _schedule = scheduleList;
  }

  /// Per subject: lecture vs lab totals and presence counts.
  Future<void> _fetchAttendance() async {
    final studentId = widget.userData['uid'];
    final division = widget.userData['division'];

    final sessionsSnap = await _db
        .collection('sessions')
        .where('division', isEqualTo: division)
        .get();

    final Map<String, Map<String, dynamic>> bySubject = {};

    for (var sessionDoc in sessionsSnap.docs) {
      final sessionData = sessionDoc.data();
      final subjectId = sessionData['subjectId']?.toString();
      if (subjectId == null || subjectId.isEmpty) continue;

      final sessionType =
          sessionData['type']?.toString() == 'lab' ? 'lab' : 'lecture';

      if (!bySubject.containsKey(subjectId)) {
        final subjectDoc =
            await _db.collection('subjects').doc(subjectId).get();
        final subjectName = subjectDoc.exists
            ? subjectDoc.data()!['name']
            : 'Unknown Subject';

        bySubject[subjectId] = {
          'name': subjectName,
          'lecture': {'total': 0, 'present': 0},
          'lab': {'total': 0, 'present': 0},
        };
      }

      final bucket = bySubject[subjectId]![sessionType] as Map<String, int>;
      bucket['total'] = (bucket['total'] ?? 0) + 1;

      final attendanceSnap = await _db
          .collection('attendance')
          .where('sessionId', isEqualTo: sessionDoc.id)
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: true)
          .get();

      if (attendanceSnap.docs.isNotEmpty) {
        bucket['present'] = (bucket['present'] ?? 0) + 1;
      }
    }

    final rows = bySubject.entries.map((e) {
      final m = e.value;
      final lec = m['lecture'] as Map<String, int>;
      final lab = m['lab'] as Map<String, int>;
      return {
        'name': m['name'],
        'lectureTotal': lec['total'] ?? 0,
        'lecturePresent': lec['present'] ?? 0,
        'labTotal': lab['total'] ?? 0,
        'labPresent': lab['present'] ?? 0,
      };
    }).toList();

    rows.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));

    _attendanceRows = rows;
  }

  double _pct(int present, int total) =>
      total == 0 ? 0.0 : (present / total) * 100;

  Map<String, dynamic>? _nextClass() {
    if (_schedule.isEmpty) return null;
    final now = DateTime.now();
    const dayOrder = {
      'Monday': 1,
      'Tuesday': 2,
      'Wednesday': 3,
      'Thursday': 4,
      'Friday': 5,
      'Saturday': 6,
      'Sunday': 7,
    };
    final currentWeekday = now.weekday;

    DateTime? parseSlotStart(Map<String, dynamic> slot) {
      final day = slot['day']?.toString() ?? '';
      final time = slot['time']?.toString() ?? '';
      final targetWeekday = dayOrder[day];
      if (targetWeekday == null) return null;

      final firstPart = time.split('to').first.trim().toLowerCase();
      final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$').firstMatch(firstPart);
      if (match == null) return null;
      int hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final ampm = match.group(3)!;
      if (ampm == 'pm' && hour != 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      int delta = targetWeekday - currentWeekday;
      if (delta < 0) delta += 7;
      var dt = DateTime(now.year, now.month, now.day, hour, minute)
          .add(Duration(days: delta));
      if (delta == 0 && dt.isBefore(now)) {
        dt = dt.add(const Duration(days: 7));
      }
      return dt;
    }

    Map<String, dynamic>? best;
    DateTime? bestTime;
    for (final s in _schedule) {
      final dt = parseSlotStart(s);
      if (dt == null) continue;
      if (bestTime == null || dt.isBefore(bestTime)) {
        bestTime = dt;
        best = s;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = <Widget>[
      _attendanceSection(theme),
      _timetableSection(theme),
      _profileSection(theme),
    ];
    final titles = ['Attendance', 'Weekly timetable', 'Profile'];

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
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanAttendanceScreen(
                      studentId: widget.userData['uid'],
                      division: widget.userData['division'],
                    ),
                  ),
                );
              },
            )
          : null,
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
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), label: 'Timetable'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _timetableSection(ThemeData theme) {
    final next = _nextClass();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Next class', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (next == null)
          _emptyCard('No upcoming class found.')
        else
          ScheduleCard(
            title: next['subject'] as String,
            time: next['time']?.toString() ?? '',
            subtitle: '${next['day']} • ${next['type'] == 'lab' ? 'Lab' : 'Lecture'}',
            isLab: next['type'] == 'lab',
          ),
        const SizedBox(height: 12),
        Text('Weekly timetable', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_schedule.isEmpty)
          _emptyCard('No schedule for your division yet.')
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('Day')),
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Subject')),
                  DataColumn(label: Text('Type')),
                ],
                rows: _schedule.map((item) {
                  final isLab = item['type'] == 'lab';
                  return DataRow(cells: [
                    DataCell(Text(item['day']?.toString() ?? '')),
                    DataCell(Text(item['time']?.toString() ?? '')),
                    DataCell(Text(item['subject']?.toString() ?? '')),
                    DataCell(
                      Text(
                        isLab ? 'Lab' : 'Lecture',
                        style: TextStyle(
                          color: isLab ? theme.colorScheme.tertiary : theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _attendanceSection(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Attendance details',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Lecture and lab are tracked separately per subject.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        if (_attendanceRows.isEmpty) _emptyCard('No sessions recorded yet for your division.'),
        ..._attendanceRows.map((item) {
          final lecT = item['lectureTotal'] as int;
          final lecP = item['lecturePresent'] as int;
          final labT = item['labTotal'] as int;
          final labP = item['labPresent'] as int;
          final lecPct = _pct(lecP, lecT);
          final labPct = _pct(labP, labT);
          final lecLow = lecT > 0 && lecPct < 75;
          final labLow = labT > 0 && labPct < 75;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name'] as String, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _attendanceRow(theme, label: 'Lectures', icon: Icons.menu_book_outlined, present: lecP, total: lecT, pct: lecPct, isLow: lecLow, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  _attendanceRow(theme, label: 'Labs', icon: Icons.science_outlined, present: labP, total: labT, pct: labPct, isLow: labLow, color: theme.colorScheme.tertiary),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _profileSection(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text((widget.userData['name']?.toString().isNotEmpty ?? false)
                  ? widget.userData['name'].toString()[0].toUpperCase()
                  : 'S'),
            ),
            title: Text(widget.userData['name']?.toString() ?? 'Student'),
            subtitle: Text(widget.userData['email']?.toString() ?? ''),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Division'),
            subtitle: Text(widget.userData['division']?.toString() ?? '-'),
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

  Widget _emptyCard(String msg) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(msg),
        ),
      );

  Widget _attendanceRow(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required int present,
    required int total,
    required double pct,
    required bool isLow,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isLow ? theme.colorScheme.error : color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: total == 0 ? 0 : present / total,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          color: isLow ? theme.colorScheme.error : color,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Text(
          '$present / $total sessions',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        if (isLow)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Below 75%',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

