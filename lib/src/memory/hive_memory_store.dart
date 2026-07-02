import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/message.dart';
import 'memory_store.dart';

/// Persistent conversation memory backed by [Hive].
///
/// History survives app restarts. Each [sessionId] is stored in its own
/// Hive box, so different agents don't share history.
///
/// ## Setup
/// Call [HiveMemoryStore.initialize] once at app startup, before
/// creating any agents that use this store:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await HiveMemoryStore.initialize();    // ← add this
///   await AgenticAI.init(...);
///   runApp(const MyApp());
/// }
/// ```
///
/// Then use it in your agent:
/// ```dart
/// final agent = AgenticAgent(
///   provider: myProvider,
///   memory: HiveMemoryStore(sessionId: 'user_123'),
/// );
/// ```
class HiveMemoryStore implements MemoryStore {
  static const _boxPrefix = 'genesis_memory_';
  static bool _initialized = false;

  /// Call this once at app startup before using [HiveMemoryStore].
  static Future<void> initialize() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _initialized = true;
  }

  Future<Box<String>> _box(String sessionId) async {
    final name = '$_boxPrefix$sessionId'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
    return Hive.openBox<String>(name);
  }

  @override
  Future<List<Message>> load(String sessionId) async {
    final box = await _box(sessionId);
    return box.values.map(_deserialize).whereType<Message>().toList();
  }

  @override
  Future<void> append(String sessionId, Message message) async {
    final box = await _box(sessionId);
    await box.add(_serialize(message));
  }

  @override
  Future<void> save(String sessionId, List<Message> messages) async {
    final box = await _box(sessionId);
    await box.clear();
    await box.addAll(messages.map(_serialize));
  }

  @override
  Future<void> clear(String sessionId) async {
    final box = await _box(sessionId);
    await box.clear();
  }

  // ── Serialization ────────────────────────────────────────────────────────

  String _serialize(Message msg) => jsonEncode({
        'role': msg.role.name,
        'content': msg.content,
        if (msg.toolName != null) 'toolName': msg.toolName,
      });

  Message? _deserialize(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final role = MessageRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => MessageRole.user,
      );
      final content = map['content'] as String;
      final toolName = map['toolName'] as String?;

      return switch (role) {
        MessageRole.system => Message.system(content),
        MessageRole.user => Message.user(content),
        MessageRole.assistant => Message.assistant(content),
        MessageRole.tool => Message.tool(toolName ?? 'unknown', content),
      };
    } catch (_) {
      return null;
    }
  }
}
