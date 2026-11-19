import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';
import '../utils.dart';
import 'board_settings_screen.dart';
import 'card_screen.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.boardId});
  final String boardId;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _DragCard {
  final CardSummary card;
  final String fromListId;
  _DragCard(this.card, this.fromListId);
}

/// Celular: arrasta com toque longo. Desktop (mouse): arrasta direto.
bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const _dueFilters = <String, String>{
  'overdue': 'Atrasados',
  'today': 'Hoje',
  'tomorrow': 'Amanhã',
  'next-week': 'Próxima semana',
  'next-month': 'Próximo mês',
  'no-due-date': 'Sem prazo',
};

class _BoardScreenState extends State<BoardScreen> {
  Board? _board;
  String? _error;
  bool _busy = false;
  final _hScroll = ScrollController();

  final Set<String> _fMembers = {};
  final Set<String> _fLabels = {};
  final Set<String> _fDue = {};

  bool get _filtering =>
      _fMembers.isNotEmpty || _fLabels.isNotEmpty || _fDue.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final b = await Session.api.getBoard(widget.boardId,
          members: _fMembers.toList(),
          labels: _fLabels.toList(),
          dueDateFilters: _fDue.toList());
      if (!mounted) return;
      setState(() {
        _board = b;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      // Com o quadro já na tela, o erro não aparecia: avisa por snackbar.
      if (_board != null) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
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

  // ------------------------------------------------------------ Listas

  Future<void> _addList() async {
    final name = await promptText(context,
        title: 'Nova lista', hint: 'Nome da lista', confirm: 'Criar');
    if (name == null) return;
    await _run(() => Session.api.createList(widget.boardId, name));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (_hScroll.hasClients) {
      _hScroll.animateTo(_hScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _listAction(BoardList list, String action) async {
    final board = _board!;
    final pos = board.lists.indexOf(list);
    switch (action) {
      case 'rename':
        final n =
            await promptText(context, title: 'Renomear lista', initial: list.name);
        if (n != null) await _run(() => Session.api.updateList(list.publicId, name: n));
      case 'left':
        if (pos > 0) {
          await _run(() => Session.api.updateList(list.publicId, index: pos - 1));
        }
      case 'right':
        if (pos < board.lists.length - 1) {
          await _run(() => Session.api.updateList(list.publicId, index: pos + 1));
        }
      case 'delete':
        final ok = await confirmDialog(context,
            title: 'Excluir lista "${list.name}"?',
            message: 'Os ${list.cards.length} cartões desta lista também serão excluídos.',
            confirm: 'Excluir',
            destructive: true);
        if (ok) await _run(() => Session.api.deleteList(list.publicId));
    }
  }

  // ----------------------------------------------------------- Cartões

  Future<void> _addCard(BoardList list) async {
    final title = await promptText(context,
        title: 'Novo cartão em "${list.name}"',
        hint: 'Título do cartão',
        confirm: 'Adicionar');
    if (title == null) return;
    await _run(() async {
      await Session.api.createCard(listId: list.publicId, title: title);
    });
  }

  Future<void> _openCard(CardSummary c) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => CardScreen(cardId: c.publicId)));
    _load();
  }

  Future<void> _moveCard(_DragCard d, String toListId, int targetIndex) async {
    final board = _board;
    if (board == null) return;
    final from = board.lists.firstWhere((l) => l.publicId == d.fromListId);
    final to = board.lists.firstWhere((l) => l.publicId == toListId);
    final oldIndex = from.cards.indexWhere((c) => c.publicId == d.card.publicId);
    if (oldIndex < 0) return;
    var newIndex = targetIndex;
    if (from == to) {
      if (oldIndex < targetIndex) newIndex -= 1;
      if (newIndex == oldIndex) return;
    }
    setState(() {
      from.cards.removeAt(oldIndex);
      newIndex = newIndex.clamp(0, to.cards.length);
      to.cards.insert(newIndex, d.card);
    });
    await _run(() => Session.api
        .updateCard(d.card.publicId, listId: toListId, index: newIndex));
  }

  void _autoScroll(DragUpdateDetails d) {
    if (!_hScroll.hasClients) return;
    final w = MediaQuery.of(context).size.width;
    const edge = 56.0;
    final x = d.globalPosition.dx;
    double delta = 0;
    if (x < edge) delta = -14;
    if (x > w - edge) delta = 14;
    if (delta == 0) return;
    final p = _hScroll.position;
    _hScroll.jumpTo((p.pixels + delta).clamp(0.0, p.maxScrollExtent));
  }

  // ----------------------------------------------------------- Filtros

  Future<void> _openFilters() async {
    final board = _board;
    if (board == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void toggle(Set<String> s, String v) {
            setSheet(() => s.contains(v) ? s.remove(v) : s.add(v));
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              children: [
                ListTile(
                  title: Text('Filtros',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  trailing: TextButton(
                    onPressed: () => setSheet(() {
                      _fMembers.clear();
                      _fLabels.clear();
                      _fDue.clear();
                    }),
                    child: const Text('Limpar'),
                  ),
                ),
                const _SectionTitle('Membros'),
                for (final m in board.workspaceMembers)
                  CheckboxListTile(
                    value: _fMembers.contains(m.publicId),
                    onChanged: (_) => toggle(_fMembers, m.publicId),
                    secondary: MemberAvatar(name: m.displayName, image: m.image),
                    title: Text(m.displayName),
                  ),
                const _SectionTitle('Etiquetas'),
                for (final l in board.labels)
                  CheckboxListTile(
                    value: _fLabels.contains(l.publicId),
                    onChanged: (_) => toggle(_fLabels, l.publicId),
                    secondary: CircleAvatar(
                        radius: 10, backgroundColor: parseColor(l.colourCode)),
                    title: Text(l.name),
                  ),
                const _SectionTitle('Prazo'),
                for (final e in _dueFilters.entries)
                  CheckboxListTile(
                    value: _fDue.contains(e.key),
                    onChanged: (_) => toggle(_fDue, e.key),
                    title: Text(e.value),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    _load();
  }

  // ------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return Scaffold(
      appBar: AppBar(
        title: Text(board?.name ?? 'Quadro'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
        actions: [
          if (board != null)
            MediaQuery.sizeOf(context).width >= 700
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.tonalIcon(
                      onPressed: _addList,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Nova lista'),
                    ),
                  )
                : IconButton(
                    tooltip: 'Nova lista',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: _addList,
                  ),
          IconButton(
            tooltip: 'Filtros',
            icon: Badge(
              isLabelVisible: _filtering,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _openFilters,
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          if (board != null)
            IconButton(
              tooltip: 'Configurações do quadro',
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                final r = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BoardSettingsScreen(board: board)));
                if (!context.mounted) return;
                if (r == 'deleted' || r == 'moved') {
                  Navigator.pop(context);
                } else {
                  _load();
                }
              },
            ),
        ],
      ),
      body: _error != null && board == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Tentar de novo')),
            ]))
          : board == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBoard(board),
    );
  }

  Widget _buildBoard(Board board) {
    final bg = Theme.of(context).colorScheme.surfaceContainerLowest;
    if (board.lists.isEmpty) {
      return Container(
        color: bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_column_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Este quadro ainda não tem listas.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addList,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Nova lista'),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Celular: coluna quase da largura da tela. Desktop: colunas fixas.
      final colWidth = (width * 0.85).clamp(240.0, 320.0);
      const sidePad = 8.0;
      const colSpace = 8.0; // margem horizontal de cada coluna (4 + 4)
      final content =
          board.lists.length * (colWidth + colSpace) + sidePad * 2;
      // Se todas as listas cabem na tela, centraliza o quadro.
      final extra = content < width ? (width - content) / 2 : 0.0;
      return Container(
        color: bg,
        child: Scrollbar(
          controller: _hScroll,
          thumbVisibility: !_isMobile,
          child: ListView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(
                sidePad + extra, 8, sidePad + extra, _isMobile ? 8 : 20),
            children: [
              for (final list in board.lists)
                _buildColumn(board, list, colWidth),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildColumn(Board board, BoardList list, double width) {
    final cs = Theme.of(context).colorScheme;
    final pos = board.lists.indexOf(list);
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(list.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text('${list.cards.length}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                PopupMenuButton<String>(
                  onSelected: (v) => _listAction(list, v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Renomear')),
                    if (pos > 0)
                      const PopupMenuItem(
                          value: 'left', child: Text('Mover para a esquerda')),
                    if (pos < board.lists.length - 1)
                      const PopupMenuItem(
                          value: 'right', child: Text('Mover para a direita')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Excluir lista')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (var i = 0; i < list.cards.length; i++)
                  _buildCardSlot(board, list, i),
                _buildEndTarget(list),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  alignment: Alignment.centerLeft),
              onPressed: () => _addCard(list),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar cartão'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSlot(Board board, BoardList list, int index) {
    final card = list.cards[index];
    return DragTarget<_DragCard>(
      onWillAcceptWithDetails: (d) => d.data.card.publicId != card.publicId,
      onAcceptWithDetails: (d) => _moveCard(d.data, list.publicId, index),
      builder: (context, candidates, _) {
        final tile = _CardTile(
          card: card,
          prefix: board.cardPrefix,
          onTap: () => _openCard(card),
        );
        final data = _DragCard(card, list.publicId);
        final feedback = Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 260, child: tile),
        );
        final ghost = Opacity(opacity: 0.3, child: tile);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (candidates.isNotEmpty) const _DropIndicator(),
            _isMobile
                ? LongPressDraggable<_DragCard>(
                    data: data,
                    onDragUpdate: _autoScroll,
                    feedback: feedback,
                    childWhenDragging: ghost,
                    child: tile,
                  )
                : Draggable<_DragCard>(
                    data: data,
                    onDragUpdate: _autoScroll,
                    feedback: feedback,
                    childWhenDragging: ghost,
                    child: tile,
                  ),
          ],
        );
      },
    );
  }

  Widget _buildEndTarget(BoardList list) {
    return DragTarget<_DragCard>(
      onAcceptWithDetails: (d) =>
          _moveCard(d.data, list.publicId, list.cards.length),
      builder: (context, candidates, _) => Column(
        children: [
          if (candidates.isNotEmpty) const _DropIndicator(),
          SizedBox(height: list.cards.isEmpty ? 80 : 40),
        ],
      ),
    );
  }
}

class _DropIndicator extends StatelessWidget {
  const _DropIndicator();

  @override
  Widget build(BuildContext context) => Container(
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _CardTile extends StatelessWidget {
  const _CardTile(
      {required this.card, required this.prefix, required this.onTap});
  final CardSummary card;
  final String prefix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final due = card.dueDate;
    final meta = <Widget>[
      if (card.cardNumber != null)
        Text(prefix.isEmpty ? '#${card.cardNumber}' : '$prefix-${card.cardNumber}',
            style: small),
      if (due != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule, size: 14, color: dueDateColor(context, due)),
          const SizedBox(width: 2),
          Text(formatDate(due),
              style: small.copyWith(color: dueDateColor(context, due))),
        ]),
      if (card.hasDescription) Icon(Icons.notes, size: 14, color: cs.onSurfaceVariant),
      if (card.commentCount > 0)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 2),
          Text('${card.commentCount}', style: small),
        ]),
      if (card.attachmentCount > 0)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.attach_file, size: 14, color: cs.onSurfaceVariant),
          Text('${card.attachmentCount}', style: small),
        ]),
      if (card.checklistTotal > 0)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_box_outlined,
              size: 14,
              color: card.checklistDone == card.checklistTotal
                  ? Colors.green
                  : cs.onSurfaceVariant),
          const SizedBox(width: 2),
          Text('${card.checklistDone}/${card.checklistTotal}', style: small),
        ]),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (card.labels.isNotEmpty) ...[
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final l in card.labels) LabelChip(label: l, small: true)
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text(card.title, style: Theme.of(context).textTheme.bodyMedium),
              if (meta.isNotEmpty || card.members.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(spacing: 10, runSpacing: 4, children: meta),
                    ),
                    for (final m in card.members.take(3))
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: MemberAvatar(
                            name: m.displayName, image: m.image, radius: 11),
                      ),
                    if (card.members.length > 3)
                      Text(' +${card.members.length - 3}', style: small),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
