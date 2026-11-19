import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';
import '../utils.dart';
import 'board_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'workspace_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Workspace> _workspaces = [];
  Workspace? _current;
  bool _loading = true;
  String? _error;
  int _boardsVersion = 0; // força recarregar as abas

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? selectId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Session.user ??= await Session.api.getMe();
      final ws = await Session.api.getWorkspaces();
      final last = selectId ?? _current?.publicId ?? await Session.lastWorkspace();
      Workspace? cur;
      for (final w in ws) {
        if (w.publicId == last) cur = w;
      }
      cur ??= ws.isNotEmpty ? ws.first : null;
      if (cur != null) await Session.setLastWorkspace(cur.publicId);
      setState(() {
        _workspaces = ws;
        _current = cur;
        _boardsVersion++;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(Workspace w) async {
    await Session.setLastWorkspace(w.publicId);
    setState(() {
      _current = w;
      _boardsVersion++;
    });
  }

  Future<void> _createWorkspace() async {
    final name = await promptText(context,
        title: 'Novo workspace', hint: 'Nome do workspace', confirm: 'Criar');
    if (name == null || !mounted) return;
    try {
      final id = await Session.api.createWorkspace(name);
      await _load(selectId: id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _acceptInvite() async {
    final code = await promptText(context,
        title: 'Entrar com convite',
        hint: 'Cole o código ou link de convite',
        confirm: 'Entrar');
    if (code == null || !mounted) return;
    final c = code.trim().split('/').where((p) => p.isNotEmpty).last;
    try {
      await Session.api.acceptInvite(c);
      await _load();
      if (mounted) showMsg(context, 'Convite aceito!');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(context,
        title: 'Sair', message: 'Deseja desconectar desta conta?', confirm: 'Sair');
    if (!ok) return;
    await Session.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _createBoard() async {
    final ws = _current;
    if (ws == null) return;
    final r = await showDialog<_NewBoard>(
        context: context, builder: (_) => _CreateBoardDialog(workspace: ws));
    if (r == null || !mounted) return;
    try {
      final id = await Session.api.createBoard(ws.publicId,
          name: r.name,
          lists: r.sourceId == null ? r.lists : const [],
          template: r.template,
          sourceBoardId: r.sourceId);
      setState(() => _boardsVersion++);
      if (!mounted) return;
      if (!r.template) {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => BoardScreen(boardId: id)));
        setState(() => _boardsVersion++);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = _current;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ws?.name ?? 'Kan'),
          actions: [
            if (ws != null)
              IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SearchScreen(workspace: ws))),
              ),
            if (ws != null)
              IconButton(
                tooltip: 'Configurações do workspace',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () async {
                  final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              WorkspaceSettingsScreen(workspace: ws)));
                  if (changed == true) _load();
                },
              ),
          ],
          bottom: ws == null
              ? null
              : const TabBar(tabs: [
                  Tab(text: 'Quadros'),
                  Tab(text: 'Templates'),
                  Tab(text: 'Arquivados'),
                ]),
        ),
        drawer: _buildDrawer(),
        floatingActionButton: ws == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _createBoard,
                icon: const Icon(Icons.add),
                label: const Text('Quadro'),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : ws == null
                    ? _EmptyWorkspaces(
                        onCreate: _createWorkspace, onInvite: _acceptInvite)
                    : TabBarView(children: [
                        _BoardsTab(
                            key: ValueKey('r$_boardsVersion${ws.publicId}'),
                            workspace: ws),
                        _BoardsTab(
                            key: ValueKey('t$_boardsVersion${ws.publicId}'),
                            workspace: ws,
                            templates: true),
                        _BoardsTab(
                            key: ValueKey('a$_boardsVersion${ws.publicId}'),
                            workspace: ws,
                            archived: true),
                      ]),
      ),
    );
  }

  Widget _buildDrawer() {
    final user = Session.user;
    return NavigationDrawer(
      children: [
        UserAccountsDrawerHeader(
          accountName: Text(user?.displayName ?? ''),
          accountEmail: Text(user?.email ?? ''),
          currentAccountPicture: MemberAvatar(
              name: user?.displayName ?? '?', image: user?.image, radius: 30),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 8, 16, 8),
          child: Text('Workspaces'),
        ),
        for (final w in _workspaces)
          ListTile(
            leading: CircleAvatar(
              radius: 16,
              child: Text(w.name.isEmpty ? '?' : w.name[0].toUpperCase()),
            ),
            title: Text(w.name),
            subtitle: Text('${w.role} · ${w.plan}'),
            selected: w.publicId == _current?.publicId,
            onTap: () {
              Navigator.pop(context);
              _select(w);
            },
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Novo workspace'),
          onTap: () {
            Navigator.pop(context);
            _createWorkspace();
          },
        ),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: const Text('Entrar com convite'),
          onTap: () {
            Navigator.pop(context);
            _acceptInvite();
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Perfil'),
          onTap: () async {
            Navigator.pop(context);
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()));
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Atualizar'),
          onTap: () {
            Navigator.pop(context);
            _load();
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sair'),
          onTap: () {
            Navigator.pop(context);
            _logout();
          },
        ),
      ],
    );
  }
}

class _BoardsTab extends StatefulWidget {
  const _BoardsTab(
      {super.key,
      required this.workspace,
      this.templates = false,
      this.archived = false});
  final Workspace workspace;
  final bool templates;
  final bool archived;

  @override
  State<_BoardsTab> createState() => _BoardsTabState();
}

class _BoardsTabState extends State<_BoardsTab>
    with AutomaticKeepAliveClientMixin {
  List<BoardSummary>? _boards;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await Session.api.getBoards(widget.workspace.publicId,
          templates: widget.templates, archived: widget.archived);
      b.sort((x, y) {
        if (x.favorite != y.favorite) return x.favorite ? -1 : 1;
        return x.name.toLowerCase().compareTo(y.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _boards = b;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(BoardSummary b) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => BoardScreen(boardId: b.publicId)));
    _load();
  }

  Future<void> _action(BoardSummary b, String action) async {
    final api = Session.api;
    try {
      switch (action) {
        case 'fav':
          await api.updateBoard(b.publicId, favorite: !b.favorite);
        case 'archive':
          await api.updateBoard(b.publicId, isArchived: !widget.archived);
        case 'rename':
          final n = await promptText(context,
              title: 'Renomear quadro', initial: b.name);
          if (n == null) return;
          await api.updateBoard(b.publicId, name: n);
        case 'delete':
          final ok = await confirmDialog(context,
              title: 'Excluir "${b.name}"?',
              message: 'Todas as listas e cartões serão excluídos.',
              confirm: 'Excluir',
              destructive: true);
          if (!ok) return;
          await api.deleteBoard(b.publicId);
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    final boards = _boards;
    if (boards == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: boards.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Icon(Icons.dashboard_outlined,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Center(
                child: Text(widget.archived
                    ? 'Nenhum quadro arquivado'
                    : widget.templates
                        ? 'Nenhum template'
                        : 'Nenhum quadro ainda. Toque em + para criar.'),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88, top: 8),
              itemCount: boards.length,
              itemBuilder: (_, i) {
                final b = boards[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: IconButton(
                      icon: Icon(b.favorite ? Icons.star : Icons.star_border,
                          color: b.favorite ? Colors.amber : null),
                      onPressed: () => _action(b, 'fav'),
                    ),
                    title: Text(b.name),
                    subtitle: Text('${b.listCount} listas'),
                    onTap: () => _open(b),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _action(b, v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'rename', child: Text('Renomear')),
                        PopupMenuItem(
                            value: 'archive',
                            child: Text(
                                widget.archived ? 'Desarquivar' : 'Arquivar')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Excluir')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _NewBoard {
  final String name;
  final List<String> lists;
  final bool template;
  final String? sourceId;
  _NewBoard(this.name, this.lists, this.template, this.sourceId);
}

class _CreateBoardDialog extends StatefulWidget {
  const _CreateBoardDialog({required this.workspace});
  final Workspace workspace;

  @override
  State<_CreateBoardDialog> createState() => _CreateBoardDialogState();
}

class _CreateBoardDialogState extends State<_CreateBoardDialog> {
  final _name = TextEditingController();
  final _lists = TextEditingController(text: 'A fazer, Fazendo, Concluído');
  bool _template = false;
  String? _sourceId;
  List<BoardSummary> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final t = await Session.api
          .getBoards(widget.workspace.publicId, templates: true);
      if (mounted) setState(() => _templates = t);
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _lists.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo quadro'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Nome', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (_templates.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _sourceId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'A partir de template',
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nenhum')),
                  for (final t in _templates)
                    DropdownMenuItem(value: t.publicId, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() => _sourceId = v),
              ),
            if (_sourceId == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _lists,
                decoration: const InputDecoration(
                    labelText: 'Listas (separadas por vírgula)',
                    border: OutlineInputBorder()),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Salvar como template'),
              value: _template,
              onChanged: (v) => setState(() => _template = v),
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
            final n = _name.text.trim();
            if (n.isEmpty) return;
            final lists = _lists.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            Navigator.pop(context, _NewBoard(n, lists, _template, _sourceId));
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}

class _EmptyWorkspaces extends StatelessWidget {
  const _EmptyWorkspaces({required this.onCreate, required this.onInvite});
  final VoidCallback onCreate;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspaces_outline, size: 64),
            const SizedBox(height: 12),
            const Text('Você ainda não participa de nenhum workspace.'),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Criar workspace')),
            TextButton(
                onPressed: onInvite, child: const Text('Tenho um convite')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () => onRetry(), child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
