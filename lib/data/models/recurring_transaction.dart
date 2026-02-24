import 'package:equatable/equatable.dart';

/// How often a recurring transaction repeats.
enum RecurringFrequency {
  daily,
  weekly,
  biweekly,
  monthly,
  quarterly,
  yearly;

  String get label {
    switch (this) {
      case RecurringFrequency.daily:
        return 'Daily';
      case RecurringFrequency.weekly:
        return 'Weekly';
      case RecurringFrequency.biweekly:
        return 'Bi-weekly';
      case RecurringFrequency.monthly:
        return 'Monthly';
      case RecurringFrequency.quarterly:
        return 'Quarterly';
      case RecurringFrequency.yearly:
        return 'Yearly';
    }
  }

  String get dbValue => name;

  static RecurringFrequency fromDb(String value) {
    return RecurringFrequency.values.firstWhere(
      (f) => f.name == value,
      orElse: () => RecurringFrequency.monthly,
    );
  }

  /// Returns the next occurrence date after [from].
  DateTime nextOccurrence(DateTime from) {
    switch (this) {
      case RecurringFrequency.daily:
        return from.add(const Duration(days: 1));
      case RecurringFrequency.weekly:
        return from.add(const Duration(days: 7));
      case RecurringFrequency.biweekly:
        return from.add(const Duration(days: 14));
      case RecurringFrequency.monthly:
        return DateTime(from.year, from.month + 1, from.day);
      case RecurringFrequency.quarterly:
        return DateTime(from.year, from.month + 3, from.day);
      case RecurringFrequency.yearly:
        return DateTime(from.year + 1, from.month, from.day);
    }
  }
}

/// A recurring transaction template that auto-generates transactions.
class RecurringTransaction extends Equatable {
  const RecurringTransaction({
    this.id,
    required this.amount,
    required this.type,
    required this.category,
    this.partyName,
    this.paymentMethod,
    required this.frequency,
    required this.nextDate,
    this.lastGenerated,
    this.isActive = true,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final double amount;
  final String type; // 'income' or 'expense'
  final String category;
  final String? partyName;
  final String? paymentMethod;
  final RecurringFrequency frequency;
  final DateTime nextDate;
  final DateTime? lastGenerated;
  final bool isActive;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'type': type,
      'category': category,
      'party_name': partyName,
      'payment_method': paymentMethod,
      'frequency': frequency.dbValue,
      'next_date': nextDate.toIso8601String(),
      'last_generated': lastGenerated?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'notes': notes,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory RecurringTransaction.fromMap(Map<String, dynamic> map) {
    return RecurringTransaction(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      category: map['category'] as String,
      partyName: map['party_name'] as String?,
      paymentMethod: map['payment_method'] as String?,
      frequency: RecurringFrequency.fromDb(map['frequency'] as String),
      nextDate: DateTime.parse(map['next_date'] as String),
      lastGenerated: map['last_generated'] != null
          ? DateTime.parse(map['last_generated'] as String)
          : null,
      isActive: (map['is_active'] as int?) == 1,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  RecurringTransaction copyWith({
    int? id,
    double? amount,
    String? type,
    String? category,
    String? partyName,
    String? paymentMethod,
    RecurringFrequency? frequency,
    DateTime? nextDate,
    DateTime? lastGenerated,
    bool? isActive,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecurringTransaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      partyName: partyName ?? this.partyName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      frequency: frequency ?? this.frequency,
      nextDate: nextDate ?? this.nextDate,
      lastGenerated: lastGenerated ?? this.lastGenerated,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id, amount, type, category, partyName, paymentMethod,
        frequency, nextDate, lastGenerated, isActive, notes,
      ];
}
