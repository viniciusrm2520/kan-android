import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../session.dart';
import '../utils.dart';

class CardScreen extends StatefulWidget {
  const CardScreen({super.key, required this.cardId});
  final String cardId;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  CardDetail? _card;
  String? _error;
  bool _busy = false;

  final List<Activity> _activities = [];
  bool _hasMore = false;
  String? _cursor;
  String? _cursorId;
  bool _loadingMore = false;

  final _comment = TextEditingController();
  bool _sending = false;

  String get _id => widget.cardId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final results = await Future.wait<Object>([
        Session.api.getCard(_id),
        Session.api.getActivities(_id),
      ]);
      final page = results[1] as ActivityPage;
      if (!mounted) return;
      setState(() {
        _card = results[0] as CardDetail;
        _activities
          ..clear()
          ..addAll(page.activities);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _cursorId = page.nextCursorPublicId;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await Session.api
          .getActivities(_id, cursor: _cursor, cursorPublicId: _cursorId);
      setState(() {
        _activities.addAll(page.activities);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _cursorId = page.nextCursorPublicId;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _run(Future<void> Function() action, {bool reload = true}) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (reload) await _load();
  }

  // ------------------------------------------------------------ Ações

  Future<void> _editTitle(CardDetail c) async {
    final t = await promptText(context, title: 'Título', initial: c.title);
    if (t != null) await _run(() => Session.api.updateCard(_id, title: t));
  }

  Future<void> _editDescription(CardDetail c) async {
    final t = await promptText(context,
        title: 'Descrição',
        initial: htmlToText(c.description),
        multiline: true,
        allowEmpty: true);
    if (t == null) return;
    await _run(() => Session.api.updateCard(_id,
        description: t.trim().isEmpty ? '' : textToHtml(t.trim())));
  }

  Future<void> _editDueDate(CardDetail c) async {
    final d = await pickDateTime(context, c.dueDate);
    if (d != null) await _run(() => Session.api.updateCard(_id, dueDate: d));
  }

  Future<void> _moveToList(CardDetail c) async {
    final target = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mover para a lista')),
            for (final l in c.boardLists)
              ListTile(
                leading: Icon(l.publicId == c.listPublicId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(l.name),
                onTap: () => Navigator.pop(ctx, l.publicId),
              ),
          ],
        ),
      ),
    );
    if (target == null || target == c.listPublicId) return;
    await _run(
        () => Session.api.updateCard(_id, listId: target, index: 0));
  }

  Future<void> _editLabels(CardDetail c) async {
    final selected = c.labels.map((l) => l.publicId).toSet();
    final labels = [...c.boardLabels];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Etiquetas')),
                for (final l in labels)
                  CheckboxListTile(
                    value: selected.contains(l.publicId),
                    secondary: CircleAvatar(
                        radius: 10, backgroundColor: parseColor(l.colourCode)),
                    title: Text(l.name),
                    onChanged: (_) async {
                      setSheet(() => selected.contains(l.publicId)
                          ? selected.remove(l.publicId)
                          : selected.add(l.publicId));
                      try {
                        await Session.api.toggleCardLabel(_id, l.publicId);
                      } catch (e) {
                        if (mounted) showError(context, e);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Criar etiqueta'),
                  onTap: () async {
                    final r = await labelDialog(ctx);
                    if (r == null) return;
                    try {
                      final l = await Session.api
                          .createLabel(c.boardPublicId, r.$1, r.$2);
                      await Session.api.toggleCardLabel(_id, l.publicId);
                      setSheet(() {
                        labels.add(l);
                        selected.add(l.publicId);
                      });
                    } catch (e) {
                      if (mounted) showError(context, e);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _load();
  }

  Future<void> _editMembers(CardDetail c) async {
    final selected = c.members.map((m) => m.publicId).toSet();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Membros')),
                for (final m in c.workspaceMembers)
                  CheckboxListTile(
                    value: selected.contains(m.publicId),
                    secondary: MemberAvatar(name: m.displayName, image: m.image),
                    title: Text(m.displayName),
                    subtitle: m.status == 'invited' ? const Text('Convidado') : null,
                    onChanged: (_) async {
                      setSheet(() => selected.contains(m.publicId)
                          ? selected.remove(m.publicId)
                          : selected.add(m.publicId));
                      try {
                        await Session.api.toggleCardMember(_id, m.publicId);
                      } catch (e) {
                        if (mounted) showError(context, e);
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await _load();
  }

  Future<void> _duplicate(CardDetail c) async {
    final r = await showDialog<(String, String, bool, bool, bool)>(
        context: context, builder: (_) => _DuplicateDialog(card: c));
    if (r == null) return;
    try {
      final newId = await Session.api.duplicateCard(_id,
          listId: r.$1,
          title: r.$2,
          copyLabels: r.$3,
          copyMembers: r.$4,
          copyChecklists: r.$5);
      if (!mounted) return;
      showMsg(context, 'Cartão duplicado');
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => CardScreen(cardId: newId)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(CardDetail c) async {
    final ok = await confirmDialog(context,
        title: 'Excluir cartão?',
        message: '"${c.title}" será excluído permanentemente.',
        confirm: 'Excluir',
        destructive: true);
    if (!ok) return;
    try {
      await Session.api.deleteCard(_id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Session.api.addComment(_id, textToHtml(text));
      _comment.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _commentAction(Activity a, String action) async {
    final id = a.commentId;
    if (id == null) return;
    if (action == 'edit') {
      final t = await promptText(context,
          title: 'Editar comentário',
          initial: htmlToText(a.comment),
          multiline: true);
      if (t == null || t.trim().isEmpty) return;
      await _run(() => Session.api.updateComment(_id, id, textToHtml(t.trim())));
    } else if (action == 'delete') {
      final ok = await confirmDialog(context,
          title: 'Excluir comentário?', confirm: 'Excluir', destructive: true);
      if (ok) await _run(() => Session.api.deleteComment(_id, id));
    }
  }

  // ------------------------------------------------------- Checklists

  Future<void> _addChecklist() async {
    final n = await promptText(context,
        title: 'Nova checklist', initial: 'Checklist', confirm: 'Criar');
    if (n != null) await _run(() => Session.api.createChecklist(_id, n));
  }

  Future<void> _checklistAction(Checklist cl, String action) async {
    switch (action) {
      case 'rename':
        final n = await promptText(context,
            title: 'Renomear checklist', initial: cl.name);
        if (n != null) {
          await _run(() => Session.api.updateChecklist(cl.publicId, n));
        }
      case 'delete':
        final ok = await confirmDialog(context,
            title: 'Excluir checklist "${cl.name}"?',
            confirm: 'Excluir',
            destructive: true);
        if (ok) await _run(() => Session.api.deleteChecklist(cl.publicId));
    }
  }

  Future<void> _addItem(Checklist cl) async {
    final t = await promptText(context,
        title: 'Novo item', hint: 'Descrição do item', confirm: 'Adicionar');
    if (t != null) {
      await _run(() => Session.api.createChecklistItem(cl.publicId, t));
    }
  }

  Future<void> _toggleItem(ChecklistItem it) async {
    setState(() => it.completed = !it.completed);
    await _run(
        () => Session.api
            .updateChecklistItem(it.publicId, completed: it.completed),
        reload: false);
  }

  Future<void> _itemAction(Checklist cl, ChecklistItem it, String action) async {
    final pos = cl.items.indexOf(it);
    switch (action) {
      case 'edit':
        final t =
            await promptText(context, title: 'Editar item', initial: it.title);
        if (t != null) {
          await _run(
              () => Session.api.updateChecklistItem(it.publicId, title: t));
        }
      case 'up':
        await _run(() =>
            Session.api.updateChecklistItem(it.publicId, index: pos - 1));
      case 'down':
        await _run(() =>
            Session.api.updateChecklistItem(it.publicId, index: pos + 1));
      case 'delete':
        await _run(() => Session.api.deleteChecklistItem(it.publicId));
    }
  }

  // --------------------------------------------------------- Anexos

  Future<void> _attach() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    showMsg(context, 'Enviando ${f.name}...');
    await _run(() => Session.api.uploadAttachment(_id,
        filename: f.name,
        contentType: guessContentType(f.name),
        bytes: bytes));
    if (mounted) showMsg(context, 'Anexo enviado');
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) {
      showMsg(context, 'Link indisponível');
      return;
    }
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMsg(context, 'Não foi possível abrir o link');
  }

  Future<void> _deleteAttachment(Attachment a) async {
    final ok = await confirmDialog(context,
        title: 'Excluir anexo "${a.name}"?',
        confirm: 'Excluir',
        destructive: true);
    if (ok) await _run(() => Session.api.deleteAttachment(a.publicId));
  }

  // ---------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final c = _card;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Cartão' : (c.reference.isEmpty ? c.boardName : c.reference)),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
        actions: [
          if (c != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'move':
                    _moveToList(c);
                  case 'dup':
                    _duplicate(c);
                  case 'refresh':
                    _load();
                  case 'delete':
                    _delete(c);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'move', child: Text('Mover')),
                PopupMenuItem(value: 'dup', child: Text('Duplicar')),
                PopupMenuItem(value: 'refresh', child: Text('Atualizar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
        ],
      ),
      body: c == null
          ? Center(
              child: _error != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _load, child: const Text('Tentar de novo')),
                    ])
                  : const CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _buildBody(c),
                  ),
                ),
                _buildCommentBox(),
              ],
            ),
    );
  }

  Widget _buildBody(CardDetail c) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final desc = htmlToText(c.description);
    final due = c.dueDate;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        InkWell(
          onTap: () => _editTitle(c),
          child: Text(c.title, style: tt.headlineSmall),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.view_column_outlined, size: 18),
              label: Text(c.listName),
              onPressed: () => _moveToList(c),
            ),
            ActionChip(
              avatar: Icon(Icons.schedule,
                  size: 18, color: due == null ? null : dueDateColor(context, due)),
              label: Text(due == null ? 'Definir prazo' : formatDateTime(due)),
              onPressed: () => _editDueDate(c),
            ),
            if (due != null)
              ActionChip(
                avatar: const Icon(Icons.close, size: 18),
                label: const Text('Remover prazo'),
                onPressed: () => _run(
                    () => Session.api.updateCard(_id, clearDueDate: true)),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Etiquetas
        _Header(
            icon: Icons.label_outline,
            title: 'Etiquetas',
            onEdit: () => _editLabels(c)),
        if (c.labels.isEmpty)
          _Empty('Nenhuma etiqueta', onTap: () => _editLabels(c))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final l in c.labels) LabelChip(label: l)],
          ),
        const SizedBox(height: 16),

        // Membros
        _Header(
            icon: Icons.people_outline,
            title: 'Membros',
            onEdit: () => _editMembers(c)),
        if (c.members.isEmpty)
          _Empty('Ninguém atribuído', onTap: () => _editMembers(c))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in c.members)
                Chip(
                  avatar: MemberAvatar(name: m.displayName, image: m.image),
                  label: Text(m.displayName),
                ),
            ],
          ),
        const SizedBox(height: 16),

        // Descrição
        _Header(
            icon: Icons.notes,
            title: 'Descrição',
            onEdit: () => _editDescription(c)),
        InkWell(
          onTap: () => _editDescription(c),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: desc.isEmpty
                ? Text('Adicionar uma descrição...',
                    style: TextStyle(color: cs.onSurfaceVariant))
                : SelectableText(desc),
          ),
        ),
        const SizedBox(height: 16),

        // Checklists
        _Header(
            icon: Icons.checklist,
            title: 'Checklists',
            editIcon: Icons.add,
            onEdit: _addChecklist),
        if (c.checklists.isEmpty)
          _Empty('Nenhuma checklist', onTap: _addChecklist),
        for (final cl in c.checklists) _buildChecklist(cl),
        const SizedBox(height: 16),

        // Anexos
        _Header(
            icon: Icons.attach_file,
            title: 'Anexos',
            editIcon: Icons.add,
            onEdit: _attach),
        if (c.attachments.isEmpty) _Empty('Nenhum anexo', onTap: _attach),
        for (final a in c.attachments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: (a.contentType.startsWith('image/') && a.url != null)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(a.url!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_outlined)),
                  )
                : const Icon(Icons.insert_drive_file_outlined),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(formatBytes(a.size)),
            onTap: () => _openUrl(a.url),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteAttachment(a),
            ),
          ),
        const SizedBox(height: 16),

        // Atividade
        const _Header(icon: Icons.history, title: 'Comentários e atividade'),
        for (final a in _activities) _buildActivity(a),
        if (_hasMore)
          Center(
            child: _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator())
                : TextButton(
                    onPressed: _loadMore, child: const Text('Carregar mais')),
          ),
      ],
    );
  }

  Widget _buildChecklist(Checklist cl) {
    final total = cl.items.length;
    final done = cl.completedCount;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(cl.name,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text('$done/$total'),
                PopupMenuButton<String>(
                  onSelected: (v) => _checklistAction(cl, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renomear')),
                    PopupMenuItem(value: 'delete', child: Text('Excluir')),
                  ],
                ),
              ],
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: LinearProgressIndicator(
                  value: done / total,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            for (var i = 0; i < cl.items.length; i++)
              Row(
                children: [
                  Checkbox(
                    value: cl.items[i].completed,
                    onChanged: (_) => _toggleItem(cl.items[i]),
                  ),
                  Expanded(
                    child: Text(
                      cl.items[i].title,
                      style: cl.items[i].completed
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey)
                          : null,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onSelected: (v) => _itemAction(cl, cl.items[i], v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      if (i > 0)
                        const PopupMenuItem(value: 'up', child: Text('Subir')),
                      if (i < cl.items.length - 1)
                        const PopupMenuItem(
                            value: 'down', child: Text('Descer')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () => _addItem(cl),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar item'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivity(Activity a) {
    final cs = Theme.of(context).colorScheme;
    final name = a.userName ?? 'Alguém';
    if (a.isComment) {
      final mine = Session.user != null &&
          (a.commentCreatedBy == Session.user!.id || a.userId == Session.user!.id);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MemberAvatar(name: name, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text(
                          '${timeAgo(a.createdAt)}${a.commentEdited ? ' (editado)' : ''}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: a.commentDeleted
                        ? Text('Comentário excluído',
                            style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: cs.onSurfaceVariant))
                        : SelectableText(htmlToText(a.comment)),
                  ),
                ],
              ),
            ),
            if (mine && !a.commentDeleted)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) => _commentAction(a, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          MemberAvatar(name: name, radius: 12),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$name ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: a.describe()),
                TextSpan(
                    text: '  ${timeAgo(a.createdAt)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentBox() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _comment,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Escreva um comentário...',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              onPressed: _sending ? null : _sendComment,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.icon, required this.title, this.onEdit, this.editIcon});
  final IconData icon;
  final String title;
  final VoidCallback? onEdit;
  final IconData? editIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (onEdit != null)
            IconButton(
              icon: Icon(editIcon ?? Icons.edit_outlined, size: 20),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(text,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

class _DuplicateDialog extends StatefulWidget {
  const _DuplicateDialog({required this.card});
  final CardDetail card;

  @override
  State<_DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<_DuplicateDialog> {
  late final _title = TextEditingController(text: widget.card.title);
  late String _listId = widget.card.listPublicId;
  bool _labels = true;
  bool _members = true;
  bool _checklists = true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Duplicar cartão'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Título', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _listId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Lista', border: OutlineInputBorder()),
              items: [
                for (final l in widget.card.boardLists)
                  DropdownMenuItem(value: l.publicId, child: Text(l.name)),
              ],
              onChanged: (v) => setState(() => _listId = v ?? _listId),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Copiar etiquetas'),
              value: _labels,
              onChanged: (v) => setState(() => _labels = v ?? true),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Copiar membros'),
              value: _members,
              onChanged: (v) => setState(() => _members = v ?? true),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Copiar checklists'),
              value: _checklists,
              onChanged: (v) => setState(() => _checklists = v ?? true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context,
              (_listId, _title.text.trim(), _labels, _members, _checklists)),
          child: const Text('Duplicar'),
        ),
      ],
    );
  }
}
