enum CashFlowDirection { cashIn, cashOut }

class CashFlowEntry {
  const CashFlowEntry({required this.row, required this.amount});

  final Map<String, Object?> row;
  final double amount;

  String get entryNumber => _text(row['entryNumber'], fallback: '—');
  String get entryDate => _text(row['entryDate'], fallback: '—');
  String get referenceType => _text(row['referenceType'], fallback: '—');
  String get referenceId => _text(row['referenceId'], fallback: '—');
  String get description => _text(row['description'], fallback: '—');
  String get partyName => _text(row['partyName'], fallback: '—');
  String get currency => _text(row['currency'], fallback: '—');
  String get accountCode => _text(row['accountCode'], fallback: '—');
  String get accountName => _text(row['accountName'], fallback: '—');
  String get accountType => _text(row['accountType'], fallback: '—');
  String get hierarchyPath =>
      _text(row['hierarchyPath'], fallback: accountName);
  String get paymentMethod => _text(row['paymentMethod'], fallback: '—');
  String get costCenterName =>
      _text(row['costCenterName'] ?? row['costCenter'], fallback: '—');
  String get branchName =>
      _text(row['branchName'] ?? row['branch'], fallback: '—');
  double get debit => _number(row['debit']);
  double get credit => _number(row['credit']);
  double get openingBalance => _number(row['openingBalance']);
  double get runningBalance => _number(row['runningBalance']);

  Map<String, String> localizedDetails({required bool arabic}) =>
      <String, String>{
        arabic ? 'رقم القيد' : 'Entry number': entryNumber,
        arabic ? 'تاريخ القيد' : 'Entry date': entryDate,
        arabic ? 'مسار الحساب' : 'Account path': hierarchyPath,
        arabic ? 'رمز الحساب' : 'Account code': accountCode,
        arabic ? 'اسم الحساب' : 'Account name': accountName,
        arabic ? 'نوع الحساب' : 'Account type': accountType,
        arabic ? 'البيان' : 'Description': description,
        arabic ? 'الطرف' : 'Party': partyName,
        arabic ? 'طريقة الدفع' : 'Payment method': paymentMethod,
        arabic ? 'نوع المرجع' : 'Reference type': referenceType,
        arabic ? 'رقم المرجع' : 'Reference ID': referenceId,
        arabic ? 'العملة' : 'Currency': currency,
        arabic ? 'المدين' : 'Debit': debit.toStringAsFixed(2),
        arabic ? 'الدائن' : 'Credit': credit.toStringAsFixed(2),
        arabic ? 'الرصيد الافتتاحي' : 'Opening balance': openingBalance
            .toStringAsFixed(2),
        arabic ? 'الرصيد الجاري' : 'Running balance': runningBalance
            .toStringAsFixed(2),
        arabic ? 'مركز الكلفة' : 'Cost center': costCenterName,
        arabic ? 'الفرع' : 'Branch': branchName,
      };

  static String _text(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class CashFlowAccountNode {
  CashFlowAccountNode({
    required this.name,
    required this.path,
    required this.depth,
    this.code = '',
  });

  final String name;
  final String path;
  final int depth;
  String code;
  final Map<String, CashFlowAccountNode> children =
      <String, CashFlowAccountNode>{};
  final List<CashFlowEntry> entries = <CashFlowEntry>[];

  double get directAmount =>
      entries.fold<double>(0, (total, entry) => total + entry.amount);

  double get totalAmount => children.values.fold<double>(
    directAmount,
    (total, child) => total + child.totalAmount,
  );

  int get entryCount => children.values.fold<int>(
    entries.length,
    (total, child) => total + child.entryCount,
  );

  List<CashFlowAccountNode> get orderedChildren {
    final values = children.values.toList(growable: false);
    values.sort((a, b) {
      final byCode = a.code.compareTo(b.code);
      return byCode != 0 ? byCode : a.name.compareTo(b.name);
    });
    return values;
  }
}

class CashFlowHierarchy {
  CashFlowHierarchy({required this.cashIn, required this.cashOut});

  final List<CashFlowAccountNode> cashIn;
  final List<CashFlowAccountNode> cashOut;

  double get cashInTotal =>
      cashIn.fold<double>(0, (total, node) => total + node.totalAmount);

  double get cashOutTotal =>
      cashOut.fold<double>(0, (total, node) => total + node.totalAmount);

  double get netTotal => cashInTotal - cashOutTotal;

  static CashFlowHierarchy fromRows(List<Map<String, Object?>> rows) {
    final inRoots = <String, CashFlowAccountNode>{};
    final outRoots = <String, CashFlowAccountNode>{};

    for (final row in rows) {
      final cashIn = _number(row['cashIn']);
      final cashOut = _number(row['cashOut']);
      if (cashIn > 0) {
        _insert(inRoots, row, CashFlowEntry(row: row, amount: cashIn));
      }
      if (cashOut > 0) {
        _insert(outRoots, row, CashFlowEntry(row: row, amount: cashOut));
      }
    }

    List<CashFlowAccountNode> ordered(Map<String, CashFlowAccountNode> roots) {
      final values = roots.values.toList(growable: false);
      values.sort((a, b) {
        final byCode = a.code.compareTo(b.code);
        return byCode != 0 ? byCode : a.name.compareTo(b.name);
      });
      return values;
    }

    return CashFlowHierarchy(
      cashIn: ordered(inRoots),
      cashOut: ordered(outRoots),
    );
  }

  static void _insert(
    Map<String, CashFlowAccountNode> roots,
    Map<String, Object?> row,
    CashFlowEntry entry,
  ) {
    final accountName = _text(row['accountName']);
    final accountCode = _text(row['accountCode']);
    final rawPath = _text(row['hierarchyPath']);
    final pathParts = rawPath
        .split(RegExp(r'\s*/\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: true);
    if (pathParts.isEmpty) {
      pathParts.add(
        [accountCode, accountName].where((part) => part.isNotEmpty).join(' — '),
      );
    }
    if (pathParts.isEmpty || pathParts.last.isEmpty) {
      pathParts
        ..clear()
        ..add('حساب غير محدد');
    }

    var currentMap = roots;
    CashFlowAccountNode? current;
    final accumulated = <String>[];
    for (var index = 0; index < pathParts.length; index++) {
      final part = pathParts[index];
      accumulated.add(part);
      final path = accumulated.join(' / ');
      current = currentMap.putIfAbsent(
        path,
        () => CashFlowAccountNode(
          name: part,
          path: path,
          depth: index,
          code: index == pathParts.length - 1 ? accountCode : '',
        ),
      );
      if (index == pathParts.length - 1 && current.code.isEmpty) {
        current.code = accountCode;
      }
      currentMap = current.children;
    }
    current!.entries.add(entry);
  }

  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.toLowerCase() == 'null' ? '' : text;
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
