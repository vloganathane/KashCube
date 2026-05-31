import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/document_template_record.dart';
import '../../data/repositories/document_template_repository_impl.dart';
import '../../data/services/pdf_document_data.dart';
import '../../domain/repositories/document_template_repository.dart';
import 'settings_provider.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final documentTemplateRepositoryProvider = Provider<DocumentTemplateRepository>(
  (_) => DocumentTemplateRepositoryImpl(),
);

// ── List notifier ─────────────────────────────────────────────────────────────

/// Manages the full list of [DocumentTemplateRecord]s (presets + custom).
///
/// Consumers can call [setActive], [create], [save], and [remove] to mutate
/// the list. Each mutation re-fetches from the DB to stay in sync.
class DocumentTemplateListNotifier
    extends StateNotifier<AsyncValue<List<DocumentTemplateRecord>>> {
  DocumentTemplateListNotifier(this._repo, this._settingsRef)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final DocumentTemplateRepository _repo;
  final Ref _settingsRef;

  Future<void> _load() async {
    try {
      final list = await _repo.getAll();
      final active = _activeFrom(list);
      if (active != null) {
        await _settingsRef
            .read(documentTemplateProvider.notifier)
            .setTemplate(active.toDocumentTemplate());
      }
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Marks the template with [id] as active and keeps [DocumentTemplate.active]
  /// (used by the PDF engine) synchronised.
  Future<void> setActive(int id) async {
    await _repo.setActive(id);
    final record = await _repo.getActive();
    if (record == null) {
      throw StateError('No active document template after setting $id.');
    }
    final template = record.toDocumentTemplate();
    // Keep existing settings notifier in sync so PDFs pick up the change
    // immediately without a hot-reload.
    await _settingsRef
        .read(documentTemplateProvider.notifier)
        .setTemplate(template);
    await _load();
  }

  /// Inserts a new custom template record.
  Future<void> create(DocumentTemplateRecord record) async {
    await _repo.insert(record);
    await _load();
  }

  /// Persists changes to an existing record (by its [id]).
  Future<void> save(DocumentTemplateRecord record) async {
    await _repo.update(record);
    // If the saved record is active, propagate the change to the PDF engine.
    if (record.isActive) {
      await _settingsRef
          .read(documentTemplateProvider.notifier)
          .setTemplate(record.toDocumentTemplate());
    }
    await _load();
  }

  /// Deletes a non-preset template by [id].
  Future<void> remove(int id) async {
    await _repo.delete(id);
    await _load();
  }

  /// Forcefully reloads the list from the database.
  Future<void> reload() => _load();

  DocumentTemplateRecord? _activeFrom(List<DocumentTemplateRecord> list) {
    for (final record in list) {
      if (record.isActive) return record;
    }
    return null;
  }
}

final documentTemplatesProvider =
    StateNotifierProvider<
      DocumentTemplateListNotifier,
      AsyncValue<List<DocumentTemplateRecord>>
    >(
      (ref) => DocumentTemplateListNotifier(
        ref.read(documentTemplateRepositoryProvider),
        ref,
      ),
    );
