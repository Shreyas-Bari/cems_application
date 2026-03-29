import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  int _secondsLeft = 15;
  Timer? _countdownTimer;

  String _generateToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _startSession() async {
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
        now.add(Duration(seconds: 15)),
      ),
      'isActive': true,
    });

    setState(() {
      _sessionId = sessionRef.id;
      _currentToken = token;
      _sessionStarted = true;
      _secondsLeft = 15;
    });

    _startTokenRefresh();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
      });
    });
  }

  void _startTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(Duration(seconds: 15), (_) async {
      final newToken = _generateToken();
      final expiry = DateTime.now().add(Duration(seconds: 15));

      await _db.collection('sessions').doc(_sessionId).update({
        'qrToken': newToken,
        'tokenExpiry': Timestamp.fromDate(expiry),
      });

      setState(() {
        _currentToken = newToken;
        _secondsLeft = 15;
      });

      _startCountdown();
    });
  }

  Future<void> _endSession() async {
    _tokenRefreshTimer?.cancel();
    _countdownTimer?.cancel();

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

            if (!_sessionStarted) ...[
              Text(
                'Press the button below to start the session and generate a QR code for attendance.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(Icons.play_arrow),
                label: Text('Start Session'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: _startSession,
              ),
            ],

            if (_sessionStarted) ...[
              Text(
                'Show this QR code to your students',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
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
                value: _secondsLeft / 15,
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