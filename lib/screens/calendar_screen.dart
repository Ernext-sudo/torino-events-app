import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import 'event_detail.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  bool _onlyLiked = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dayEvents = state.eventsOn(_selected, onlyLiked: _onlyLiked);

    return Column(
      children: [
        TableCalendar<EventItem>(
          locale: 'it_IT',
          firstDay: DateTime.now().subtract(const Duration(days: 7)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _focused,
          startingDayOfWeek: StartingDayOfWeek.monday,
          selectedDayPredicate: (d) => isSameDay(d, _selected),
          eventLoader: (d) => state.eventsOn(d, onlyLiked: _onlyLiked),
          onDaySelected: (sel, foc) =>
              setState(() { _selected = sel; _focused = foc; }),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
                color: Colors.white24, shape: BoxShape.circle),
            selectedDecoration: const BoxDecoration(
                color: Color(0xFFFCA311), shape: BoxShape.circle),
            selectedTextStyle: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold),
            markerDecoration: const BoxDecoration(
                color: Color(0xFF3A86FF), shape: BoxShape.circle),
            markersMaxCount: 3,
          ),
          headerStyle: const HeaderStyle(
              formatButtonVisible: false, titleCentered: true),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Solo eventi salvati'),
          secondary: const Icon(Icons.favorite, size: 20),
          value: _onlyLiked,
          onChanged: (v) => setState(() => _onlyLiked = v),
        ),
        const Divider(height: 1),
        Expanded(
          child: dayEvents.isEmpty
              ? const Center(
                  child: Text('Nessun evento questo giorno',
                      style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  itemCount: dayEvents.length,
                  itemBuilder: (_, i) {
                    final e = dayEvents[i];
                    return ListTile(
                      leading: Container(
                        width: 6,
                        decoration: BoxDecoration(
                          color: categoryColor(e.category),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      title: Text(e.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${categoryLabel(e.category)} · ${formatDateIt(e.start, allDay: e.allDay)}'),
                      trailing: state.liked.contains(e.id)
                          ? const Icon(Icons.favorite,
                              color: Colors.greenAccent, size: 18)
                          : null,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EventDetailScreen(event: e))),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
