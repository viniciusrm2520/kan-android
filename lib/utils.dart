import 'package:flutter/material.dart';

import 'models.dart';

// ------------------------------------------------------------------- Texto

/// O editor do Kan grava descrição/comentários em HTML. Converte para texto.
String htmlToText(String? html) {
  if (html == null || html.isEmpty) return '';
  var t = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  t = t
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Converte texto simples para o HTML que o editor web do Kan entende.
String textToHtml(String text) {
  final esc = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return esc
      .split('\n')
      .map((l) => l.trim().isEmpty ? '<p></p>' : '<p>$l</p>')
      .join();
}

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${two(d.hour)}:${two(d.minute)}';

String timeAgo(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  if (diff.inDays < 7) return 'há ${diff.inDays} d';
  return formatDate(d);
}

String formatBytes(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String guessContentType(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const map = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'mp4': 'video/mp4',
    'mp3': 'audio/mpeg',
  };
  return map[ext] ?? 'application/octet-stream';
}

// ------------------------------------------------------------------- Cores

const labelPalette = <String>[
  '#0d9488',
  '#65a30d',
  '#eab308',
  '#f97316',
  '#ef4444',
  '#ec4899',
  '#8b5cf6',
  '#3b82f6',
  '#06b6d4',
  '#64748b',
];

Color parseColor(String? hex, [Color fallback = Colors.blueGrey]) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

Color onColor(Color c) =>
    c.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

// ------------------------------------------------------------ Mensagens/UI

void showMsg(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('$e'),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'Confirmar',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String confirm = 'Salvar',
  bool multiline = false,
  bool allowEmpty = false,
  TextInputType? keyboardType,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: title,
        initial: initial,
        hint: hint,
        confirm: confirm,
        multiline: multiline,
        allowEmpty: allowEmpty,
        keyboardType: keyboardType,
      ),
    );

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    this.hint,
    required this.confirm,
    required this.multiline,
    required this.allowEmpty,
    this.keyboardType,
  });

  final String title;
  final String initial;
  final String? hint;
  final String confirm;
  final bool multiline;
  final bool allowEmpty;
  final TextInputType? keyboardType;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty && !widget.allowEmpty) return;
    Navigator.pop(context, widget.multiline ? _c.text : v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _c,
          autofocus: true,
          keyboardType: widget.multiline
              ? TextInputType.multiline
              : widget.keyboardType,
          minLines: widget.multiline ? 5 : 1,
          maxLines: widget.multiline ? 12 : 1,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.multiline ? null : (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

/// Diálogo para criar/editar etiqueta. Retorna (nome, cor).
Future<(String, String)?> labelDialog(BuildContext context,
        {String name = '', String? colour}) =>
    showDialog<(String, String)>(
      context: context,
      builder: (_) => _LabelDialog(name: name, colour: colour),
    );

class _LabelDialog extends StatefulWidget {
  const _LabelDialog({required this.name, this.colour});
  final String name;
  final String? colour;

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.name);
  late String _colour = widget.colour ?? labelPalette.first;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.name.isEmpty ? 'Nova etiqueta' : 'Editar etiqueta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Nome', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hex in labelPalette)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _colour = hex),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: parseColor(hex),
                    child: _colour.toLowerCase() == hex
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final n = _c.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(context, (n, _colour));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- Widgets

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(
      {super.key, required this.name, this.image, this.radius = 14});
  final String name;
  final String? image;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'[\s@.]+'))
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join();
    final color = Colors.primaries[name.hashCode.abs() % Colors.primaries.length];
    final img = image;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage:
          (img != null && img.startsWith('http')) ? NetworkImage(img) : null,
      child: Text(initials,
          style: TextStyle(
              fontSize: radius * 0.8,
              color: Colors.white,
              fontWeight: FontWeight.w600)),
    );
  }
}

class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label, this.small = false});
  final Label label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = parseColor(label.colourCode);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(small ? 4 : 8),
      ),
      child: Text(
        label.name,
        style: TextStyle(
            color: onColor(c),
            fontSize: small ? 11 : 13,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

Color dueDateColor(BuildContext context, DateTime due) {
  final now = DateTime.now();
  if (due.isBefore(now)) return Colors.red;
  if (due.difference(now).inHours < 24) return Colors.orange;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

/// Seleciona data e hora. Retorna null se cancelar.
Future<DateTime?> pickDateTime(BuildContext context, DateTime? initial) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? DateTime(now.year, now.month, now.day, 12)),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
