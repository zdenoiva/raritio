import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:raritio/services/shared_binder_service.dart';

class SharedBinderDetailScreen extends StatefulWidget {
  const SharedBinderDetailScreen({
    super.key,
    required this.service,
    required this.summary,
  });

  final SharedBinderService service;
  final SharedBinderSummary summary;

  @override
  State<SharedBinderDetailScreen> createState() =>
      _SharedBinderDetailScreenState();
}

class _SharedBinderDetailScreenState extends State<SharedBinderDetailScreen> {
  SharedBinderData? _data;
  String? _error;
  bool _loading = true;
  Map<String, CardLike> _likes = <String, CardLike>{};
  final Set<String> _likePending = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.getSharedBinder(widget.summary.id);
      Map<String, CardLike> likes = <String, CardLike>{};
      try {
        likes = await widget.service.getCardLikes(widget.summary.id);
      } catch (_) {
        // Likes are optional; the binder still opens without them.
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _likes = likes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _toggleLike(String cardId) async {
    if (_likePending.contains(cardId)) return;
    setState(() => _likePending.add(cardId));
    try {
      final result = await widget.service.toggleCardLike(
        widget.summary.id,
        cardId,
      );
      if (!mounted) return;
      setState(() {
        _likes[cardId] = result;
        _likePending.remove(cardId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _likePending.remove(cardId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Like sa nepodarilo uložiť: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _data?.summary ?? widget.summary;
    final cards = _cardsFromSnapshot(_data?.snapshot);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0C),
        foregroundColor: Colors.white,
        title: Text(
          summary.name,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF3B82F6),
                  backgroundColor: const Color(0xFF16161A),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _SharedBinderHeader(
                          summary: summary,
                          cardCount: cards.length,
                        ),
                      ),
                      if (cards.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyCards(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisExtent: 318,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final card = cards[index];
                                final cardId = card['id']?.toString() ?? '';
                                return _SharedCard(
                                  card: card,
                                  like: _likes[cardId] ??
                                      const CardLike(count: 0, likedByMe: false),
                                  canLike: !summary.isOwner,
                                  pending: _likePending.contains(cardId),
                                  onToggleLike: () => _toggleLike(cardId),
                                );
                              },
                              childCount: cards.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  List<Map<String, dynamic>> _cardsFromSnapshot(
    Map<String, dynamic>? snapshot,
  ) {
    final raw = snapshot?['cards'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((card) => Map<String, dynamic>.from(card))
        .toList();
  }
}

class _SharedBinderHeader extends StatelessWidget {
  const _SharedBinderHeader({
    required this.summary,
    required this.cardCount,
  });

  final SharedBinderSummary summary;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final updated = summary.updatedAt;
    final updatedText = updated == null
        ? 'neznámy čas'
        : DateFormat('d. M. yyyy, HH:mm').format(updated.toLocal());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2D2D35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 16, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Zdieľa ${summary.ownerNickname}',
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _Pill(
                  icon: Icons.style_outlined,
                  text: '$cardCount kariet',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Aktualizované $updatedText',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Read-only náhľad. Vlastné fotky sa v zdieľaní nezobrazujú.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedCard extends StatelessWidget {
  const _SharedCard({
    required this.card,
    required this.like,
    required this.canLike,
    required this.pending,
    required this.onToggleLike,
  });

  final Map<String, dynamic> card;
  final CardLike like;
  final bool canLike;
  final bool pending;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    final name = card['name']?.toString() ?? 'Karta';
    final set = card['set']?.toString() ?? '';
    final rarity = card['rarity']?.toString() ?? '';
    final price = double.tryParse(card['currentPrice']?.toString() ?? '') ?? 0;
    final image = card['imageUri']?.toString() ?? '';
    final finish = card['finish']?.toString() ?? '';
    final color = _rarityColor(rarity);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _cardImage(image),
                Positioned(
                  top: 7,
                  left: 7,
                  right: 7,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (rarity.isNotEmpty)
                        _Pill(text: rarity, small: true),
                      const Spacer(),
                      if (finish.isNotEmpty && finish.toLowerCase() != 'normal')
                        _Pill(
                          text: _finishLabel(finish),
                          small: true,
                          accent: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
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
                  set,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    _LikeButton(
                      like: like,
                      canLike: canLike,
                      pending: pending,
                      onTap: onToggleLike,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardImage(String uri) {
    if (uri.startsWith('data:image') && uri.contains(',')) {
      try {
        final bytes = base64Decode(uri.split(',').last);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _NoImage(),
        );
      } catch (_) {
        return const _NoImage();
      }
    }
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _NoImage(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const _NoImage(loading: true);
        },
      );
    }
    return const _NoImage();
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.like,
    required this.canLike,
    required this.pending,
    required this.onTap,
  });

  final CardLike like;
  final bool canLike;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: canLike && !pending ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0C),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: like.likedByMe
                ? const Color(0x66EF4444)
                : const Color(0xFF2D2D35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                like.likedByMe
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 15,
                color: like.likedByMe
                    ? const Color(0xFFF87171)
                    : const Color(0xFF94A3B8),
              ),
            const SizedBox(width: 4),
            Text(
              '${like.count}',
              style: TextStyle(
                color: like.likedByMe
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoImage extends StatelessWidget {
  const _NoImage({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.image_not_supported_outlined,
                  color: Color(0xFF64748B), size: 26),
            if (!loading) ...[
              const SizedBox(height: 5),
              const Text(
                'Bez obrázka',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    this.icon,
    required this.text,
    this.small = false,
    this.accent = false,
  });

  final IconData? icon;
  final String text;
  final bool small;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0xFF3B82F6).withValues(alpha: 0.85)
            : const Color(0xFF0A0A0C).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: small ? 9 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCards extends StatelessWidget {
  const _EmptyCards();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined, size: 44, color: Color(0xFF64748B)),
            SizedBox(height: 12),
            Text(
              'Balík je prázdny',
              style: TextStyle(
                color: Color(0xFFF8FAFC),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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

Color _rarityColor(String rarity) {
  final value = rarity.toLowerCase();
  if (value.contains('secret') ||
      value.contains('rainbow') ||
      value.contains('hyper')) {
    return const Color(0xFFF472B6);
  }
  if (value.contains('illustration') ||
      value.contains('alt art') ||
      value.contains('special')) {
    return const Color(0xFFA78BFA);
  }
  if (value.contains('ultra') ||
      value.contains('gold') ||
      value.contains('vmax') ||
      value.contains('vstar') ||
      value.contains('ex') ||
      value.contains('gx')) {
    return const Color(0xFFF59E0B);
  }
  if (value.contains('holo') || value.contains('foil')) {
    return const Color(0xFF8B5CF6);
  }
  if (value.contains('rare')) return const Color(0xFF3B82F6);
  if (value.contains('uncommon')) return const Color(0xFF22C55E);
  return const Color(0xFF64748B);
}

String _finishLabel(String finish) {
  switch (finish.toLowerCase()) {
    case 'holo':
      return 'Holo';
    case 'reverse':
      return 'Reverse Holo';
    case 'rainbow':
      return 'Rainbow';
    case 'gold':
      return 'Gold';
    case 'cosmos':
      return 'Cosmos';
    case 'textured':
      return 'Texture';
    case 'etched':
      return 'Etched';
    case 'foil':
      return 'Foil';
    case 'firstedition':
      return '1st Edition';
    default:
      return finish;
  }
}
