import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:raritio/services/shared_binder_service.dart';
import 'package:raritio/utils/card_finish.dart';
import 'package:raritio/widgets/holo_card_view.dart';

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
    final artist = card['artist']?.toString() ?? '';
    final language = card['language']?.toString() ?? '';
    final finish = primaryCardFinish(card);
    final price =
        double.tryParse(
          (card['currentPrice'] ?? card['price'] ?? '').toString(),
        ) ??
        0;
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
          HoloCardView(
            image: _cardImage(image),
            finish: finish,
            maxWidth: 320,
            borderRadius: 18,
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
            set.isEmpty ? '-' : set,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 12),
          _infoRow(
            _infoCard('Jazyk', _languageValue(language)),
            _infoCard('Edícia', set.isEmpty ? '-' : set),
          ),
          const SizedBox(height: 10),
          _infoRow(
            _infoCard('Rarita', rarity.isEmpty ? '-' : rarity),
            _infoCard('Prevedenie', finishLabelFor(finish)),
          ),
          const SizedBox(height: 10),
          _infoRow(
            _infoCard('Číslo', number.isEmpty ? '-' : number),
            _infoCard('Autor', artist.isEmpty ? '-' : artist),
          ),
          const SizedBox(height: 10),
          _infoRow(
            _infoCard(
              'Cena',
              '\$${price.toStringAsFixed(2)}',
              valueColor: const Color(0xFF10B981),
            ),
            _infoCard('Zdroj ceny', _priceSourceLabel(card)),
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
                const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFF93C5FD),
                  size: 20,
                ),
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
          const SizedBox(height: 10),
          _likeRow(),
        ],
      ),
    );
  }

  Widget _infoRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  Widget _infoCard(String label, String value, {Color? valueColor}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? const Color(0xFFF8FAFC),
              fontWeight: FontWeight.w800,
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _likeRow() {
    final owner = widget.summary.isOwner;
    final color = _like.likedByMe
        ? const Color(0xFFF87171)
        : const Color(0xFF94A3B8);
    return Row(
      children: [
        Expanded(
          child: Text(
            owner
                ? 'Lajky od kamošov: ${_like.count}'
                : '${_like.count} ${_like.count == 1 ? 'like' : 'likes'}',
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: owner || _pending ? null : _toggleLike,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pending)
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1.35, 1.05, 1),
                      child: Icon(
                        _like.likedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: color,
                        size: 32,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    owner
                        ? 'Lajky'
                        : (_like.likedByMe ? 'Odobrať like' : 'Dať like'),
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
    );
  }

  String _languageValue(String value) {
    final code = value.toLowerCase().replaceAll('_', '-');
    if (code.startsWith('en')) return '🇬🇧 Angličtina';
    if (code.startsWith('ja')) return '🇯🇵 Japončina';
    if (code.startsWith('zh-tw') || code.startsWith('zh-hant')) {
      return '🇹🇼 Čínština (tradičná)';
    }
    if (code.startsWith('zh')) return '🇨🇳 Čínština';
    if (code.startsWith('ko')) return '🇰🇷 Kórejčina';
    if (code.startsWith('de')) return '🇩🇪 Nemčina';
    if (code.startsWith('fr')) return '🇫🇷 Francúzština';
    if (code.startsWith('es')) return '🇪🇸 Španielčina';
    if (code.startsWith('it')) return '🇮🇹 Taliančina';
    if (code.startsWith('pt')) return '🇵🇹 Portugalčina';
    return code.isEmpty ? '-' : value;
  }

  String _priceSourceLabel(Map<String, dynamic> card) {
    final source = (card['priceSource'] ?? card['source'] ?? '')
        .toString()
        .toLowerCase();
    if (source == 'pricecharting') return 'PriceCharting';
    if (source == 'cardmarket') return 'Cardmarket';
    if (source == 'tcgplayer') return 'TCGPlayer';
    if (source == 'scryfall') return 'Scryfall';
    if (source == 'tcgdex') return 'TCGdex';
    return source.isEmpty ? '-' : source;
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
            Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: Color(0xFF64748B),
            ),
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
