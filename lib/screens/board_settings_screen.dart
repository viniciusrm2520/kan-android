import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/kan_api.dart';
import '../models.dart';
import '../session.dart';
import '../utils.dart';

/// Configurações do quadro. Ao sair, retorna 'deleted', 'moved' ou null.
class BoardSettingsScreen extends StatefulWidget {
  const BoardSettingsScreen({super.key, required this.board});
  final Board board;

  @override
  State<BoardSettingsScreen> createState() => _BoardSettingsScreenState();
}

class _BoardSettingsScreenState extends State<BoardSettingsScreen> {
  late Board _board = widget.board;
  List<Member>? _boardMembers;
  String? _membersError;

  /// O kan.bn em produção ainda não publica /boards/{id}/members na API REST.
  bool _membersUnsupported = false;

  String get _id => _board.publicId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _reload() async {
    try {
      final b = await Session.api.getBoard(_id);
      if (mounted) setState(() => _board = b);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final m = await Session.api.getBoardMembers(_id);
      if (mounted) {
        setState(() {
          _boardMembers = m;
          _membersError = null;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 404 || e.statusCode == 405) {
          _membersUnsupported = true;
        } else {
          _membersError = '$e';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _membersError = '$e');
    }
  }

  Future<void> _openInBrowser() async {
    final ok = await launchUrl(Uri.parse('${Session.siteUrl}/boards/$_id'),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMsg(context, 'Não foi possível abrir o navegador');
  }

  Future<void> _run(Future<void> Function() action,
      {bool members = false}) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    await _reload();
    if (members) await _loadMembers();
  }

  Future<void> _rename() async {
    final n =
        await promptText(context, title: 'Nome do quadro', initial: _board.name);
    if (n != null) await _run(() => Session.api.updateBoard(_id, name: n));
  }

  Future<void> _editSlug() async {
    final s = await promptText(context,
        title: 'Slug (endereço público)', initial: _board.slug);
    if (s == null) return;
    await _run(() async {
      if (await Session.api.isBoardSlugReserved(_id, s)) {
        throw Exception('Este slug está reservado.');
      }
      await Session.api.updateBoard(_id, slug: s);
    });
  }

  Future<void> _addLabel() async {
    final r = await labelDialog(context);
    if (r != null) {
      await _run(() async {
        await Session.api.createLabel(_id, r.$1, r.$2);
      });
    }
  }

  Future<void> _editLabel(Label l) async {
    final r = await labelDialog(context, name: l.name, colour: l.colourCode);
    if (r != null) {
      await _run(() => Session.api.updateLabel(l.publicId, r.$1, r.$2));
    }
  }

  Future<void> _deleteLabel(Label l) async {
    final ok = await confirmDialog(context,
        title: 'Excluir etiqueta "${l.name}"?',
        message: 'Ela será removida de todos os cartões.',
        confirm: 'Excluir',
        destructive: true);
    if (ok) await _run(() => Session.api.deleteLabel(l.publicId));
  }

  Future<void> _addBoardMember() async {
    final current = (_boardMembers ?? []).map((m) => m.publicId).toSet();
    final candidates = _board.workspaceMembers
        .where((m) => !current.contains(m.publicId))
        .toList();
    if (candidates.isEmpty) {
      showMsg(context, 'Todos os membros do workspace já estão no quadro.');
      return;
    }
    final picked = await showModalBottomSheet<Member>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Adicionar ao quadro')),
            for (final m in candidates)
              ListTile(
                leading: MemberAvatar(name: m.displayName, image: m.image),
                title: Text(m.displayName),
                subtitle: Text(m.email),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await _run(() => Session.api.addBoardMember(_id, picked.publicId),
          members: true);
    }
  }

  Future<void> _moveToWorkspace() async {
    List<Workspace> ws;
    try {
      ws = (await Session.api.getWorkspaces())
          .where((w) => w.publicId != _board.workspacePublicId)
          .toList();
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    if (ws.isEmpty) {
      showMsg(context, 'Você não tem outro workspace.');
      return;
    }
    final target = await showModalBottomSheet<Workspace>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mover para o workspace')),
            for (final w in ws)
              ListTile(
                  title: Text(w.name), onTap: () => Navigator.pop(ctx, w)),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await Session.api.moveBoard(_id, target.publicId);
      if (mounted) Navigator.pop(context, 'moved');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Excluir quadro "${_board.name}"?',
        message: 'Esta ação não pode ser desfeita.',
        confirm: 'Excluir',
        destructive: true);
    if (!ok) return;
    try {
      await Session.api.deleteBoard(_id);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    final members = _boardMembers;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do quadro')),
      body: ListView(
        children: [
          const _Section('Geral'),
          ListTile(
            leading: const Icon(Icons.title),
            title: const Text('Nome'),
            subtitle: Text(b.name),
            onTap: _rename,
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Slug'),
            subtitle: Text(b.slug),
            onTap: _editSlug,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('Quadro público'),
            subtitle: const Text('Qualquer pessoa com o link pode ver'),
            value: b.visibility == 'public',
            onChanged: (v) => _run(() => Session.api
                .updateBoard(_id, visibility: v ? 'public' : 'private')),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.star_outline),
            title: const Text('Favorito'),
            value: b.favorite,
            onChanged: (v) =>
                _run(() => Session.api.updateBoard(_id, favorite: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.archive_outlined),
            title: const Text('Arquivado'),
            value: b.isArchived,
            onChanged: (v) =>
                _run(() => Session.api.updateBoard(_id, isArchived: v)),
          ),
          const _Section('Etiquetas'),
          for (final l in b.labels)
            ListTile(
              leading: CircleAvatar(
                  radius: 12, backgroundColor: parseColor(l.colourCode)),
              title: Text(l.name),
              onTap: () => _editLabel(l),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteLabel(l),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Nova etiqueta'),
            onTap: _addLabel,
          ),
          const _Section('Membros do quadro'),
          if (_membersUnsupported) ...[
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Ainda não disponível pelo app'),
              subtitle: Text(
                  'O servidor do Kan ainda não libera os membros do quadro '
                  'pela API. Por enquanto, gerencie pelo site.'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Abrir quadro no navegador'),
              onTap: _openInBrowser,
            ),
          ] else if (_membersError != null)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Não foi possível carregar os membros'),
              subtitle: Text(_membersError!),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() => _membersError = null);
                  _loadMembers();
                },
              ),
            )
          else if (members == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (members.isEmpty)
              const ListTile(
                  title: Text('Todos os membros do workspace têm acesso')),
            for (final m in members)
              ListTile(
                leading: MemberAvatar(name: m.displayName, image: m.image),
                title: Text(m.displayName),
                subtitle: Text(m.role == 'admin' ? 'Admin' : 'Membro'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _run(
                      () => v == 'remove'
                          ? Session.api.removeBoardMember(_id, m.publicId)
                          : Session.api
                              .updateBoardMemberRole(_id, m.publicId, v),
                      members: true),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'admin', child: Text('Tornar admin')),
                    PopupMenuItem(value: 'member', child: Text('Tornar membro')),
                    PopupMenuItem(value: 'remove', child: Text('Remover')),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Adicionar membro'),
              onTap: _addBoardMember,
            ),
          ],
          const _Section('Avançado'),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Mover para outro workspace'),
            onTap: _moveToWorkspace,
          ),
          ListTile(
            leading: Icon(Icons.delete_forever,
                color: Theme.of(context).colorScheme.error),
            title: Text('Excluir quadro',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: _delete,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
