/// Ключи сервисов. Для публичного релиза лучше передавать их через
/// `--dart-define` и ограничить по package name / SHA-1 в кабинете Яндекса.
class AppConfig {
  AppConfig._();

  // Яндекс MapKit (карта)
  static const String mapkitApiKey = '673d50b7-d921-4885-9b09-6bfe856d3a0d';
  // Яндекс Геокодер
  static const String geocoderApiKey = 'e7f31599-4b12-4ff7-b616-25635e6ae8db';
  // Яндекс Геосаджест
  static const String suggestApiKey = '2f505185-7be6-4da5-b2e8-cc4fc964051b';

  // Supabase
  static const String supabaseUrl = 'https://iqsetzkvefsccbrtkksp.supabase.co';
  static const String supabasePublishableKey =
      'sb_publishable_pzZ8IGRvTpQ9eLLGiirNfg_1Qq2BvPG';

  // Центр карты по умолчанию (Москва), пока нет геопозиции
  static const double defaultLat = 55.755864;
  static const double defaultLon = 37.617698;
}
