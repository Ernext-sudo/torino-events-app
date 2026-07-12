import 'package:flutter/material.dart';

/// Colori e etichette per categoria (i colori marcano il bordo delle carte).
const categoryMeta = <String, ({String label, Color color})>{
  'concerti': (label: 'Concerti', color: Color(0xFFE63946)),
  'club': (label: 'Club / Ballare', color: Color(0xFFB86BFF)),
  'mostre': (label: 'Mostre', color: Color(0xFF2EC4B6)),
  'musei': (label: 'Musei', color: Color(0xFF3A86FF)),
  'teatro': (label: 'Teatro', color: Color(0xFFFF6B9D)),
  'workshop': (label: 'Workshop', color: Color(0xFFF77F00)),
  'corsi': (label: 'Corsi', color: Color(0xFFFFB703)),
  'conferenze': (label: 'Conferenze', color: Color(0xFF8ECAE6)),
  'centri_sociali': (label: 'Centri sociali', color: Color(0xFF80B918)),
  'eventi': (label: 'Eventi', color: Color(0xFFFCA311)),
  'altro': (label: 'Altro', color: Color(0xFF9E9E9E)),
};

Color categoryColor(String c) =>
    (categoryMeta[c] ?? categoryMeta['altro']!).color;
String categoryLabel(String c) =>
    (categoryMeta[c] ?? (label: c, color: Colors.grey)).label;

/// Parser disponibili nello scraper: il `type` di una fonte è la chiave con
/// cui main.py sceglie il parser (PARSERS), non il formato del feed.
/// Deve restare allineato al dict PARSERS di scraper/main.py.
const sourceTypes = <String, String>{
  'rss': 'RSS generico',
  'gancio': 'Gancio (gancio.cisti.org)',
  'xceed': 'Xceed (JSON-LD)',
  'html_guidatorino': 'GuidaTorino (HTML)',
  'html_torinotoday': 'TorinoToday (HTML)',
  'html_bunker': 'Bunker (HTML)',
};

String sourceTypeLabel(String t) => sourceTypes[t] ?? t;

class EventItem {
  final String id;
  final String title;
  final String sourceId;
  final String url;
  final String description;
  final String category;
  final String venue;
  final String address;
  final double? lat;
  final double? lon;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String dateConfidence; // high | low
  final String price;
  final String image;

  EventItem({
    required this.id,
    required this.title,
    required this.sourceId,
    this.url = '',
    this.description = '',
    this.category = 'eventi',
    this.venue = '',
    this.address = '',
    this.lat,
    this.lon,
    this.start,
    this.end,
    this.allDay = false,
    this.dateConfidence = 'low',
    this.price = '',
    this.image = '',
  });

  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        sourceId: j['source_id'] ?? '',
        url: j['url'] ?? '',
        description: j['description'] ?? '',
        category: j['category'] ?? 'eventi',
        venue: j['venue'] ?? '',
        address: j['address'] ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        start: j['start'] != null ? DateTime.tryParse(j['start']) : null,
        end: j['end'] != null ? DateTime.tryParse(j['end']) : null,
        allDay: j['all_day'] ?? false,
        dateConfidence: j['date_confidence'] ?? 'low',
        price: j['price'] ?? '',
        image: j['image'] ?? '',
      );
}

class SourceItem {
  final String id;
  String name;
  String type;
  String url;
  String defaultCategory;
  bool enabled;

  SourceItem({
    required this.id,
    required this.name,
    this.type = 'rss',
    this.url = '',
    this.defaultCategory = 'eventi',
    this.enabled = true,
  });

  Map<String, dynamic> toYamlMap() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'default_category': defaultCategory,
        'enabled': enabled,
      };
}

const _mesi = [
  'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
  'lug', 'ago', 'set', 'ott', 'nov', 'dic',
];
const _giorni = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];

/// "gio 12 lug, 21:00" — senza dipendere dai dati locale di intl.
String formatDateIt(DateTime? d, {bool allDay = false}) {
  if (d == null) return 'Data da definire';
  final base = '${_giorni[d.weekday - 1]} ${d.day} ${_mesi[d.month - 1]}';
  if (allDay || (d.hour == 0 && d.minute == 0)) return base;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$base, $hh:$mm';
}
