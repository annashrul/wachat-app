import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../widgets/avatar.dart';
import '../widgets/primary_button.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  String? _avatarUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().user;
    _name = TextEditingController(text: u?.displayName ?? '');
    _about = TextEditingController(text: u?.about ?? '');
    _avatarUrl = u?.avatarUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final svc = context.read<ChatProvider>().service;
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final up = await svc.uploadFile(bytes, picked.name);
      setState(() => _avatarUrl = up.url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().updateProfile(
            displayName: _name.text.trim(),
            about: _about.text.trim(),
            avatarUrl: _avatarUrl,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil diperbarui')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                children: [
                  Avatar(url: _avatarUrl, name: _name.text, radius: 56),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _uploading ? null : _pickAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.surface,
                            width: 2,
                          ),
                        ),
                        child: _uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text('Nama',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Tentang',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _about,
              maxLength: 140,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.info_outline_rounded),
                hintText: 'Hey there! I am using WAChat.',
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Simpan',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
