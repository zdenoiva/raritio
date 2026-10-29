import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:raritio/screens/qr_scan_screen.dart';
import 'package:raritio/screens/shared_binder_detail_screen.dart';
import 'package:raritio/services/shared_binder_service.dart';

class SharedBindersScreen extends StatefulWidget {
  const SharedBindersScreen({super.key, required this.service});

  final SharedBinderService service;

  @override
  State<SharedBindersScreen> createState() => _SharedBindersScreenState();
}

class _SharedBindersScreenState extends State<SharedBindersScreen> {
  RaritioProfile? _profile;
  List<FriendProfile> _friends = const [];
  List<SharedBinderSummary> _shared = const [];
  List<SharedBinderSummary> _mine = const [];
  bool _loading = true;
  String? _error;
  bool _profilePromptShown = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await widget.service.getProfile() ??
          await widget.service.ensureProfile();
      final results = await Future.wait([
        widget.service.getFriends(),
        widget.service.getSharedWithMe(),
        widget.service.getMySharedBinders(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _friends = results[0] as List<FriendProfile>;
        _shared = results[1] as List<SharedBinderSummary>;
        _mine = results[2] as List<SharedBinderSummary>;
        _loading = false;
        _error = null;
      });

      if (!_profilePromptShown && profile.nickname == 'Raritio hráč') {
        _profilePromptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _editProfile();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _profile?.friendCode ?? '';
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend kód je skopírovaný.')),
    );
  }

  Future<void> _showFriendQr() async {
    final profile = _profile;
    if (profile == null || profile.friendCode.isEmpty) return;
    final link = widget.service.friendLink(profile.friendCode);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F13),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3F3F46),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Môj QR kód',
                style: TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kamoš naskenuje kód a pridá si ťa ako kamoša.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: link,
                  version: QrVersions.auto,
                  size: 220,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0A0A0C),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0A0A0C),
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                profile.nickname,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'Friend kód: ${profile.friendCode}',
                style: const TextStyle(
                  color: Color(0xFF93C5FD),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2D2D35)),
                ),
                child: const Text(
                  'Ak appku ešte nemá, po naskenovaní sa mu otvorí stránka s tlačidlom na stiahnutie. Potom zadá kód v Zdieľané → Pridať kód.',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Pridaj si ma v Raritio. Friend kód: ${profile.friendCode}\n$link',
                        subject: 'Raritio – pozvánka',
                      ),
                    );
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Zdieľať pozvánku'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Zavrieť'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    final nicknameController =
        TextEditingController(text: profile?.nickname == 'Raritio hráč' ? '' : profile?.nickname);
    final emailController = TextEditingController(text: profile?.email ?? '');
    String? localError;
    var saving = false;

    final result = await showDialog<RaritioProfile>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Môj profil'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nicknameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Prezývka',
                    hintText: 'Ako ťa majú vidieť kamoši',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (voliteľný)',
                    hintText: 'len pre tvoj kontakt',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Friend kód: ${profile?.friendCode ?? '—'}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
                if (localError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    localError!,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Zrušiť'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final nickname = nicknameController.text.trim();
                      if (nickname.isEmpty) {
                        setDialogState(() {
                          localError = 'Zadaj prezývku.';
                        });
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        localError = null;
                      });
                      try {
                        final saved = await widget.service.saveProfile(
                          nickname: nickname,
                          email: emailController.text,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context, saved);
                      } catch (e) {
                        if (!context.mounted) return;
                        setDialogState(() {
                          saving = false;
                          localError =
                              e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Uložiť'),
            ),
          ],
        ),
      ),
    );

    nicknameController.dispose();
    emailController.dispose();
    if (result != null) {
      setState(() => _profile = result);
      await _load(quiet: true);
    }
  }

  Future<void> _addFriendByCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pridať kamoša'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Friend kód',
            hintText: 'napr. AB3K9Q',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().toUpperCase()),
            child: const Text('Pridať'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty) return;

    try {
      final friend = await widget.service.addFriendByCode(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kamoš ${friend.nickname} je pridaný.')),
      );
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _acceptShareCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pridať zdieľaný balík'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Kód zdieľania',
            hintText: 'Vlož kód z QR alebo správy',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Pridať'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty) return;

    try {
      final data = await widget.service.acceptShareToken(code);
      if (!mounted) return;
      await _load(quiet: true);
      if (!mounted) return;
      await _openSharedBinder(data.summary);
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _openQr() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScanScreen()),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    final cleaned = value.trim();

    try {
      final shareToken = _extractShareToken(cleaned);
      if (shareToken != null) {
        final data = await widget.service.acceptShareToken(shareToken);
        if (!mounted) return;
        await _load(quiet: true);
        if (!mounted) return;
        await _openSharedBinder(data.summary);
        return;
      }

      final friendCode = _extractFriendCode(cleaned);
      if (friendCode != null) {
        final friend = await widget.service.addFriendByCode(friendCode);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamoš ${friend.nickname} je pridaný.')),
        );
        await _load(quiet: true);
        return;
      }

      _showError(Exception('QR kód nie je pre Raritio.'));
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  String? _extractShareToken(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final queryToken = uri.queryParameters['share']?.trim() ?? '';
      if (queryToken.isNotEmpty) return queryToken;
      if (uri.scheme == 'raritio' && uri.host == 'share') {
        final token = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
        return token.isEmpty ? null : token;
      }
      if (value.contains('/share/')) {
        final token = value.split('/share/').last.split(RegExp(r'[?#]')).first;
        return token.isEmpty ? null : token;
      }
    }
    if (value.length >= 16 && !value.contains('://')) return value;
    return null;
  }

  String? _extractFriendCode(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final queryCode = uri.queryParameters['friend']?.trim() ?? '';
      if (queryCode.isNotEmpty) return queryCode.toUpperCase();
      if (uri.scheme == 'raritio' && uri.host == 'friend') {
        final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
        return code.isEmpty ? null : code.toUpperCase();
      }
    }
    final compact = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (compact.length == 6) return compact;
    return null;
  }

  Future<void> _openSharedBinder(SharedBinderSummary summary) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedBinderDetailScreen(
          service: widget.service,
          summary: summary,
        ),
      ),
    );
    if (mounted) await _load(quiet: true);
  }

  Future<void> _removeFriend(FriendProfile friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Odobrať ${friend.nickname}?'),
        content: const Text('Kamoš nebude mať prístup k tvojim novým zdieľaniam.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Odobrať'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.removeFriend(friend.id);
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _stopSharing(SharedBinderSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zrušiť zdieľanie?'),
        content: Text(
          'Balík „${summary.name}“ prestane byť dostupný kamošom. Karty v tvojom balíku zostanú.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nechať'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Zrušiť zdieľanie'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.stopSharing(summary.id);
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  void _showError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<_OwnerGroup> _ownerGroups() {
    final groups = <String, _OwnerGroup>{};
    for (final binder in _shared) {
      final key = '${binder.ownerId}\u0000${binder.ownerNickname}';
      groups.putIfAbsent(
        key,
        () => _OwnerGroup(
          ownerId: binder.ownerId,
          nickname: binder.ownerNickname,
          binders: [],
        ),
      ).binders.add(binder);
    }
    final list = groups.values.toList();
    list.sort((a, b) => a.nickname.toLowerCase().compareTo(
          b.nickname.toLowerCase(),
        ));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A0C),
          foregroundColor: Colors.white,
          title: const Text('Zdieľané'),
          actions: [
            IconButton(
              onPressed: _acceptShareCode,
              tooltip: 'Pridať zdieľanie podľa kódu',
              icon: const Icon(Icons.add_link_rounded),
            ),
            IconButton(
              onPressed: _openQr,
              tooltip: 'Skenovať QR',
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
            IconButton(
              onPressed: () => _load(),
              tooltip: 'Obnoviť',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF3B82F6),
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFF94A3B8),
            tabs: [
              Tab(text: 'Od kamošov'),
              Tab(text: 'Moje zdieľané'),
              Tab(text: 'Kamoši'),
            ],
          ),
        ),
        body: _loading && _profile == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _profile == null
                ? _ErrorView(message: _error!, onRetry: () => _load())
                : TabBarView(
                    children: [
                      _buildSharedTab(),
                      _buildMineTab(),
                      _buildFriendsTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSharedTab() {
    final groups = _ownerGroups();
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      color: const Color(0xFF3B82F6),
      backgroundColor: const Color(0xFF16161A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _ProfileCard(
            profile: _profile,
            onEdit: _editProfile,
            onCopy: _copyCode,
            onQr: _showFriendQr,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Balíky od kamošov',
                  style: TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _acceptShareCode,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Pridať kód'),
              ),
            ],
          ),
          if (_shared.isEmpty)
            const _EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'Zatiaľ ti nikto nezdieľal balík',
              text: 'Keď ti kamoš pošle kód alebo QR, pridáš si balík sem.',
            )
          else
            ...groups.map(
              (group) => _OwnerTile(
                group: group,
                onOpen: _openSharedBinder,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMineTab() {
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      color: const Color(0xFF3B82F6),
      backgroundColor: const Color(0xFF16161A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Balíky, ktoré zdieľaš',
            style: TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Zmeny sa kamošom prejavia pri ďalšom obnovení.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_mine.isEmpty)
            const _EmptyState(
              icon: Icons.ios_share_rounded,
              title: 'Zatiaľ nezdieľaš žiadny balík',
              text: 'Otvor balík v appke, zvoľ Spravovať balík → Zdieľať balík.',
            )
          else
            ..._mine.map(
              (summary) => _BinderTile(
                summary: summary,
                onTap: () => _openSharedBinder(summary),
                trailing: IconButton(
                  tooltip: 'Zrušiť zdieľanie',
                  onPressed: () => _stopSharing(summary),
                  icon: const Icon(
                    Icons.link_off_rounded,
                    color: Color(0xFFFCA5A5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFriendsTab() {
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      color: const Color(0xFF3B82F6),
      backgroundColor: const Color(0xFF16161A),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _ProfileCard(
            profile: _profile,
            onEdit: _editProfile,
            onCopy: _copyCode,
            onQr: _showFriendQr,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Kamoši',
                  style: TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _addFriendByCode,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Pridať'),
              ),
            ],
          ),
          if (_friends.isEmpty)
            const _EmptyState(
              icon: Icons.person_outline_rounded,
              title: 'Zatiaľ nemáš kamošov',
              text: 'Pridaj kamoša podľa friend kódu alebo QR.',
            )
          else
            ..._friends.map(
              (friend) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2D2D35)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    child: Text(
                      friend.nickname.isEmpty
                          ? '?'
                          : friend.nickname.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(
                    friend.nickname,
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Friend kód: ${friend.friendCode}',
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  trailing: IconButton(
                    tooltip: 'Odobrať kamoša',
                    onPressed: () => _removeFriend(friend),
                    icon: const Icon(
                      Icons.person_remove_outlined,
                      color: Color(0xFFFCA5A5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OwnerGroup {
  _OwnerGroup({
    required this.ownerId,
    required this.nickname,
    required this.binders,
  });

  final String ownerId;
  final String nickname;
  final List<SharedBinderSummary> binders;
}

class _OwnerTile extends StatelessWidget {
  const _OwnerTile({
    required this.group,
    required this.onOpen,
  });

  final _OwnerGroup group;
  final Future<void> Function(SharedBinderSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2D2D35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: const Color(0xFF94A3B8),
          collapsedIconColor: const Color(0xFF94A3B8),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            child: Text(
              group.nickname.isEmpty
                  ? '?'
                  : group.nickname.characters.first.toUpperCase(),
            ),
          ),
          title: Text(
            group.nickname,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '${group.binders.length} ${group.binders.length == 1 ? 'balík' : 'balíky'}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          children: group.binders
              .map(
                (summary) => _BinderTile(
                  summary: summary,
                  onTap: () => onOpen(summary),
                  padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _BinderTile extends StatelessWidget {
  const _BinderTile({
    required this.summary,
    required this.onTap,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(0, 0, 0, 8),
  });

  final SharedBinderSummary summary;
  final VoidCallback onTap;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final updated = summary.updatedAt;
    final updatedText = updated == null
        ? ''
        : ' · ${DateFormat('d. M.').format(updated.toLocal())}';
    return Padding(
      padding: padding,
      child: Material(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.style_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary.cardCount} kariet · \$${summary.totalValue.toStringAsFixed(2)}$updatedText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onEdit,
    required this.onCopy,
    required this.onQr,
  });

  final RaritioProfile? profile;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    final nickname = profile?.nickname ?? 'Raritio hráč';
    final code = profile?.friendCode ?? '—';
    final email = profile?.email ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172554), Color(0xFF16161A)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x553B82F6)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              nickname.isEmpty ? 'R' : nickname.characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                InkWell(
                  onTap: onCopy,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Friend kód: $code',
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Color(0xFF93C5FD),
                        ),
                      ],
                    ),
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onQr,
            tooltip: 'Môj QR kód',
            icon: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF93C5FD)),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Upraviť profil',
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF93C5FD)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Column(
        children: [
          Icon(icon, size: 44, color: const Color(0xFF64748B)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 46, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Skúsiť znova'),
            ),
          ],
        ),
      ),
    );
  }
}
