import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../utils/local_storage.dart';
import '../models/user.dart';

class LoginModal extends StatefulWidget {
  const LoginModal({super.key});

  @override
  State<LoginModal> createState() => _LoginModalState();
}

class _LoginModalState extends State<LoginModal> {
  bool _showRollLogin = false;
  bool _isLoading = false;
  final TextEditingController _rollNoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Google Sign-In instance (will be configured with user's keys later)
  late GoogleSignIn _googleSignIn;
  
  @override
  void initState() {
    super.initState();
    // Initialize Google Sign-In with placeholder configuration
    // User will provide actual keys later
    _googleSignIn = GoogleSignIn(
      scopes: [
        'email',
        'profile',
      ],
    );
  }
  
  @override
  void dispose() {
    _rollNoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  void _toggleRollLogin() {
    setState(() {
      _showRollLogin = !_showRollLogin;
    });
  }
  
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Attempt to sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // Sign in was canceled by the user
        return;
      }
      
      // Get authentication details
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;
      
      // Create user object with Google account info
      final user = User(
        name: googleUser.displayName ?? 'Google User',
        email: googleUser.email,
        rollNo: '', // Not applicable for Google login
        familyName: googleUser.displayName?.split(' ').last ?? 'User',
        token: googleAuth.idToken ?? '',
      );
      
      // Save user data
      await LocalStorage.saveUser(user);
      
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Google Sign-In successful!')),
        );
      }
    } catch (error) {
      print('Google Sign-In error: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Google Sign-In failed. Please try again.')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _submitLogin() async {
    final rollNo = _rollNoController.text.trim();
    final password = _passwordController.text.trim();
    
    if (rollNo.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Enter Roll No and Password!')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // In a real app, you would send this to your WebSocket service
      // For now, we'll just simulate a successful login
      final user = User(
        name: 'Student',
        email: '$rollNo@vnrvjiet.in',
        rollNo: rollNo,
        familyName: rollNo,
        token: 'sample_token',
      );
      
      // Save user data
      await LocalStorage.saveUser(user);
      
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Login successful!')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Login failed. Please try again.')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Login',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          if (!_showRollLogin) ...[
            // Google login button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.account_circle),
                label: const Text('Sign in with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 15),
            
            // Divider with "or" text
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            
            const SizedBox(height: 15),
            
            // Roll login option
            TextButton(
              onPressed: _toggleRollLogin,
              child: const Text(
                'Login with Roll No',
                style: TextStyle(
                  fontSize: 16,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ] else ...[
            // Roll number login form
            TextField(
              controller: _rollNoController,
              decoration: const InputDecoration(
                labelText: 'Roll No',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            
            const SizedBox(height: 15),
            
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitLogin,
                child: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Submit'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 10),
            
            TextButton(
              onPressed: _toggleRollLogin,
              child: const Text(
                'Back to Google Login',
                style: TextStyle(
                  fontSize: 16,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
