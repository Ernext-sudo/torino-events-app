import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import 'event_detail.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final _controller = CardSwiperController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final deck = state.deck;

    if (state.error != null && state.events.isEmpty) {
      return _Message(
          icon: Icons.cloud_off, text: state.error!, onRetry: state.refresh);
    }
    if (deck.isEmpty) {
      return _Message(
        icon: Icons.check_circle_outline,
        text: state.events.isEmpty
            ? 'Nessun evento caricato.\nConfigura il repo nella tab Fonti.'
            : 'Hai visto tutto!\nCambia filtri o aspetta il prossimo scrape.',
        onRetry: state.refresh,
      );
    }

    return Column(
      children: [
        Expanded(
          child: CardSwiper(
            controller: _controller,
            // key forza il rebuild quando il mazzo cambia (filtri/refresh) o
            // quando viene rimandata una carta senza che il mazzo si accorci
            key: ValueKey('${state.deckRevision}|${deck.map((e) => e.id).join()}'),
            cardsCount: deck.length,
            numberOfCardsDisplayed: deck.length < 3 ? deck.length : 3,
            isLoop: false,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            allowedSwipeDirection: const AllowedSwipeDirection.only(
                left: true, right: true, down: true),
            onSwipe: (prev, _, direction) {
              final event = deck[prev];
              switch (direction) {
                case CardSwiperDirection.right:
                  state.swipe(event, likedIt: true);
                case CardSwiperDirection.bottom:
                  state.swipe(event, likedIt: false); // scarta per sempre
                case CardSwiperDirection.left:
                  state.defer(event); // rimanda in fondo al mazzo
                default:
                  return false;
              }
              return true;
            },
            cardBuilder: (context, i, __, ___) => _EventCard(event: deck[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundBtn(
                icon: Icons.history,
                tooltip: 'Rimanda — torna in fondo al mazzo',
                color: Colors.amberAccent,
                onTap: () => _controller.swipe(CardSwiperDirection.left),
              ),
              const SizedBox(width: 16),
              _RoundBtn(
                icon: Icons.arrow_downward,
                tooltip: 'Scarta — non lo rivedrai più',
                color: Colors.redAccent,
                onTap: () => _controller.swipe(CardSwiperDirection.bottom),
              ),
              const SizedBox(width: 16),
              _RoundBtn(
                icon: Icons.info_outline,
                tooltip: 'Dettagli',
                color: Colors.white70,
                small: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EventDetailScreen(event: deck.first)),
                ),
              ),
              const SizedBox(width: 16),
              _RoundBtn(
                icon: Icons.favorite,
                tooltip: 'Salva',
                color: Colors.greenAccent,
                onTap: () => _controller.swipe(CardSwiperDirection.right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventItem event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(event.category);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16203A),
          borderRadius: BorderRadius.circular(24),
          border: Border(left: BorderSide(color: color, width: 6)),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 6))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: event.image.isNotEmpty
                  ? Image.network(eventImageUrl(event.image, width: 800),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(color),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : _placeholder(color))
                  : _placeholder(color),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Chip(text: categoryLabel(event.category), color: color),
                        if (event.dateConfidence == 'low') ...[
                          const SizedBox(width: 6),
                          const _Chip(
                              text: 'data da verificare',
                              color: Colors.orangeAccent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      event.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.2),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(Icons.event, size: 16, color: Colors.white60),
                        const SizedBox(width: 6),
                        Text(formatDateIt(event.start, allDay: event.allDay),
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    if (event.venue.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.place, size: 16, color: Colors.white60),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(event.venue,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(color: Colors.white70))),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(Color color) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(.55), const Color(0xFF0C1220)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
            child: Icon(Icons.celebration, size: 56, color: Colors.white38)),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(.22),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(.6)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  final bool small;
  const _RoundBtn(
      {required this.icon,
      required this.color,
      required this.onTap,
      required this.tooltip,
      this.small = false});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: small ? 44 : 56,
            height: small ? 44 : 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF16203A),
              border: Border.all(color: color.withOpacity(.6), width: 2),
            ),
            child: Icon(icon, color: color, size: small ? 20 : 26),
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onRetry;
  const _Message(
      {required this.icon, required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.white38),
              const SizedBox(height: 16),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova')),
            ],
          ),
        ),
      );
}
