import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

class RaritioProfile {
  const RaritioProfile({
    required this.id,
    required this.nickname,
    required this.friendCode,
    this.email = '',
  });

  final String id;
  final String nickname;
  final String friendCode;
  final String email;

  factory RaritioProfile.fromRow(Map<String, dynamic> row) {
    return RaritioProfile(
      id: row['id']?.toString() ?? '',
      nickname: row['nickname']?.toString() ?? 'Raritio hráč',
      friendCode: row['friend_code']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
    );
  }
}

class FriendProfile {
  const FriendProfile({
    required this.id,
    required this.nickname,
    required this.friendCode,
  });

  final String id;
  final String nickname;
  final String friendCode;

  factory FriendProfile.fromRow(Map<String, dynamic> row) {
    return FriendProfile(
      id: row['friend_id']?.toString() ?? row['id']?.toString() ?? '',
      nickname: row['nickname']?.toString() ?? 'Kamoš',
      friendCode: row['friend_code']?.toString() ?? '',
    );
  }
}

class SharedBinderSummary {
  const SharedBinderSummary({
    required this.id,
    required this.ownerId,
    required this.ownerNickname,
    required this.name,
    required this.cardCount,
    required this.totalValue,
    required this.updatedAt,
    required this.shareToken,
    required this.isActive,
    required this.isOwner,
  });

  final String id;
  final String ownerId;
  final String ownerNickname;
  final String name;
  final int cardCount;
  final double totalValue;
  final DateTime? updatedAt;
  final String shareToken;
  final bool isActive;
  final bool isOwner;

  factory SharedBinderSummary.fromRow(
    Map<String, dynamic> row, {
    required String currentUserId,
  }) {
    final ownerId = row['owner_id']?.toString() ?? '';
    return SharedBinderSummary(
      id: row['id']?.toString() ?? '',
      ownerId: ownerId,
      ownerNickname: row['owner_nickname']?.toString() ?? 'Raritio hráč',
      name: row['name']?.toString() ?? 'Balík',
      cardCount: int.tryParse(row['card_count']?.toString() ?? '') ?? 0,
      totalValue:
          double.tryParse(row['total_value']?.toString() ?? '') ?? 0.0,
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
      shareToken: row['share_token']?.toString() ?? '',
      isActive: row['is_active'] != false,
      isOwner: ownerId == currentUserId,
    );
  }
}

class SharedBinderData {
  const SharedBinderData({
    required this.summary,
    required this.snapshot,
  });

  final SharedBinderSummary summary;
  final Map<String, dynamic> snapshot;
}

class SharedBinderService {
  final SupabaseClient _client = Supabase.instance.client;
  final Random _random = Random.secure();

  Future<void> _ensureAuth() async {
    if (_client.auth.currentUser != null) return;
    try {
      await _client.auth.signInAnonymously();
    } catch (e) {
      throw Exception(
        'Nepodarilo sa prihlásiť. V Supabase zapni Anonymous sign-ins v Authentication → Providers.',
      );
    }
  }

  String get _currentUserId {
    final id = _client.auth.currentUser?.id ?? '';
    if (id.isEmpty) {
      throw Exception('Chýba prihlásenie do Raritio účtu.');
    }
    return id;
  }

  Future<RaritioProfile?> getProfile() async {
    await _ensureAuth();
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', _currentUserId)
        .maybeSingle();
    if (row == null) return null;
    return RaritioProfile.fromRow(Map<String, dynamic>.from(row));
  }

  Future<RaritioProfile> ensureProfile({
    String? nickname,
    String? email,
  }) async {
    await _ensureAuth();
    final existing = await getProfile();
    if (existing != null) {
      if ((nickname != null && nickname.trim().isNotEmpty) ||
          (email != null && email.trim().isNotEmpty)) {
        return saveProfile(
          nickname: nickname?.trim().isNotEmpty == true
              ? nickname!.trim()
              : existing.nickname,
          email: email ?? existing.email,
        );
      }
      return existing;
    }

    final finalNickname = (nickname?.trim().isNotEmpty == true)
        ? nickname!.trim()
        : 'Raritio hráč';
    final finalEmail = (email?.trim().isNotEmpty == true) ? email!.trim() : '';

    for (var attempt = 0; attempt < 8; attempt++) {
      final code = _newFriendCode();
      try {
        final row = await _client
            .from('profiles')
            .insert({
              'id': _currentUserId,
              'nickname': finalNickname,
              'friend_code': code,
              'email': finalEmail.isEmpty ? null : finalEmail,
            })
            .select()
            .single();
        return RaritioProfile.fromRow(Map<String, dynamic>.from(row));
      } on PostgrestException catch (e) {
        if (e.code == '23505') continue;
        rethrow;
      }
    }
    throw Exception('Nepodarilo sa vytvoriť unikátny friend kód.');
  }

  Future<RaritioProfile> saveProfile({
    required String nickname,
    String? email,
  }) async {
    await _ensureAuth();
    final trimmedNickname = nickname.trim();
    if (trimmedNickname.isEmpty) {
      throw Exception('Prezývka nemôže byť prázdna.');
    }
    final trimmedEmail = email?.trim() ?? '';
    final row = await _client
        .from('profiles')
        .update({
          'nickname': trimmedNickname,
          'email': trimmedEmail.isEmpty ? null : trimmedEmail,
        })
        .eq('id', _currentUserId)
        .select()
        .single();
    await _client
        .from('shared_binders')
        .update({'owner_nickname': trimmedNickname})
        .eq('owner_id', _currentUserId);
    return RaritioProfile.fromRow(Map<String, dynamic>.from(row));
  }

  Future<List<FriendProfile>> getFriends() async {
    await _ensureAuth();
    final data = await _client.rpc('get_friends');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => FriendProfile.fromRow(Map<String, dynamic>.from(row)))
        .where((friend) => friend.id.isNotEmpty)
        .toList();
  }

  Future<FriendProfile> addFriendByCode(String code) async {
    await _ensureAuth();
    final cleaned = code.trim();
    if (cleaned.isEmpty) throw Exception('Zadaj friend kód.');
    final data = await _client.rpc(
      'add_friend_by_code',
      params: {'p_code': cleaned},
    );
    if (data is List && data.isNotEmpty && data.first is Map) {
      return FriendProfile.fromRow(
        Map<String, dynamic>.from(data.first as Map),
      );
    }
    throw Exception('Kamoša sa nepodarilo pridať.');
  }

  Future<void> removeFriend(String friendId) async {
    await _ensureAuth();
    await _client
        .from('friendships')
        .delete()
        .eq('user_id', _currentUserId)
        .eq('friend_id', friendId);
  }

  Future<List<SharedBinderSummary>> getSharedWithMe() async {
    await _ensureAuth();
    final rows = await _client
        .from('shared_binders')
        .select()
        .eq('is_active', true)
        .neq('owner_id', _currentUserId)
        .order('updated_at', ascending: false);
    return rows
        .map((row) => SharedBinderSummary.fromRow(
              Map<String, dynamic>.from(row),
              currentUserId: _currentUserId,
            ))
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<List<SharedBinderSummary>> getMySharedBinders() async {
    await _ensureAuth();
    final rows = await _client
        .from('shared_binders')
        .select()
        .eq('owner_id', _currentUserId)
        .eq('is_active', true)
        .order('updated_at', ascending: false);
    return rows
        .map((row) => SharedBinderSummary.fromRow(
              Map<String, dynamic>.from(row),
              currentUserId: _currentUserId,
            ))
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<SharedBinderData> getSharedBinder(String id) async {
    await _ensureAuth();
    final row = await _client
        .from('shared_binders')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw Exception('Balík už nie je dostupný.');
    }
    final map = Map<String, dynamic>.from(row);
    final snapshot = map['snapshot'];
    return SharedBinderData(
      summary: SharedBinderSummary.fromRow(
        map,
        currentUserId: _currentUserId,
      ),
      snapshot: snapshot is Map
          ? Map<String, dynamic>.from(snapshot)
          : <String, dynamic>{},
    );
  }

  Future<SharedBinderSummary> shareBinder({
    String? sharedId,
    required String name,
    required Map<String, dynamic> snapshot,
    required int cardCount,
    required double totalValue,
    String? existingToken,
  }) async {
    await _ensureAuth();
    final profile = await ensureProfile();
    final token = (existingToken?.trim().isNotEmpty == true)
        ? existingToken!.trim()
        : _newShareToken();

    if (sharedId != null && sharedId.isNotEmpty) {
      final updated = await _client
          .from('shared_binders')
          .update({
            'owner_nickname': profile.nickname,
            'name': name,
            'snapshot': snapshot,
            'card_count': cardCount,
            'total_value': totalValue,
            'is_active': true,
          })
          .eq('id', sharedId)
          .eq('owner_id', _currentUserId)
          .select()
          .maybeSingle();
      if (updated != null) {
        return SharedBinderSummary.fromRow(
          Map<String, dynamic>.from(updated),
          currentUserId: _currentUserId,
        );
      }
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      final actualToken = attempt == 0 ? token : _newShareToken();
      try {
        final row = await _client
            .from('shared_binders')
            .insert({
              'owner_id': _currentUserId,
              'owner_nickname': profile.nickname,
              'name': name,
              'snapshot': snapshot,
              'card_count': cardCount,
              'total_value': totalValue,
              'share_token': actualToken,
              'is_active': true,
            })
            .select()
            .single();
        return SharedBinderSummary.fromRow(
          Map<String, dynamic>.from(row),
          currentUserId: _currentUserId,
        );
      } on PostgrestException catch (e) {
        if (e.code == '23505') continue;
        rethrow;
      }
    }
    throw Exception('Nepodarilo sa vytvoriť zdieľanie.');
  }

  Future<void> syncSharedBinder({
    required String sharedId,
    required String name,
    required Map<String, dynamic> snapshot,
    required int cardCount,
    required double totalValue,
  }) async {
    await _ensureAuth();
    await _client
        .from('shared_binders')
        .update({
          'name': name,
          'snapshot': snapshot,
          'card_count': cardCount,
          'total_value': totalValue,
          'is_active': true,
        })
        .eq('id', sharedId)
        .eq('owner_id', _currentUserId)
        .select('id')
        .maybeSingle();
  }

  Future<void> stopSharing(String sharedId) async {
    await _ensureAuth();
    await _client
        .from('shared_binders')
        .update({'is_active': false})
        .eq('id', sharedId)
        .eq('owner_id', _currentUserId);
  }

  Future<SharedBinderData> acceptShareToken(String token) async {
    await _ensureAuth();
    final cleaned = token.trim();
    if (cleaned.isEmpty) throw Exception('Chýba kód zdieľania.');
    final result = await _client.rpc(
      'accept_shared_binder',
      params: {'p_token': cleaned},
    );
    final id = result?.toString() ?? '';
    if (id.isEmpty) throw Exception('Zdieľanie sa nenašlo.');
    return getSharedBinder(id);
  }

  static const String webBase = 'https://zdenoiva.github.io/raritio/';

  String shareLink(String token) =>
      '${webBase}?share=${Uri.encodeQueryComponent(token)}';

  String friendLink(String code) =>
      '${webBase}?friend=${Uri.encodeQueryComponent(code)}';

  String appShareLink(String token) => 'raritio://share/$token';

  String appFriendLink(String code) => 'raritio://friend/$code';

  String _newFriendCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => alphabet[_random.nextInt(alphabet.length)])
        .join();
  }

  String _newShareToken() {
    const alphabet =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(24, (_) => alphabet[_random.nextInt(alphabet.length)])
        .join();
  }
}
