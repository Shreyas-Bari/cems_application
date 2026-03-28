import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const StudentDashboard({super.key, required this.userData});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _schedule = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSchedule();
  }

  Future<void> _fetchSchedule() async {
    final division = widget.userData['division'];

    // Fetch all schedule entries for this student's division
    final scheduleSnap = await _db
        .collection('schedule')
        .where('division', isEqualTo: division)
        .get();

    List<Map<String, dynamic>> scheduleList = [];

    for (var doc in scheduleSnap.docs) {
      final data = doc.data();

      // Fetch the subject name using the subjectId
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

    // Sort by day order
    const dayOrder = [
      'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday'
    ];
    scheduleList.sort((a, b) =>
        dayOrder.indexOf(a['day']) - dayOrder.indexOf(b['day']));

    setState(() {
      _schedule = scheduleList;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.userData['name']}'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _schedule.length,
                          itemBuilder: (context, index) {
                            final item = _schedule[index];
                            return Card(
                              margin: EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Icon(
                                  item['type'] == 'lab'
                                      ? Icons.science
                                      : Icons.menu_book,
                                ),
                                title: Text(item['subject']),
                                subtitle: Text('${item['day']} • ${item['time']}'),
                                trailing: Chip(
                                  label: Text(item['type']),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }
}