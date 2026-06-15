import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().register(
            _phone.text.trim(),
            _name.text.trim(),
            _password.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Buat akun')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Daftar gratis & mulai mengobrol',
                    style: TextStyle(color: palette.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  _label('Nama tampilan'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      hintText: 'mis. Budi Santoso',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 18),
                  _label('Nomor telepon'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '08xxxxxxxxxx',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                      final ok = RegExp(r'^\+?[0-9]{8,15}$').hasMatch(v.trim());
                      return ok ? null : 'Nomor tidak valid (8-15 digit)';
                    },
                  ),
                  const SizedBox(height: 18),
                  _label('Password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'Minimal 6 karakter',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Minimal 6 karakter' : null,
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: 'Daftar',
                    loading: _loading,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Dengan mendaftar, Anda setuju dengan ketentuan layanan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.muted, fontSize: 12),
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

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      );
}
