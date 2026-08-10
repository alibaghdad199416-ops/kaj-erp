class CompanySettingsModel {
  const CompanySettingsModel({
    required this.companyName,
    required this.companyNameEn,
    required this.phone,
    required this.email,
    required this.address,
    required this.taxNumber,
    required this.defaultCurrency,
    required this.language,
  });

  final String companyName;
  final String companyNameEn;
  final String phone;
  final String email;
  final String address;
  final String taxNumber;
  final String defaultCurrency;
  final String language;

  factory CompanySettingsModel.defaults() => const CompanySettingsModel(
    companyName: 'شركة خط الجودة',
    companyNameEn: 'Quality Line',
    phone: '',
    email: '',
    address: '',
    taxNumber: '',
    defaultCurrency: 'USD',
    language: 'ar',
  );

  Map<String, String> toSettingsMap() => {
    'company_name': companyName,
    'company_name_en': companyNameEn,
    'company_phone': phone,
    'company_email': email,
    'company_address': address,
    'company_tax_number': taxNumber,
    'default_currency': defaultCurrency,
    'app_language': language,
  };

  factory CompanySettingsModel.fromSettingsMap(Map<String, String> map) {
    final defaults = CompanySettingsModel.defaults();
    return CompanySettingsModel(
      companyName: map['company_name'] ?? defaults.companyName,
      companyNameEn: map['company_name_en'] ?? defaults.companyNameEn,
      phone: map['company_phone'] ?? '',
      email: map['company_email'] ?? '',
      address: map['company_address'] ?? '',
      taxNumber: map['company_tax_number'] ?? '',
      defaultCurrency: map['default_currency'] ?? 'USD',
      language: map['app_language'] ?? 'ar',
    );
  }
}
