import "log_service.dart";

/// ModelService — заглушка.
/// Google SpeechRecognizer встроен в Android, никаких моделей не нужно.
class ModelService {
  static final ModelService _i = ModelService._();
  factory ModelService() => _i;
  ModelService._();

  /// Модели не требуются — всегда готов
  Future<bool> checkModel() async {
    return true;
  }

  /// Заглушка: SpeechRecognizer не требует распаковки модели
  Future<String> unpackBuiltinModel() async {
    LogService.info("SpeechRecognizer встроен в Android — пропускаем", tag: "Model");
    return "";
  }
}
