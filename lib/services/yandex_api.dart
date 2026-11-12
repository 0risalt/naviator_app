import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;
}

class Suggestion {
  const Suggestion({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
        title: (json['title']?['text'] as String?) ?? '',
        subtitle: json['subtitle']?['text'] as String?,
      );

  /// Текст для геокодирования: название + уточнение (адрес/город).
  String get geocodeText =>
      (subtitle != null && subtitle!.isNotEmpty) ? '$title, $subtitle' : title;
}

class GeoResult {
  const GeoResult({required this.address, required this.point});
  final String address;
  final LatLon point;
}

class RouteInfo {
  const RouteInfo({
    required this.points,
    required this.distance,
    required this.duration,
  });

  final List<LatLon> points;
  final double distance; // метры
  final double duration; // секунды
}

/// Подсказки, геокодер (Яндекс) и построение маршрута (OSRM).
class YandexApi {
  Future<List<Suggestion>> suggest(
    String query, {
    required bool organizations,
    LatLon? near,
  }) async {
    final params = <String, String>{
      'apikey': AppConfig.suggestApiKey,
      'text': query,
      'lang': 'ru_RU',
      'type': organizations ? 'biz' : 'geo',
    };
    if (near != null) {
      params['ll'] = '${near.lon},${near.lat}';
      params['spn'] = '0.5,0.5';
    }
    try {
      final res = await http
          .get(Uri.https('suggest-maps.yandex.ru', '/v1/suggest', params));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? const [];
      return results
          .map((e) => Suggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Suggest error: $e');
      return [];
    }
  }

  /// Адрес по координатам.
  Future<String?> reverseGeocode(LatLon p) async {
    final r = await _geocode('${p.lon},${p.lat}');
    return r?.address;
  }

  /// Координаты по тексту.
  Future<GeoResult?> geocode(String text) => _geocode(text);

  Future<GeoResult?> _geocode(String query) async {
    try {
      final url = Uri.https('geocode-maps.yandex.ru', '/1.x/', {
        'apikey': AppConfig.geocoderApiKey,
        'geocode': query,
        'format': 'json',
        'results': '1',
        'lang': 'ru_RU',
      });
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final members = data['response']['GeoObjectCollection']['featureMember']
          as List?;
      if (members == null || members.isEmpty) return null;
      final obj = members[0]['GeoObject'];
      final pos = (obj['Point']['pos'] as String).split(' ');
      final address =
          obj['metaDataProperty']['GeocoderMetaData']['text'] as String;
      return GeoResult(
        address: address,
        point: LatLon(double.parse(pos[1]), double.parse(pos[0])),
      );
    } catch (e) {
      debugPrint('Geocode error: $e');
      return null;
    }
  }

  /// Маршрут на авто через OSRM (старт, промежуточные точки, финиш).
  Future<RouteInfo?> buildRoute(List<LatLon> points) async {
    try {
      final coords = points.map((p) => '${p.lon},${p.lat}').join(';');
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coords'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes[0];
      final coordsJson = route['geometry']['coordinates'] as List;
      return RouteInfo(
        points: coordsJson
            .map((c) => LatLon((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList(),
        distance: (route['distance'] as num).toDouble(),
        duration: (route['duration'] as num).toDouble(),
      );
    } catch (e) {
      debugPrint('OSRM route error: $e');
      return null;
    }
  }
}
