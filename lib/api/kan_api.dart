import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Cliente REST da API do Kan. Documentação: https://kan.bn/api/v1/openapi.json
/// Autenticação: `Authorization: Bearer <API key>` (gerada em Configurações > API).
class KanApi {
  KanApi({required String baseUrl, required this.apiKey})
      : baseUrl = normalizeBaseUrl(baseUrl);

  final String baseUrl;
  final String apiKey;
  final http.Client _client = http.Client();

  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) url = 'https://kan.bn';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/api/v1')) url = '$url/api/v1';
    return url;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$baseUrl$path');
    if (query == null) return base;
    final q = <String, dynamic>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is List) {
        if (v.isNotEmpty) q[k] = v.map((e) => '$e').toList();
      } else {
        q[k] = '$v';
      }
    });
    return q.isEmpty ? base : base.replace(queryParameters: q);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['Authorization'] = 'Bearer $apiKey';
    req.headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      final streamed =
          await _client.send(req).timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'Tempo de conexão esgotado.');
    } catch (e) {
      throw ApiException(0, 'Falha de conexão: $e');
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _errorMessage(res.statusCode, text));
    }
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  String _errorMessage(int code, String body) {
    String? msg;
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final m = j['message'] ?? j['error'];
        if (m is List) {
          msg = m.join('\n');
        } else if (m != null) {
          msg = '$m';
        }
      }
    } catch (_) {}
    switch (code) {
      case 401:
        return 'Não autorizado. Verifique sua API key.';
      case 403:
        return msg ?? 'Você não tem permissão para esta ação.';
      case 404:
        return msg ?? 'Não encontrado.';
      case 429:
        return 'Muitas requisições. Aguarde um pouco.';
    }
    return msg ?? 'Erro $code';
  }

  Future<dynamic> _get(String p, [Map<String, dynamic>? q]) =>
      _send('GET', p, query: q);
  Future<dynamic> _post(String p, [Object? b]) => _send('POST', p, body: b);
  Future<dynamic> _put(String p, [Object? b]) => _send('PUT', p, body: b);
  Future<dynamic> _patch(String p, [Object? b]) => _send('PATCH', p, body: b);
  Future<dynamic> _delete(String p) => _send('DELETE', p);

  List<Map<String, dynamic>> _list(dynamic v) => v is List
      ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];
  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  // ---------------------------------------------------------------- Usuário

  Future<KanUser> getMe() async => KanUser.fromJson(_map(await _get('/users/me')));

  Future<void> updateUser({String? name, String? image}) => _put('/users', {
        'name': ?name,
        'image': ?image,
      });

  Future<void> setPassword(String newPassword) =>
      _post('/users/me/password', {'newPassword': newPassword});

  // ------------------------------------------------------------- Workspaces

  Future<List<Workspace>> getWorkspaces() async {
    final ws = _list(await _get('/workspaces'))
        .where((j) => j['deletedAt'] == null)
        .map(Workspace.fromListItem)
        .where((w) => w.publicId.isNotEmpty)
        .toList();
    // O formato achatado não traz o papel do usuário: busca em paralelo.
    return Future.wait(ws.map((w) async {
      if (w.role.isNotEmpty) return w;
      try {
        return w.copyWith(role: await myRole(w.publicId));
      } catch (_) {
        return w;
      }
    }));
  }

  Future<WorkspaceDetail> getWorkspace(String id) async =>
      WorkspaceDetail.fromJson(_map(await _get('/workspaces/$id')));

  Future<String> createWorkspace(String name,
      {String? description, String? slug}) async {
    final r = _map(await _post('/workspaces', {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (slug != null && slug.isNotEmpty) 'slug': slug,
    }));
    return '${r['publicId']}';
  }

  Future<void> updateWorkspace(
    String id, {
    String? name,
    String? slug,
    String? description,
    bool? showEmailsToMembers,
    int? weekStartDay,
  }) =>
      _put('/workspaces/$id', {
        'name': ?name,
        'slug': ?slug,
        'description': ?description,
        'showEmailsToMembers': ?showEmailsToMembers,
        'weekStartDay': ?weekStartDay,
      });

  Future<void> deleteWorkspace(String id) => _delete('/workspaces/$id');

  Future<bool> isWorkspaceSlugAvailable(String slug, {String? workspaceId}) async {
    final r = _map(await _get('/workspaces/check-slug-availability', {
      'workspaceSlug': slug,
      'workspacePublicId': workspaceId,
    }));
    return r['isAvailable'] == true && r['isReserved'] != true;
  }

  Future<List<SearchResult>> search(String workspaceId, String query,
          {int limit = 20}) async =>
      _list(await _get('/workspaces/$workspaceId/search',
              {'query': query, 'limit': limit}))
          .map(SearchResult.fromJson)
          .toList();

  // Membros do workspace
  Future<void> inviteMember(String workspaceId, String email) =>
      _post('/workspaces/$workspaceId/members/invite', {'email': email});

  Future<void> removeMember(String workspaceId, String memberId) =>
      _delete('/workspaces/$workspaceId/members/$memberId');

  Future<void> updateMemberRole(
          String workspaceId, String memberId, String role) =>
      _put('/workspaces/$workspaceId/members/$memberId/role', {'role': role});

  // Link de convite
  Future<InviteLink> getInviteLink(String workspaceId) async =>
      InviteLink.fromJson(_map(await _get('/workspaces/$workspaceId/invite')));

  Future<InviteLink> createInviteLink(String workspaceId) async =>
      InviteLink.fromJson(_map(await _post('/workspaces/$workspaceId/invites')));

  Future<void> deactivateInviteLinks(String workspaceId) =>
      _delete('/workspaces/$workspaceId/invites');

  Future<void> acceptInvite(String inviteCode) =>
      _post('/invites/accept', {'inviteCode': inviteCode});

  Future<String> myRole(String workspaceId) async {
    final r = _map(await _get('/workspaces/$workspaceId/permissions/me'));
    return '${r['role'] ?? ''}';
  }

  // Webhooks
  Future<List<Webhook>> getWebhooks(String workspaceId) async =>
      _list(await _get('/workspaces/$workspaceId/webhooks'))
          .map(Webhook.fromJson)
          .toList();

  Future<void> createWebhook(String workspaceId,
          {required String name,
          required String url,
          String? secret,
          required List<String> events}) =>
      _post('/workspaces/$workspaceId/webhooks', {
        'name': name,
        'url': url,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
        'events': events,
      });

  Future<void> updateWebhook(String workspaceId, String webhookId,
          {String? name,
          String? url,
          String? secret,
          List<String>? events,
          bool? active}) =>
      _put('/workspaces/$workspaceId/webhooks/$webhookId', {
        'name': ?name,
        'url': ?url,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
        'events': ?events,
        'active': ?active,
      });

  Future<void> deleteWebhook(String workspaceId, String webhookId) =>
      _delete('/workspaces/$workspaceId/webhooks/$webhookId');

  Future<Map<String, dynamic>> testWebhook(
          String workspaceId, String webhookId) async =>
      _map(await _post('/workspaces/$workspaceId/webhooks/$webhookId/test'));

  // ----------------------------------------------------------------- Quadros

  Future<List<BoardSummary>> getBoards(String workspaceId,
          {bool templates = false, bool archived = false}) async =>
      _list(await _get('/workspaces/$workspaceId/boards', {
        'type': templates ? 'template' : 'regular',
        // Só envia quando true: a API antiga do kan.bn converte a string
        // "false" com Boolean("false") === true e devolveria só arquivados.
        // Sem o parâmetro, as duas versões listam apenas os não arquivados.
        'archived': archived ? 'true' : null,
      })).map(BoardSummary.fromJson).toList();

  Future<Board> getBoard(
    String boardId, {
    List<String> members = const [],
    List<String> labels = const [],
    List<String> dueDateFilters = const [],
  }) async =>
      Board.fromJson(_map(await _get('/boards/$boardId', {
        'members': members,
        'labels': labels,
        'dueDateFilters': dueDateFilters,
      })));

  Future<String> createBoard(
    String workspaceId, {
    required String name,
    List<String> lists = const [],
    List<String> labels = const [],
    bool template = false,
    String? sourceBoardId,
  }) async {
    final r = _map(await _post('/workspaces/$workspaceId/boards', {
      'name': name,
      'lists': lists,
      'labels': labels,
      'type': template ? 'template' : 'regular',
      'sourceBoardPublicId': ?sourceBoardId,
    }));
    return '${r['publicId']}';
  }

  Future<void> updateBoard(String boardId,
          {String? name,
          String? slug,
          String? visibility,
          bool? favorite,
          bool? isArchived}) =>
      _put('/boards/$boardId', {
        'name': ?name,
        'slug': ?slug,
        'visibility': ?visibility,
        'favorite': ?favorite,
        'isArchived': ?isArchived,
      });

  Future<void> deleteBoard(String boardId) => _delete('/boards/$boardId');

  Future<void> moveBoard(String boardId, String targetWorkspaceId) =>
      _post('/boards/$boardId/move',
          {'targetWorkspacePublicId': targetWorkspaceId});

  Future<bool> isBoardSlugReserved(String boardId, String slug) async {
    final r = _map(await _get(
        '/boards/$boardId/check-slug-availability', {'boardSlug': slug}));
    return r['isReserved'] == true;
  }

  // Membros do quadro
  Future<List<Member>> getBoardMembers(String boardId) async =>
      _list(await _get('/boards/$boardId/members')).map(Member.fromJson).toList();

  Future<void> addBoardMember(String boardId, String workspaceMemberId,
          {String role = 'member'}) =>
      _post('/boards/$boardId/members',
          {'workspaceMemberPublicId': workspaceMemberId, 'role': role});

  Future<void> updateBoardMemberRole(
          String boardId, String workspaceMemberId, String role) =>
      _put('/boards/$boardId/members/$workspaceMemberId', {'role': role});

  Future<void> removeBoardMember(String boardId, String workspaceMemberId) =>
      _delete('/boards/$boardId/members/$workspaceMemberId');

  // ------------------------------------------------------------------ Listas

  Future<void> createList(String boardId, String name) =>
      _post('/lists', {'name': name, 'boardPublicId': boardId});

  Future<void> updateList(String listId, {String? name, int? index}) =>
      _put('/lists/$listId', {'name': ?name, 'index': ?index});

  Future<void> deleteList(String listId) => _delete('/lists/$listId');

  // --------------------------------------------------------------- Etiquetas

  Future<Label> createLabel(String boardId, String name, String colour) async =>
      Label.fromJson(_map(await _post('/labels',
          {'name': name, 'boardPublicId': boardId, 'colourCode': colour})));

  Future<void> updateLabel(String labelId, String name, String colour) =>
      _put('/labels/$labelId', {'name': name, 'colourCode': colour});

  Future<void> deleteLabel(String labelId) => _delete('/labels/$labelId');

  // ---------------------------------------------------------------- Cartões

  Future<String> createCard({
    required String listId,
    required String title,
    String description = '',
    List<String> labelIds = const [],
    List<String> memberIds = const [],
    bool atStart = false,
    DateTime? dueDate,
  }) async {
    final r = _map(await _post('/cards', {
      'title': title,
      'description': description,
      'listPublicId': listId,
      'labelPublicIds': labelIds,
      'memberPublicIds': memberIds,
      'position': atStart ? 'start' : 'end',
      if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
    }));
    return '${r['publicId']}';
  }

  Future<CardDetail> getCard(String cardId) async =>
      CardDetail.fromJson(_map(await _get('/cards/$cardId')));

  /// [clearDueDate] envia `dueDate: null` para remover o prazo.
  Future<void> updateCard(
    String cardId, {
    String? title,
    String? description,
    int? index,
    String? listId,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) =>
      _put('/cards/$cardId', {
        'title': ?title,
        'description': ?description,
        'index': ?index,
        'listPublicId': ?listId,
        if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
        if (clearDueDate) 'dueDate': null,
      });

  Future<void> deleteCard(String cardId) => _delete('/cards/$cardId');

  Future<String> duplicateCard(
    String cardId, {
    required String listId,
    String? title,
    bool copyLabels = true,
    bool copyMembers = true,
    bool copyChecklists = true,
  }) async {
    final r = _map(await _post('/cards/$cardId/duplicate', {
      'listPublicId': listId,
      if (title != null && title.isNotEmpty) 'title': title,
      'copyLabels': copyLabels,
      'copyMembers': copyMembers,
      'copyChecklists': copyChecklists,
    }));
    return '${r['publicId']}';
  }

  Future<void> toggleCardLabel(String cardId, String labelId) =>
      _put('/cards/$cardId/labels/$labelId');

  Future<void> toggleCardMember(String cardId, String workspaceMemberId) =>
      _put('/cards/$cardId/members/$workspaceMemberId');

  Future<ActivityPage> getActivities(String cardId,
          {int limit = 30,
          String? cursor,
          String? cursorPublicId,
          bool newestFirst = true}) async =>
      ActivityPage.fromJson(_map(await _get('/cards/$cardId/activities', {
        'limit': limit,
        'cursor': cursor,
        'cursorPublicId': cursorPublicId,
        'order': newestFirst ? 'newest' : 'oldest',
      })));

  // Comentários
  Future<void> addComment(String cardId, String comment) =>
      _post('/cards/$cardId/comments', {'comment': comment});

  Future<void> updateComment(String cardId, String commentId, String comment) =>
      _put('/cards/$cardId/comments/$commentId', {'comment': comment});

  Future<void> deleteComment(String cardId, String commentId) =>
      _delete('/cards/$cardId/comments/$commentId');

  // Checklists
  Future<void> createChecklist(String cardId, String name) =>
      _post('/cards/$cardId/checklists', {'name': name});

  Future<void> updateChecklist(String checklistId, String name) =>
      _put('/checklists/$checklistId', {'name': name});

  Future<void> deleteChecklist(String checklistId) =>
      _delete('/checklists/$checklistId');

  Future<void> createChecklistItem(String checklistId, String title) =>
      _post('/checklists/$checklistId/items', {'title': title});

  Future<void> updateChecklistItem(String itemId,
          {String? title, bool? completed, int? index}) =>
      _patch('/checklists/items/$itemId', {
        'title': ?title,
        'completed': ?completed,
        'index': ?index,
      });

  Future<void> deleteChecklistItem(String itemId) =>
      _delete('/checklists/items/$itemId');

  // Anexos: pede URL pré-assinada, envia o arquivo e confirma.
  Future<void> uploadAttachment(String cardId,
      {required String filename,
      required String contentType,
      required Uint8List bytes}) async {
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final up = _map(await _post('/cards/$cardId/attachments/upload-url', {
      'filename': safeName,
      'contentType': contentType,
      'size': bytes.length,
    }));
    final res = await http.put(Uri.parse('${up['url']}'),
        headers: {'Content-Type': contentType}, body: bytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, 'Falha ao enviar o arquivo.');
    }
    await _post('/cards/$cardId/attachments/confirm', {
      's3Key': up['key'],
      'filename': safeName,
      'originalFilename': filename,
      'contentType': contentType,
      'size': bytes.length,
    });
  }

  Future<void> deleteAttachment(String attachmentId) =>
      _delete('/attachments/$attachmentId');
}
