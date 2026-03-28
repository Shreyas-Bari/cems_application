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

    // Get all subjects this teacher teaches
    final subjectsSnap = await _db
        .collection('subjects')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    List<String> subjectIds =
        subjectsSnap.docs.map((doc) => doc.id).toList();

    if (subjectIds.isEmpty) return;

    // Get schedule entries for those subjects
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

    // Get all sessions conducted by this teacher
    final sessionsSnap = await _db
        .collection('sessions')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    // Group by subjectId
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
                                          label:
                                              Text('${item['labs']} Labs'),
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
                ],
              ),
            ),
    );
  }
}