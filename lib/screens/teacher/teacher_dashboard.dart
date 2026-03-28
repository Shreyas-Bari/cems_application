import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    final totalSessions = sessionsSnap.docs.length;
    final sessionIds = sessionsSnap.docs.map((doc) => doc.id).toList();

    List<Map<String, dynamic>> studentStats = [];

    for (var studentDoc in studentsSnap.docs) {
      final studentData = studentDoc.data();
      final studentId = studentDoc.id;

      int present = 0;
      for (String sessionId in sessionIds) {
        final attendanceSnap = await _db
            .collection('attendance')
            .where('sessionId', isEqualTo: sessionId)
            .where('studentId', isEqualTo: studentId)
            .where('status', isEqualTo: true)
            .get();

        if (attendanceSnap.docs.isNotEmpty) present++;
      }

      final percentage =
          totalSessions == 0 ? 0.0 : (present / totalSessions) * 100;

      studentStats.add({
        'name': studentData['name'],
        'present': present,
        'total': totalSessions,
        'percentage': percentage,
      });
    }

    studentStats.sort((a, b) =>
        (a['percentage'] as double).compareTo(b['percentage'] as double));

    return studentStats;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.userData['name']}'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Sessions Conducted ---
                  Text(
                    'Sessions Conducted',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  _sessionStats.isEmpty
                      ? Text('No sessions found.')
                      : Column(
                          children: _sessionStats.map((item) {
                            return Card(
                              margin: EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'],
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Division: ${item['division']}',
                                      style:
                                          TextStyle(color: Colors.grey[600]),
                                    ),
                                    SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Chip(
                                          label: Text(
                                              '${item['lectures']} Lectures'),
                                          backgroundColor: Colors.blue[100],
                                        ),
                                        SizedBox(width: 8),
                                        Chip(
                                          label: Text('${item['labs']} Labs'),
                                          backgroundColor: Colors.purple[100],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                  SizedBox(height: 24),

                  // --- Weekly Schedule ---
                  Text(
                    'Your Weekly Schedule',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  _schedule.isEmpty
                      ? Text('No schedule found.')
                      : Column(
                          children: _schedule.map((item) {
                            return Card(
                              margin: EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Icon(
                                  item['type'] == 'lab'
                                      ? Icons.science
                                      : Icons.menu_book,
                                ),
                                title: Text(item['subject']),
                                subtitle: Text(
                                    '${item['day']} • ${item['time']} • Division ${item['division']}'),
                                trailing: Chip(label: Text(item['type'])),
                              ),
                            );
                          }).toList(),
                        ),

                  SizedBox(height: 24),

                  // --- Student Attendance ---
                  Text(
                    'Student Attendance',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),

                  ..._sessionStats.map((stat) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.people),
                        label: Text(
                            'View Division ${stat['division']} Attendance'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 50),
                        ),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) =>
                                Center(child: CircularProgressIndicator()),
                          );

                          final students = await _fetchStudentAttendance(
                              stat['division']);

                          Navigator.pop(context);

                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                            ),
                            builder: (_) => DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.6,
                              maxChildSize: 0.95,
                              builder: (_, controller) => Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Division ${stat['division']} - Student Attendance',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    Expanded(
                                      child: ListView.builder(
                                        controller: controller,
                                        itemCount: students.length,
                                        itemBuilder: (_, index) {
                                          final s = students[index];
                                          final isLow =
                                              (s['percentage'] as double) < 75;
                                          return ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: isLow
                                                  ? Colors.red
                                                  : Colors.green,
                                              child: Text(
                                                s['name'][0],
                                                style: TextStyle(
                                                    color: Colors.white),
                                              ),
                                            ),
                                            title: Text(s['name']),
                                            subtitle: Text(
                                                '${s['present']} / ${s['total']} classes'),
                                            trailing: Text(
                                              '${(s['percentage'] as double).toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isLow
                                                    ? Colors.red
                                                    : Colors.green,
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
                  }).toList(),
                ],
              ),
            ),
    );
  }
}