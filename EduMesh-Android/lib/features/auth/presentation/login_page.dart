import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/lumina_button.dart';
import '../../../shared/widgets/lumina_card.dart';
import '../../../shared/widgets/lumina_stepper.dart';
import '../../../pages/app_shell.dart';
import '../data/auth_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/connection_service.dart';
import '../../../widgets/connection_gate.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final ConnectionService _connectionService = ConnectionService();
  
  bool _isLoading = false;
  bool _isRegisterMode = true;
  String? _errorMessage;
  
  // Gatekeeper state
  bool _isConnected = false;
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    _startGatekeeper();
  }

  void _startGatekeeper() {
    // Check immediately, then every 3 seconds
    _checkHub();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkHub());
  }

  Future<void> _checkHub() async {
    final connected = await _connectionService.ping(timeout: const Duration(seconds: 2));
    if (mounted && _isConnected != connected) {
      setState(() => _isConnected = connected);
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_isConnected) return; // Prevent action if offline
    
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = AuthService();
    final sync = SyncService();

    final success = _isRegisterMode
        ? await auth.register(
            username: _usernameController.text,
            password: _passwordController.text,
          )
        : await auth.login(
            username: _usernameController.text,
            password: _passwordController.text,
          );

    if (mounted) {
      if (success) {
        if (!_isRegisterMode) {
          await sync.restoreProfile();
        }
        
        setState(() => _isLoading = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ConnectionGate(child: AppShell()),
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = _isRegisterMode 
              ? 'Registration failed. Check Hub connection.' 
              : 'Login failed. Invalid name or password.';
        });
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
        actions: [
          _buildConnectionBadge(),
          SizedBox(width: 16.w),
        ],
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
                  _isRegisterMode 
                    ? 'Start your journey on the Lumina Mesh' 
                    : 'Access your lessons from any device',
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
                        label: 'Full Name',
                        hint: 'e.g. John Doe',
                        icon: Icons.person_outline,
                        enabled: _isConnected,
                      ),
                      SizedBox(height: 20.h),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: '••••••••',
                        icon: Icons.lock_outline,
                        isPassword: true,
                        enabled: _isConnected,
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
                        const Center(child: CircularProgressIndicator(color: Color(0xFFF8BC4B)))
                      else
                        Opacity(
                          opacity: _isConnected ? 1.0 : 0.5,
                          child: LuminaButton(
                            label: _isRegisterMode ? 'Register & Sync' : 'Login & Sync',
                            onPressed: _isConnected ? _handleAuth : () {},
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 24.h),
                Center(
                  child: TextButton(
                    onPressed: _isConnected 
                      ? () => setState(() => _isRegisterMode = !_isRegisterMode) 
                      : null,
                    child: Text(
                      _isRegisterMode
                          ? 'Already have an account? Login'
                          : "Don't have an account? Register",
                      style: GoogleFonts.atkinsonHyperlegible(
                        color: _isConnected ? cs.secondary : Colors.grey,
                        fontWeight: FontWeight.w700,
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

  Widget _buildConnectionBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: _isConnected ? Colors.green : Colors.red,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            _isConnected ? 'Hub Connected' : 'Waiting for Hub...',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: _isConnected ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool enabled = true,
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
            color: enabled ? cs.onSurface : Colors.grey,
          ),
        ),
        SizedBox(height: 8.h),
        TextField(
          controller: controller,
          obscureText: isPassword,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: enabled ? cs.primary : Colors.grey, size: 20.sp),
            filled: true,
            fillColor: enabled ? Colors.white : Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }
}
