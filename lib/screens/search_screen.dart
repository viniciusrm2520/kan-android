import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';
import '../utils.dart';
import 'board_screen.dart';
import 'card_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.workspace});
  final Workspace workspace;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = v.trim();
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await Session.api.search(widget.workspace.publicId, q, limit: 30);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _error = null;
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = '$e');
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.workspace.cardPrefix;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar em ${widget.workspace.name}',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _results.isEmpty
              ? Center(
                  child: Text(_q.text.trim().isEmpty
                      ? 'Digite para buscar quadros e cartões'
                      : 'Nenhum resultado'))
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    final isCard = r.type == 'card';
                    final desc = htmlToText(r.description);
                    return ListTile(
                      leading: Icon(isCard
                          ? Icons.sticky_note_2_outlined
                          : Icons.dashboard_outlined),
                      title: Text(r.title),
                      subtitle: Text(
                        isCard
                            ? [
                                if (r.cardNumber != null)
                                  prefix.isEmpty
                                      ? '#${r.cardNumber}'
                                      : '$prefix-${r.cardNumber}',
                                r.boardName ?? '',
                                r.listName ?? '',
                              ].where((s) => s.isNotEmpty).join(' · ')
                            : (desc.isEmpty ? 'Quadro' : desc),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => isCard
                              ? CardScreen(cardId: r.publicId)
                              : BoardScreen(boardId: r.publicId),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
