import 'package:shared_preferences/shared_preferences.dart';

import 'api/kan_api.dart';
import 'models.dart';

/// Guarda a conexão atual (servidor + API key) e o usuário logado.
class Session {
  static const _kUrl = 'kan_base_url';
  static const _kKey = 'kan_api_key';
  static const _kWorkspace = 'kan_last_workspace';

  static KanApi? _api;
  static KanUser? user;
  static String serverUrl = 'https://kan.bn';

  static KanApi get api {
    final a = _api;
    if (a == null) throw StateError('Sessão não iniciada');
    return a;
  }

  static bool get isLoggedIn => _api != null;

  static Future<bool> restore() async {
    final p = await SharedPreferences.getInstance();
    final url = p.getString(_kUrl);
    final key = p.getString(_kKey);
    if (url == null || key == null || key.isEmpty) return false;
    serverUrl = url;
    _api = KanApi(baseUrl: url, apiKey: key);
    return true;
  }

  /// Valida a API key chamando /users/me e salva se der certo.
  static Future<void> login(String url, String key) async {
    final api = KanApi(baseUrl: url, apiKey: key.trim());
    user = await api.getMe();
    _api = api;
    serverUrl = url.trim().isEmpty ? 'https://kan.bn' : url.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, serverUrl);
    await p.setString(_kKey, key.trim());
  }

  static Future<void> logout() async {
    _api = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    await p.remove(_kWorkspace);
  }

  static Future<String?> lastWorkspace() async =>
      (await SharedPreferences.getInstance()).getString(_kWorkspace);

  static Future<void> setLastWorkspace(String id) async =>
      (await SharedPreferences.getInstance()).setString(_kWorkspace, id);

  /// URL pública do site (sem /api/v1), usada para montar links.
  static String get siteUrl {
    var u = serverUrl.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    return u.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'/api/v1$'), '');
  }
}
