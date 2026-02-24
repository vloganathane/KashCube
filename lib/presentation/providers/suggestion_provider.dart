import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/suggestion_service.dart';

/// Provider for the suggestion service instance.
final suggestionServiceProvider = Provider<SuggestionService>((ref) {
  return SuggestionService.instance;
});

/// Provider for known party names (autocomplete).
final knownPartyNamesProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.read(suggestionServiceProvider);
  return service.getKnownPartyNames();
});

/// Provider for a suggestion for a specific party name.
///
/// Usage:
/// ```dart
/// final suggestion = await ref.read(
///   partySuggestionProvider('Swiggy').future,
/// );
/// ```
final partySuggestionProvider =
    FutureProvider.family<TransactionSuggestion?, String>((ref, partyName) {
  final service = ref.read(suggestionServiceProvider);
  return service.suggestForParty(partyName);
});
