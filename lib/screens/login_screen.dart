import 'package:flutter/material.dart';
import '../services/auth_services.dart';
import 'admin/admin_dashboard.dart';
import 'student/student_dashboard.dart';
import 'teacher/teacher_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String _errorMessage = '';

  void _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final userData = await _authService.signIn(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (userData == null) {
      setState(() {
        _errorMessage = 'Invalid email or password.';
      });
      return;
    }

    final role = userData['role']?.toString();
    if (role == 'student') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StudentDashboard(userData: userData),
        ),
      );
    } else if (role == 'teacher') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherDashboard(userData: userData),
        ),
      );
    } else if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboard(userData: userData),
        ),
      );
    } else {
      setState(() {
        _errorMessage = 'Unknown account role. Contact admin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.school_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              SizedBox(height: 16),
              Text(
                'CEMS',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'College attendance & schedule',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              SizedBox(height: 40),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 24),
              if (_errorMessage.isNotEmpty)
                Text(_errorMessage, style: TextStyle(color: Colors.red)),
              SizedBox(height: 8),
              _isLoading
                  ? CircularProgressIndicator()
                  : FilledButton(
                      onPressed: _login,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                      ),
                      child: Text('Sign in'),
                    ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}