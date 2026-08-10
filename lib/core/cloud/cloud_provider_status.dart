import 'supabase_config.dart';

class CloudProviderStatus {
  const CloudProviderStatus({
    required this.firebaseConfigured,
    required this.supabaseConfigured,
  });

  factory CloudProviderStatus.current() => CloudProviderStatus(
    firebaseConfigured: true,
    supabaseConfigured: SupabaseConfig.isConfigured,
  );

  final bool firebaseConfigured;
  final bool supabaseConfigured;

  bool get anyConfigured => firebaseConfigured || supabaseConfigured;
  bool get hybridConfigured => supabaseConfigured;
}
