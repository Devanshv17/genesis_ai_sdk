import '../agentic_tool.dart';
import '../tool_param.dart';

/// Returns the current date, time, day, timezone info, and optional formatting.
///
/// Zero dependencies — works on all platforms.
///
/// Usage:
/// ```dart
/// tools: [AgenticTools.dateTime]
/// ```
final AgenticTool dateTimeTool = AgenticTool.define(
  name: 'get_datetime',
  description:
      'Returns the current date and time. Use this whenever the user asks '
      'about the current time, date, day of the week, or needs to know '
      'how much time has passed. Also use for timezone queries.',
  params: {
    'timezone_offset_hours': ToolParam.number(
      description:
          'UTC offset in hours, e.g. 5.5 for IST, -5 for EST. '
          'If omitted, device local time is returned.',
    ),
  },
  execute: (args) async {
    final now = DateTime.now();
    final offset = args['timezone_offset_hours'];

    DateTime display = now;
    String tzLabel = 'local';

    if (offset != null) {
      final offsetMinutes = ((offset as num) * 60).round();
      display = now.toUtc().add(Duration(minutes: offsetMinutes));
      final sign = offsetMinutes >= 0 ? '+' : '-';
      final h = (offsetMinutes.abs() ~/ 60).toString().padLeft(2, '0');
      final m = (offsetMinutes.abs() % 60).toString().padLeft(2, '0');
      tzLabel = 'UTC$sign$h:$m';
    }

    return {
      'date': _formatDate(display),
      'time': _formatTime(display),
      'day_of_week': _dayName(display.weekday),
      'timezone': tzLabel,
      'unix_timestamp': now.millisecondsSinceEpoch ~/ 1000,
      'iso8601': display.toIso8601String(),
    };
  },
);

String _formatDate(DateTime dt) =>
    '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';

String _formatTime(DateTime dt) =>
    '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';

String _pad(int n) => n.toString().padLeft(2, '0');

String _dayName(int weekday) => const [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ][weekday];
