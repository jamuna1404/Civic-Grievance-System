import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isCitizen = true;
  bool _otpSent = false;
  bool _isLoading = false;

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleStaffLogin() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (response.session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCitizenSendOTP() async {
    setState(() => _isLoading = true);
    try {
      // Supabase OTP login (using Email OTP or Phone OTP)
      await _supabase.auth.signInWithOtp(
        email: _emailController.text.trim(),
        shouldCreateUser: true,
      );
      setState(() => _otpSent = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP sent to your email. Please check your inbox.'),
            backgroundColor: Colors.skyBlueAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send OTP: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCitizenVerifyOTP() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase.auth.verifyOTP(
        token: _otpController.text.trim(),
        type: OtpType.email,
        email: _emailController.text.trim(),
      );
      if (response.session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid OTP: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Premium dark design system colors
    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Premium Brand Header
                const Icon(
                  Icons.account_balance_outlined,
                  size: 64,
                  color: primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'CivicRoute',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Intelligent Grievance Resolution Portal',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.slateRescale ?? Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Card Container
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Citizen vs Staff Tab Switcher
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Citizen'),
                                selected: _isCitizen,
                                onSelected: (val) {
                                  setState(() {
                                    _isCitizen = true;
                                    _otpSent = false;
                                  });
                                },
                                selectedColor: primaryColor,
                                labelStyle: TextStyle(
                                  color: _isCitizen ? Colors.white : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Staff'),
                                selected: !_isCitizen,
                                onSelected: (val) {
                                  setState(() {
                                    _isCitizen = false;
                                  });
                                },
                                selectedColor: primaryColor,
                                labelStyle: TextStyle(
                                  color: !_isCitizen ? Colors.white : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Dynamic login forms based on selected tab
                        if (_isCitizen) ...[
                          // Citizen Form
                          if (!_otpSent) ...[
                            Text(
                              'Submit or track your complaint using passwordless OTP login.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[300]),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emailController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email_outlined, color: Colors.grey),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleCitizenSendOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Send Verification OTP', style: TextStyle(color: Colors.white)),
                            ),
                          ] else ...[
                            Text(
                              'Enter the 6-digit OTP code sent to ${_emailController.text}.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[300]),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _otpController,
                              style: const TextStyle(color: Colors.white, letterSpacing: 8),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'OTP Code',
                                labelStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleCitizenVerifyOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Verify & Sign In', style: TextStyle(color: Colors.white)),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _otpSent = false),
                              child: const Text('Change email address', style: TextStyle(color: primaryColor)),
                            ),
                          ],
                        ] else ...[
                          // Staff Form
                          Text(
                            'Administrative and Field Officer portal.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[300]),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _emailController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Staff Email',
                              labelStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.badge_outlined, color: Colors.grey),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            style: const TextStyle(color: Colors.white),
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              labelStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock_outline, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleStaffLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Login to Dashboard', style: TextStyle(color: Colors.white)),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Minimal utility to avoid compilation failures on older flutter SDK configurations
extension on Colors {
  static Color? get slateRescale => const Color(0xFF94A3B8);
}
