import 'package:equatable/equatable.dart';

/// Type of bill file attached to a transaction.
enum BillFileType {
  image,
  pdf;

  String get label {
    switch (this) {
      case BillFileType.image:
        return 'Image';
      case BillFileType.pdf:
        return 'PDF';
    }
  }

  String get dbValue => name;

  static BillFileType fromDb(String value) {
    return BillFileType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BillFileType.image,
    );
  }
}

/// A bill / receipt attached to a transaction.
///
/// Each transaction can have at most one bill attachment.
class BillAttachment extends Equatable {
  const BillAttachment({
    this.id,
    required this.transactionId,
    required this.filePath,
    required this.fileName,
    required this.fileType,
    this.fileSize,
    this.createdAt,
  });

  final int? id;
  final int transactionId;

  /// Absolute path to the file stored in app-private directory.
  final String filePath;

  /// Original file name (for display purposes).
  final String fileName;

  /// Whether this is an image or PDF.
  final BillFileType fileType;

  /// File size in bytes (optional).
  final int? fileSize;

  final DateTime? createdAt;

  /// Whether this is a PDF file.
  bool get isPdf => fileType == BillFileType.pdf;

  /// Whether this is an image file.
  bool get isImage => fileType == BillFileType.image;

  /// Convert to a map for database insertion.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'transaction_id': transactionId,
      'file_path': filePath,
      'file_name': fileName,
      'file_type': fileType.dbValue,
      'file_size': fileSize,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  /// Create a BillAttachment from a database row.
  factory BillAttachment.fromMap(Map<String, dynamic> map) {
    return BillAttachment(
      id: map['id'] as int?,
      transactionId: map['transaction_id'] as int,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      fileType: BillFileType.fromDb(map['file_type'] as String),
      fileSize: map['file_size'] as int?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  BillAttachment copyWith({
    int? id,
    int? transactionId,
    String? filePath,
    String? fileName,
    BillFileType? fileType,
    int? fileSize,
    DateTime? createdAt,
  }) {
    return BillAttachment(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, transactionId, filePath, fileType];
}
