import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:raritio/services/shared_binder_service.dart';

class SharedCardDetailScreen extends StatefulWidget {
  const SharedCardDetailScreen({
    super.key,
    required this.service,
    required this.summary,
    required this.card,
    required this.initialLike,
    required this.onLikeChanged,
  });

  final SharedBinderService service;
  final SharedBinderSummary summary;
  final Map<String, dynamic> card;
  final CardLike initialLike;
  final ValueChanged<CardLike> onLikeChanged;

  @override
  State<SharedCardDetailScreen> createState() => _SharedCardDetailScreenState();
}

class _SharedCardDetailScreenState extends State<SharedCardDetailScreen> {
  late CardLike _like = widget.initialLike;
  bool _pending = false;

  Future<void> _toggleLike() async {
    if (_pending || widget.summary.isOwner) return;
    setState(() => _pending = true);
    try {
      final like = await widget.service.toggleCardLike(
        widget.summary.id,
        widget.card['id']?.toString() ?? '',
      );
      if (!mounted) return;
      setState(() {
        _like = like;
        _pending = false;
      });
      widget.onLikeChanged(like);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending = false);
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
    final card = widget.card;
    final name = card['name']?.toString() ?? 'Karta';
    final set = card['set']?.toString() ?? '';
    final rarity = card['rarity']?.toString() ?? '';
    final number = card['number']?.toString() ?? '';
    final finish = card['finish']?.toString() ?? '';
    final price = double.tryParse(card['currentPrice']?.toString() ?? '') ?? 0;
    final image = card['imageUri']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0C),
        foregroundColor: Colors.white,
        title: const Text('Detail karty'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 320,
                child: AspectRatio(
                  aspectRatio: 2.5 / 3.5,
                  child: _cardImage(image),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            set,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Rarita',
                  rarity.isEmpty ? 'Neznáma' : rarity,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoCard(
                  'Prevedenie',
                  finish.isEmpty ? 'Normal' : finish,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Číslo',
                  number.isEmpty ? '—' : number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoCard(
                  'Cena',
                  '\$${price.toStringAsFixed(2)}',
                  valueColor: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2D2D35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    color: Color(0xFF93C5FD), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.summary.ownerNickname} · ${widget.summary.name}',
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: const Color(0xFF16161A),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: widget.summary.isOwner || _pending ? null : _toggleLike,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    if (_pending)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _like.likedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _like.likedByMe
                            ? const Color(0xFFF87171)
                            : const Color(0xFF94A3B8),
                        size: 24,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.summary.isOwner
                            ? 'Lajky od kamošov: ${_like.count}'
                            : '${_like.count} ${_like.count == 1 ? 'like' : 'likes'}',
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!widget.summary.isOwner)
                      Text(
                        _like.likedByMe ? 'Odobrať like' : 'Dať like',
                        style: const TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? const Color(0xFFF8FAFC),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardImage(String uri) {
    if (uri.startsWith('data:image') && uri.contains(',')) {
      try {
        return Image.memory(
          base64Decode(uri.split(',').last),
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
          return const _NoImage();
        },
      );
    }
    return const _NoImage();
  }
}

class _NoImage extends StatelessWidget {
  const _NoImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E24),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 40, color: Color(0xFF64748B)),
            SizedBox(height: 8),
            Text(
              'Bez obrázka',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
