import 'package:flutter/material.dart';

import '../session.dart';
import '../utils.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      Session.user = await Session.api.getMe();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editName() async {
    final n = await promptText(context,
        title: 'Seu nome', initial: Session.user?.name ?? '');
    if (n == null) return;
    try {
      await Session.api.updateUser(name: n);
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editImage() async {
    final url = await promptText(context,
        title: 'URL da foto de perfil',
        initial: Session.user?.image ?? '',
        hint: 'https://...',
        keyboardType: TextInputType.url);
    if (url == null) return;
    try {
      await Session.api.updateUser(image: url);
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setPassword() async {
    final p = await promptText(context,
        title: 'Nova senha', hint: 'Mínimo de 8 caracteres');
    if (p == null) return;
    if (p.length < 8) {
      if (mounted) showMsg(context, 'A senha precisa ter ao menos 8 caracteres');
      return;
    }
    try {
      await Session.api.setPassword(p);
      if (mounted) showMsg(context, 'Senha definida');
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: MemberAvatar(
                name: u?.displayName ?? '?', image: u?.image, radius: 44),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Nome'),
            subtitle: Text(u?.name ?? '-'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editName,
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('E-mail'),
            subtitle: Text(u?.email ?? '-'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Foto de perfil (URL)'),
            subtitle: Text(u?.image ?? 'Nenhuma',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editImage,
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: Text(u?.hasPassword == true ? 'Alterar senha' : 'Definir senha'),
            onTap: _setPassword,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servidor'),
            subtitle: Text(Session.siteUrl),
          ),
        ],
      ),
    );
  }
}
