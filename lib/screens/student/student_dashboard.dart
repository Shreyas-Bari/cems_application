import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'scan_attendance_screen.dart';
import '../../services/auth_services.dart';
import '../login_screen.dart';
import '../../widgets/schedule_card.dart';
import '../../widgets/ui_blocks.dart';

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

  String _baseSubjectName(String name) {
    final n = name.trim();
    final lower = n.toLowerCase();
    if (lower.endsWith(' lab')) {
      return n.substring(0, n.length - 4).trim();
    }
    return n;
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
          ? subjectDoc.data()!['name']?.toString() ?? 'Unknown Subject'
          : 'Unknown Subject';

      scheduleList.add({
        'subject': subjectName,
        'day': data['day'],
        'time': data['time'],
        'type': data['type'],
        'batch': data['batch'],
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
          _isFirestoreLab(sessionData['type']) ? 'lab' : 'lecture';

      final subjectDoc =
          await _db.collection('subjects').doc(subjectId).get();
      final rawName = subjectDoc.exists
          ? subjectDoc.data()!['name']?.toString() ?? 'Unknown Subject'
          : 'Unknown Subject';
      final subjectName = _baseSubjectName(rawName);

      if (!bySubject.containsKey(subjectName)) {
        bySubject[subjectName] = {
          'name': subjectName,
          'lecture': {'total': 0, 'present': 0},
          'lab': {'total': 0, 'present': 0},
        };
      }

      final bucket = bySubject[subjectName]![sessionType] as Map<String, int>;
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

  bool _isFirestoreLab(dynamic type) =>
      type?.toString().trim().toLowerCase() == 'lab';

  String _typeLabelFromFirestore(dynamic type) {
    final raw = type?.toString().trim() ?? '';
    final lower = raw.toLowerCase();
    if (lower == 'lab') return 'Lab';
    if (lower == 'lecture') return 'Lecture';
    if (raw.isEmpty) return '—';
    return raw;
  }

  ({int hour24, int minute})? _parseScheduleTimeStart(String time) {
    final t = time.toLowerCase().replaceAll('.', ':');
    int? startHour24;
    var minute = 0;
    final matchAmPm =
        RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)').firstMatch(t);
    if (matchAmPm != null) {
      var hour = int.parse(matchAmPm.group(1)!);
      minute = int.parse(matchAmPm.group(2) ?? '0');
      final ampm = matchAmPm.group(3)!;
      if (ampm == 'pm' && hour != 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
      startHour24 = hour;
    } else {
      final match24 = RegExp(r'(\d{1,2})(?::(\d{2}))?').firstMatch(t);
      if (match24 != null) {
        startHour24 = int.parse(match24.group(1)!);
        minute = int.parse(match24.group(2) ?? '0');
      }
    }
    if (startHour24 == null) return null;
    return (hour24: startHour24, minute: minute);
  }

  String _slotKeyFromTime(String time) {
    final parsed = _parseScheduleTimeStart(time);
    if (parsed == null) return '';
    final h = parsed.hour24;
    if (h >= 8 && h < 12) return '10-12';
    if (h >= 12 && h < 14) return '12-2';
    return '';
  }

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

      final parsed = _parseScheduleTimeStart(time);
      if (parsed == null) return null;
      final hour = parsed.hour24;
      final minute = parsed.minute;

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
          NavigationDestination(
              icon: Icon(Icons.analytics_outlined), label: 'Attendance'),
          NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined), label: 'Timetable'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _timetableSection(ThemeData theme) {
    final next = _nextClass();
    const days = [
      'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday'
    ];

    final table = <String, Map<String, String>>{};
    for (final d in days) {
      table[d] = {'10-12': '-', '12-2': '-'};
    }
    for (final s in _schedule) {
      final day = s['day']?.toString() ?? '';
      if (!table.containsKey(day)) continue;
      final key = _slotKeyFromTime(s['time']?.toString() ?? '');
      if (key.isEmpty) continue;
      final label = s['subject']?.toString() ?? '-';
      final prev = table[day]![key]!;
      if (prev == '-' || prev.isEmpty) {
        table[day]![key] = label;
      } else if (!prev.split('\n').contains(label)) {
        table[day]![key] = '$prev\n$label';
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const AppSectionHeader(
          title: 'Next class',
          subtitle: 'Your upcoming lecture/lab from timetable',
        ),
        const SizedBox(height: 8),
        if (next == null)
          const EmptyStateCard(
            message: 'No upcoming class found.',
            hint: 'Ask admin to add schedule entries for your division.',
            icon: Icons.event_busy_outlined,
          )
        else
          ScheduleCard(
            title: next['subject'] as String,
            time: next['time']?.toString() ?? '',
            subtitle: () {
              final parts = <String>[next['day']?.toString() ?? ''];
              final b = next['batch']?.toString().trim();
              if (b != null && b.isNotEmpty) parts.add('Batch $b');
              parts.add(_typeLabelFromFirestore(next['type']));
              return parts.join(' • ');
            }(),
            isLab: _isFirestoreLab(next['type']),
          ),
        const SizedBox(height: 12),
        const AppSectionHeader(
          title: 'Weekly timetable',
          subtitle: 'Current class plan for your division',
        ),
        const SizedBox(height: 8),
        if (_schedule.isEmpty)
          const EmptyStateCard(
            message: 'No schedule for your division yet.',
            hint: 'Admin needs to create timetable slots first.',
            icon: Icons.calendar_month_outlined,
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('Day')),
                  DataColumn(label: Text('10:00 AM - 12:00 PM')),
                  DataColumn(label: Text('12:00 PM - 2:00 PM')),
                ],
                rows: days.map((day) {
                  return DataRow(cells: [
                    DataCell(Text(day)),
                    DataCell(Text(table[day]!['10-12']!)),
                    DataCell(Text(table[day]!['12-2']!)),
                  ]);
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _attendanceSection(ThemeData theme) {
    final totalSessions = _attendanceRows.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item['lectureTotal'] as int) +
          (item['labTotal'] as int),
    );
    final totalPresent = _attendanceRows.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item['lecturePresent'] as int) +
          (item['labPresent'] as int),
    );
    final overallPct = _pct(totalPresent, totalSessions);
    final lowSubjects = _attendanceRows.where((item) {
      final lecT = item['lectureTotal'] as int;
      final lecP = item['lecturePresent'] as int;
      final labT = item['labTotal'] as int;
      final labP = item['labPresent'] as int;
      final combinedTotal = lecT + labT;
      final combinedPresent = lecP + labP;
      return combinedTotal > 0 && _pct(combinedPresent, combinedTotal) < 75;
    }).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const AppSectionHeader(
          title: 'Attendance details',
          subtitle: 'Lecture and lab are tracked separately per subject',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: QuickStatCard(
                label: 'Overall',
                value: '${overallPct.toStringAsFixed(1)}%',
                icon: Icons.pie_chart_outline,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: QuickStatCard(
                label: 'Low subjects',
                value: '$lowSubjects',
                icon: Icons.warning_amber_outlined,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_attendanceRows.isEmpty)
          const EmptyStateCard(
            message: 'No sessions recorded yet for your division.',
            hint: 'You will see percentages after teachers start sessions.',
            icon: Icons.assignment_outlined,
          ),
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
                  Text(
                    item['name'] as String,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _attendanceRow(
                    theme,
                    label: 'Lectures',
                    icon: Icons.menu_book_outlined,
                    present: lecP,
                    total: lecT,
                    pct: lecPct,
                    isLow: lecLow,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  _attendanceRow(
                    theme,
                    label: 'Labs',
                    icon: Icons.science_outlined,
                    present: labP,
                    total: labT,
                    pct: labPct,
                    isLow: labLow,
                    color: theme.colorScheme.tertiary,
                  ),
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
                  widget.userData['name']?.toString() ?? 'Student',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userData['email']?.toString() ?? '',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
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
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Division'),
            subtitle:
                Text(widget.userData['division']?.toString() ?? '-'),
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
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
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
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
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