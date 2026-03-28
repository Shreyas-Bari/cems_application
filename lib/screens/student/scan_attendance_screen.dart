import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScanAttendanceScreen extends StatefulWidget {
  final String studentId;
  final String division;

  const ScanAttendanceScreen({
    super.key,
    required this.studentId,
    required this.division,
  });

  @override
  State<ScanAttendanceScreen> createState() => _ScanAttendanceScreenState();
}

class _ScanAttendanceScreenState extends State<ScanAttendanceScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isProcessing = false;
  bool _done = false;
  String _message = '';
  bool _success = false;

  Future<void> _handleScan(String scannedToken) async {
    if (_isProcessing || _done) return;

    setState(() {
      _isProcessing = true;
    });

    // Find an active session matching this token
    final sessionSnap = await _db
        .collection('sessions')
        .where('qrToken', isEqualTo: scannedToken)
        .where('isActive', isEqualTo: true)
        .where('division', isEqualTo: widget.division)
        .get();

    if (sessionSnap.docs.isEmpty) {
      setState(() {
        _isProcessing = false;
        _done = true;
        _success = false;
        _message = 'Invalid or expired QR code. Ask your teacher to refresh it.';
      });
      return;
    }

    final sessionDoc = sessionSnap.docs.first;
    final sessionData = sessionDoc.data();
    final sessionId = sessionDoc.id;

    // Check if token is expired
    final expiry = (sessionData['tokenExpiry'] as Timestamp).toDate();
    if (DateTime.now().isAfter(expiry)) {
      setState(() {
        _isProcessing = false;
        _done = true;
        _success = false;
        _message = 'QR code has expired. Ask your teacher to refresh it.';
      });
      return;
    }

    // Check if student already marked attendance for this session
    final existingSnap = await _db
        .collection('attendance')
        .where('sessionId', isEqualTo: sessionId)
        .where('studentId', isEqualTo: widget.studentId)
        .get();

    if (existingSnap.docs.isNotEmpty) {
      setState(() {
        _isProcessing = false;
        _done = true;
        _success = false;
        _message = 'You have already marked attendance for this session.';
      });
      return;
    }

    // All checks passed - mark attendance
    await _db.collection('attendance').add({
      'sessionId': sessionId,
      'studentId': widget.studentId,
      'status': true,
      'markedAt': Timestamp.now(),
    });

    setState(() {
      _isProcessing = false;
      _done = true;
      _success = true;
      _message = 'Attendance marked successfully!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan Attendance'),
      ),
      body: _done
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _success ? Icons.check_circle : Icons.error,
                      color: _success ? Colors.green : Colors.red,
                      size: 80,
                    ),
                    SizedBox(height: 24),
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                    SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                      ),
                      child: Text('Go Back'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    final barcode = capture.barcodes.first;
                    if (barcode.rawValue != null) {
                      _handleScan(barcode.rawValue!);
                    }
                  },
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'Point your camera at the QR code',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}