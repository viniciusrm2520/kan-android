import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../session.dart';
import '../utils.dart';

/// Configurações do workspace: geral, membros/convites e webhooks.
/// Retorna true se algo mudou.
class WorkspaceSettingsScreen extends StatefulWidget {
  const WorkspaceSettingsScreen({super.key, required this.workspace});
  final Workspace workspace;

  @override
  State<WorkspaceSettingsScreen> createState() =>
      _WorkspaceSettingsScreenState();
}

class _WorkspaceSettingsScreenState extends State<WorkspaceSettingsScreen> {
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.workspace.name),
            bottom: const TabBar(tabs: [
              Tab(text: 'Geral'),
              Tab(text: 'Membros'),
              Tab(text: 'Webhooks'),
            ]),
          ),
          body: TabBarView(children: [
            _GeneralTab(
                workspace: widget.workspace,
                onChanged: () => _changed = true),
            _MembersTab(workspace: widget.workspace),
            _WebhooksTab(workspace: widget.workspace),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Geral

class _GeneralTab extends StatefulWidget {
  const _GeneralTab({required this.workspace, required this.onChanged});
  final Workspace workspace;
  final VoidCallback onChanged;

  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab>
    with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _desc = TextEditingController();
  bool _showEmails = false;
  int _weekStart = 1;
  bool _loading = true;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  String get _id => widget.workspace.publicId;

  @override
  void initState() {
    super.initState();
    _name.text = widget.workspace.name;
    _slug.text = widget.workspace.slug;
    _desc.text = widget.workspace.description ?? '';
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Session.api.getWorkspace(_id);
      if (!mounted) return;
      setState(() {
        _name.text = d.name;
        _slug.text = d.slug;
        _showEmails = d.showEmailsToMembers;
        _weekStart = d.weekStartDay ?? 1;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final slug = _slug.text.trim();
      if (slug != widget.workspace.slug &&
          !await Session.api.isWorkspaceSlugAvailable(slug, workspaceId: _id)) {
        throw Exception('Este slug não está disponível.');
      }
      await Session.api.updateWorkspace(_id,
          name: _name.text.trim(),
          slug: slug,
          description: _desc.text.trim(),
          showEmailsToMembers: _showEmails,
          weekStartDay: _weekStart);
      widget.onChanged();
      if (mounted) showMsg(context, 'Workspace atualizado');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final typed = await promptText(context,
        title: 'Excluir workspace',
        hint: 'Digite "${widget.workspace.name}" para confirmar',
        confirm: 'Excluir');
    if (typed == null || !mounted) return;
    if (typed != widget.workspace.name) {
      showMsg(context, 'O nome não confere.');
      return;
    }
    try {
      await Session.api.deleteWorkspace(_id);
      widget.onChanged();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    final admin = widget.workspace.isAdmin;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!admin)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Apenas administradores podem alterar o workspace.'),
            ),
          ),
        TextField(
          controller: _name,
          enabled: admin,
          decoration: const InputDecoration(
              labelText: 'Nome', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _slug,
          enabled: admin,
          decoration: InputDecoration(
              labelText: 'Slug',
              helperText: '${Session.siteUrl}/${_slug.text}',
              border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          enabled: admin,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Descrição', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: const [0, 1, 6].contains(_weekStart) ? _weekStart : 1,
          decoration: const InputDecoration(
              labelText: 'A semana começa em', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Domingo')),
            DropdownMenuItem(value: 1, child: Text('Segunda-feira')),
            DropdownMenuItem(value: 6, child: Text('Sábado')),
          ],
          onChanged: admin ? (v) => setState(() => _weekStart = v ?? 1) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar e-mails aos membros'),
          value: _showEmails,
          onChanged: admin ? (v) => setState(() => _showEmails = v) : null,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: admin && !_saving ? _save : null,
          child: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
        const SizedBox(height: 32),
        Text('Plano: ${widget.workspace.plan}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        if (admin)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Excluir workspace'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Membros

const _roleNames = {'admin': 'Admin', 'member': 'Membro', 'guest': 'Convidado'};
const _statusNames = {
  'invited': 'Convite pendente',
  'active': 'Ativo',
  'paused': 'Pausado',
  'removed': 'Removido',
};

class _MembersTab extends StatefulWidget {
  const _MembersTab({required this.workspace});
  final Workspace workspace;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab>
    with AutomaticKeepAliveClientMixin {
  List<Member>? _members;
  InviteLink? _link;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  String get _id => widget.workspace.publicId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Session.api.getWorkspace(_id);
      InviteLink? link;
      if (widget.workspace.isAdmin) {
        try {
          link = await Session.api.getInviteLink(_id);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _members = d.members.where((m) => m.status != 'removed').toList();
        _link = link;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    await _load();
  }

  Future<void> _invite() async {
    final email = await promptText(context,
        title: 'Convidar por e-mail',
        hint: 'email@exemplo.com',
        confirm: 'Convidar',
        keyboardType: TextInputType.emailAddress);
    if (email == null) return;
    await _run(() async {
      await Session.api.inviteMember(_id, email);
      if (mounted) showMsg(context, 'Convite enviado para $email');
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMsg(context, 'Link copiado');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final members = _members;
    final admin = widget.workspace.isAdmin;
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Tentar de novo')),
      ]));
    }
    if (members == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final link = _link;
    final linkUrl =
        (link != null && link.isActive) ? link.inviteLink : null;
    final linkExpires = link?.expiresAt;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (admin)
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Link de convite',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (linkUrl != null) ...[
                      SelectableText(linkUrl),
                      if (linkExpires != null)
                        Text('Expira em ${formatDateTime(linkExpires)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _copy(linkUrl),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                        ),
                        OutlinedButton(
                          onPressed: () => _run(
                              () => Session.api.deactivateInviteLinks(_id)),
                          child: const Text('Desativar'),
                        ),
                      ]),
                    ] else
                      FilledButton.tonalIcon(
                        onPressed: () => _run(() async {
                          final l = await Session.api.createInviteLink(_id);
                          if (l.inviteLink != null) await _copy(l.inviteLink!);
                        }),
                        icon: const Icon(Icons.add_link),
                        label: const Text('Gerar link de convite'),
                      ),
                  ],
                ),
              ),
            ),
          if (admin)
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Convidar por e-mail'),
              onTap: _invite,
            ),
          const Divider(),
          for (final m in members)
            ListTile(
              leading: MemberAvatar(name: m.displayName, image: m.image),
              title: Text(m.displayName),
              subtitle: Text(
                  '${_roleNames[m.role] ?? m.role ?? ''} · ${_statusNames[m.status] ?? m.status}'),
              trailing: admin && m.userId != Session.user?.id
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'remove') {
                          final ok = await confirmDialog(context,
                              title: 'Remover ${m.displayName}?',
                              confirm: 'Remover',
                              destructive: true);
                          if (ok) {
                            await _run(() =>
                                Session.api.removeMember(_id, m.publicId));
                          }
                        } else {
                          await _run(() =>
                              Session.api.updateMemberRole(_id, m.publicId, v));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'admin', child: Text('Tornar admin')),
                        PopupMenuItem(
                            value: 'member', child: Text('Tornar membro')),
                        PopupMenuItem(
                            value: 'guest', child: Text('Tornar convidado')),
                        PopupMenuItem(value: 'remove', child: Text('Remover')),
                      ],
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Webhooks

const _events = {
  'card.created': 'Cartão criado',
  'card.updated': 'Cartão atualizado',
  'card.moved': 'Cartão movido',
  'card.deleted': 'Cartão excluído',
};

class _WebhooksTab extends StatefulWidget {
  const _WebhooksTab({required this.workspace});
  final Workspace workspace;

  @override
  State<_WebhooksTab> createState() => _WebhooksTabState();
}

class _WebhooksTabState extends State<_WebhooksTab>
    with AutomaticKeepAliveClientMixin {
  List<Webhook>? _hooks;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  String get _id => widget.workspace.publicId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await Session.api.getWebhooks(_id);
      if (mounted) {
        setState(() {
          _hooks = h;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    await _load();
  }

  Future<void> _edit([Webhook? h]) async {
    final r = await showDialog<_HookData>(
        context: context, builder: (_) => _WebhookDialog(hook: h));
    if (r == null) return;
    await _run(() => h == null
        ? Session.api.createWebhook(_id,
            name: r.name, url: r.url, secret: r.secret, events: r.events)
        : Session.api.updateWebhook(_id, h.publicId,
            name: r.name, url: r.url, secret: r.secret, events: r.events));
  }

  Future<void> _test(Webhook h) async {
    try {
      final r = await Session.api.testWebhook(_id, h.publicId);
      if (!mounted) return;
      showMsg(
          context,
          r['success'] == true
              ? 'Teste OK (HTTP ${r['statusCode'] ?? '-'})'
              : 'Falhou: ${r['error'] ?? 'HTTP ${r['statusCode']}'}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hooks = _hooks;
    return Scaffold(
      floatingActionButton: widget.workspace.isAdmin
          ? FloatingActionButton(
              onPressed: () => _edit(), child: const Icon(Icons.add))
          : null,
      body: _error != null
          ? Center(
              child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ))
          : hooks == null
              ? const Center(child: CircularProgressIndicator())
              : hooks.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Nenhum webhook. Webhooks enviam eventos de cartões '
                          'para uma URL HTTPS.',
                          textAlign: TextAlign.center),
                    ))
                  : ListView(
                      children: [
                        for (final h in hooks)
                          Card(
                            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: Text(h.name),
                                  subtitle: Text(h.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  value: h.active,
                                  onChanged: (v) => _run(() => Session.api
                                      .updateWebhook(_id, h.publicId,
                                          active: v)),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 16),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final e in h.events)
                                        Chip(
                                            label: Text(_events[e] ?? e),
                                            visualDensity:
                                                VisualDensity.compact),
                                    ],
                                  ),
                                ),
                                OverflowBar(
                                  alignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                        onPressed: () => _test(h),
                                        child: const Text('Testar')),
                                    TextButton(
                                        onPressed: () => _edit(h),
                                        child: const Text('Editar')),
                                    TextButton(
                                      onPressed: () async {
                                        final ok = await confirmDialog(context,
                                            title: 'Excluir webhook?',
                                            confirm: 'Excluir',
                                            destructive: true);
                                        if (ok) {
                                          await _run(() => Session.api
                                              .deleteWebhook(_id, h.publicId));
                                        }
                                      },
                                      child: const Text('Excluir'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 88),
                      ],
                    ),
    );
  }
}

class _HookData {
  final String name;
  final String url;
  final String secret;
  final List<String> events;
  _HookData(this.name, this.url, this.secret, this.events);
}

class _WebhookDialog extends StatefulWidget {
  const _WebhookDialog({this.hook});
  final Webhook? hook;

  @override
  State<_WebhookDialog> createState() => _WebhookDialogState();
}

class _WebhookDialogState extends State<_WebhookDialog> {
  late final _name = TextEditingController(text: widget.hook?.name ?? '');
  late final _url = TextEditingController(text: widget.hook?.url ?? 'https://');
  final _secret = TextEditingController();
  late final Set<String> _sel =
      (widget.hook?.events ?? _events.keys.toList()).toSet();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.hook == null ? 'Novo webhook' : 'Editar webhook'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Nome', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'URL (HTTPS)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              decoration: InputDecoration(
                  labelText: 'Segredo (opcional)',
                  helperText: widget.hook == null
                      ? null
                      : 'Deixe vazio para manter o atual',
                  border: const OutlineInputBorder()),
            ),
            for (final e in _events.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.value),
                value: _sel.contains(e.key),
                onChanged: (v) => setState(
                    () => v == true ? _sel.add(e.key) : _sel.remove(e.key)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty ||
                !_url.text.trim().startsWith('https://') ||
                _sel.isEmpty) {
              showMsg(context, 'Preencha nome, URL https:// e ao menos 1 evento');
              return;
            }
            Navigator.pop(
                context,
                _HookData(_name.text.trim(), _url.text.trim(),
                    _secret.text.trim(), _sel.toList()));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
