import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../widgets/ui_blocks.dart';

class StartSessionScreen extends StatefulWidget {
  final String teacherId;
  final String subjectId;
  final String subjectName;
  final String division;
  final String type;

  const StartSessionScreen({
    super.key,
    required this.teacherId,
    required this.subjectId,
    required this.subjectName,
    required this.division,
    required this.type,
  });

  @override
  State<StartSessionScreen> createState() => _StartSessionScreenState();
}

class _StartSessionScreenState extends State<StartSessionScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _sessionId;
  String _currentToken = '';
  Timer? _tokenRefreshTimer;
  bool _sessionStarted = false;
  bool _isValidSetup = false;
  bool _isCheckingSetup = true;
  int _secondsLeft = 25;
  Timer? _countdownTimer;
  StreamSubscription<Position>? _locationSubscription;
  Position? _teacherPosition;
  bool _locationReady = false;
  bool _isAcquiringLocation = false;
  double _radiusMetres = 50;

  @override
  void initState() {
    super.initState();
    // Start GPS acquisition immediately so it's ready by the time
    // the user taps "Start Session" — eliminates the 3-15s cold-start wait.
    _startLocationTracking();
    _validateSetup();
  }

  Future<void> _validateSetup() async {
    // Run both Firestore reads in parallel instead of sequentially.
    final results = await Future.wait([
      _db.collection('subjects').doc(widget.subjectId).get(),
      _db
          .collection('schedule')
          .where('subjectId', isEqualTo: widget.subjectId)
          .where('division', isEqualTo: widget.division)
          .where('type', isEqualTo: widget.type)
          .limit(1)
          .get(),
    ]);

    final subject = results[0] as DocumentSnapshot;
    final schedule = results[1] as QuerySnapshot;

    if (!subject.exists || subject.data() is! Map<String, dynamic> ||
        (subject.data() as Map<String, dynamic>)['teacherId'] != widget.teacherId) {
      if (!mounted) return;
      setState(() {
        _isValidSetup = false;
        _isCheckingSetup = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isValidSetup = schedule.docs.isNotEmpty;
      _isCheckingSetup = false;
    });
  }

  String _generateToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<bool> _startLocationTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable location services to start session.')),
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required.')),
      );
      return false;
    }

    // Get an immediate position first — getPositionStream with distanceFilter
    // may not fire its first event until the device moves, which blocks session start.
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return false;
      setState(() {
        _teacherPosition = position;
        _locationReady = true;
      });
    } catch (e) {
      // getCurrentPosition failed — we'll still try the stream below.
    }

    // Start the stream for live location updates during the session.
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 5,
      ),
    ).listen((position) async {
      if (!mounted) return;
      setState(() {
        _teacherPosition = position;
        _locationReady = true;
      });
      if (_sessionId != null) {
        await _db.collection('sessions').doc(_sessionId).update({
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
      }
    });

    return true;
  }

  Future<void> _startSession() async {
    if (!_isValidSetup) return;
    setState(() => _isAcquiringLocation = true);

    // If location tracking failed during initState (e.g. permission wasn't
    // granted yet), retry it now.
    if (_locationSubscription == null) {
      final locationOk = await _startLocationTracking();
      if (!locationOk) {
        if (mounted) setState(() => _isAcquiringLocation = false);
        return;
      }
    }

    // Wait for GPS to deliver a position (up to 10 seconds).
    for (var i = 0; i < 20; i++) {
      if (_locationReady) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    if (_teacherPosition == null) {
      setState(() => _isAcquiringLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get current location. Try again.')),
      );
      return;
    }
    setState(() => _isAcquiringLocation = false);
    final token = _generateToken();
    final now = DateTime.now();

    final sessionRef = await _db.collection('sessions').add({
      'subjectId': widget.subjectId,
      'teacherId': widget.teacherId,
      'date': now.toIso8601String().split('T')[0],
      'type': widget.type,
      'division': widget.division,
      'batch': null,
      'qrToken': token,
      'tokenExpiry': Timestamp.fromDate(
        now.add(const Duration(seconds: 25)),
      ),
      'isActive': true,
      'latitude': _teacherPosition!.latitude,
      'longitude': _teacherPosition!.longitude,
      'radiusMetres': _radiusMetres,
    });

    setState(() {
      _sessionId = sessionRef.id;
      _currentToken = token;
      _sessionStarted = true;
      _secondsLeft = 25;
    });

    _startTokenRefresh();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  void _startTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(Duration(seconds: 25), (_) async {
      final newToken = _generateToken();
      final expiry = DateTime.now().add(Duration(seconds: 25));

      await _db.collection('sessions').doc(_sessionId).update({
        'qrToken': newToken,
        'tokenExpiry': Timestamp.fromDate(expiry),
      });

      setState(() {
        _currentToken = newToken;
        _secondsLeft = 25;
      });

      _startCountdown();
    });
  }

  Future<void> _endSession() async {
    _tokenRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _locationSubscription?.cancel();

    if (_sessionId != null) {
      await _db.collection('sessions').doc(_sessionId).update({
        'isActive': false,
        'qrToken': null,
      });
    }

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _tokenRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.type == 'lab' ? 'Lab session' : 'Lecture session',
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      widget.subjectName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Division ${widget.division} • '
                      '${widget.type == 'lab' ? 'Lab' : 'Lecture'}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 32),

            if (_isCheckingSetup) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Verifying subject and schedule setup...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],

            if (!_isCheckingSetup && !_isValidSetup) ...[
              Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange[700]),
              const SizedBox(height: 12),
              Text(
                'Session cannot be started.\nAdmin must assign this subject/division with ${widget.type}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go back'),
              ),
            ],

            if (!_sessionStarted && !_isCheckingSetup && _isValidSetup) ...[
              const EmptyStateCard(
                message: 'Start session to generate attendance QR code.',
                hint: 'Students can scan and mark attendance instantly.',
                icon: Icons.qr_code_2_outlined,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Allowed check-in radius',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.radar, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${_radiusMetres.toStringAsFixed(0)} metres',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Slider(
                value: _radiusMetres,
                min: 10,
                max: 100,
                divisions: 18,
                label: '${_radiusMetres.toStringAsFixed(0)} m',
                onChanged: (v) => setState(() => _radiusMetres = v),
              ),
              Text(
                'Students must be within this distance from your position.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 24),
              if (_isAcquiringLocation) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  'Getting your location...',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ] else
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Session'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _startSession,
                ),
            ],

            if (_sessionStarted) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      _teacherPosition != null
                          ? 'Live anchor active • ${_radiusMetres.toStringAsFixed(0)} m radius'
                          : 'Acquiring location...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const AppSectionHeader(
                title: 'Session is live',
                subtitle: 'Show this QR code to students in class',
              ),
              SizedBox(height: 16),

              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _currentToken,
                  version: QrVersions.auto,
                  size: 250,
                ),
              ),

              SizedBox(height: 16),

              Text(
                'QR refreshes in $_secondsLeft seconds',
                style: TextStyle(
                  fontSize: 14,
                  color: _secondsLeft <= 10 ? Colors.red : Colors.grey[600],
                ),
              ),

              SizedBox(height: 8),

              LinearProgressIndicator(
                value: _secondsLeft / 25,
                backgroundColor: Colors.grey[300],
                color: _secondsLeft <= 10 ? Colors.red : Colors.green,
              ),

              SizedBox(height: 32),

              ElevatedButton.icon(
                icon: Icon(Icons.stop),
                label: Text('End Session'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _endSession,
              ),
            ],
          ],
        ),
      ),
    );
  }
}