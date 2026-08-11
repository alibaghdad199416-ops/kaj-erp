import 'domain_translation_catalog.dart';
import 'module_translation_catalog.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/utils/display_number_formatter.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('ar')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(Localizations.localeOf(context));
  }

  bool get isArabic => locale.languageCode == 'ar';

  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  String text(String key) {
    final values = _localizedValues[key];
    if (values == null) {
      return key;
    }
    return values[locale.languageCode] ?? values['en'] ?? values['ar'] ?? key;
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'appName': {'ar': 'نظام خط الجودة KAJ', 'en': 'KAJ ERP'},
    'arabic': {'ar': 'العربية', 'en': 'Arabic'},
    'english': {'ar': 'الإنجليزية', 'en': 'English'},
    'language': {'ar': 'اللغة', 'en': 'Language'},
    'theme': {'ar': 'المظهر', 'en': 'Theme'},
    'lightTheme': {'ar': 'فاتح', 'en': 'Light'},
    'darkTheme': {'ar': 'غامق', 'en': 'Dark'},
    'dashboard': {'ar': 'لوحة التحكم', 'en': 'Dashboard'},
    'notifications': {'ar': 'مركز الإشعارات', 'en': 'Notification Center'},
    'globalSearch': {'ar': 'البحث الشامل', 'en': 'Global Search'},
    'globalSearchHint': {
      'ar': 'ابحث بالاسم أو الرقم أو الشاصي أو كود المستند...',
      'en': 'Search by name, number, chassis, or document code...',
    },
    'clearSearch': {'ar': 'مسح البحث', 'en': 'Clear search'},
    'stockCatalog': {'ar': 'المنتجات والمخزون', 'en': 'Products & Inventory'},
    'businessPartner': {'ar': 'شركاء الأعمال', 'en': 'Business Partners'},
    'salesReservations': {'ar': 'المبيعات', 'en': 'Sales'},
    'products': {'ar': 'المنتجات', 'en': 'Products'},
    'cars': {'ar': 'السيارات', 'en': 'Cars'},
    'customers': {'ar': 'العملاء', 'en': 'Customers'},
    'customerService': {'ar': 'خدمة العملاء', 'en': 'Customer Service'},
    'suppliers': {'ar': 'الموردون', 'en': 'Suppliers'},
    'purchases': {'ar': 'المشتريات', 'en': 'Purchases'},
    'sales': {'ar': 'المبيعات', 'en': 'Sales'},
    'expenses': {'ar': 'المصروفات', 'en': 'Expenses'},
    'inventory': {'ar': 'المخزون والمنتجات', 'en': 'Inventory & Products'},
    'maintenance': {'ar': 'الصيانة', 'en': 'Maintenance'},
    'installments': {'ar': 'الأقساط', 'en': 'Installments'},
    'cashbox': {'ar': 'الصندوق', 'en': 'Cashbox'},
    'accounting': {'ar': 'المحاسبة', 'en': 'Accounting'},
    'reports': {'ar': 'التقارير', 'en': 'Reports'},
    'usersPermissions': {
      'ar': 'المستخدمون والصلاحيات',
      'en': 'Users & Permissions',
    },
    'settings': {'ar': 'الإعدادات', 'en': 'Settings'},
    'navigationHome': {'ar': 'الرئيسية', 'en': 'Home'},
    'navigationInventoryOperations': {
      'ar': 'المخزون والعمليات',
      'en': 'Inventory & Operations',
    },
    'navigationPartnersService': {
      'ar': 'الشركاء وخدمة العملاء',
      'en': 'Partners & Customer Service',
    },
    'navigationCommercial': {
      'ar': 'المبيعات والمشتريات',
      'en': 'Sales & Purchases',
    },
    'navigationFinance': {'ar': 'المالية', 'en': 'Finance'},
    'navigationAdministration': {'ar': 'الإدارة', 'en': 'Administration'},
    'favorites': {'ar': 'المفضلة', 'en': 'Favorites'},
    'searchModules': {'ar': 'البحث في الوحدات...', 'en': 'Search modules...'},
    'expandNavigation': {'ar': 'توسيع القائمة', 'en': 'Expand navigation'},
    'collapseNavigation': {'ar': 'طي القائمة', 'en': 'Collapse navigation'},
    'useSideNavigation': {
      'ar': 'استخدام القائمة الجانبية',
      'en': 'Use side navigation',
    },
    'useTopNavigation': {
      'ar': 'استخدام القائمة العلوية',
      'en': 'Use top navigation',
    },
    'noResults': {'ar': 'لا توجد نتائج', 'en': 'No results'},
    'interactiveLoginRequired': {
      'ar': 'أدخل بياناتك لتسجيل الدخول.',
      'en': 'Enter your credentials to sign in.',
    },
    'logout': {'ar': 'تسجيل الخروج', 'en': 'Sign out'},
    'login': {'ar': 'تسجيل الدخول', 'en': 'Sign in'},
    'username': {'ar': 'اسم المستخدم', 'en': 'Username'},
    'password': {'ar': 'كلمة المرور', 'en': 'Password'},
    'showPassword': {'ar': 'إظهار كلمة المرور', 'en': 'Show password'},
    'hidePassword': {'ar': 'إخفاء كلمة المرور', 'en': 'Hide password'},
    'enterUsername': {
      'ar': 'يرجى إدخال اسم المستخدم',
      'en': 'Please enter the username',
    },
    'enterPassword': {
      'ar': 'يرجى إدخال كلمة المرور',
      'en': 'Please enter the password',
    },
    'loggingIn': {'ar': 'جارٍ تسجيل الدخول...', 'en': 'Signing in...'},
    'defaultAccount': {
      'ar': 'الحساب الافتراضي: admin / admin123',
      'en': 'Default account: admin / admin123',
    },
    'loginFailed': {'ar': 'تعذر تسجيل الدخول.', 'en': 'Unable to sign in.'},
    'users': {'ar': 'المستخدمون', 'en': 'Users'},
    'permissions': {'ar': 'الصلاحيات', 'en': 'Permissions'},
    'auditLog': {'ar': 'سجل العمليات', 'en': 'Audit log'},
    'recycleBin': {'ar': 'سلة المحذوفات', 'en': 'Recycle bin'},
    'restore': {'ar': 'استعادة', 'en': 'Restore'},
    'permanentDelete': {'ar': 'حذف نهائي', 'en': 'Delete permanently'},
    'recordType': {'ar': 'نوع السجل', 'en': 'Record type'},
    'newUser': {'ar': 'مستخدم جديد', 'en': 'New user'},
    'addUser': {'ar': 'إضافة مستخدم', 'en': 'Add user'},
    'editUser': {'ar': 'تعديل مستخدم', 'en': 'Edit user'},
    'fullName': {'ar': 'الاسم الكامل', 'en': 'Full name'},
    'email': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
    'phone': {'ar': 'الهاتف', 'en': 'Phone'},
    'role': {'ar': 'الدور', 'en': 'Role'},
    'activeAccount': {'ar': 'الحساب نشط', 'en': 'Active account'},
    'save': {'ar': 'حفظ', 'en': 'Save'},
    'cancel': {'ar': 'إلغاء', 'en': 'Cancel'},
    'delete': {'ar': 'حذف', 'en': 'Delete'},
    'edit': {'ar': 'تعديل', 'en': 'Edit'},
    'userPhoto': {'ar': 'صورة المستخدم', 'en': 'User photo'},
    'choosePhoto': {'ar': 'اختيار صورة', 'en': 'Choose photo'},
    'removePhoto': {'ar': 'إزالة الصورة', 'en': 'Remove photo'},
    'invalidUserPhoto': {
      'ar': 'ملف صورة المستخدم غير صالح.',
      'en': 'The user photo file is invalid.',
    },
    'userPhotoTooLarge': {
      'ar': 'صورة المستخدم كبيرة جدًا. اختر صورة أصغر من 900 كيلوبايت.',
      'en': 'The user photo is too large. Choose an image smaller than 900 KB.',
    },
    'nameRequired': {'ar': 'الاسم مطلوب', 'en': 'Name is required'},
    'minimum3': {'ar': '3 أحرف على الأقل', 'en': 'At least 3 characters'},
    'minimum6': {'ar': '6 أحرف على الأقل', 'en': 'At least 6 characters'},
    'chooseRole': {'ar': 'اختر الدور', 'en': 'Choose a role'},
    'newPasswordOptional': {
      'ar': 'كلمة مرور جديدة (اختياري)',
      'en': 'New password (optional)',
    },
    'accessManagement': {'ar': 'إدارة الوصول', 'en': 'Access management'},
    'accessManagementSubtitle': {
      'ar': 'إنشاء المستخدمين وتحديد الأدوار وحالة الحسابات.',
      'en': 'Create users and manage roles and account status.',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (item) => item.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class AppTranslation {
  static String localeCode = 'en';

  static bool get isArabic => localeCode == 'ar';

  static String translate(String value) =>
      translateForLocale(value, localeCode);

  /// Translates [value] for an explicit locale without depending on mutable
  /// global state. Widgets should prefer this method so tests and nested
  /// localized trees cannot leak a previous locale into the current UI.
  static String translateForLocale(String value, String targetLocaleCode) {
    if (value.trim().isEmpty) return value;
    final normalizedLocale = targetLocaleCode == 'ar' ? 'ar' : 'en';
    final repaired = DomainTranslationCatalog.repairMojibake(value);
    final domainValue = DomainTranslationCatalog.translate(
      repaired,
      normalizedLocale,
    );
    if (domainValue != repaired) return domainValue;

    if (normalizedLocale != 'ar') {
      final exact =
          ModuleTranslationCatalog.values[repaired] ?? _exact[repaired];
      if (exact != null) return exact;
      // Translate dynamic messages in one pass over the original Arabic
      // input. Sequential replacement used to reprocess generated English
      // words when a legacy English alias was also present in the catalog,
      // which produced mixed or corrupted labels.
      final replacements =
          <String, String>{
            ..._exact,
            ...ModuleTranslationCatalog.values,
            ..._phrases,
            ...ModuleTranslationCatalog.phrases,
          }.entries.where(
            (entry) =>
                _containsArabic(entry.key) && !_containsArabic(entry.value),
          );
      final translated = _replaceCatalogPhrases(
        repaired,
        replacements,
        sourceArabic: true,
      ).replaceAll('؟', '?');
      return translated == repaired
          ? _translateTechnicalIdentifier(repaired, false)
          : translated;
    }

    // Legacy screens also contain raw English strings. Translate them back
    // to Arabic so the selected locale is applied consistently everywhere.
    final reverseExact = <String, String>{
      for (final entry in _exact.entries) entry.value: entry.key,
      for (final entry in ModuleTranslationCatalog.values.entries)
        entry.value: entry.key,
      // Canonical Arabic labels must win when multiple legacy Arabic keys share
      // the same English translation.
      'Customer': 'عميل',
      'customer': 'عميل',
      'Supplier': 'مورد',
      'supplier': 'مورد',
      'Suppliers': 'الموردون',
      'Expenses': 'المصروفات',
      'Assets': 'الأصول',
      'Liabilities': 'الخصوم',
      'Equity': 'حقوق الملكية',
      'Revenue': 'الإيرادات',
    };
    final exactArabic = reverseExact[repaired];
    if (exactArabic != null) return exactArabic;

    final reverseReplacements =
        <String, String>{
              ..._exact,
              ...ModuleTranslationCatalog.values,
              ..._phrases,
              ...ModuleTranslationCatalog.phrases,
            }.entries
            .where(
              (entry) =>
                  _containsArabic(entry.key) && _containsLatin(entry.value),
            )
            .map((entry) => MapEntry(entry.value, entry.key));
    final translated = _replaceCatalogPhrases(
      repaired,
      reverseReplacements,
      sourceArabic: false,
    ).replaceAll('?', '؟');
    return translated == repaired
        ? _translateTechnicalIdentifier(repaired, true)
        : translated;
  }

  static const Map<String, String> _technicalArabic = <String, String>{
    'active': 'نشط',
    'inactive': 'غير نشط',
    'draft': 'مسودة',
    'approved': 'مصدق',
    'confirmed': 'مؤكد',
    'posted': 'مرحّل',
    'completed': 'مكتمل',
    'cancelled': 'ملغى',
    'deleted': 'محذوف',
    'pending': 'قيد الانتظار',
    'partially': 'جزئيًا',
    'executed': 'منفذ',
    'sales': 'مبيعات',
    'purchase': 'شراء',
    'maintenance': 'صيانة',
    'invoice': 'فاتورة',
    'payment': 'دفعة',
    'customer': 'عميل',
    'supplier': 'مورد',
    'account': 'حساب',
    'debit': 'مدين',
    'credit': 'دائن',
    'balance': 'رصيد',
    'inventory': 'مخزون',
    'warehouse': 'مخزن',
    'transfer': 'تحويل',
    'expense': 'مصروف',
    'revenue': 'إيراد',
    'cost': 'تكلفة',
    'opening': 'افتتاحي',
    'closing': 'ختامي',
  };

  static String _translateTechnicalIdentifier(String value, bool arabic) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_\- ]*$').hasMatch(value)) return value;
    final words = value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .split(RegExp(r'[_\-\s]+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return value;
    if (!arabic) {
      return words
          .map(
            (word) =>
                '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
          )
          .join(' ');
    }
    final translated = words
        .map((word) => _technicalArabic[word.toLowerCase()] ?? word)
        .toList();
    return translated.join(' ');
  }

  static final RegExp _arabicCharacters = RegExp(r'[\u0600-\u06FF]');
  static final RegExp _latinCharacters = RegExp(r'[A-Za-z]');

  static bool _containsArabic(String value) =>
      _arabicCharacters.hasMatch(value);

  static bool _containsLatin(String value) => _latinCharacters.hasMatch(value);

  /// Replaces the longest catalog phrases while scanning [input] exactly once.
  /// Inserted output is never scanned again, preventing translation cascades.
  static String _replaceCatalogPhrases(
    String input,
    Iterable<MapEntry<String, String>> entries, {
    required bool sourceArabic,
  }) {
    final candidates =
        entries
            .where(
              (entry) =>
                  entry.key.trim().isNotEmpty &&
                  entry.value.trim().isNotEmpty &&
                  entry.key != entry.value,
            )
            .toList(growable: false)
          ..sort((left, right) => right.key.length.compareTo(left.key.length));
    if (candidates.isEmpty) return input;

    final output = StringBuffer();
    var offset = 0;
    while (offset < input.length) {
      MapEntry<String, String>? selected;
      for (final candidate in candidates) {
        final token = candidate.key;
        if (offset + token.length > input.length ||
            !input.startsWith(token, offset) ||
            !_hasTranslationBoundaries(
              input,
              offset,
              token.length,
              sourceArabic: sourceArabic,
            )) {
          continue;
        }
        selected = candidate;
        break;
      }
      if (selected == null) {
        output.writeCharCode(input.codeUnitAt(offset));
        offset += 1;
      } else {
        output.write(selected.value);
        offset += selected.key.length;
      }
    }
    return output.toString();
  }

  static bool _hasTranslationBoundaries(
    String input,
    int start,
    int length, {
    required bool sourceArabic,
  }) {
    bool isWordCode(int code) {
      if (sourceArabic) return code >= 0x0600 && code <= 0x06ff;
      return (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5a) ||
          (code >= 0x61 && code <= 0x7a) ||
          code == 0x5f;
    }

    final beforeIsWord = start > 0 && isWordCode(input.codeUnitAt(start - 1));
    final end = start + length;
    final afterIsWord = end < input.length && isWordCode(input.codeUnitAt(end));
    return !beforeIsWord && !afterIsWord;
  }

  static const Map<String, String> _exact = {
    'جارٍ حفظ العميل...': 'Saving customer...',
    'تعذر حفظ اسم العميل وبياناته.':
        'Unable to save the customer name and details.',
    'تعذر حفظ بيانات المورد.': 'Unable to save supplier data.',
    'بيانات العميل والبنود والأسعار والتاريخ التشغيلي في نموذج واحد مرن.':
        'Customer, items, pricing, and operational date in one responsive form.',
    'المورد والبنود والكلف والتاريخ التشغيلي ضمن نموذج واضح ومتجاوب.':
        'Supplier, items, costs, and operational date in a clear responsive form.',
    'حذف أو عكس إذن التجهيز': 'Delete or reverse delivery note',
    'حذف أو عكس إشعار الاستلام': 'Delete or reverse warehouse receipt',
    'حذف أو عكس فاتورة البيع': 'Delete or reverse sales invoice',
    'حذف أو عكس فاتورة الشراء': 'Delete or reverse purchase invoice',
    'إلغاء فاتورة البيع': 'Cancel sales invoice',
    'إلغاء فاتورة الشراء': 'Cancel purchase invoice',
    'تأكيد الإلغاء والعكس': 'Confirm cancellation and reversal',
    'سبب الإلغاء': 'Cancellation reason',
    'حذف كامل': 'Delete completely',
    'تعديل الأمر والارتباطات': 'Edit order and linked records',
    'إنشاء إذن تجهيز مخزني': 'Create warehouse delivery note',
    'تصديق إذن التجهيز': 'Approve delivery note',
    'إنشاء إشعار استلام مخزني': 'Create warehouse receipt',
    'تصديق إشعار الاستلام': 'Approve warehouse receipt',
    'إنشاء فاتورة بيع': 'Create sales invoice',
    'تصديق فاتورة البيع': 'Approve sales invoice',
    'إنشاء فاتورة شراء': 'Create purchase invoice',
    'تصديق فاتورة الشراء': 'Approve purchase invoice',
    'الدفعات متعددة العملات': 'Multi-currency payments',
    'اختر المورد': 'Choose supplier',
    'اسم المجهز': 'Supplier name',
    'مسودة': 'Draft',
    'القسم الرئيسي': 'Main section',
    'إجمالي القسم': 'Section total',
    'التدفقات النقدية الداخلة': 'Cash In',
    'التدفقات النقدية الخارجة': 'Cash Out',
    'يرجى إدخال الاسم الكامل': 'Please enter the full name',
    'اسم المخزن مطلوب': 'Warehouse name is required',
    'تم ربط العميل بالأصول بنجاح.':
        'Customer was linked to Assets successfully.',
    'يتم تسجيل الدخول عبر Supabase، ثم تحميل مستخدم ERP من قاعدة البيانات':
        'Sign in through Supabase, then load the ERP user from the database',
    'هذا القيد مرتبط بمستند تشغيلي. سيُحذف المستند المصدر وتُعكس ارتباطاته المحاسبية والمخزنية. هل تريد المتابعة؟':
        'This journal entry is linked to an operational document. The source document will be deleted and its accounting and inventory effects reversed. Continue?',
    'تعذر حذف القيد أو المستند المصدر المرتبط.':
        'Unable to delete the journal entry or its source document.',
    'تحديد الكل': 'Select all',
    'إلغاء الكل': 'Clear all',
    'جميع الوحدات': 'All modules',
    'مفتوحة': 'Open',
    'مغلقة': 'Closed',
    'حذف العملة': 'Delete currency',
    'استعادة النسخة الاحتياطية': 'Restore backup',
    'ستُستبدل البيانات الحالية بمحتوى النسخة. يوصى بإنشاء نسخة جديدة قبل المتابعة.':
        'Current data will be replaced with the backup contents. Create a new backup before continuing.',
    'استعادة': 'Restore',
    'الاتصال السحابي': 'Cloud connection',
    'طابور المزامنة': 'Sync queue',
    'آخر نسخة احتياطية': 'Latest backup',
    'البيانات سحابية مباشرة ولا توجد مزامنة محلية معلقة.':
        'Data is cloud-native and there are no pending local sync operations.',
    'حذف المخزن': 'Delete warehouse',
    'تعديل الحساب': 'Edit account',
    'إجراءات الحساب': 'Account actions',
    'حذف الفاتورة': 'Delete invoice',
    'أسطول السيارات': 'Vehicle fleet',
    'الأقساط المستحقة': 'Due installments',
    'رصيد الصناديق IQD': 'IQD cash balance',
    'تنبيهات السيارات': 'Vehicle alerts',
    'حركة المبيعات': 'Sales activity',
    'الأقساط والمتابعات': 'Installments and follow-ups',
    'حالة الأسطول': 'Fleet status',
    'آخر النشاطات': 'Latest activity',
    'تعذر البحث': 'Search failed',
    'ابحث في جميع بيانات النظام': 'Search all system data',
    'جرّب رقم مستند أو اسم طرف أو رقم شاصي أو كود منتج مختلف.':
        'Try a different document number, party name, chassis number, or product code.',
    'إعداد Supabase': 'Supabase configuration',
    'اتصال PostgreSQL السحابي': 'Cloud PostgreSQL connection',
    'أدخل بريدًا إلكترونيًا صالحًا.': 'Enter a valid email address.',
    'Supabase Authentication غير مضبوط في هذه النسخة.':
        'Supabase authentication is not configured in this build.',
    'تم إرسال رابط استعادة كلمة المرور عبر Supabase.':
        'The password recovery link was sent through Supabase.',
    'انتهت مهلة الاتصال بخدمة Supabase.':
        'The connection to Supabase timed out.',
    'الإنجليزية — المصطلحات المحاسبية': 'English — Accounting terminology',
    'التحديث الفوري': 'Real-time updates',
    'مصادقة Supabase وقاعدة بيانات PostgreSQL للنظام':
        'Supabase authentication and PostgreSQL ERP database',
    'حدث خطأ غير متوقع': 'An unexpected error occurred',
    'تم حفظ المورد بنجاح': 'Supplier saved successfully',
    'أعد تحميل الصفحة. إذا تكرر الخطأ، احتفظ بصورة من الشاشة وسجل المتصفح.':
        'Reload the page. If the error recurs, keep a screenshot and the browser log.',
    'إزالة': 'Remove',
    'الإنجليزية': 'English',
    'العربية': 'Arabic',
    'مخطط قاعدة البيانات': 'Database schema',
    'لا توجد نتائج': 'No results',
    'ملخص لحظي لأعمال خط الجودة اليوم':
        'Live summary of Quality Line operations today',
    'إجمالي الفترة': 'Period total',
    'اختر حساب أصل مخزون فعالًا من نفس العملة.':
        'Select an active inventory asset account in the same currency.',
    'اختر حساب تكلفة مبيعات من المصاريف وبنفس العملة.':
        'Select a cost-of-sales expense account in the same currency.',
    'مادة مخزنية': 'Stock item',
    'خدمة غير مخزنية': 'Non-stock service',
    'مخزن اعتيادي': 'Regular warehouse',
    'مخزن توالف واستهلاك': 'Scrap and consumption warehouse',
    'فرز السيارات حسب مجموعة مخازن': 'Filter cars by warehouse group',
    'الإعدادات العامة': 'General settings',
    'حفظ الإعدادات': 'Save settings',
    'إضافة عملة': 'Add currency',
    'الأساسية': 'Primary',
    'نشطة': 'Active',
    'صلاحيات النسخ الاحتياطية': 'Backup permissions',
    'أنشئ نسخة داخلية أو استورد ملف نسخة محمولًا. يمكن تصدير أي نسخة وحفظها خارج النظام ثم استيرادها على جهاز آخر.':
        'Create an internal backup or import a portable backup file. Any backup can be exported, stored outside the system, and imported on another device.',
    'إنشاء نسخة الآن': 'Create backup now',
    'استيراد ملف نسخة': 'Import backup file',
    'لا توجد نسخ احتياطية بعد': 'No backups yet',
    'تم تصدير النسخة الاحتياطية.': 'The backup was exported.',
    'تم استيراد النسخة وفحص سلامتها بنجاح.':
        'The backup was imported and validated successfully.',
    'غير مصرح': 'Unauthorized',
    'ليس لديك صلاحية للوصول إلى هذه الصفحة':
        'You do not have permission to access this page',
    'العودة إلى لوحة التحكم': 'Back to dashboard',
    'تفاصيل التشغيل': 'Runtime details',
    'إعادة محاولة العمليات الفاشلة': 'Retry failed operations',
    'إلزامي': 'Required',
    'إرشادي': 'Advisory',
    'توصيات الصيانة': 'Maintenance recommendations',
    'فاتورة البيع السابقة: ': 'Previous sales invoice: ',
    'لم تكتمل تهيئة قاعدة البيانات. حدّث الصفحة أو أعد المحاولة.':
        'Database initialization is incomplete. Refresh the page or try again.',
    'لم تكتمل تهيئة قاعدة البيانات. حدّث الصفحة ثم أعد المحاولة.':
        'Database initialization is incomplete. Refresh the page, then try again.',
    'تعذر تجهيز تسجيل الدخول السحابي. أعد المحاولة بعد تحديث الصفحة.':
        'Cloud sign-in could not be prepared. Refresh the page and try again.',
    'أدخل البريد الإلكتروني أولًا.': 'Enter the email address first.',
    'تعذر إرسال رابط استعادة كلمة المرور.':
        'Unable to send the password reset link.',
    'حسنًا': 'OK',
    'الحساب السحابي': 'Cloud account',
    'الدخول إلى الحساب السحابي': 'Sign in to cloud account',
    'يتم تسجيل الدخول عبر Supabase، ثم تحميل مستخدم ERP من قاعدة البيانات ':
        'Sign-in is handled through Supabase, then the ERP user is loaded from the database ',
    'يجب تهيئة Supabase في نسخة التطبيق الحالية.':
        'Supabase must be configured in the current app build.',
    'استعادة كلمة المرور': 'Reset password',
    'العودة إلى شاشة الدخول': 'Back to sign-in',
    'حفظ العميل': 'Save customer',
    'تم توليد قيد الإهلاك بنجاح.':
        'The depreciation entry was generated successfully.',
    'الأصول الثابتة وغير المتداولة': 'Fixed and non-current assets',
    'إضافة أصل': 'Add asset',
    'لا توجد أصول ثابتة مسجلة.': 'No fixed assets are registered.',
    'توليد الإهلاك': 'Generate depreciation',
    'اختر حساب الأصل ومجمع الإهلاك ومصروف الإهلاك.':
        'Select the asset, accumulated depreciation, and depreciation expense accounts.',
    'القسط الثابت': 'Straight-line',
    'القسط المتناقص': 'Declining balance',
    'لا توجد أسطر مرتبطة بهذا القيد.':
        'No lines are linked to this journal entry.',
    'حفظ الفرع': 'Save branch',
    'طباعة السند': 'Print voucher',
    'غير مخزنة': 'Not in warehouse',
    'متوفرة في المخزن': 'Available in warehouse',
    'لوحة التحكم': 'Dashboard',
    'المؤشر': 'Metric',
    'القيمة': 'Value',
    'السيارات المحجوزة': 'Reserved cars',
    'السيارات المباعة': 'Sold cars',
    'المبيعات المدفوعة': 'Paid sales',
    'الذمم المدينة': 'Receivables',
    'ديون المشتريات': 'Purchase debt',
    'رصيد الصندوق بالدولار': 'Cash USD balance',
    'رصيد الصندوق بالدينار': 'Cash IQD balance',
    'الشهر': 'Month',
    'الإجراء': 'Action',
    'الكيان': 'Entity',
    'تقرير إداري': 'Management Report',
    'آخر ستة أشهر': 'Last six months',
    'منفذو إدخال البيانات': 'Data entry executors',
    'الرئيسية': 'Home',
    'نظرة عامة': 'Overview',
    'لوحة المعلومات التنفيذية': 'Executive Dashboard',
    'مرحباً بك،': 'Welcome,',
    'إدارة ومتابعة أعمال الشركة بسهولة':
        'Manage and monitor company operations with ease',
    'الإشعارات': 'Notifications',
    'آخر تحديث:': 'Last updated:',
    'السيولة والتسهيلات': 'Liquidity & facilities',
    'علاقات العمل': 'Business relationships',
    'حالة الربحية': 'Profitability status',
    'موجب': 'Positive',
    'سالب': 'Negative',
    'مدير النظام': 'System Administrator',
    'مسؤول النظام': 'Administrator',
    'المركز المحاسبي': 'Accounting Center',
    'المحاسبة الموحدة': 'Unified Accounting',
    'دليل الحسابات الشجري': 'Chart of Accounts',
    'القيود اليومية': 'Journal Entries',
    'دفتر الأستاذ العام': 'General Ledger',
    'قائمة التدفق النقدي': 'Cash Flow Statement',
    'الشركاء التجاريون': 'Business Partners',
    'العملاء والموردون': 'Customers & Suppliers',
    'تعديل العميل': 'Edit Customer',
    'إضافة مورد': 'Add Supplier',
    'تعديل المورد': 'Edit Supplier',
    'إضافة سيارة': 'Add Car',
    'تعديل السيارة': 'Edit Car',
    'إضافة عملية بيع': 'Add Sale',
    'تعديل عملية البيع': 'Edit Sale',
    'إضافة عملية شراء': 'Add Purchase',
    'حفظ التعديلات': 'Save Changes',
    'العودة': 'Back',
    'إدارة السيارات': 'Car Management',
    'إدارة العملاء': 'Customer Management',
    'إدارة الموردين': 'Supplier Management',
    'إدارة المجهزين': 'Supplier Management',
    'إدارة بيانات المجهزين وأرصدتهم وحالة تعاملهم.':
        'Manage supplier data, balances and status.',
    'تعذر تحميل المجهزين': 'Unable to load suppliers',
    'لا يوجد مجهزون مطابقون': 'No matching suppliers',
    'ابدأ بإضافة أول مجهز إلى النظام.':
        'Start by adding the first supplier to the system.',
    'إضافة مجهز': 'Add supplier',
    'تعديل مجهز': 'Edit supplier',
    'تفعيل المجهز': 'Activate supplier',
    'تعطيل المجهز': 'Deactivate supplier',
    'هل تريد تفعيل هذا المجهز؟': 'Do you want to activate this supplier?',
    'هل تريد تعطيل هذا المجهز؟': 'Do you want to deactivate this supplier?',
    'تعذر تحديث حالة المجهز.': 'Unable to update supplier status.',
    'تأكيد حذف المجهز': 'Confirm supplier deletion',
    'هل تريد حذف هذا المجهز؟ لا يمكن التراجع عن هذا الإجراء.':
        'Delete this supplier? This action cannot be undone.',
    'تعذر حذف المجهز.': 'Unable to delete supplier.',
    'إجمالي المجهزين': 'Total suppliers',
    'المجهزون النشطون': 'Active suppliers',
    'النتائج الظاهرة': 'Visible results',
    'البحث بالاسم أو الهاتف أو العنوان': 'Search by name, phone or address',
    'الأحدث': 'Newest',
    'إدارة بيانات السيارات ومتابعة حالاتها وقيمها.':
        'Manage vehicles, statuses and values.',
    'إدارة بيانات العملاء وسجل التعامل معهم.':
        'Manage customer data and relationship history.',
    'إدارة بيانات الموردين وأرصدتهم وحالة تعاملهم.':
        'Manage supplier data, balances and status.',
    'لا توجد سيارات مطابقة': 'No matching cars',
    'لا يوجد عملاء': 'No customers found',
    'جرّب تغيير معايير البحث أو أضف سيارة جديدة':
        'Change the search criteria or add a new car.',
    'إضافة سيارة جديدة': 'Add a new car',
    'تأكيد حذف السيارة': 'Confirm car deletion',
    'تأكيد حذف العميل': 'Confirm customer deletion',
    'هل تريد حذف هذه السيارة؟ لا يمكن التراجع عن هذا الإجراء.':
        'Delete this car? This action cannot be undone.',
    'هل تريد حذف هذا العميل؟ لا يمكن التراجع عن هذا الإجراء.':
        'Delete this customer? This action cannot be undone.',
    'المجهز': 'Supplier',
    'إضافة فرصة': 'Add opportunity',
    'تعديل فرصة': 'Edit opportunity',
    'حذف الفرصة': 'Delete opportunity',
    'لا توجد فرص عملاء': 'No customer opportunities',
    'انتظار': 'Pending',
    'قيمة المسار': 'Pipeline value',
    'إنشاء مسودة أمر بيع': 'Create sales order draft',
    'تم إنشاء مسودة أمر البيع من الفرصة':
        'Sales order draft created from the opportunity',
    'مسودة أمر بيع': 'Sales order draft',
    'تعديل أمر البيع': 'Edit sales order',
    'مسودة أمر شراء': 'Purchase order draft',
    'تعديل أمر الشراء': 'Edit purchase order',
    'عملة أمر البيع': 'Sales order currency',
    'عملة أمر الشراء': 'Purchase order currency',
    'البنود': 'Items',
    'إضافة بند': 'Add item',
    'حفظ كمسودة': 'Save as draft',
    'حفظ وتصديق أمر البيع': 'Save and approve sales order',
    'حفظ وتصديق أمر الشراء': 'Save and approve purchase order',
    'الإجمالي الفرعي': 'Subtotal',
    'الإجمالي النهائي': 'Grand total',
    'الخصم': 'Discount',
    'اختر العميل': 'Select customer',
    'اختر المجهز': 'Select supplier',
    'إضافة عميل': 'Add customer',
    'يجب اختيار العميل': 'A customer must be selected',
    'يجب اختيار المجهز': 'A supplier must be selected',
    'يجب إضافة سيارة أو منتج واحد على الأقل':
        'Add at least one vehicle or product',
    'قيمة الخصم غير صحيحة': 'Invalid discount amount',
    'أدخل معاملاً صحيحاً': 'Enter a valid exchange rate',
    'ابحث واختر السيارة أو المنتج': 'Search and select a vehicle or product',
    'اختيار السيارة أو المنتج': 'Select vehicle or product',
    'اضغط للبحث والاختيار': 'Tap to search and select',
    'البحث بالاسم أو الكود أو الشاصي أو اللوحة':
        'Search by name, code, chassis, or plate',
    'لا توجد نتائج مطابقة': 'No matching results',
    'النوع': 'Type',
    'الكود': 'Code',
    'الكمية المتاحة': 'Available quantity',
    'الكمية المتوفرة': 'Available quantity',
    'الكلفة': 'Cost',
    'رقم السيارة': 'Vehicle number',
    'رقم المادة': 'Item number',
    'الرمز الثانوي': 'Secondary code',
    'سنة الصنع': 'Year',
    'المخزن': 'Warehouse',
    'غير محدد': 'Not specified',
    'إنشاء مسودة تجهيز مخزني': 'Create warehouse delivery draft',
    'إنشاء مسودة استلام مخزني': 'Create warehouse receipt draft',
    'مخزن الاستلام': 'Receiving warehouse',
    'تسجيل الدفعة': 'Record payment',
    'تسجيل دفعة فاتورة شراء': 'Record purchase invoice payment',
    'تسجيل دفعة فاتورة بيع': 'Record sales invoice payment',
    'الصندوق المالي': 'Cash account',
    'طريقة معالجة فرق الصرف': 'Exchange difference treatment',
    'دفعة جزئية حسب القيمة المحولة فعلياً':
        'Partial payment by converted amount',
    'تسديد كامل وتقييد فرق الصرف': 'Full settlement with exchange adjustment',
    'لا يوجد صندوق مالي فعال': 'No active cash account',
    'دفعات فاتورة الشراء': 'Purchase invoice payments',
    'دفعات فاتورة البيع': 'Sales invoice payments',
    'المتبقي': 'Remaining',
    'إضافة دفعة أخرى': 'Add another payment',
    'تسجيل جميع الدفعات': 'Record all payments',
    'الدفعة': 'Payment',
    'نوع الدفعة': 'Payment type',
    'دفعة جزئية': 'Partial payment',
    'دفعة كلية': 'Full payment',
    'دفعة تسوية': 'Settlement payment',
    'المبلغ بعملة الفاتورة': 'Invoice-currency amount',
    'مبلغ الصندوق': 'Cash amount',
    'أدخل مبلغًا صحيحًا': 'Enter a valid amount',
    'أدخل مبلغ الصندوق': 'Enter the cash amount',
    'أدخل معاملًا صحيحًا': 'Enter a valid exchange rate',
    'حساب التسوية في الشجرة المحاسبية':
        'Settlement account in chart of accounts',
    'اختر حساب التسوية': 'Select a settlement account',
    'ملاحظات الدفعة': 'Payment notes',
    'مجموع الدفعات يتجاوز المبلغ المتبقي':
        'Payment total exceeds the remaining amount',
    'يجب اختيار حساب التسوية المحاسبي':
        'A settlement ledger account must be selected',
    'يجب أن تكون الدفعة الكلية أو دفعة التسوية هي الدفعة الأخيرة فقط':
        'A full or settlement payment must be the final payment only',
    'إدارة المبيعات': 'Sales management',
    'إضافة فاتورة بيع': 'Add sales invoice',
    'تعديل فاتورة بيع': 'Edit sales invoice',
    'لا توجد مبيعات': 'No sales found',
    'مسح': 'Clear',
    'السيارات': 'Cars',
    'خدمة العملاء': 'Customer Service',
    'فرصة جديدة': 'New opportunity',
    'فرص العملاء': 'Customer opportunities',
    'قيد الانتظار': 'Pending',
    'رابحة': 'Won',
    'خاسرة': 'Lost',
    'الموردون': 'Suppliers',
    'المشتريات': 'Purchases',
    'الحجوزات': 'Reservations',
    'المبيعات': 'Sales',
    'المصاريف': 'Expenses',
    'المخزون': 'Inventory',
    'المخزون والمنتجات': 'Inventory & Products',
    'الصيانة': 'Maintenance',
    'الأقساط': 'Installments',
    'الصندوق': 'Cashbox',
    'المحاسبة': 'Accounting',
    'التقارير': 'Reports',
    'الإعدادات': 'Settings',
    'المستخدمون والصلاحيات': 'Users & Permissions',
    'المستخدمون': 'Users',
    'الصلاحيات': 'Permissions',
    'سجل العمليات': 'Audit Log',
    'تسجيل الخروج': 'Sign out',
    'تسجيل الدخول': 'Sign in',
    'دخول': 'Sign in',
    'إلغاء': 'Cancel',
    'حفظ': 'Save',
    'حذف': 'Delete',
    'تعديل': 'Edit',
    'إضافة': 'Add',
    'بحث': 'Search',
    'البحث': 'Search',
    'تحديث': 'Refresh',
    'نشط': 'Active',
    'غير نشط': 'Inactive',
    'متوفرة': 'Available',
    'محجوزة': 'Reserved',
    'مباعة': 'Sold',
    'الكل': 'All',
    'نعم': 'Yes',
    'لا': 'No',
    'اسم المستخدم': 'Username',
    'كلمة المرور': 'Password',
    'الاسم الكامل': 'Full name',
    'البريد الإلكتروني': 'Email',
    'الهاتف': 'Phone',
    'العنوان': 'Address',
    'الدور': 'Role',
    'الحساب نشط': 'Active account',
    'مستخدم جديد': 'New user',
    'إضافة مستخدم': 'Add user',
    'تعديل مستخدم': 'Edit user',
    'اختيار صورة': 'Choose photo',
    'إزالة الصورة': 'Remove photo',
    'لا توجد نتائج.': 'No results.',
    'لا توجد بيانات': 'No data',
    'إعادة المحاولة': 'Try again',
    'جارٍ التحميل...': 'Loading...',
    'جارٍ الحفظ...': 'Saving...',
    'جارٍ تسجيل الدخول...': 'Signing in...',
    'رقم الفاتورة': 'Invoice number',
    'تاريخ الفاتورة': 'Invoice date',
    'تاريخ الشراء': 'Purchase date',
    'تاريخ البيع': 'Sale date',
    'المبلغ': 'Amount',
    'الإجمالي': 'Total',
    'المدفوع': 'Paid',
    'العملة': 'Currency',
    'ملاحظات': 'Notes',
    'طريقة الدفع': 'Payment method',
    'نقداً': 'Cash',
    'تحويل مصرفي': 'Bank transfer',
    'شيك': 'Cheque',
    'بطاقة': 'Card',
    'رقم الهيكل': 'Chassis number',
    'الموديل': 'Model',
    'اللون': 'Color',
    'السنة': 'Year',
    'السعر': 'Price',
    'سعر الشراء': 'Purchase price',
    'سعر البيع': 'Sale price',
    'الكمية': 'Quantity',
    'التصنيف': 'Category',
    'اسم المورد': 'Supplier name',
    'اسم العميل': 'Customer name',
    'رقم الهاتف': 'Phone number',
    'الفرع الرئيسي': 'Main branch',
    'دولار أمريكي': 'US Dollar',
    'دينار عراقي': 'Iraqi Dinar',
    'قيد جديد': 'New entry',
    'كشف حساب': 'Account statement',
    'ميزان المراجعة': 'Trial balance',
    'مدين': 'Debit',
    'دائن': 'Credit',
    'الرصيد': 'Balance',
    'المركز المالي والفروع': 'Finance Center & Branches',
    'الحسابات': 'Accounts',
    'التحويلات': 'Transfers',
    'العملات': 'Currencies',
    'الفروع': 'Branches',
    'الحسابات النقدية والمصرفية': 'Cash & Bank Accounts',
    'أنشئ عددًا غير محدود من الصناديق والبنوك والمحافظ مع رصيد مستقل لكل حساب.':
        'Create unlimited cashboxes, bank accounts, and wallets with an independent balance for each account.',
    'حساب جديد': 'New account',
    'الرصيد الحالي': 'Current balance',
    'التحويل بين الحسابات': 'Transfers Between Accounts',
    'يدعم التحويل بين حسابات بعملات مختلفة مع تسجيل معامل الصرف والحركتين المحاسبيتين تلقائيًا.':
        'Transfer between accounts in different currencies while recording the exchange rate and both accounting movements automatically.',
    'تحويل جديد': 'New transfer',
    'الرقم': 'Number',
    'من': 'From',
    'إلى': 'To',
    'معامل الصرف': 'Exchange rate',
    'التاريخ': 'Date',
    'العملات وأسعار الصرف': 'Currencies & Exchange Rates',
    'يُستخدم سعر الصرف المركزي كقيمة مساعدة في تسويات الدفعات والتحويلات المالية فقط.':
        'The central exchange rate is used only as a reference for payment settlements and financial transfers.',
    'عملة جديدة': 'New currency',
    'العملة الأساسية': 'Base currency',
    'أساس لتخصيص المخزون والسيارات والمستخدمين والتقارير لكل فرع.':
        'Foundation for assigning inventory, cars, users, and reports to each branch.',
    'فرع جديد': 'New branch',
    'اسم الحساب': 'Account name',
    'نوع الحساب': 'Account type',
    'صندوق نقدي': 'Cashbox',
    'حساب مصرفي': 'Bank account',
    'محفظة إلكترونية': 'E-wallet',
    'الرصيد الافتتاحي': 'Opening balance',
    'تحويل بين الحسابات': 'Transfer between accounts',
    'من حساب': 'From account',
    'إلى حساب': 'To account',
    'المبلغ المستلم': 'Received amount',
    'تنفيذ التحويل': 'Execute transfer',
    'بيانات العملة': 'Currency details',
    'الاسم العربي': 'Arabic name',
    'الاسم الإنجليزي': 'English name',
    'الرمز': 'Symbol',
    'بيانات الفرع': 'Branch details',
    'الرصيد الختامي': 'Closing balance',
    'سند قبض': 'Receipt voucher',
    'سند صرف': 'Payment voucher',
    'حركة جديدة': 'New transaction',
    'حفظ السيارة': 'Save car',
    'إدارة الوصول': 'Access management',
    'مدير': 'Manager',
    'محاسب': 'Accountant',
    'موظف مبيعات': 'Sales Representative',
    'صلاحيات كاملة': 'Full access',
    'إدارة العمليات والتقارير': 'Operations and reports management',
    'الصندوق والمحاسبة والتقارير': 'Cashbox, accounting and reports',
    'الماركة': 'Brand',
    'اسم الماركة': 'Brand name',
    'رقم الشاصي': 'Chassis number',
    'رقم اللوحة': 'Plate number',
    'إضافة صور': 'Add images',
    'لم تتم إضافة صور بعد': 'No images added yet',
    'حفظ الحركة': 'Save transaction',
    'إدارة الصندوق': 'Cash accounts management',
    'الحسابات النقدية': 'Cash accounts',
    'من الحساب': 'From account',
    'إلى الحساب': 'To account',
    'معامل التحويل': 'Exchange rate',
    'سعر الصرف': 'Exchange rate',
    'المبلغ بالعملة الأساسية': 'Amount in base currency',
    'نقدي': 'Cash',
    'مصرفي': 'Bank',
    'الجهة والملاحظات': 'Party and notes',
    'نوع الجهة': 'Party type',
    'اسم الجهة': 'Party name',
    'عميل': 'Customer',
    'مورد': 'Supplier',
    'موظف': 'Employee',
    'أخرى': 'Other',
    'إيصال': 'Receipt',
    'دفع': 'Payment',
    'تحويل': 'Transfer',
    'الماركات': 'Brands',
    'الموديلات': 'Models',
    'الخصائص': 'Attributes',
    'اسم المنتج': 'Product name',
    'الوحدة': 'Unit',
    'قطعة': 'Piece',
    'عام': 'General',
    'تكلفة الشراء': 'Purchase cost',
    'الكلفة الواصلة': 'Landed cost',
    'كلفة الوحدة': 'Unit cost',
    'الحد الأدنى': 'Minimum quantity',
    'الوارد المتوقع': 'Expected incoming',
    'الصادر المتوقع': 'Expected outgoing',
    'اسم المصروف': 'Expense name',
    'فئة المصروف': 'Expense category',
    'التكلفة بالدولار': 'Cost in USD',
    'التكلفة بالدينار': 'Cost in IQD',
    'السعر بالدولار': 'Price in USD',
    'السعر بالدينار': 'Price in IQD',
    'تقارير المودل': 'Module reports',
    'تقرير مخصص': 'Custom report',
    'تخصيص الأعمدة': 'Customize columns',
    'تصدير Excel': 'Export Excel',
    'تصدير PDF': 'Export PDF',
    'الفترة الزمنية': 'Date range',
    'تصفية حسب': 'Filter by',
    'جميع الفترات': 'All periods',
    'المالية': 'Finance',
    'التشغيل': 'Operations',
    'إجمالي السيارات': 'Total cars',
    'المتوفرة': 'Available',
    'قيد الشراء': 'Purchase pending',
    'قيد البيع': 'Sale pending',
    'المباعة': 'Sold',
    'معرفة': 'Identified',
    'الحالة': 'Status',
    'نقل بين المخازن': 'Warehouse transfer',
    'نقل السيارات بين المخازن': 'Vehicle warehouse transfers',
    'نقل سيارة بين المخازن': 'Transfer vehicle between warehouses',
    'المخزن الجديد': 'Destination warehouse',
    'تنفيذ النقل': 'Complete transfer',
    'المخزن والمنتجات': 'Products & Inventory',
    'الوحدات المتوفرة': 'Available units',
    'الرصيد المتوقع': 'Expected balance',
    'منخفض المخزون': 'Low stock',
    'حركة متوقعة': 'Planned movement',
    'نقل مخزني': 'Stock transfer',
    'بيع منتج': 'Sell product',
    'شراء / استلام': 'Purchase / Receipt',
    'منتج جديد': 'New product',
    'جميع المخازن': 'All warehouses',
    'السيارات المتاحة': 'Available cars',
    'إجمالي المبيعات': 'Total sales',
    'إجمالي المشتريات': 'Total purchases',
    'إجمالي المصاريف': 'Total expenses',
    'قيمة المخزون': 'Inventory value',
    'صافي الربح': 'Net profit',
    'رصيد الصندوق USD': 'Cash balance USD',
    'رصيد الصندوق IQD': 'Cash balance IQD',
    'ذمم العملاء': 'Customer receivables',
    'ذمم الموردين': 'Supplier payables',
    'لا توجد أرصدة مستحقة.': 'No outstanding balances.',
    'حسب الطرف والعملة': 'by party and currency',
    'لا يتم جمع العملات أو تحويلها داخل كشف الذمم.':
        'Currencies are not combined or converted in the subledger statement.',
    'تعذر تحميل تفاصيل الذمم': 'Unable to load subledger details',
    'مستند مستحق': 'outstanding document',
    'الحجوزات النشطة': 'Active reservations',
    'الأقساط المتأخرة': 'Overdue installments',
    'التقارير التنفيذية': 'Executive reports',
    'مؤشرات المبيعات والمشتريات والسيولة والمخزون.':
        'Sales, purchases, liquidity and inventory indicators.',
    'العملاء والحجوزات والمبيعات': 'Customers, reservations and sales',
    'stockCatalog': 'Stock & Catalog',
    'businessPartner': 'Business Partners',
    'salesReservations': 'Sales & Reservations',
    'الشريك التجاري': 'Business Partner',
    'المبيعات والحجوزات': 'Sales & Reservations',
    'الأصناف والمخزون': 'Products & Inventory',
    'الإعدادات والإدارة': 'Settings & Administration',
    'إعدادات النظام والمودلات': 'System & Module Settings',
    'الحجوزات وحالة السيارة': 'Reservations & Vehicle Status',
    'المنتجات والمخازن': 'Products & Warehouses',
    'لا توجد مخازن فعالة لإكمال العملية.':
        'No active warehouses are available to complete this operation.',
    'وزّع بنود التجهيز على المخازن. يجب أن يساوي مجموع كل بند كمية أمر البيع.':
        'Allocate delivery items across warehouses. Each item total must match the sales order quantity.',
    'وزّع بنود الاستلام على المخازن. يمكن تقسيم المنتج الواحد على أكثر من مخزن.':
        'Allocate receipt items across warehouses. A product may be split across multiple warehouses.',
    'اعتماد التوزيع': 'Confirm allocation',
    'تقسيم': 'Split',
    'المتاح': 'Available',
    'يجب اختيار المخزن': 'A warehouse must be selected',
    'الكمية يجب أن تكون أكبر من صفر': 'Quantity must be greater than zero',
    'خفّض كمية سطر آخر أو ارفعها قبل إضافة تقسيم جديد.':
        'Reduce another row quantity or increase it before adding a new split.',
    'مجموع توزيع البند يجب أن يساوي': 'The allocated item total must equal',
    'والقيمة الحالية': 'and the current total is',
    'يجب تجهيز السيارة من مخزنها الحالي أو نقلها أولًا إلى مخزن آخر.':
        'The vehicle must be delivered from its current warehouse or transferred first.',
    'الرصيد المتاح في أحد المخازن لا يكفي للتوزيع المطلوب':
        'The available balance in one warehouse is insufficient for the requested allocation',
    'لا توجد أرصدة متاحة لهذا المنتج.':
        'No available warehouse balances exist for this product.',
    'توزيع التجهيز على المخازن': 'Warehouse delivery allocation',
    'توزيع الاستلام على المخازن': 'Warehouse receipt allocation',
    'لا توجد بنود قابلة للتجهيز في الأمر.':
        'This order has no items available for delivery.',
    'لا توجد بنود قابلة للاستلام في الأمر.':
        'This order has no items available for receipt.',
    'تعذر تحميل السيارات والمنتجات المتاحة للبيع':
        'Unable to load vehicles and products available for sale',
    'تعذر تحميل السيارات والمنتجات المتاحة للشراء':
        'Unable to load vehicles and products available for purchase',
    'تعذر تحميل الخط العربي اللازم لإنشاء ملف PDF. تحقق من الاتصال بالإنترنت ثم أعد المحاولة؛ تم إيقاف التصدير لمنع ظهور رموز بدل الأحرف العربية.':
        'Unable to load the Arabic font required for PDF generation. Check the internet connection and try again; export was stopped to prevent corrupted Arabic characters.',
    'تعذر تحميل الخط العربي اللازم لإنشاء تقرير PDF. تحقق من الاتصال بالإنترنت ثم أعد المحاولة؛ تم إيقاف التصدير لمنع ظهور رموز بدل الأحرف العربية.':
        'Unable to load the Arabic font required for the PDF report. Check the internet connection and try again; export was stopped to prevent corrupted Arabic characters.',
  };

  static const Map<String, String> _phrases = {
    'يرجى إدخال': 'Please enter ',
    'يرجى اختيار': 'Please select ',
    'اختر ': 'Select ',
    'إضافة ': 'Add ',
    'تعديل ': 'Edit ',
    'حذف ': 'Delete ',
    'حفظ ': 'Save ',
    'عرض ': 'View ',
    'إدارة ': 'Manage ',
    'تعذر تحميل': 'Unable to load',
    'تعذر حفظ': 'Unable to save',
    'تعذر حذف': 'Unable to delete',
    'تعذر تحديث': 'Unable to update',
    'تعذر تسجيل الدخول': 'Unable to sign in',
    'تم الحفظ بنجاح': 'Saved successfully',
    'تم التحديث بنجاح': 'Updated successfully',
    'تم الحذف بنجاح': 'Deleted successfully',
    'تمت الإضافة بنجاح': 'Added successfully',
    'هل أنت متأكد من': 'Are you sure you want to',
    'لا يمكن التراجع عن هذه العملية': 'This action cannot be undone',
    'لا توجد': 'There are no',
    'إجمالي ': 'Total ',
    'عدد ': 'Number of ',
    'اسم ': 'Name ',
    'رقم ': 'Number ',
    'تاريخ ': 'Date ',
    'سعر ': 'Price ',
    'مبلغ ': 'Amount ',
    'لوحة التحكم': 'Dashboard',
    'المؤشر': 'Metric',
    'القيمة': 'Value',
    'السيارات المحجوزة': 'Reserved cars',
    'السيارات المباعة': 'Sold cars',
    'المبيعات المدفوعة': 'Paid sales',
    'الذمم المدينة': 'Receivables',
    'ديون المشتريات': 'Purchase debt',
    'رصيد الصندوق بالدولار': 'Cash USD balance',
    'رصيد الصندوق بالدينار': 'Cash IQD balance',
    'الشهر': 'Month',
    'الإجراء': 'Action',
    'الكيان': 'Entity',
    'تقرير إداري': 'Management Report',
    'آخر ستة أشهر': 'Last six months',
    'منفذو إدخال البيانات': 'Data entry executors',
    'الرئيسية': 'Home',
    'نظرة عامة': 'Overview',
    'لوحة المعلومات التنفيذية': 'Executive Dashboard',
    'مدير النظام': 'System Administrator',
    'مسؤول النظام': 'Administrator',
    'المركز المحاسبي': 'Accounting Center',
    'المحاسبة الموحدة': 'Unified Accounting',
    'دليل الحسابات الشجري': 'Chart of Accounts',
    'القيود اليومية': 'Journal Entries',
    'دفتر الأستاذ العام': 'General Ledger',
    'قائمة التدفق النقدي': 'Cash Flow Statement',
    'الشركاء التجاريون': 'Business Partners',
    'العملاء والموردون': 'Customers & Suppliers',
    'تعديل العميل': 'Edit Customer',
    'إضافة مورد': 'Add Supplier',
    'تعديل المورد': 'Edit Supplier',
    'إضافة سيارة': 'Add Car',
    'تعديل السيارة': 'Edit Car',
    'إضافة عملية بيع': 'Add Sale',
    'تعديل عملية البيع': 'Edit Sale',
    'إضافة عملية شراء': 'Add Purchase',
    'حفظ التعديلات': 'Save Changes',
    'العودة': 'Back',
    'إدارة السيارات': 'Car Management',
    'إدارة العملاء': 'Customer Management',
    'إدارة الموردين': 'Supplier Management',
    'إدارة المجهزين': 'Supplier Management',
    'إدارة بيانات المجهزين وأرصدتهم وحالة تعاملهم.':
        'Manage supplier data, balances and status.',
    'تعذر تحميل المجهزين': 'Unable to load suppliers',
    'لا يوجد مجهزون مطابقون': 'No matching suppliers',
    'ابدأ بإضافة أول مجهز إلى النظام.':
        'Start by adding the first supplier to the system.',
    'إضافة مجهز': 'Add supplier',
    'تعديل مجهز': 'Edit supplier',
    'تفعيل المجهز': 'Activate supplier',
    'تعطيل المجهز': 'Deactivate supplier',
    'هل تريد تفعيل هذا المجهز؟': 'Do you want to activate this supplier?',
    'هل تريد تعطيل هذا المجهز؟': 'Do you want to deactivate this supplier?',
    'تعذر تحديث حالة المجهز.': 'Unable to update supplier status.',
    'تأكيد حذف المجهز': 'Confirm supplier deletion',
    'هل تريد حذف هذا المجهز؟ لا يمكن التراجع عن هذا الإجراء.':
        'Delete this supplier? This action cannot be undone.',
    'تعذر حذف المجهز.': 'Unable to delete supplier.',
    'إجمالي المجهزين': 'Total suppliers',
    'المجهزون النشطون': 'Active suppliers',
    'النتائج الظاهرة': 'Visible results',
    'البحث بالاسم أو الهاتف أو العنوان': 'Search by name, phone or address',
    'الأحدث': 'Newest',
    'إدارة بيانات السيارات ومتابعة حالاتها وقيمها.':
        'Manage vehicles, statuses and values.',
    'إدارة بيانات العملاء وسجل التعامل معهم.':
        'Manage customer data and relationship history.',
    'إدارة بيانات الموردين وأرصدتهم وحالة تعاملهم.':
        'Manage supplier data, balances and status.',
    'لا توجد سيارات مطابقة': 'No matching cars',
    'لا يوجد عملاء': 'No customers found',
    'جرّب تغيير معايير البحث أو أضف سيارة جديدة':
        'Change the search criteria or add a new car.',
    'إضافة سيارة جديدة': 'Add a new car',
    'تأكيد حذف السيارة': 'Confirm car deletion',
    'تأكيد حذف العميل': 'Confirm customer deletion',
    'هل تريد حذف هذه السيارة؟ لا يمكن التراجع عن هذا الإجراء.':
        'Delete this car? This action cannot be undone.',
    'هل تريد حذف هذا العميل؟ لا يمكن التراجع عن هذا الإجراء.':
        'Delete this customer? This action cannot be undone.',
    'الشريك التجاري': 'Business Partners',
    'المجهز': 'Supplier',
    'خدمة العملاء': 'Customer Service',
    'فرصة جديدة': 'New opportunity',
    'إضافة فرصة': 'Add opportunity',
    'تعديل فرصة': 'Edit opportunity',
    'حذف الفرصة': 'Delete opportunity',
    'لا توجد فرص عملاء': 'No customer opportunities',
    'قيد الانتظار': 'Pending',
    'انتظار': 'Pending',
    'رابحة': 'Won',
    'خاسرة': 'Lost',
    'قيمة المسار': 'Pipeline value',
    'إنشاء مسودة أمر بيع': 'Create sales order draft',
    'تم إنشاء مسودة أمر البيع من الفرصة':
        'Sales order draft created from the opportunity',
    'مسودة أمر بيع': 'Sales order draft',
    'تعديل أمر البيع': 'Edit sales order',
    'مسودة أمر شراء': 'Purchase order draft',
    'تعديل أمر الشراء': 'Edit purchase order',
    'عملة أمر البيع': 'Sales order currency',
    'عملة أمر الشراء': 'Purchase order currency',
    'معامل التحويل': 'Exchange rate',
    'البنود': 'Items',
    'إضافة بند': 'Add item',
    'حفظ كمسودة': 'Save as draft',
    'حفظ وتصديق أمر البيع': 'Save and approve sales order',
    'حفظ وتصديق أمر الشراء': 'Save and approve purchase order',
    'الإجمالي الفرعي': 'Subtotal',
    'الإجمالي النهائي': 'Grand total',
    'الخصم': 'Discount',
    'ملاحظات': 'Notes',
    'اختر العميل': 'Select customer',
    'اختر المجهز': 'Select supplier',
    'إضافة عميل': 'Add customer',
    'يجب اختيار العميل': 'A customer must be selected',
    'يجب اختيار المجهز': 'A supplier must be selected',
    'يجب إضافة سيارة أو منتج واحد على الأقل':
        'Add at least one vehicle or product',
    'قيمة الخصم غير صحيحة': 'Invalid discount amount',
    'أدخل معاملاً صحيحاً': 'Enter a valid exchange rate',
    'ابحث واختر السيارة أو المنتج': 'Search and select a vehicle or product',
    'اختيار السيارة أو المنتج': 'Select vehicle or product',
    'اضغط للبحث والاختيار': 'Tap to search and select',
    'البحث بالاسم أو الكود أو الشاصي أو اللوحة':
        'Search by name, code, chassis, or plate',
    'لا توجد نتائج مطابقة': 'No matching results',
    'النوع': 'Type',
    'الكود': 'Code',
    'الكمية': 'Quantity',
    'الكمية المتاحة': 'Available quantity',
    'الكمية المتوفرة': 'Available quantity',
    'الكلفة': 'Cost',
    'رقم السيارة': 'Vehicle number',
    'رقم المادة': 'Item number',
    'الرمز الثانوي': 'Secondary code',
    'سعر البيع': 'Sale price',
    'سعر الشراء': 'Purchase price',
    'الماركة': 'Brand',
    'الموديل': 'Model',
    'سنة الصنع': 'Year',
    'اللون': 'Color',
    'رقم الشاصي': 'Chassis number',
    'رقم اللوحة': 'Plate number',
    'الحالة': 'Status',
    'المخزن': 'Warehouse',
    'غير محدد': 'Not specified',
    'إنشاء مسودة تجهيز مخزني': 'Create warehouse delivery draft',
    'إنشاء مسودة استلام مخزني': 'Create warehouse receipt draft',
    'مخزن الاستلام': 'Receiving warehouse',
    'تسجيل الدفعة': 'Record payment',
    'تسجيل دفعة فاتورة شراء': 'Record purchase invoice payment',
    'تسجيل دفعة فاتورة بيع': 'Record sales invoice payment',
    'الصندوق المالي': 'Cash account',
    'طريقة معالجة فرق الصرف': 'Exchange difference treatment',
    'دفعة جزئية حسب القيمة المحولة فعلياً':
        'Partial payment by converted amount',
    'تسديد كامل وتقييد فرق الصرف': 'Full settlement with exchange adjustment',
    'لا يوجد صندوق مالي فعال': 'No active cash account',
    'دفعات فاتورة الشراء': 'Purchase invoice payments',
    'دفعات فاتورة البيع': 'Sales invoice payments',
    'المتبقي': 'Remaining',
    'إضافة دفعة أخرى': 'Add another payment',
    'تسجيل جميع الدفعات': 'Record all payments',
    'الدفعة': 'Payment',
    'نوع الدفعة': 'Payment type',
    'دفعة جزئية': 'Partial payment',
    'دفعة كلية': 'Full payment',
    'دفعة تسوية': 'Settlement payment',
    'المبلغ بعملة الفاتورة': 'Invoice-currency amount',
    'مبلغ الصندوق': 'Cash amount',
    'أدخل مبلغًا صحيحًا': 'Enter a valid amount',
    'أدخل مبلغ الصندوق': 'Enter the cash amount',
    'أدخل معاملًا صحيحًا': 'Enter a valid exchange rate',
    'حساب التسوية في الشجرة المحاسبية':
        'Settlement account in chart of accounts',
    'اختر حساب التسوية': 'Select a settlement account',
    'ملاحظات الدفعة': 'Payment notes',
    'مجموع الدفعات يتجاوز المبلغ المتبقي':
        'Payment total exceeds the remaining amount',
    'يجب اختيار حساب التسوية المحاسبي':
        'A settlement ledger account must be selected',
    'يجب أن تكون الدفعة الكلية أو دفعة التسوية هي الدفعة الأخيرة فقط':
        'A full or settlement payment must be the final payment only',
    'إدارة المبيعات': 'Sales management',
    'إضافة فاتورة بيع': 'Add sales invoice',
    'تعديل فاتورة بيع': 'Edit sales invoice',
    'لا توجد مبيعات': 'No sales found',
    'مسح': 'Clear',
    'السيارات': 'Cars',
    'العملاء': 'Customers',
    'الموردون': 'Suppliers',
    'المشتريات': 'Purchases',
    'الحجوزات': 'Reservations',
    'المبيعات': 'Sales',
    'المصاريف': 'Expenses',
    'المخزون': 'Inventory',
    'المخزون والمنتجات': 'Inventory & Products',
    'الصيانة': 'Maintenance',
    'الأقساط': 'Installments',
    'الصندوق': 'Cashbox',
    'المحاسبة': 'Accounting',
    'التقارير': 'Reports',
    'المستخدم': 'user',
    'المورد': 'supplier',
    'العميل': 'customer',
    'السيارة': 'car',
    'الفاتورة': 'invoice',
    'الحجز': 'reservation',
    'البيع': 'sale',
    'الشراء': 'purchase',
    'الحساب': 'account',
    'الفرع': 'branch',
    'العملة': 'currency',
    'الصلاحية': 'permission',
    'البيانات': 'data',
    'مطلوب': 'is required',
    'على الأقل': 'at least',
    'جديد': 'new',
    'جديدة': 'new',
    'الحالي': 'current',
    'الحالية': 'current',
    'اليوم': 'today',
    'شهري': 'monthly',
    'سنوي': 'yearly',
    'المستندات المستحقة': 'Outstanding documents',
    'القيم معروضة بعملة المستند الأصلية دون تحويل، ولا تظهر أي مراجع تقنية.':
        'Values are shown in the original document currency without conversion, and no technical references are displayed.',
    'تعذر تحميل مستندات الذمم': 'Unable to load subledger documents',
    'لا توجد مستندات مستحقة.': 'There are no outstanding documents.',
    'بدون رقم': 'No number',
    'العربية — مصطلحات محاسبية عربية': 'Arabic — Arabic accounting terminology',
    'English — Accounting terminology': 'الإنجليزية — مصطلحات محاسبية إنجليزية',
    'المجهزون': 'Suppliers',
    'اسم الصندوق *': 'Cash account name *',
    'اسم الفرع': 'Branch name',
    'اسم المورد *': 'Supplier name *',
    'عدد الأقساط': 'Installment count',
    'طباعة PDF': 'Print PDF',
    'تنزيل PDF': 'Download PDF',
    'دولار أمريكي - USD': 'US Dollar - USD',
    'دينار عراقي - IQD': 'Iraqi Dinar - IQD',
    'USD - دولار أمريكي': 'USD - US Dollar',
    'IQD - دينار عراقي': 'IQD - Iraqi Dinar',
    'حذف حركة الصندوق': 'Delete cash transaction',
    'حذف تحويل الصناديق': 'Delete cash transfer',
    'حذف القيد المحاسبي': 'Delete journal entry',
    'تم حذف الحركة وتحديث القيد والارتباطات.':
        'The transaction, journal entry, and links were updated successfully.',
    'تم حذف أمر البيع وعكس التجهيز والفاتورة والدفعات والقيود.':
        'The sales order and its delivery, invoice, payments, and journals were reversed.',
    'تم حذف أمر الشراء وعكس الاستلام والفاتورة والدفعات والقيود.':
        'The purchase order and its receipt, invoice, payments, and journals were reversed.',
  };
}

class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final activeLocale =
        Localizations.maybeLocaleOf(context)?.languageCode ??
        AppTranslation.localeCode;
    final translated = AppTranslation.translateForLocale(data, activeLocale);
    return Text(
      DisplayNumberFormatter.formatText(translated),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

/// Selectable counterpart of [AppText]. It applies the active locale,
/// translates technical/status tokens, and formats user-facing numbers
/// without changing identifiers, dates, account codes, or document numbers.
class AppSelectableText extends StatelessWidget {
  const AppSelectableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.maxLines,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final activeLocale =
        Localizations.maybeLocaleOf(context)?.languageCode ??
        AppTranslation.localeCode;
    final translated = AppTranslation.translateForLocale(data, activeLocale);
    return SelectableText(
      DisplayNumberFormatter.formatText(translated),
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      maxLines: maxLines,
    );
  }
}
