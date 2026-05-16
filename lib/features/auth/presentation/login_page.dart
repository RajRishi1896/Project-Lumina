import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/lumina_button.dart';
import '../../../shared/widgets/lumina_card.dart';
import '../../../shared/widgets/lumina_stepper.dart';
import '../../../pages/app_shell.dart';
import '../data/auth_service.dart';
import '../../../widgets/connection_gate.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isRegisterMode = false;
  String? _errorMessage;

  Future<void> _handleAuth() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = _isRegisterMode
        ? await AuthService().register(
            username: _usernameController.text,
            password: _passwordController.text,
          )
        : await AuthService().login(
            username: _usernameController.text,
            password: _passwordController.text,
          );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        final userId = await AuthService().getUniqueUserId();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isRegisterMode 
                  ? 'Registration Successful! ID: $userId' 
                  : 'Login Successful!'),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const ConnectionGate(child: AppShell()),
            ),
          );
        }
      } else {
        setState(() => _errorMessage = _isRegisterMode 
            ? 'Registration failed. Username may already exist.' 
            : 'Login failed. Invalid username or password.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: cs.primary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LuminaStepper(currentStep: 1),
                SizedBox(height: 32.h),
                Text(
                  _isRegisterMode ? 'Create Scholar\nIdentity' : 'Scholar\nLogin',
                  style: GoogleFonts.atkinsonHyperlegible(
                    fontSize: 36.sp,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Secure access to your learning portal',
                  style: GoogleFonts.atkinsonHyperlegible(
                    fontSize: 16.sp,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 48.h),
                LuminaCard(
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTextField(
                        controller: _usernameController,
                        label: 'Username',
                        hint: 'e.g. scholar_john',
                        icon: Icons.person_outline,
                      ),
                      SizedBox(height: 20.h),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: '••••••••',
                        icon: Icons.lock_outline,
                        isPassword: true,
                      ),
                      if (_errorMessage != null) ...[
                        SizedBox(height: 16.h),
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: cs.error, fontSize: 12.sp),
                        ),
                      ],
                      SizedBox(height: 32.h),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        LuminaButton(
                          label: _isRegisterMode ? 'Register & Sync' : 'Login & Sync',
                          onPressed: _handleAuth,
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 24.h),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isRegisterMode = !_isRegisterMode),
                    child: Text(
                      _isRegisterMode
                          ? 'Already have an account? Login'
                          : "Don't have an account? Register",
                      style: GoogleFonts.atkinsonHyperlegible(
                        color: cs.secondary,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.atkinsonHyperlegible(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        SizedBox(height: 8.h),
        TextField(
          controller: controller,
          obscureText: isPassword,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: cs.primary, size: 20.sp),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
