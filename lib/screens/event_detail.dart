import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/app_state.dart';

class EventDetailScreen extends StatelessWidget {
  final EventItem event;
  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final color = categoryColor(event.category);
    final isLiked = state.liked.contains(event.id);
    final hasCoords = event.lat != null && event.lon != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evento'),
        actions: [
          IconButton(
            icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.greenAccent : null),
            onPressed: () => isLiked
                ? state.undo(event)
                : state.swipe(event, likedIt: true),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (event.image.isNotEmpty)
            Image.network(event.image,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(categoryLabel(event.category)),
                      backgroundColor: color.withOpacity(.25),
                      side: BorderSide(color: color),
                    ),
                    Chip(label: Text('Fonte: ${event.sourceId}')),
                    if (event.dateConfidence == 'low')
                      const Chip(
                        label: Text('Data da verificare'),
                        backgroundColor: Color(0x33FFA726),
                        side: BorderSide(color: Colors.orangeAccent),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(event.title,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _InfoRow(
                    icon: Icons.event,
                    text: formatDateIt(event.start, allDay: event.allDay)),
                if (event.venue.isNotEmpty)
                  _InfoRow(icon: Icons.place, text: event.venue),
                if (event.address.isNotEmpty)
                  _InfoRow(icon: Icons.signpost, text: event.address),
                if (event.price.isNotEmpty)
                  _InfoRow(icon: Icons.euro, text: event.price),
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(event.description,
                      style:
                          const TextStyle(height: 1.5, color: Colors.white70)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (event.url.isNotEmpty)
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Apri link'),
                          onPressed: () => launchUrl(Uri.parse(event.url),
                              mode: LaunchMode.externalApplication),
                        ),
                      ),
                    if (event.url.isNotEmpty) const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.directions),
                        label: const Text('Portami lì'),
                        onPressed: () => _openMaps(),
                      ),
                    ),
                  ],
                ),
                if (hasCoords) ...[
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 220,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(event.lat!, event.lon!),
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.pinchZoom |
                                  InteractiveFlag.drag),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'it.torinoevents.app',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(event.lat!, event.lon!),
                              width: 44,
                              height: 44,
                              child: Icon(Icons.location_pin,
                                  color: color, size: 44),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Con coordinate: naviga al punto. Senza: cerca "titolo/venue Torino".
  Future<void> _openMaps() async {
    final Uri uri;
    if (event.lat != null && event.lon != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${event.lat},${event.lon}');
    } else {
      final q = Uri.encodeComponent(
          '${event.venue.isNotEmpty ? event.venue : event.title} Torino');
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
