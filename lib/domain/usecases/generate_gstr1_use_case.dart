import '../../data/services/gstr1_service.dart';
import '../repositories/business_repository.dart';
import '../repositories/invoice_repository.dart';

/// Encapsulates generating a GSTR-1 workbook for a given period.
///
/// Delegates to [Gstr1Service] while keeping the business rule of requiring a
/// valid date range (from ≤ to) in the domain layer rather than in UI code.
class GenerateGstr1UseCase {
  GenerateGstr1UseCase({
    required BusinessRepository businessRepository,
    required InvoiceRepository invoiceRepository,
  }) : _service = Gstr1Service(
          businessRepo: businessRepository,
          invoiceRepo: invoiceRepository,
        );

  final Gstr1Service _service;

  /// Generates and returns the GSTR-1 workbook for [businessId] and the
  /// period [[from], [to]] (both inclusive, date-part only).
  ///
  /// Throws [ArgumentError] if [from] is after [to] or if [businessId] ≤ 0.
  Future<Gstr1Workbook> call({
    required int businessId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (businessId <= 0) {
      throw ArgumentError.value(businessId, 'businessId', 'Must be a valid ID.');
    }
    if (from.isAfter(to)) {
      throw ArgumentError(
        'from ($from) must not be after to ($to) for GSTR-1 generation.',
      );
    }
    return _service.generateWorkbook(
      businessId: businessId,
      from: from,
      to: to,
    );
  }
}
