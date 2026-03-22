import 'package:flutter/material.dart';

class StudentDashboard extends StatelessWidget {
  final Map<String, dynamic> userData;
  const StudentDashboard({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Student Dashboard')),
      body: Center(
        child: Text('Welcome, ${userData['name']}!'),
      ),
    );
  }
}