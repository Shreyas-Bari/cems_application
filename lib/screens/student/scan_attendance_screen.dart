import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

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
      // Could be wrong division OR invalid/expired token
      // Check if there's an active session with this token for ANY division
      final anyDivisionSnap = await _db
          .collection('sessions')
          .where('qrToken', isEqualTo: scannedToken)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      setState(() {
        _isProcessing = false;
        _done = true;
        _success = false;
        _message = anyDivisionSnap.docs.isNotEmpty
            ? 'This session belongs to a different division. You cannot mark attendance here.'
            : 'Invalid or expired QR code. Please scan the latest QR shown by your teacher.';
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
        _message = 'This QR code has expired. Wait for the next QR to appear and scan again.';
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
      // Run location check and duplicate-attendance check in parallel for speed.
      final studentPosFuture = _cachedPosition != null
          ? Future.value(_cachedPosition)
          : _getStudentPosition();
      final existingFuture = _db
          .collection('attendance')
          .where('sessionId', isEqualTo: sessionId)
          .where('studentId', isEqualTo: widget.studentId)
          .limit(1)
          .get();

      final results = await Future.wait([studentPosFuture, existingFuture]);
      final studentPos = results[0] as Position?;
      final existingSnap = results[1] as QuerySnapshot;

      // Check duplicate first
      if (existingSnap.docs.isNotEmpty) {
        setState(() {
          _isProcessing = false;
          _done = true;
          _success = false;
          _message = 'Your attendance is already recorded for this session.';
        });
        return;
      }

      if (studentPos == null) {
        setState(() {
          _isProcessing = false;
          _done = true;
          _success = false;
          _message =
              'Location access is required to verify your presence. Please enable location services and try again.';
        });
        return;
      }

      studentLat = studentPos.latitude;
      studentLng = studentPos.longitude;
      distance = Geolocator.distanceBetween(lat, lng, studentLat, studentLng);
      if (distance > radius) {
        setState(() {
          _isProcessing = false;
          _done = true;
          _success = false;
          _message =
              'You are too far from the classroom.\nYour distance: ${distance!.toStringAsFixed(0)} m — Allowed: ${radius.toStringAsFixed(0)} m';
        });
        return;
      }
    } else {
      // No location on session — just check for duplicate
      final existingSnap = await _db
          .collection('attendance')
          .where('sessionId', isEqualTo: sessionId)
          .where('studentId', isEqualTo: widget.studentId)
          .limit(1)
          .get();

      if (existingSnap.docs.isNotEmpty) {
        setState(() {
          _isProcessing = false;
          _done = true;
          _success = false;
          _message = 'Your attendance is already recorded for this session.';
        });
        return;
      }
    }

    // All checks passed — mark attendance
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
      _message = 'Attendance marked successfully! ✓';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan attendance'),
      ),
      body: _done ? _buildResultView(context) : _buildScannerView(),
    );
  }

  Widget _buildResultView(BuildContext context) {
    final theme = Theme.of(context);
    final color = _success ? Colors.green : theme.colorScheme.error;
    final bgColor = _success
        ? Colors.green.withValues(alpha: 0.08)
        : theme.colorScheme.error.withValues(alpha: 0.08);

    String hint;
    if (_success) {
      hint = 'You can return to the dashboard now.';
    } else if (_message.contains('division')) {
      hint = 'Make sure you are scanning the QR for your own division.';
    } else if (_message.contains('far')) {
      hint = 'Move closer to the classroom and try again.';
    } else if (_message.contains('already')) {
      hint = 'No action needed — you\'re all set.';
    } else if (_message.contains('Location')) {
      hint = 'Go to Settings → Location and enable it.';
    } else {
      hint = 'Wait for the next QR and scan again.';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, value, child) => Transform.scale(
                scale: value,
                child: child,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _success ? Icons.check_rounded : Icons.close_rounded,
                  size: 56,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Status title
            Text(
              _success ? 'Attendance Recorded' : 'Could Not Mark Attendance',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            // Detail card
            Card(
              color: bgColor,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              label: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcode = capture.barcodes.first;
            if (barcode.rawValue != null) {
              _handleScan(barcode.rawValue!);
            }
          },
        ),
        // Scan overlay with cutout
        CustomPaint(
          painter: _ScanOverlayPainter(),
          child: const SizedBox.expand(),
        ),
        // Animated corner brackets
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.95, end: 1.05),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            // Restart animation by rebuilding
            onEnd: () => setState(() {}),
            child: SizedBox(
              width: 260,
              height: 260,
              child: CustomPaint(
                painter: _CornerBracketPainter(),
              ),
            ),
          ),
        ),
        // Processing overlay
        if (_isProcessing)
          Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: Center(
              child: Card(
                margin: const EdgeInsets.all(48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Verifying attendance...',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Checking QR, location & records',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Bottom instruction
        Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Point your camera at the QR code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints a semi-transparent overlay with a clear cutout in the center.
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final cutoutSize = 260.0;
    final left = (size.width - cutoutSize) / 2;
    final top = (size.height - cutoutSize) / 2;
    final cutout = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cutoutSize, cutoutSize),
      const Radius.circular(16),
    );
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Paints animated corner brackets around the scan area.
class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 32.0;
    const r = 12.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(len, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w, 0, w, r)
        ..lineTo(w, len),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, h - len)
        ..lineTo(0, h - r)
        ..quadraticBezierTo(0, h, r, h)
        ..lineTo(len, h),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(w - len, h)
        ..lineTo(w - r, h)
        ..quadraticBezierTo(w, h, w, h - r)
        ..lineTo(w, h - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}