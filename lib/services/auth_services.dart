import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Sign in with email and password
  Future<Map<String, dynamic>?> signIn(String email, String password) async {
  try {
    UserCredential result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    DocumentSnapshot doc =
        await _db.collection('users').doc(result.user!.uid).get();

    if (doc.exists) {
      Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
      userData['uid'] = result.user!.uid; // ← add this line
      return userData;
    }
    return null;
  } catch (e) {
    print('Login error: $e');
    return null;
  }
}

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}