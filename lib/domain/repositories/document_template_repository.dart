import '../../data/models/document_template_record.dart';

/// Persistence contract for the [document_templates] table.
abstract class DocumentTemplateRepository {
  /// Returns all templates ordered by [is_preset] DESC, then [name] ASC.
  Future<List<DocumentTemplateRecord>> getAll();

  /// Returns the currently active template, or null if none is marked active.
  Future<DocumentTemplateRecord?> getActive();

  /// Inserts a new template row and returns the auto-increment id.
  Future<int> insert(DocumentTemplateRecord record);

  /// Updates the mutable columns of an existing template.
  /// Preset rows can be updated (e.g. to change accent colour), but
  /// callers should verify [isPreset] before allowing deletion.
  Future<void> update(DocumentTemplateRecord record);

  /// Hard-deletes a template by [id]. Only non-preset rows should be deleted.
  Future<void> delete(int id);

  /// Marks [id] as active and clears the flag on all other rows.
  Future<void> setActive(int id);
}
