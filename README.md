# PickMe Navigator (Flutter)

Розовый навигатор на Яндекс.Картах: поиск адресов и организаций, клик по карте,
промежуточные точки, пробки, маршрут (OSRM), избранное, история, Дом/Работа (Supabase).

## Запуск
1. Скопируйте в ваш проект `lib/`, `assets/`, `pubspec.yaml` и папку `android/app/`
   (поверх существующей: `build.gradle.kts`, `src/main/AndroidManifest.xml`, иконки `mipmap-*`).
   Остальные файлы Android (settings.gradle.kts, gradle.properties, MainActivity.kt) менять не нужно.
2. Создайте таблицу в Supabase: `supabase_schema.sql`.
3. `flutter pub get && flutter run`

Нужен Flutter 3.27+ (используется `Color.withValues`).

## Сборка APK на GitHub
Workflow `.github/workflows/build-apk.yml` запускается при push в main/master, в pull request
и вручную (вкладка Actions → Build APK → Run workflow). Готовый `app-release.apk` лежит в
артефактах запуска (`navigator-app-release-apk`). Workflow сам находит `pubspec.yaml`, поэтому работает и если проект лежит не в корне репозитория, а во вложенной папке (сам `.github` при этом должен быть в корне). При push тега вида `v1.0.0` APK
дополнительно прикрепляется к GitHub Release.

APK подписан debug-ключом (так настроено в `build.gradle.kts`) — для личной установки подходит,
для Google Play нужен свой keystore.

## Что изменено в Android-части
- `android/app/build.gradle.kts`: `minSdk = 26` (требование Yandex MapKit) и подключён плагин
  `org.jetbrains.kotlin.android` (он объявлен в settings.gradle.kts, но в app-модуле не применялся,
  а MainActivity.kt написан на Kotlin).
- `AndroidManifest.xml` и иконки `launcher_icon` — ваши, без изменений.
- Иконки уже сгенерированы, запускать `flutter_launcher_icons` не нужно.
- Файлы `ic_launcher*.png` (стандартные флаттеровские) приложению не нужны, их можно удалить.

## Структура
- `lib/config.dart` — ключи и координаты по умолчанию
- `lib/theme/app_colors.dart` — палитра (#FF4081, #D81B60, #FDF2F5, #FFF0F5)
- `lib/assets/map_style.dart` — розовый стиль карты (без изменений)
- `lib/services/` — `supabase_service.dart` (без изменений), `yandex_api.dart` (подсказки, геокодер, OSRM)
- `lib/screens/home_screen.dart` — карта, поиск, вкладки; `navigation_screen.dart` — экран «Поехали»
