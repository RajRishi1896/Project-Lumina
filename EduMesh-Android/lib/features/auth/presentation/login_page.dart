import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/lumina_stepper.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/password_strength.dart';
import '../../../pages/app_shell.dart';
import '../data/auth_service.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../core/network/api_client.dart';
import '../../../widgets/connection_gate.dart';
import 'profile_setup_page.dart';
import 'welcome_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// A page for student registration and login.
///
/// Provides toggling between register and login modes, form validation
/// (password strength checks), a hub-connection badge, and a password-reset
/// dialog flow. On successful auth it navigates to [ProfileSetupPage] (new
/// users) or [AppShell] (returning users).
///
/// Connection state is tracked via the [ConnectivityService] singleton --
/// inputs and buttons are disabled when the Hub is unreachable, and a
/// guidance message is shown prompting the user to connect.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _connectivity = ConnectivityService();
  
  bool _isLoading = false;
  bool _isRegisterMode = true;
  bool _obscurePassword = true;
  String? _errorMessage;
  
  // Gatekeeper state
  bool _isConnected = false;
  
  @override
  void initState() {
    super.initState();
    _isConnected = _connectivity.isOnline;
    _connectivity.addListener(_onConnectivityChange);
  }

  /// Updates [_isConnected] when the [ConnectivityService] reports a
  /// change in Hub reachability.
  void _onConnectivityChange() {
    if (mounted) {
      setState(() => _isConnected = _connectivity.isOnline);
    }
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChange);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_isConnected) return; // Prevent action if offline
    
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = AppLocalizations.of(context)!.errorFillAllFields);
      return;
    }
    if (_isRegisterMode) {
      final pwd = _passwordController.text;
      if (pwd.length < 8 || !pwd.contains(upperCaseRegExp) || !pwd.contains(lowerCaseRegExp) || !pwd.contains(digitRegExp)) {
        setState(() => _errorMessage = AppLocalizations.of(context)!.errorPasswordStrength);
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = AuthService();

    if (_isRegisterMode) {
      final error = await auth.register(
        username: _usernameController.text,
        password: _passwordController.text,
      );
      if (mounted) {
        if (error == null) {
          setState(() => _isLoading = false);
          if (!mounted) return;
          unawaited(Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ProfileSetupPage(username: _usernameController.text),
            ),
          ));
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = _mapRegisterError(error);
          });
        }
      }
      return;
    }

    final result = await auth.login(
      username: _usernameController.text,
      password: _passwordController.text,
    );

    if (mounted) {
      if (result == 'reset_required') {
        setState(() => _isLoading = false);
        unawaited(_showResetPasswordDialog());
      } else if (result == 'ok') {
        setState(() => _isLoading = false);
        if (!mounted) return;
        unawaited(Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ConnectionGate(child: AppShell()),
          ),
        ));
      } else if (result == 'local_only') {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.snackbarOfflineLogin),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        unawaited(Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ConnectionGate(child: AppShell()),
          ),
        ));
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.errorLoginFailed;
        });
      }
    }
  }

  /// Maps [AuthService] register error sentinels to localized messages.
  String _mapRegisterError(String? error) {
    final l10n = AppLocalizations.of(context)!;
    switch (error) {
      case 'username_taken':
        return l10n.errorUsernameTaken;
      case 'registration_failed':
        return l10n.errorRegistrationFailed;
      default:
        return error ?? l10n.errorRegistrationFailed;
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final newPwdController = TextEditingController();
    final confirmPwdController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool obscureNew = true;
        bool obscureConfirm = true;
        String? dialogError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
              title: Text(AppLocalizations.of(context)!.dialogPasswordResetTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppLocalizations.of(context)!.dialogPasswordResetBody),
                    SizedBox(height: AppSpacing.lg.h),
                    TextField(
                      controller: newPwdController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.labelNewPassword,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                          tooltip: obscureNew ? AppLocalizations.of(context)!.showPassword : AppLocalizations.of(context)!.hidePassword,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs.h),
                      child: Text(
                            AppLocalizations.of(context)!.hintPasswordRequirements,
                        style: tt.labelSmall?.copyWith(color: cs.outline),
                      ),
                    ),
                    SizedBox(height: AppSpacing.md.h),
                    TextField(
                      controller: confirmPwdController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.labelConfirmPassword,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                          tooltip: obscureConfirm ? AppLocalizations.of(context)!.showPassword : AppLocalizations.of(context)!.hidePassword,
                        ),
                      ),
                    ),
                    if (dialogError != null)
                      Padding(
                        padding: EdgeInsets.only(top: AppSpacing.sm.h),
                        child: Text(dialogError!, style: tt.bodySmall?.copyWith(color: cs.error)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(AppLocalizations.of(context)!.buttonCancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final pwd = newPwdController.text;
                    if (pwd.length < 8) {
                      setDialogState(() => dialogError = AppLocalizations.of(context)!.errorPasswordMinLength);
                      return;
                    }
                    if (pwd != confirmPwdController.text) {
                      setDialogState(() => dialogError = AppLocalizations.of(context)!.errorPasswordsDoNotMatch);
                      return;
                    }
                    if (!pwd.contains(upperCaseRegExp) || !pwd.contains(lowerCaseRegExp) || !pwd.contains(digitRegExp)) {
                      setDialogState(() => dialogError = AppLocalizations.of(context)!.errorPasswordComplexity);
                      return;
                    }
                    Navigator.of(ctx).pop(pwd);
                  },
                  child: Text(AppLocalizations.of(context)!.buttonSetPassword),
                ),
              ],
            );
          },
        );
      },
    );

    newPwdController.dispose();
    confirmPwdController.dispose();

    if (result == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ApiClient.post('/student/change-password', data: {
        'new_password': result,
      });
      if (!mounted) return;
      await AuthService().logout();
      if (!mounted) return;
      unawaited(Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomePage()),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = AppLocalizations.of(context)!.errorPasswordChangeFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: cs.primary),
        actions: [
          SizedBox(width: AppSpacing.sm.w),
          _buildConnectionBadge(),
          SizedBox(width: AppSpacing.lg.w),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LuminaStepper(currentStep: 1),
                SizedBox(height: AppSpacing.section.h),
                Text(
                  _isRegisterMode ? AppLocalizations.of(context)!.titleRegisterMode : AppLocalizations.of(context)!.titleLoginMode,
                  style: tt.displaySmall?.copyWith(
                    color: cs.primary,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: AppSpacing.sm.h),
                Text(
                  _isRegisterMode ? AppLocalizations.of(context)!.subtitleRegisterMode : AppLocalizations.of(context)!.subtitleLoginMode,
                  style: tt.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: AppSpacing.touchTarget.h),
                Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTextField(
                        controller: _usernameController,
                        label: AppLocalizations.of(context)!.labelUsername,
                        hint: AppLocalizations.of(context)!.hintUsername,
                        icon: Icons.person_outline,
                        enabled: _isConnected,
                      ),
                      SizedBox(height: AppSpacing.xl.h),
                      _buildTextField(
                        controller: _passwordController,
                        label: AppLocalizations.of(context)!.labelPassword,
                        hint: AppLocalizations.of(context)!.labelPassword,
                        icon: Icons.lock_outline,
                        isPassword: true,
                        obscureText: _obscurePassword,
                        onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                        enabled: _isConnected,
                      ),
                      if (_isRegisterMode) ...[
                        SizedBox(height: AppSpacing.xs.h),
                        Text(
                      AppLocalizations.of(context)!.hintPasswordRequirements,
                          style: tt.labelSmall?.copyWith(color: cs.outline),
                        ),
                      ],
                      if (_errorMessage != null) ...[
                        SizedBox(height: AppSpacing.lg.h),
                        Text(
                          _errorMessage!,
                          style: tt.bodySmall?.copyWith(color: cs.error),
                        ),
                      ],
                      SizedBox(height: AppSpacing.section.h),
                      if (_isLoading)
                        Center(child: CircularProgressIndicator(color: cs.tertiary))
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isConnected ? _handleAuth : () {},
                            child: Text(_isRegisterMode ? AppLocalizations.of(context)!.buttonRegister : AppLocalizations.of(context)!.buttonLogin),
                          ),
                        ),
                      if (!_isConnected)
                        Padding(
                          padding: EdgeInsets.only(top: AppSpacing.md.h),
                          child: Text(
                            AppLocalizations.of(context)!.loginConnectToHub,
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(color: cs.outline),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.xxl.h),
                Center(
                  child: TextButton(
                    onPressed: _isConnected 
                      ? () => setState(() => _isRegisterMode = !_isRegisterMode) 
                      : null,
                    child: Text(
                      _isRegisterMode
                          ? AppLocalizations.of(context)!.toggleToLogin
                          : AppLocalizations.of(context)!.toggleToRegister,
                      style: tt.titleSmall?.copyWith(
                        color: _isConnected ? cs.secondary : cs.outline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBadge() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 200.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.xs.h),
        decoration: BoxDecoration(
          color: _isConnected ? cs.tertiaryContainer.withValues(alpha: 0.1) : cs.errorContainer.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg.r),
          border: Border.all(
            color: _isConnected ? cs.tertiary : cs.error,
          ),
        ),
        child: Text(
          _isConnected ? AppLocalizations.of(context)!.badgeHubConnected : AppLocalizations.of(context)!.badgeWaitingForHub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(
            color: _isConnected ? cs.onTertiaryContainer : cs.onErrorContainer,
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
    bool obscureText = true,
    VoidCallback? onToggleObscure,
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.titleSmall?.copyWith(
            color: enabled ? cs.onSurface : cs.outline,
          ),
        ),
        SizedBox(height: AppSpacing.sm.h),
        TextField(
          controller: controller,
          obscureText: isPassword ? obscureText : false,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: enabled ? cs.primary : cs.outline, size: 20.sp),
            suffixIcon: isPassword && onToggleObscure != null
                ? IconButton(
                    icon: Icon(obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: onToggleObscure,
                    tooltip: obscureText ? AppLocalizations.of(context)!.showPassword : AppLocalizations.of(context)!.hidePassword,
                  )
                : null,
            filled: true,
            fillColor: enabled ? cs.surface : cs.surfaceContainerHighest,
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
