enum TargetType {
  bot('Бот'),
  user('Пользователь'),
  group('Группа / Супергруппа'),
  channel('Канал');

  const TargetType(this.label);
  final String label;
}

class TelegramTarget {
  final String name;
  final String chatId;
  final TargetType type;

  const TelegramTarget({
    required this.name,
    required this.chatId,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'chatId': chatId,
        'type': type.name,
      };

  factory TelegramTarget.fromJson(Map<String, dynamic> j) => TelegramTarget(
        name: j['name'] as String? ?? '',
        chatId: j['chatId'] as String,
        type: TargetType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => TargetType.bot,
        ),
      );
}
