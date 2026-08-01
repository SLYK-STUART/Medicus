import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads `.env` and initializes the global [Supabase] client.
///
/// Call once from `main()` before `runApp`. Only the anon key is used in
/// the Flutter app — never the service role key.
Future<void> initSupabase() async {
  await dotenv.load(fileName: '.env');

  final url = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env. '
      'Copy .env.example and fill values from the Supabase dashboard.',
    );
  }

  await Supabase.initialize(url: url, publishableKey: anonKey);
}

SupabaseClient get supabase => Supabase.instance.client;
