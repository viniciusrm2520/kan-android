// Modelos de dados da API do Kan (https://kan.bn/api/v1).

String _s(dynamic v) => v?.toString() ?? '';
String? _ns(dynamic v) => v?.toString();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _ni(dynamic v) => v is num ? v.toInt() : null;
bool _b(dynamic v) => v == true;
List<dynamic> _l(dynamic v) => v is List ? v : const [];
Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
DateTime? _d(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class KanUser {
  final String id;
  final String email;
  final String? name;
  final String? image;
  final bool hasPassword;

  KanUser({
    required this.id,
    required this.email,
    this.name,
    this.image,
    this.hasPassword = false,
  });

  String get displayName => (name == null || name!.isEmpty) ? email : name!;

  factory KanUser.fromJson(Map<String, dynamic> j) => KanUser(
        id: _s(j['id']),
        email: _s(j['email']),
        name: _ns(j['name']),
        image: _ns(j['image']),
        hasPassword: _b(j['hasPassword']),
      );
}

class Workspace {
  final String publicId;
  final String name;
  final String slug;
  final String? description;
  final String plan;
  final String cardPrefix;
  final String role;

  Workspace({
    required this.publicId,
    required this.name,
    required this.slug,
    this.description,
    this.plan = 'free',
    this.cardPrefix = '',
    this.role = 'member',
  });

  bool get isAdmin => role == 'admin';

  /// Item de GET /workspaces ({role, workspace: {...}}).
  factory Workspace.fromListItem(Map<String, dynamic> j) {
    final w = _m(j['workspace']);
    return Workspace(
      publicId: _s(w['publicId']),
      name: _s(w['name']),
      slug: _s(w['slug']),
      description: _ns(w['description']),
      plan: _s(w['plan']),
      cardPrefix: _s(w['cardPrefix']),
      role: _s(j['role']),
    );
  }
}

class Label {
  final String publicId;
  final String name;
  final String? colourCode;

  Label({required this.publicId, required this.name, this.colourCode});

  factory Label.fromJson(Map<String, dynamic> j) => Label(
        publicId: _s(j['publicId']),
        name: _s(j['name']),
        colourCode: _ns(j['colourCode']),
      );
}

class Member {
  final String publicId;
  final String email;
  final String status;
  final String? role;
  final String? userId;
  final String? userName;
  final String? image;
  final DateTime? createdAt;

  Member({
    required this.publicId,
    required this.email,
    this.status = 'active',
    this.role,
    this.userId,
    this.userName,
    this.image,
    this.createdAt,
  });

  String get displayName =>
      (userName == null || userName!.isEmpty) ? email : userName!;

  factory Member.fromJson(Map<String, dynamic> j) {
    final u = _m(j['user']);
    return Member(
      publicId: _s(j['publicId']),
      email: _s(j['email'] ?? u['email']),
      status: _s(j['status']),
      role: _ns(j['role']),
      userId: _ns(u['id']),
      userName: _ns(u['name']),
      image: _ns(u['image']),
      createdAt: _d(j['createdAt']),
    );
  }
}

class ChecklistItem {
  final String publicId;
  String title;
  bool completed;
  int index;

  ChecklistItem({
    required this.publicId,
    required this.title,
    required this.completed,
    required this.index,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        publicId: _s(j['publicId']),
        title: _s(j['title']),
        completed: _b(j['completed']),
        index: _i(j['index']),
      );
}

class Checklist {
  final String publicId;
  String name;
  final int index;
  final List<ChecklistItem> items;

  Checklist({
    required this.publicId,
    required this.name,
    required this.index,
    required this.items,
  });

  int get completedCount => items.where((i) => i.completed).length;

  factory Checklist.fromJson(Map<String, dynamic> j) => Checklist(
        publicId: _s(j['publicId']),
        name: _s(j['name']),
        index: _i(j['index']),
        items: _l(j['items']).map((e) => ChecklistItem.fromJson(_m(e))).toList()
          ..sort((a, b) => a.index.compareTo(b.index)),
      );
}

/// Cartão como aparece dentro de um quadro.
class CardSummary {
  final String publicId;
  final String title;
  final String? description;
  final int index;
  final int? cardNumber;
  final DateTime? dueDate;
  final List<Label> labels;
  final List<Member> members;
  final int attachmentCount;
  final int commentCount;
  final int checklistTotal;
  final int checklistDone;

  CardSummary({
    required this.publicId,
    required this.title,
    this.description,
    required this.index,
    this.cardNumber,
    this.dueDate,
    this.labels = const [],
    this.members = const [],
    this.attachmentCount = 0,
    this.commentCount = 0,
    this.checklistTotal = 0,
    this.checklistDone = 0,
  });

  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;

  factory CardSummary.fromJson(Map<String, dynamic> j) {
    final checklists =
        _l(j['checklists']).map((e) => Checklist.fromJson(_m(e))).toList();
    var total = 0;
    var done = 0;
    for (final c in checklists) {
      total += c.items.length;
      done += c.completedCount;
    }
    return CardSummary(
      publicId: _s(j['publicId']),
      title: _s(j['title']),
      description: _ns(j['description']),
      index: _i(j['index']),
      cardNumber: _ni(j['cardNumber']),
      dueDate: _d(j['dueDate']),
      labels: _l(j['labels']).map((e) => Label.fromJson(_m(e))).toList(),
      members: _l(j['members']).map((e) => Member.fromJson(_m(e))).toList(),
      attachmentCount: _l(j['attachments']).length,
      commentCount: _l(j['comments']).length,
      checklistTotal: total,
      checklistDone: done,
    );
  }
}

class BoardList {
  final String publicId;
  final String name;
  final int index;
  final List<CardSummary> cards;

  BoardList({
    required this.publicId,
    required this.name,
    required this.index,
    required this.cards,
  });

  factory BoardList.fromJson(Map<String, dynamic> j) => BoardList(
        publicId: _s(j['publicId']),
        name: _s(j['name']),
        index: _i(j['index']),
        cards: _l(j['cards']).map((e) => CardSummary.fromJson(_m(e))).toList()
          ..sort((a, b) => a.index.compareTo(b.index)),
      );
}

/// Item de GET /workspaces/{id}/boards.
class BoardSummary {
  final String publicId;
  final String name;
  final bool favorite;
  final int listCount;
  final List<Label> labels;

  BoardSummary({
    required this.publicId,
    required this.name,
    required this.favorite,
    required this.listCount,
    this.labels = const [],
  });

  factory BoardSummary.fromJson(Map<String, dynamic> j) => BoardSummary(
        publicId: _s(j['publicId']),
        name: _s(j['name']),
        favorite: _b(j['favorite']),
        listCount: _l(j['lists']).length,
        labels: _l(j['labels']).map((e) => Label.fromJson(_m(e))).toList(),
      );
}

class Board {
  final String publicId;
  final String name;
  final String slug;
  final String visibility;
  final bool isArchived;
  final bool favorite;
  final String workspacePublicId;
  final String cardPrefix;
  final List<Member> workspaceMembers;
  final List<Label> labels;
  final List<BoardList> lists;

  Board({
    required this.publicId,
    required this.name,
    required this.slug,
    required this.visibility,
    required this.isArchived,
    required this.favorite,
    required this.workspacePublicId,
    required this.cardPrefix,
    required this.workspaceMembers,
    required this.labels,
    required this.lists,
  });

  factory Board.fromJson(Map<String, dynamic> j) {
    final w = _m(j['workspace']);
    return Board(
      publicId: _s(j['publicId']),
      name: _s(j['name']),
      slug: _s(j['slug']),
      visibility: _s(j['visibility']),
      isArchived: _b(j['isArchived']),
      favorite: _b(j['favorite']),
      workspacePublicId: _s(w['publicId']),
      cardPrefix: _s(w['cardPrefix']),
      workspaceMembers: _l(w['members'])
          .map((e) => Member.fromJson(_m(e)))
          .where((m) => m.status != 'removed')
          .toList(),
      labels: _l(j['labels']).map((e) => Label.fromJson(_m(e))).toList(),
      lists: _l(j['lists']).map((e) => BoardList.fromJson(_m(e))).toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
    );
  }
}

class Attachment {
  final String publicId;
  final String contentType;
  final String? originalFilename;
  final int? size;
  final String? url;

  Attachment({
    required this.publicId,
    required this.contentType,
    this.originalFilename,
    this.size,
    this.url,
  });

  String get name => originalFilename ?? 'arquivo';

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        publicId: _s(j['publicId']),
        contentType: _s(j['contentType']),
        originalFilename: _ns(j['originalFilename']),
        size: _ni(j['size']),
        url: _ns(j['url']),
      );
}

class Activity {
  final String publicId;
  final String type;
  final DateTime? createdAt;
  final String? userName;
  final String? userId;
  final String? fromTitle;
  final String? toTitle;
  final DateTime? toDueDate;
  final String? fromListName;
  final String? toListName;
  final String? labelName;
  final String? memberName;
  final String? commentId;
  final String? comment;
  final String? commentCreatedBy;
  final bool commentDeleted;
  final bool commentEdited;
  final String? attachmentName;

  Activity({
    required this.publicId,
    required this.type,
    this.createdAt,
    this.userName,
    this.userId,
    this.fromTitle,
    this.toTitle,
    this.toDueDate,
    this.fromListName,
    this.toListName,
    this.labelName,
    this.memberName,
    this.commentId,
    this.comment,
    this.commentCreatedBy,
    this.commentDeleted = false,
    this.commentEdited = false,
    this.attachmentName,
  });

  bool get isComment => type == 'card.updated.comment.added' && comment != null;

  factory Activity.fromJson(Map<String, dynamic> j) {
    final user = _m(j['user']);
    final member = _m(j['member']);
    final memberUser = _m(member['user']);
    final comment = _m(j['comment']);
    final attachment = _m(j['attachment']);
    final userName = _ns(user['name']);
    final memberName = _ns(memberUser['name']);
    return Activity(
      publicId: _s(j['publicId']),
      type: _s(j['type']),
      createdAt: _d(j['createdAt']),
      userName: (userName == null || userName.isEmpty)
          ? _ns(user['email'])
          : userName,
      userId: _ns(user['id']),
      fromTitle: _ns(j['fromTitle']),
      toTitle: _ns(j['toTitle']),
      toDueDate: _d(j['toDueDate']),
      fromListName: _ns(_m(j['fromList'])['name']),
      toListName: _ns(_m(j['toList'])['name']),
      labelName: _ns(_m(j['label'])['name']),
      memberName: (memberName == null || memberName.isEmpty)
          ? _ns(memberUser['email'])
          : memberName,
      commentId: _ns(comment['publicId']),
      comment: _ns(comment['comment']),
      commentCreatedBy: _ns(comment['createdBy']),
      commentDeleted: comment['deletedAt'] != null,
      commentEdited: comment['updatedAt'] != null,
      attachmentName: _ns(attachment['originalFilename'] ?? attachment['filename']),
    );
  }

  /// Texto legível da atividade.
  String describe() {
    switch (type) {
      case 'card.created':
        return 'criou este cartão';
      case 'card.archived':
        return 'arquivou este cartão';
      case 'card.updated.title':
        return 'renomeou o cartão para "${toTitle ?? ''}"';
      case 'card.updated.description':
        return 'atualizou a descrição';
      case 'card.updated.index':
        return 'mudou a posição do cartão';
      case 'card.updated.list':
        return 'moveu de "${fromListName ?? '?'}" para "${toListName ?? '?'}"';
      case 'card.updated.label.added':
        return 'adicionou a etiqueta "${labelName ?? ''}"';
      case 'card.updated.label.removed':
        return 'removeu a etiqueta "${labelName ?? ''}"';
      case 'card.updated.member.added':
        return 'adicionou ${memberName ?? 'um membro'}';
      case 'card.updated.member.removed':
        return 'removeu ${memberName ?? 'um membro'}';
      case 'card.updated.comment.added':
        return 'comentou';
      case 'card.updated.comment.updated':
        return 'editou um comentário';
      case 'card.updated.comment.deleted':
        return 'excluiu um comentário';
      case 'card.updated.dueDate.added':
      case 'card.updated.dueDate.updated':
        return 'definiu o prazo';
      case 'card.updated.dueDate.removed':
        return 'removeu o prazo';
      case 'card.updated.checklist.added':
        return 'adicionou uma checklist';
      case 'card.updated.checklist.renamed':
        return 'renomeou uma checklist';
      case 'card.updated.checklist.deleted':
        return 'excluiu uma checklist';
      case 'card.updated.checklist.item.added':
        return 'adicionou um item à checklist';
      case 'card.updated.checklist.item.updated':
        return 'atualizou um item da checklist';
      case 'card.updated.checklist.item.completed':
        return 'concluiu um item da checklist';
      case 'card.updated.checklist.item.uncompleted':
        return 'reabriu um item da checklist';
      case 'card.updated.checklist.item.deleted':
        return 'excluiu um item da checklist';
      case 'card.updated.attachment.added':
        return 'anexou ${attachmentName ?? 'um arquivo'}';
      case 'card.updated.attachment.removed':
        return 'removeu o anexo ${attachmentName ?? ''}';
      default:
        return type.replaceAll('card.updated.', '').replaceAll('.', ' ');
    }
  }
}

class ActivityPage {
  final List<Activity> activities;
  final bool hasMore;
  final String? nextCursor;
  final String? nextCursorPublicId;

  ActivityPage(
      this.activities, this.hasMore, this.nextCursor, this.nextCursorPublicId);

  factory ActivityPage.fromJson(Map<String, dynamic> j) => ActivityPage(
        _l(j['activities']).map((e) => Activity.fromJson(_m(e))).toList(),
        _b(j['hasMore']),
        _ns(j['nextCursor']),
        _ns(j['nextCursorPublicId']),
      );
}

class NamedRef {
  final String publicId;
  final String name;
  NamedRef(this.publicId, this.name);
}

class CardDetail {
  final String publicId;
  final String title;
  final String? description;
  final int? cardNumber;
  final int index;
  final DateTime? dueDate;
  final List<Label> labels;
  final List<Attachment> attachments;
  final List<Checklist> checklists;
  final List<Member> members;
  final String listPublicId;
  final String listName;
  final String boardPublicId;
  final String boardName;
  final List<Label> boardLabels;
  final List<NamedRef> boardLists;
  final String workspacePublicId;
  final String cardPrefix;
  final List<Member> workspaceMembers;

  CardDetail({
    required this.publicId,
    required this.title,
    this.description,
    this.cardNumber,
    required this.index,
    this.dueDate,
    required this.labels,
    required this.attachments,
    required this.checklists,
    required this.members,
    required this.listPublicId,
    required this.listName,
    required this.boardPublicId,
    required this.boardName,
    required this.boardLabels,
    required this.boardLists,
    required this.workspacePublicId,
    required this.cardPrefix,
    required this.workspaceMembers,
  });

  String get reference => cardNumber == null
      ? ''
      : (cardPrefix.isEmpty ? '#$cardNumber' : '$cardPrefix-$cardNumber');

  factory CardDetail.fromJson(Map<String, dynamic> j) {
    final list = _m(j['list']);
    final board = _m(list['board']);
    final ws = _m(board['workspace']);
    return CardDetail(
      publicId: _s(j['publicId']),
      title: _s(j['title']),
      description: _ns(j['description']),
      cardNumber: _ni(j['cardNumber']),
      index: _i(j['index']),
      dueDate: _d(j['dueDate']),
      labels: _l(j['labels']).map((e) => Label.fromJson(_m(e))).toList(),
      attachments:
          _l(j['attachments']).map((e) => Attachment.fromJson(_m(e))).toList(),
      checklists: _l(j['checklists'])
          .map((e) => Checklist.fromJson(_m(e)))
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
      members: _l(j['members']).map((e) => Member.fromJson(_m(e))).toList(),
      listPublicId: _s(list['publicId']),
      listName: _s(list['name']),
      boardPublicId: _s(board['publicId']),
      boardName: _s(board['name']),
      boardLabels: _l(board['labels']).map((e) => Label.fromJson(_m(e))).toList(),
      boardLists: _l(board['lists'])
          .map((e) => NamedRef(_s(_m(e)['publicId']), _s(_m(e)['name'])))
          .toList(),
      workspacePublicId: _s(ws['publicId']),
      cardPrefix: _s(ws['cardPrefix']),
      workspaceMembers: _l(ws['members'])
          .map((e) => Member.fromJson(_m(e)))
          .where((m) => m.status != 'removed')
          .toList(),
    );
  }
}

class WorkspaceDetail {
  final String publicId;
  final String name;
  final String slug;
  final bool showEmailsToMembers;
  final int? weekStartDay;
  final List<Member> members;

  WorkspaceDetail({
    required this.publicId,
    required this.name,
    required this.slug,
    required this.showEmailsToMembers,
    this.weekStartDay,
    required this.members,
  });

  factory WorkspaceDetail.fromJson(Map<String, dynamic> j) => WorkspaceDetail(
        publicId: _s(j['publicId']),
        name: _s(j['name']),
        slug: _s(j['slug']),
        showEmailsToMembers: _b(j['showEmailsToMembers']),
        weekStartDay: _ni(j['weekStartDay']),
        members: _l(j['members']).map((e) => Member.fromJson(_m(e))).toList(),
      );
}

class Webhook {
  final String publicId;
  final String name;
  final String url;
  final List<String> events;
  final bool active;

  Webhook({
    required this.publicId,
    required this.name,
    required this.url,
    required this.events,
    required this.active,
  });

  factory Webhook.fromJson(Map<String, dynamic> j) => Webhook(
        publicId: _s(j['publicId']),
        name: _s(j['name']),
        url: _s(j['url']),
        events: _l(j['events']).map((e) => '$e').toList(),
        active: _b(j['active']),
      );
}

class InviteLink {
  final bool isActive;
  final String? inviteLink;
  final DateTime? expiresAt;

  InviteLink({required this.isActive, this.inviteLink, this.expiresAt});

  factory InviteLink.fromJson(Map<String, dynamic> j) => InviteLink(
        isActive: j.containsKey('isActive') ? _b(j['isActive']) : true,
        inviteLink: _ns(j['inviteLink']),
        expiresAt: _d(j['expiresAt']),
      );
}

class SearchResult {
  final String type; // 'board' ou 'card'
  final String publicId;
  final String title;
  final String? description;
  final String? boardPublicId;
  final String? boardName;
  final String? listName;
  final int? cardNumber;

  SearchResult({
    required this.type,
    required this.publicId,
    required this.title,
    this.description,
    this.boardPublicId,
    this.boardName,
    this.listName,
    this.cardNumber,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        type: _s(j['type']),
        publicId: _s(j['publicId']),
        title: _s(j['title']),
        description: _ns(j['description']),
        boardPublicId: _ns(j['boardPublicId']),
        boardName: _ns(j['boardName']),
        listName: _ns(j['listName']),
        cardNumber: _ni(j['cardNumber']),
      );
}
