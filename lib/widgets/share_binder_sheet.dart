import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:raritio/services/shared_binder_service.dart';

Future<bool?> showShareBinderSheet(
  BuildContext context, {
  required SharedBinderSummary summary,
  required SharedBinderService service,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ShareBinderSheet(
      summary: summary,
      service: service,
    ),
  );
}

class _ShareBinderSheet extends StatefulWidget {
  const _ShareBinderSheet({
    required this.summary,
    required this.service,
  });

  final SharedBinderSummary summary;
  final SharedBinderService service;

  @override
  State<_ShareBinderSheet> createState() => _ShareBinderSheetState();
}

class _ShareBinderSheetState extends State<_ShareBinderSheet> {
  bool _stopping = false;
  bool _loadingFriends = true;
  bool _savingFriends = false;
  String? _friendsError;
  List<FriendProfile> _friends = const [];
  Set<String> _selectedFriendIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (!widget.summary.isOwner) {
      setState(() => _loadingFriends = false);
      return;
    }
    try {
      final results = await Future.wait([
        widget.service.getFriends(),
        widget.service.getSharedBinderFriendIds(widget.summary.id),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<FriendProfile>;
        _selectedFriendIds = results[1] as Set<String>;
        _loadingFriends = false;
        _friendsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFriends = false;
        _friendsError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _saveFriends() async {
    setState(() => _savingFriends = true);
    try {
      await widget.service.setSharedBinderFriends(
        widget.summary.id,
        _selectedFriendIds,
      );
      if (!mounted) return;
      setState(() => _savingFriends = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zdieľanie s kamošmi je uložené.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingFriends = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Výber sa nepodarilo uložiť: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _share() async {
    final token = widget.summary.shareToken;
    final link = widget.service.shareLink(token);
    final text = 'Pridaj si môj balík „${widget.summary.name}“ v Raritio.\n'
        'Kód: $token\n$link';
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Raritio – ${widget.summary.name}',
      ),
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.summary.shareToken));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kód zdieľania je skopírovaný.')),
    );
  }

  Future<void> _stopSharing() async {
    setState(() => _stopping = true);
    try {
      await widget.service.stopSharing(widget.summary.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zdieľanie sa nepodarilo zrušiť: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.service.shareLink(widget.summary.shareToken);

    return Container(
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
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.ios_share_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zdieľať balík',
                        style: TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
            const Text(
              'Kamoš môže naskenovať QR bežnou kamerou. Ak Raritio ešte nemá, otvorí sa jednoduchá stránka s tlačidlom na stiahnutie.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _copyCode,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2D2D35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded,
                        size: 18, color: Color(0xFF60A5FA)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        widget.summary.shareToken,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.android_rounded),
                label: const Text('Zdieľať cez Android'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (widget.summary.isOwner) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFF2D2D35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Zdieľať kamošom',
                            style: TextStyle(
                              color: Color(0xFFF8FAFC),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_selectedFriendIds.isNotEmpty)
                          Text(
                            '${_selectedFriendIds.length} vybraní',
                            style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Kamoši, ktorí už majú Raritio, uvidia balík hneď po obnovení.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingFriends)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (_friendsError != null)
                      Text(
                        _friendsError!,
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 11,
                        ),
                      )
                    else if (_friends.isEmpty)
                      const Text(
                        'Zatiaľ nemáš kamošov. Pridaj si ich v Zdieľané → Kamoši.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      )
                    else ...[
                      ..._friends.map(
                        (friend) => CheckboxListTile(
                          value: _selectedFriendIds.contains(friend.id),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedFriendIds.add(friend.id);
                              } else {
                                _selectedFriendIds.remove(friend.id);
                              }
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFF3B82F6),
                          checkColor: Colors.white,
                          title: Text(
                            friend.nickname,
                            style: const TextStyle(
                              color: Color(0xFFF8FAFC),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Friend kód: ${friend.friendCode}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _savingFriends ? null : _saveFriends,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF93C5FD),
                            side: const BorderSide(color: Color(0x663B82F6)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _savingFriends
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Uložiť výber kamošov'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.summary.isOwner) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _stopping ? null : _stopSharing,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFCA5A5),
                        side: const BorderSide(color: Color(0x66EF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: _stopping
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Zrušiť zdieľanie'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFF2D2D35)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Zavrieť'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
