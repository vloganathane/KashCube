/// Transport details collected before generating an e-Way Bill.
///
/// These map 1:1 to the GSTN EWB JSON transport fields. All fields
/// are optional in the JSON spec except [mode].
class EwbTransportDetails {
  const EwbTransportDetails({
    this.mode = '1',
    this.vehicleNo,
    this.transporterName,
    this.transporterGstin,
    this.distanceKm,
    this.transDocNo,
    this.transDocDate,
  });

  /// GSTN transport mode code.
  /// '1' = Road (default), '2' = Rail, '3' = Air, '4' = Ship.
  final String mode;

  /// Vehicle registration number (e.g. KA01AB1234).
  final String? vehicleNo;

  /// Transporter trade name.
  final String? transporterName;

  /// Transporter GSTIN (optional — only for registered transporters).
  final String? transporterGstin;

  /// Distance in km. Used to calculate EWB validity:
  /// validity_days = max(1, floor(distanceKm / 100))
  final int? distanceKm;

  /// Transport document number (LR/RR/airway bill).
  final String? transDocNo;

  /// Transport document date (DD/MM/YYYY).
  final String? transDocDate;

  /// Human-readable label for [mode].
  String get modeLabel =>
      const {'1': 'Road', '2': 'Rail', '3': 'Air', '4': 'Ship / Water'}[mode] ??
      'Road';

  /// Validity in days: 1 day per 100 km, minimum 1 day.
  int get validityDays {
    final km = distanceKm ?? 0;
    if (km <= 0) return 1;
    return (km / 100).floor().clamp(1, 999);
  }

  /// Date by which the EWB expires, starting from [generatedAt].
  DateTime validUntil(DateTime generatedAt) =>
      generatedAt.add(Duration(days: validityDays));
}
