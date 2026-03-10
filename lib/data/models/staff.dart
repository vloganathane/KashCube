import 'package:equatable/equatable.dart';

enum SalaryType { monthly, daily, hourly, contractual }

/// A staff member (employee/contractor).
class Staff extends Equatable {
  const Staff({
    this.id,
    required this.name,
    this.designation,
    this.phone,
    this.email,
    this.department,
    this.salaryType = SalaryType.monthly,
    this.baseSalary = 0,
    this.joinDate,
    this.isActive = true,
    this.bankName,
    this.accountNo,
    this.ifscCode,
    this.pan,
    this.pfNo,
    this.esiNo,
    this.notes,
    this.businessId,
    required this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String? designation;
  final String? phone;
  final String? email;
  final String? department;
  final SalaryType salaryType;
  final double baseSalary;
  final DateTime? joinDate;
  final bool isActive;
  final String? bankName;
  final String? accountNo;
  final String? ifscCode;
  final String? pan;
  final String? pfNo;
  final String? esiNo;
  final String? notes;
  final int? businessId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Staff copyWith({
    int? id,
    String? name,
    String? designation,
    String? phone,
    String? email,
    String? department,
    SalaryType? salaryType,
    double? baseSalary,
    DateTime? joinDate,
    bool? isActive,
    String? bankName,
    String? accountNo,
    String? ifscCode,
    String? pan,
    String? pfNo,
    String? esiNo,
    String? notes,
    int? businessId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Staff(
        id: id ?? this.id,
        name: name ?? this.name,
        designation: designation ?? this.designation,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        department: department ?? this.department,
        salaryType: salaryType ?? this.salaryType,
        baseSalary: baseSalary ?? this.baseSalary,
        joinDate: joinDate ?? this.joinDate,
        isActive: isActive ?? this.isActive,
        bankName: bankName ?? this.bankName,
        accountNo: accountNo ?? this.accountNo,
        ifscCode: ifscCode ?? this.ifscCode,
        pan: pan ?? this.pan,
        pfNo: pfNo ?? this.pfNo,
        esiNo: esiNo ?? this.esiNo,
        notes: notes ?? this.notes,
        businessId: businessId ?? this.businessId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'designation': designation,
        'phone': phone,
        'email': email,
        'department': department,
        'salary_type': salaryType.name,
        'base_salary': baseSalary,
        'join_date': joinDate?.toIso8601String().substring(0, 10),
        'is_active': isActive ? 1 : 0,
        'bank_name': bankName,
        'account_no': accountNo,
        'ifsc_code': ifscCode,
        'pan': pan,
        'pf_no': pfNo,
        'esi_no': esiNo,
        'notes': notes,
        'business_id': businessId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory Staff.fromMap(Map<String, dynamic> map) => Staff(
        id: map['id'] as int?,
        name: map['name'] as String,
        designation: map['designation'] as String?,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        department: map['department'] as String?,
        salaryType: SalaryType.values.firstWhere(
          (t) => t.name == (map['salary_type'] as String?),
          orElse: () => SalaryType.monthly,
        ),
        baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
        joinDate: map['join_date'] != null
            ? DateTime.tryParse(map['join_date'] as String)
            : null,
        isActive: (map['is_active'] as int?) == 1,
        bankName: map['bank_name'] as String?,
        accountNo: map['account_no'] as String?,
        ifscCode: map['ifsc_code'] as String?,
        pan: map['pan'] as String?,
        pfNo: map['pf_no'] as String?,
        esiNo: map['esi_no'] as String?,
        notes: map['notes'] as String?,
        businessId: map['business_id'] as int?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [id, name, designation, phone, isActive, businessId];
}

/// Status of a salary payment.
enum SalaryPaymentStatus { pending, paid, partial }

/// A salary payment record for a staff member.
class SalaryPayment extends Equatable {
  const SalaryPayment({
    this.id,
    required this.staffId,
    required this.payPeriodMonth,
    required this.payPeriodYear,
    this.baseSalary = 0,
    this.allowances = 0,
    this.deductions = 0,
    this.bonus = 0,
    required this.netSalary,
    this.paymentMethod = 'bank_transfer',
    this.paidDate,
    this.status = SalaryPaymentStatus.pending,
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int staffId;
  final int payPeriodMonth;
  final int payPeriodYear;
  final double baseSalary;
  final double allowances;
  final double deductions;
  final double bonus;
  final double netSalary;
  final String paymentMethod;
  final DateTime? paidDate;
  final SalaryPaymentStatus status;
  final String? notes;
  final DateTime createdAt;

  /// Human-readable pay period, e.g. "March 2026".
  String get periodLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[payPeriodMonth - 1]} $payPeriodYear';
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'staff_id': staffId,
        'pay_period_month': payPeriodMonth,
        'pay_period_year': payPeriodYear,
        'base_salary': baseSalary,
        'allowances': allowances,
        'deductions': deductions,
        'bonus': bonus,
        'net_salary': netSalary,
        'payment_method': paymentMethod,
        'paid_date': paidDate?.toIso8601String().substring(0, 10),
        'status': status.name,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory SalaryPayment.fromMap(Map<String, dynamic> map) => SalaryPayment(
        id: map['id'] as int?,
        staffId: map['staff_id'] as int,
        payPeriodMonth: map['pay_period_month'] as int,
        payPeriodYear: map['pay_period_year'] as int,
        baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
        allowances: (map['allowances'] as num?)?.toDouble() ?? 0,
        deductions: (map['deductions'] as num?)?.toDouble() ?? 0,
        bonus: (map['bonus'] as num?)?.toDouble() ?? 0,
        netSalary: (map['net_salary'] as num).toDouble(),
        paymentMethod: (map['payment_method'] as String?) ?? 'bank_transfer',
        paidDate: map['paid_date'] != null
            ? DateTime.tryParse(map['paid_date'] as String)
            : null,
        status: SalaryPaymentStatus.values.firstWhere(
          (s) => s.name == (map['status'] as String?),
          orElse: () => SalaryPaymentStatus.pending,
        ),
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, staffId, payPeriodMonth, payPeriodYear, netSalary, status];
}
