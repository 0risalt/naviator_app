import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Сохранить точку (закладка, дом, работа, история)
  Future<void> savePlace({
    required String address,
    required double lat,
    required double lon,
    required String type,
  }) async {
    await _client.from('bookmarks').insert({
      'address': address,
      'latitude': lat,
      'longitude': lon,
      'type': type,
    });
  }

  // Получить закладки
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final data = await _client
        .from('bookmarks')
        .select()
        .eq('type', 'bookmark')
        .order('created_at', ascending: false);
    return data;
  }

  // Получить историю
  Future<List<Map<String, dynamic>>> getHistory() async {
    final data = await _client
        .from('bookmarks')
        .select()
        .eq('type', 'history')
        .order('created_at', ascending: false)
        .limit(20); // Храним только 20 последних маршрутов
    return data;
  }

  // Получить Дом или Работу
  Future<Map<String, dynamic>?> getPlace(String type) async {
    final data = await _client
        .from('bookmarks')
        .select()
        .eq('type', type)
        .order('created_at', ascending: false) // Берем самый свежий
        .limit(1)
        .maybeSingle();
    return data;
  }

  // Удалить любую запись по ID (работает для закладок и истории)
  Future<void> deleteItem(int id) async {
    await _client.from('bookmarks').delete().eq('id', id);
  }
}