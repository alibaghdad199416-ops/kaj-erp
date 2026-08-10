class EnterpriseDocumentCreateInput {
  const EnterpriseDocumentCreateInput({
    required this.documentNumber,
    required this.titleAr,
    required this.fileName,
    required this.mimeType,
    required this.storagePath,
    required this.checksumSha256,
    this.titleEn = '',
    this.categoryId,
    this.ownerUserId,
    this.companyId,
    this.branchId,
    this.confidentiality = 'internal',
    this.fileSize = 0,
    this.extractedText = '',
    this.expiryDate,
    this.createdBy,
    this.metadata = const {},
  });

  final String documentNumber;
  final String titleAr;
  final String titleEn;
  final String fileName;
  final String mimeType;
  final String storagePath;
  final String checksumSha256;
  final String? categoryId;
  final String? ownerUserId;
  final String? companyId;
  final String? branchId;
  final String confidentiality;
  final int fileSize;
  final String extractedText;
  final DateTime? expiryDate;
  final String? createdBy;
  final Map<String, Object?> metadata;
}

class DocumentPermissionInput {
  const DocumentPermissionInput({
    this.canView = true,
    this.canDownload = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canShare = false,
    this.canPrint = false,
  });

  final bool canView;
  final bool canDownload;
  final bool canEdit;
  final bool canDelete;
  final bool canShare;
  final bool canPrint;
}
