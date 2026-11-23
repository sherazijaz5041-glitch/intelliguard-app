import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../services/cloud_api.dart';
import '../theme/app_theme.dart';

enum _Mode { signIn, register, confirm, recoveryEmail, recoveryCode, newPassword }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();
  final _code     = TextEditingController();
  int _passwordFieldKey = 0;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  static String _cleanEmail(String input) {
    return input.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF\u00A0]'), '').toLowerCase();
  }

  void _changeMode(_Mode mode) {
    _email.text = _cleanEmail(_email.text);
    _password.clear();
    _confirm.clear();
    _code.clear();
    _passwordFieldKey++;
    setState(() {
      _mode = mode;
      _message = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final auth = context.read<AuthProvider>();
    final email = _cleanEmail(_email.text);
    final password = _password.text;
    final code = _code.text.trim();

    if (_mode != _Mode.newPassword && (email.isEmpty || !email.contains('@'))) {
      setState(() => _message = 'Enter a valid email address.');
      return;
    }
    if ((_mode == _Mode.register || _mode == _Mode.newPassword) &&
        (password.length < 8 || password != _confirm.text)) {
      setState(() => _message = 'Use at least 8 characters and matching passwords.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      switch (_mode) {
        case _Mode.signIn:
          await auth.signIn(email, password);
          break;
        case _Mode.register:
          final needsConfirmation = await auth.signUp(email, password);
          if (mounted && needsConfirmation) {
            setState(() {
              _mode = _Mode.confirm;
              _message = 'Account created!\n\n'
                  'Check your inbox (and spam/junk folder) for a 6-digit code.\n\n'
                  'No email after 2 minutes? Tap "Resend code" below, or '
                  'disable "Confirm email" in Supabase Dashboard '
                  '(Authentication → Providers → Email).';
            });
          }
          break;
        case _Mode.confirm:
          await auth.confirmEmail(email, code);
          break;
        case _Mode.recoveryEmail:
          await auth.sendRecovery(email);
          if (mounted) {
            setState(() {
              _mode = _Mode.recoveryCode;
              _message = 'If this account exists, a recovery code will be sent. Check your inbox and spam folder.';
            });
          }
          break;
        case _Mode.recoveryCode:
          await auth.verifyRecovery(email, code);
          if (mounted) {
            setState(() {
              _mode = _Mode.newPassword;
              _password.clear();
              _confirm.clear();
              _passwordFieldKey++;
            });
          }
          break;
        case _Mode.newPassword:
          await auth.setRecoveredPassword(password);
          break;
      }
    } catch (e) {
      if (mounted) {
        if (e is AuthException &&
            (e.message.toLowerCase().contains('email not confirmed') ||
             e.message.toLowerCase().contains('email_not_confirmed'))) {
          setState(() {
            _mode = _Mode.confirm;
            _message = 'Email not confirmed yet.\n\n'
                'Enter the 6-digit code from your email, or tap "Resend code".\n\n'
                'Tip: If no email arrives, go to Supabase Dashboard → '
                'Authentication → Users → click your email → Confirm.';
          });
        } else if (isConnectionFailure(e)) {
          setState(() => _message = 'Could not reach Supabase.\n\n'
              '• Check your phone\'s internet connection\n'
              '• Make sure Wi-Fi or mobile data is on\n'
              '• Try again in a few seconds');
        } else {
          setState(() => _message = friendlyCloudError(e));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await context.read<AuthProvider>().resendConfirmation(_email.text);
      if (mounted) {
        setState(() => _message = 'Confirmation code requested. Check inbox and spam folder.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = friendlyCloudError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final waiting = auth.hasCloudSession && !auth.recovering;
    final title = switch (_mode) {
      _Mode.signIn        => 'Sign in',
      _Mode.register      => 'Create account',
      _Mode.confirm       => 'Confirm email',
      _Mode.recoveryEmail => 'Reset password',
      _Mode.recoveryCode  => 'Enter recovery code',
      _Mode.newPassword   => 'Set new password',
    };
    final needsPassword = [_Mode.signIn, _Mode.register, _Mode.newPassword].contains(_mode);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_outlined, size: 62, color: AppColors.accentPrimary),
                  const SizedBox(height: 16),
                  const Text('IntelliGuard', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Shared campus security', textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  if (waiting) ...[
                    const Text('Organization access', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(auth.username ?? '', style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 12),
                    if (auth.error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Text(auth.error!, style: const TextStyle(fontSize: 13, height: 1.4)),
                      )
                    else
                      const Text('Ask the admin to approve your account from the Account tab, then tap Check access.'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : () async {
                        setState(() => _busy = true);
                        await auth.refreshAccess();
                        if (mounted) {
                          setState(() => _busy = false);
                          if (auth.isLoggedIn) return; // success — _RootRouter rebuilds
                          setState(() => _message = auth.error ?? 'Access not yet approved. Ask your admin.');
                        }
                      },
                      icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                      label: Text(_busy ? 'Checking…' : 'Check access'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : () async {
                        try {
                          await auth.logout();
                        } catch (e) {
                          if (mounted) setState(() => _message = friendlyCloudError(e));
                        }
                      },
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Sign out'),
                    ),
                  ] else ...[
                    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    if (_mode != _Mode.newPassword)
                      TextField(
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'[\s\u200B-\u200D\uFEFF\u00A0]')),
                        ],
                        autofillHints: const [AutofillHints.email],
                        textInputAction: needsPassword ? TextInputAction.next : TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                    if (needsPassword) ...[
                      const SizedBox(height: 14),
                      TextField(
                        key: ValueKey('pw_$_passwordFieldKey'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscurePassword,
                        autofillHints: _mode == _Mode.signIn ? const [AutofillHints.password] : const [AutofillHints.newPassword],
                        textInputAction: _mode == _Mode.signIn ? TextInputAction.done : TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        onSubmitted: _mode == _Mode.signIn ? (_) => _submit() : null,
                      ),
                    ],
                    if (_mode == _Mode.register || _mode == _Mode.newPassword) ...[
                      const SizedBox(height: 14),
                      TextField(
                        key: ValueKey('cp_$_passwordFieldKey'),
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: _obscureConfirm,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_mode == _Mode.confirm || _mode == _Mode.recoveryCode) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _code,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Email code',
                          hintText: '6-digit code from your inbox',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy ? 'Please wait...' : title),
                    ),
                    if (_mode == _Mode.signIn) ...[
                      TextButton(onPressed: _busy ? null : () => _changeMode(_Mode.register), child: const Text('Create an account')),
                      TextButton(onPressed: _busy ? null : () => _changeMode(_Mode.recoveryEmail), child: const Text('Forgot password?')),
                      TextButton(onPressed: _busy ? null : () => _changeMode(_Mode.confirm), child: const Text('Confirm an existing email')),
                    ],
                    if (_mode == _Mode.confirm) TextButton(onPressed: _busy ? null : _resend, child: const Text('Resend code')),
                    if (_mode != _Mode.signIn)
                      TextButton(
                        onPressed: _busy ? null : () async {
                          if (auth.recovering) await auth.logout();
                          if (mounted) _changeMode(_Mode.signIn);
                        },
                        child: const Text('Back to sign in'),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'New accounts need administrator approval before accessing cameras and events.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    if (auth.error != null)
                      Padding(padding: const EdgeInsets.only(top: 12), child: Text(auth.error!)),
                  ],
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _message!,
                          style: const TextStyle(fontSize: 13, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
