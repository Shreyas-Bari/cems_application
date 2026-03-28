import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'scan_attendance_screen.dart';

class StudentDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const StudentDashboard({super.key, required this.userData});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _schedule = [];
  List<Map<String, dynamic>> _attendance = [];
  bool _isLoading = true;

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

  Future<void> _fetchAttendance() async {
    final studentId = widget.userData['uid'];
    final division = widget.userData['division'];

    final sessionsSnap = await _db
        .collection('sessions')
        .where('division', isEqualTo: division)
        .get();

    Map<String, Map<String, dynamic>> subjectMap = {};

    for (var sessionDoc in sessionsSnap.docs) {
      final sessionData = sessionDoc.data();
      final subjectId = sessionData['subjectId'];
      final sessionId = sessionDoc.id;

      if (!subjectMap.containsKey(subjectId)) {
        final subjectDoc =
            await _db.collection('subjects').doc(subjectId).get();
        final subjectName = subjectDoc.exists
            ? subjectDoc.data()!['name']
            : 'Unknown Subject';

        subjectMap[subjectId] = {
          'name': subjectName,
          'total': 0,
          'present': 0,
        };
      }

      subjectMap[subjectId]!['total'] += 1;

      final attendanceSnap = await _db
          .collection('attendance')
          .where('sessionId', isEqualTo: sessionId)
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: true)
          .get();

      if (attendanceSnap.docs.isNotEmpty) {
        subjectMap[subjectId]!['present'] += 1;
      }
    }

    _attendance = subjectMap.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.userData['name']}'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(Icons.qr_code_scanner),
        label: Text('Scan Attendance'),
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
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Attendance Section ---
                  Text(
                    'Your Attendance',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  _attendance.isEmpty
                      ? Text('No attendance data found.')
                      : Column(
                          children: _attendance.map((item) {
                            final total = item['total'] as int;
                            final present = item['present'] as int;
                            final percentage = total == 0
                                ? 0.0
                                : (present / total) * 100;
                            final isLow = percentage < 75;

                            return Card(
                              margin: EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          item['name'],
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${percentage.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isLow
                                                ? Colors.red
                                                : Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: total == 0
                                          ? 0
                                          : present / total,
                                      backgroundColor: Colors.grey[300],
                                      color: isLow
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      '$present / $total classes attended',
                                      style:
                                          TextStyle(color: Colors.grey[600]),
                                    ),
                                    if (isLow)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Attendance below 75%',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                  SizedBox(height: 24),

                  // --- Schedule Section ---
                  Text(
                    'Your Weekly Schedule',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  _schedule.isEmpty
                      ? Text('No schedule found for your division.')
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
                                    '${item['day']} • ${item['time']}'),
                                trailing: Chip(label: Text(item['type'])),
                              ),
                            );
                          }).toList(),
                        ),

                  // Bottom padding so FAB doesn't cover last card
                  SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}