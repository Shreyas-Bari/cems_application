import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../widgets/ui_blocks.dart';

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
  Position? _cachedPosition;

  @override
  void initState() {
    super.initState();
    // Pre-fetch location as soon as the scan screen opens so it's ready
    // by the time a QR code is scanned — eliminates 3-10s post-scan delay.
    _prefetchLocation();
  }

  Future<void> _prefetchLocation() async {
    final pos = await _getStudentPosition();
    if (mounted) {
      setState(() => _cachedPosition = pos);
    }
  }

  Future<Position?> _getStudentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );
  }

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

    final lat = (sessionData['latitude'] as num?)?.toDouble();
    final lng = (sessionData['longitude'] as num?)?.toDouble();
    final radius = (sessionData['radiusMetres'] as num?)?.toDouble() ?? 30;
    double? distance;
    double? studentLat;
    double? studentLng;

    if (lat != null && lng != null) {
      // Use the pre-fetched position if available, otherwise fetch now.
      final studentPos = _cachedPosition ?? await _getStudentPosition();
      if (studentPos == null) {
        setState(() {
          _isProcessing = false;
          _done = true;
          _success = false;
          _message =
              'Location permission is required to mark attendance. Enable location and try again.';
        });
        return;
      }

      studentLat = studentPos.latitude;
      studentLng = studentPos.longitude;
      distance = Geolocator.distanceBetween(lat, lng, studentLat, studentLng);
      if (distance != null && distance > radius) {
        setState(() {
          _isProcessing = false;
          _done = true;
          _success = false;
          _message =
              'You are outside allowed range.\nDistance: ${distance!.toStringAsFixed(0)} m • Limit: ${radius.toStringAsFixed(0)} m';
        });
        return;
      }
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

    // All checks passed - mark attendance (sessionType mirrors session for rules & stats)
    final sessionType = sessionData['type']?.toString() ?? 'lecture';
    final attendanceId = '${sessionId}_${widget.studentId}';
    await _db.collection('attendance').doc(attendanceId).set({
      'sessionId': sessionId,
      'studentId': widget.studentId,
      'subjectId': sessionData['subjectId'],
      'sessionType': sessionType,
      'status': true,
      'markedAt': Timestamp.now(),
      if (studentLat != null) 'studentLatitude': studentLat,
      if (studentLng != null) 'studentLongitude': studentLng,
      if (distance != null) 'distanceMeters': distance,
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
        title: const Text('Scan attendance'),
      ),
      body: _done
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EmptyStateCard(
                      icon:
                          _success ? Icons.check_circle_outline : Icons.error_outline,
                      message: _message,
                      hint: _success
                          ? 'You can return to dashboard now.'
                          : 'Please ask your teacher to refresh the QR.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('Go Back'),
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
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Verifying QR and location...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
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