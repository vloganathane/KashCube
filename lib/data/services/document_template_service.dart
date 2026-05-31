import '../repositories/document_template_repository_impl.dart';
import 'pdf_document_data.dart';

/// Resolves the DB-backed active document template used by PDF generation.
class DocumentTemplateService {
  DocumentTemplateService._();

  static final instance = DocumentTemplateService._();

  final DocumentTemplateRepositoryImpl _repo = DocumentTemplateRepositoryImpl();

  Future<DocumentTemplate> getActiveTemplate() async {
    final record = await _repo.getActive();
    final template = record?.toDocumentTemplate() ?? DocumentTemplate.modern;
    DocumentTemplate.setActive(template);
    return template;
  }
}
