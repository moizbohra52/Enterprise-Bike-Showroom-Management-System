import 'package:enterprise_bike_showroom/common/models/base_model.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';

/// A chart-of-accounts entry.
class AccountModel extends BaseModel {
  AccountModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    required this.code,
    required this.name,
    required this.type,
    this.subType,
    this.parentId,
    this.isSystem = false,
    this.status = 'active',
  });

  final String? showroomId;
  final String code;
  final String name;
  // asset | liability | equity | income | expense
  final String type;
  final String? subType;
  final String? parentId;
  final bool isSystem;
  final String status;

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return AccountModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      code: SafeJson.asText(json['code']),
      name: SafeJson.asText(json['name']),
      type: SafeJson.asText(json['type'], fallback: 'asset'),
      subType: SafeJson.asText(json['sub_type']),
      parentId: SafeJson.asId(json['parent_id']),
      isSystem: SafeJson.asBoolOr(json['is_system'], false),
      status: SafeJson.asText(json['status'], fallback: 'active'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'code': code,
        'name': name,
        'type': type,
        'sub_type': subType,
        'parent_id': parentId,
        'is_system': isSystem,
        'status': status,
      };
}

/// One line of a journal entry.
class JournalLineModel {
  JournalLineModel({
    this.id,
    this.entryId,
    this.accountId = '',
    this.accountName = '',
    this.accountCode = '',
    this.side = 'debit',
    this.amount = 0,
    this.notes = '',
  });

  final String? id;
  final String? entryId;
  final String accountId;
  final String accountName;
  final String accountCode;
  final String side; // debit | credit
  final num amount;
  final String notes;

  factory JournalLineModel.fromJson(Map<String, dynamic> json) {
    // Accept both denormalized columns and a joined `accounts(*)`.
    final dynamic accounts = json['accounts'];
    final Map<String, dynamic> am =
        accounts is Map ? SafeJson.asMap(accounts) : <String, dynamic>{};
    return JournalLineModel(
      id: SafeJson.asId(json['id']),
      entryId: SafeJson.asId(json['journal_entry_id']),
      accountId: SafeJson.asText(json['account_id']),
      accountName: SafeJson.asText(am['name'],
          fallback: SafeJson.asText(json['account_name'])),
      accountCode: SafeJson.asText(am['code'],
          fallback: SafeJson.asText(json['account_code'])),
      side: SafeJson.asText(json['side'], fallback: 'debit'),
      amount: SafeJson.asMoney(json['amount']),
      notes: SafeJson.asText(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'account_id': accountId,
        'side': side,
        'amount': amount,
        'notes': notes,
      };
}

/// A journal entry (one or more debit/credit lines, always balanced).
class JournalEntryModel extends BaseModel {
  JournalEntryModel({
    super.id,
    super.createdAt,
    super.updatedAt,
    this.showroomId,
    required this.entryNumber,
    this.entryDate,
    this.narration = '',
    this.sourceModule,
    this.sourceId,
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.status = 'posted',
    this.lines = const <JournalLineModel>[],
  });

  final String? showroomId;
  final String entryNumber;
  final DateTime? entryDate;
  final String narration;
  // sales | purchases | expenses | finance | payments | manual
  final String? sourceModule;
  final String? sourceId;
  final num totalDebit;
  final num totalCredit;
  final String status; // posted | void
  final List<JournalLineModel> lines;

  factory JournalEntryModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> base = BaseModel().baseFromJson(json);
    return JournalEntryModel(
      id: base['id'] as String?,
      createdAt: base['createdAt'] as DateTime?,
      updatedAt: base['updatedAt'] as DateTime?,
      showroomId: SafeJson.asId(json['showroom_id']),
      entryNumber: SafeJson.asText(json['entry_number']),
      entryDate: SafeJson.asDay(json['entry_date']),
      narration: SafeJson.asText(json['narration']),
      sourceModule: SafeJson.asText(json['source_module']),
      sourceId: SafeJson.asId(json['source_id']),
      totalDebit: SafeJson.asMoney(json['total_debit']),
      totalCredit: SafeJson.asMoney(json['total_credit']),
      status: SafeJson.asText(json['status'], fallback: 'posted'),
      lines: <JournalLineModel>[
        for (final dynamic row in SafeJson.asList(json['journal_lines']))
          JournalLineModel.fromJson(SafeJson.asMap(row)),
      ],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toBaseJson(),
        'showroom_id': showroomId,
        'entry_number': entryNumber,
        if (entryDate != null)
          'entry_date': entryDate!.toIso8601String(),
        'narration': narration,
        'source_module': sourceModule,
        'source_id': sourceId,
        'status': status,
      };

  bool get balanced => totalDebit == totalCredit;
}
