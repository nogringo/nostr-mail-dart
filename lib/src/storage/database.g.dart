// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class Emails extends Table with TableInfo<Emails, EmailRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Emails(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _senderPubkeyMeta = const VerificationMeta(
    'senderPubkey',
  );
  late final GeneratedColumn<String> senderPubkey = GeneratedColumn<String>(
    'sender_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _recipientPubkeyMeta = const VerificationMeta(
    'recipientPubkey',
  );
  late final GeneratedColumn<String> recipientPubkey = GeneratedColumn<String>(
    'recipient_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _isPublicMeta = const VerificationMeta(
    'isPublic',
  );
  late final GeneratedColumn<bool> isPublic = GeneratedColumn<bool>(
    'is_public',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _isBridgedMeta = const VerificationMeta(
    'isBridged',
  );
  late final GeneratedColumn<bool> isBridged = GeneratedColumn<bool>(
    'is_bridged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lightMimeTextMeta = const VerificationMeta(
    'lightMimeText',
  );
  late final GeneratedColumn<String> lightMimeText = GeneratedColumn<String>(
    'light_mime_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _blossomHashMeta = const VerificationMeta(
    'blossomHash',
  );
  late final GeneratedColumn<String> blossomHash = GeneratedColumn<String>(
    'blossom_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _decryptionKeyMeta = const VerificationMeta(
    'decryptionKey',
  );
  late final GeneratedColumn<String> decryptionKey = GeneratedColumn<String>(
    'decryption_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _decryptionNonceMeta = const VerificationMeta(
    'decryptionNonce',
  );
  late final GeneratedColumn<String> decryptionNonce = GeneratedColumn<String>(
    'decryption_nonce',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fromAddressMeta = const VerificationMeta(
    'fromAddress',
  );
  late final GeneratedColumn<String> fromAddress = GeneratedColumn<String>(
    'from_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _bodyPlainMeta = const VerificationMeta(
    'bodyPlain',
  );
  late final GeneratedColumn<String> bodyPlain = GeneratedColumn<String>(
    'body_plain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    senderPubkey,
    recipientPubkey,
    isPublic,
    isBridged,
    lightMimeText,
    blossomHash,
    decryptionKey,
    decryptionNonce,
    createdAt,
    date,
    fromAddress,
    subject,
    bodyPlain,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emails';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmailRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sender_pubkey')) {
      context.handle(
        _senderPubkeyMeta,
        senderPubkey.isAcceptableOrUnknown(
          data['sender_pubkey']!,
          _senderPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_senderPubkeyMeta);
    }
    if (data.containsKey('recipient_pubkey')) {
      context.handle(
        _recipientPubkeyMeta,
        recipientPubkey.isAcceptableOrUnknown(
          data['recipient_pubkey']!,
          _recipientPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientPubkeyMeta);
    }
    if (data.containsKey('is_public')) {
      context.handle(
        _isPublicMeta,
        isPublic.isAcceptableOrUnknown(data['is_public']!, _isPublicMeta),
      );
    } else if (isInserting) {
      context.missing(_isPublicMeta);
    }
    if (data.containsKey('is_bridged')) {
      context.handle(
        _isBridgedMeta,
        isBridged.isAcceptableOrUnknown(data['is_bridged']!, _isBridgedMeta),
      );
    } else if (isInserting) {
      context.missing(_isBridgedMeta);
    }
    if (data.containsKey('light_mime_text')) {
      context.handle(
        _lightMimeTextMeta,
        lightMimeText.isAcceptableOrUnknown(
          data['light_mime_text']!,
          _lightMimeTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lightMimeTextMeta);
    }
    if (data.containsKey('blossom_hash')) {
      context.handle(
        _blossomHashMeta,
        blossomHash.isAcceptableOrUnknown(
          data['blossom_hash']!,
          _blossomHashMeta,
        ),
      );
    }
    if (data.containsKey('decryption_key')) {
      context.handle(
        _decryptionKeyMeta,
        decryptionKey.isAcceptableOrUnknown(
          data['decryption_key']!,
          _decryptionKeyMeta,
        ),
      );
    }
    if (data.containsKey('decryption_nonce')) {
      context.handle(
        _decryptionNonceMeta,
        decryptionNonce.isAcceptableOrUnknown(
          data['decryption_nonce']!,
          _decryptionNonceMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('from_address')) {
      context.handle(
        _fromAddressMeta,
        fromAddress.isAcceptableOrUnknown(
          data['from_address']!,
          _fromAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromAddressMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('body_plain')) {
      context.handle(
        _bodyPlainMeta,
        bodyPlain.isAcceptableOrUnknown(data['body_plain']!, _bodyPlainMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyPlainMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EmailRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmailRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      senderPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_pubkey'],
      )!,
      recipientPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_pubkey'],
      )!,
      isPublic: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_public'],
      )!,
      isBridged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_bridged'],
      )!,
      lightMimeText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}light_mime_text'],
      )!,
      blossomHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blossom_hash'],
      ),
      decryptionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decryption_key'],
      ),
      decryptionNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decryption_nonce'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      fromAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_address'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      bodyPlain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_plain'],
      )!,
    );
  }

  @override
  Emails createAlias(String alias) {
    return Emails(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class EmailRow extends DataClass implements Insertable<EmailRow> {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final bool isPublic;
  final bool isBridged;
  final String lightMimeText;
  final String? blossomHash;
  final String? decryptionKey;
  final String? decryptionNonce;
  final int createdAt;
  final int date;
  final String fromAddress;
  final String subject;
  final String bodyPlain;
  const EmailRow({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.isPublic,
    required this.isBridged,
    required this.lightMimeText,
    this.blossomHash,
    this.decryptionKey,
    this.decryptionNonce,
    required this.createdAt,
    required this.date,
    required this.fromAddress,
    required this.subject,
    required this.bodyPlain,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sender_pubkey'] = Variable<String>(senderPubkey);
    map['recipient_pubkey'] = Variable<String>(recipientPubkey);
    map['is_public'] = Variable<bool>(isPublic);
    map['is_bridged'] = Variable<bool>(isBridged);
    map['light_mime_text'] = Variable<String>(lightMimeText);
    if (!nullToAbsent || blossomHash != null) {
      map['blossom_hash'] = Variable<String>(blossomHash);
    }
    if (!nullToAbsent || decryptionKey != null) {
      map['decryption_key'] = Variable<String>(decryptionKey);
    }
    if (!nullToAbsent || decryptionNonce != null) {
      map['decryption_nonce'] = Variable<String>(decryptionNonce);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['date'] = Variable<int>(date);
    map['from_address'] = Variable<String>(fromAddress);
    map['subject'] = Variable<String>(subject);
    map['body_plain'] = Variable<String>(bodyPlain);
    return map;
  }

  EmailsCompanion toCompanion(bool nullToAbsent) {
    return EmailsCompanion(
      id: Value(id),
      senderPubkey: Value(senderPubkey),
      recipientPubkey: Value(recipientPubkey),
      isPublic: Value(isPublic),
      isBridged: Value(isBridged),
      lightMimeText: Value(lightMimeText),
      blossomHash: blossomHash == null && nullToAbsent
          ? const Value.absent()
          : Value(blossomHash),
      decryptionKey: decryptionKey == null && nullToAbsent
          ? const Value.absent()
          : Value(decryptionKey),
      decryptionNonce: decryptionNonce == null && nullToAbsent
          ? const Value.absent()
          : Value(decryptionNonce),
      createdAt: Value(createdAt),
      date: Value(date),
      fromAddress: Value(fromAddress),
      subject: Value(subject),
      bodyPlain: Value(bodyPlain),
    );
  }

  factory EmailRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmailRow(
      id: serializer.fromJson<String>(json['id']),
      senderPubkey: serializer.fromJson<String>(json['sender_pubkey']),
      recipientPubkey: serializer.fromJson<String>(json['recipient_pubkey']),
      isPublic: serializer.fromJson<bool>(json['is_public']),
      isBridged: serializer.fromJson<bool>(json['is_bridged']),
      lightMimeText: serializer.fromJson<String>(json['light_mime_text']),
      blossomHash: serializer.fromJson<String?>(json['blossom_hash']),
      decryptionKey: serializer.fromJson<String?>(json['decryption_key']),
      decryptionNonce: serializer.fromJson<String?>(json['decryption_nonce']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      date: serializer.fromJson<int>(json['date']),
      fromAddress: serializer.fromJson<String>(json['from_address']),
      subject: serializer.fromJson<String>(json['subject']),
      bodyPlain: serializer.fromJson<String>(json['body_plain']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sender_pubkey': serializer.toJson<String>(senderPubkey),
      'recipient_pubkey': serializer.toJson<String>(recipientPubkey),
      'is_public': serializer.toJson<bool>(isPublic),
      'is_bridged': serializer.toJson<bool>(isBridged),
      'light_mime_text': serializer.toJson<String>(lightMimeText),
      'blossom_hash': serializer.toJson<String?>(blossomHash),
      'decryption_key': serializer.toJson<String?>(decryptionKey),
      'decryption_nonce': serializer.toJson<String?>(decryptionNonce),
      'created_at': serializer.toJson<int>(createdAt),
      'date': serializer.toJson<int>(date),
      'from_address': serializer.toJson<String>(fromAddress),
      'subject': serializer.toJson<String>(subject),
      'body_plain': serializer.toJson<String>(bodyPlain),
    };
  }

  EmailRow copyWith({
    String? id,
    String? senderPubkey,
    String? recipientPubkey,
    bool? isPublic,
    bool? isBridged,
    String? lightMimeText,
    Value<String?> blossomHash = const Value.absent(),
    Value<String?> decryptionKey = const Value.absent(),
    Value<String?> decryptionNonce = const Value.absent(),
    int? createdAt,
    int? date,
    String? fromAddress,
    String? subject,
    String? bodyPlain,
  }) => EmailRow(
    id: id ?? this.id,
    senderPubkey: senderPubkey ?? this.senderPubkey,
    recipientPubkey: recipientPubkey ?? this.recipientPubkey,
    isPublic: isPublic ?? this.isPublic,
    isBridged: isBridged ?? this.isBridged,
    lightMimeText: lightMimeText ?? this.lightMimeText,
    blossomHash: blossomHash.present ? blossomHash.value : this.blossomHash,
    decryptionKey: decryptionKey.present
        ? decryptionKey.value
        : this.decryptionKey,
    decryptionNonce: decryptionNonce.present
        ? decryptionNonce.value
        : this.decryptionNonce,
    createdAt: createdAt ?? this.createdAt,
    date: date ?? this.date,
    fromAddress: fromAddress ?? this.fromAddress,
    subject: subject ?? this.subject,
    bodyPlain: bodyPlain ?? this.bodyPlain,
  );
  EmailRow copyWithCompanion(EmailsCompanion data) {
    return EmailRow(
      id: data.id.present ? data.id.value : this.id,
      senderPubkey: data.senderPubkey.present
          ? data.senderPubkey.value
          : this.senderPubkey,
      recipientPubkey: data.recipientPubkey.present
          ? data.recipientPubkey.value
          : this.recipientPubkey,
      isPublic: data.isPublic.present ? data.isPublic.value : this.isPublic,
      isBridged: data.isBridged.present ? data.isBridged.value : this.isBridged,
      lightMimeText: data.lightMimeText.present
          ? data.lightMimeText.value
          : this.lightMimeText,
      blossomHash: data.blossomHash.present
          ? data.blossomHash.value
          : this.blossomHash,
      decryptionKey: data.decryptionKey.present
          ? data.decryptionKey.value
          : this.decryptionKey,
      decryptionNonce: data.decryptionNonce.present
          ? data.decryptionNonce.value
          : this.decryptionNonce,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      date: data.date.present ? data.date.value : this.date,
      fromAddress: data.fromAddress.present
          ? data.fromAddress.value
          : this.fromAddress,
      subject: data.subject.present ? data.subject.value : this.subject,
      bodyPlain: data.bodyPlain.present ? data.bodyPlain.value : this.bodyPlain,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmailRow(')
          ..write('id: $id, ')
          ..write('senderPubkey: $senderPubkey, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('isPublic: $isPublic, ')
          ..write('isBridged: $isBridged, ')
          ..write('lightMimeText: $lightMimeText, ')
          ..write('blossomHash: $blossomHash, ')
          ..write('decryptionKey: $decryptionKey, ')
          ..write('decryptionNonce: $decryptionNonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('date: $date, ')
          ..write('fromAddress: $fromAddress, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    senderPubkey,
    recipientPubkey,
    isPublic,
    isBridged,
    lightMimeText,
    blossomHash,
    decryptionKey,
    decryptionNonce,
    createdAt,
    date,
    fromAddress,
    subject,
    bodyPlain,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmailRow &&
          other.id == this.id &&
          other.senderPubkey == this.senderPubkey &&
          other.recipientPubkey == this.recipientPubkey &&
          other.isPublic == this.isPublic &&
          other.isBridged == this.isBridged &&
          other.lightMimeText == this.lightMimeText &&
          other.blossomHash == this.blossomHash &&
          other.decryptionKey == this.decryptionKey &&
          other.decryptionNonce == this.decryptionNonce &&
          other.createdAt == this.createdAt &&
          other.date == this.date &&
          other.fromAddress == this.fromAddress &&
          other.subject == this.subject &&
          other.bodyPlain == this.bodyPlain);
}

class EmailsCompanion extends UpdateCompanion<EmailRow> {
  final Value<String> id;
  final Value<String> senderPubkey;
  final Value<String> recipientPubkey;
  final Value<bool> isPublic;
  final Value<bool> isBridged;
  final Value<String> lightMimeText;
  final Value<String?> blossomHash;
  final Value<String?> decryptionKey;
  final Value<String?> decryptionNonce;
  final Value<int> createdAt;
  final Value<int> date;
  final Value<String> fromAddress;
  final Value<String> subject;
  final Value<String> bodyPlain;
  final Value<int> rowid;
  const EmailsCompanion({
    this.id = const Value.absent(),
    this.senderPubkey = const Value.absent(),
    this.recipientPubkey = const Value.absent(),
    this.isPublic = const Value.absent(),
    this.isBridged = const Value.absent(),
    this.lightMimeText = const Value.absent(),
    this.blossomHash = const Value.absent(),
    this.decryptionKey = const Value.absent(),
    this.decryptionNonce = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.date = const Value.absent(),
    this.fromAddress = const Value.absent(),
    this.subject = const Value.absent(),
    this.bodyPlain = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmailsCompanion.insert({
    required String id,
    required String senderPubkey,
    required String recipientPubkey,
    required bool isPublic,
    required bool isBridged,
    required String lightMimeText,
    this.blossomHash = const Value.absent(),
    this.decryptionKey = const Value.absent(),
    this.decryptionNonce = const Value.absent(),
    required int createdAt,
    required int date,
    required String fromAddress,
    required String subject,
    required String bodyPlain,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       senderPubkey = Value(senderPubkey),
       recipientPubkey = Value(recipientPubkey),
       isPublic = Value(isPublic),
       isBridged = Value(isBridged),
       lightMimeText = Value(lightMimeText),
       createdAt = Value(createdAt),
       date = Value(date),
       fromAddress = Value(fromAddress),
       subject = Value(subject),
       bodyPlain = Value(bodyPlain);
  static Insertable<EmailRow> custom({
    Expression<String>? id,
    Expression<String>? senderPubkey,
    Expression<String>? recipientPubkey,
    Expression<bool>? isPublic,
    Expression<bool>? isBridged,
    Expression<String>? lightMimeText,
    Expression<String>? blossomHash,
    Expression<String>? decryptionKey,
    Expression<String>? decryptionNonce,
    Expression<int>? createdAt,
    Expression<int>? date,
    Expression<String>? fromAddress,
    Expression<String>? subject,
    Expression<String>? bodyPlain,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (senderPubkey != null) 'sender_pubkey': senderPubkey,
      if (recipientPubkey != null) 'recipient_pubkey': recipientPubkey,
      if (isPublic != null) 'is_public': isPublic,
      if (isBridged != null) 'is_bridged': isBridged,
      if (lightMimeText != null) 'light_mime_text': lightMimeText,
      if (blossomHash != null) 'blossom_hash': blossomHash,
      if (decryptionKey != null) 'decryption_key': decryptionKey,
      if (decryptionNonce != null) 'decryption_nonce': decryptionNonce,
      if (createdAt != null) 'created_at': createdAt,
      if (date != null) 'date': date,
      if (fromAddress != null) 'from_address': fromAddress,
      if (subject != null) 'subject': subject,
      if (bodyPlain != null) 'body_plain': bodyPlain,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmailsCompanion copyWith({
    Value<String>? id,
    Value<String>? senderPubkey,
    Value<String>? recipientPubkey,
    Value<bool>? isPublic,
    Value<bool>? isBridged,
    Value<String>? lightMimeText,
    Value<String?>? blossomHash,
    Value<String?>? decryptionKey,
    Value<String?>? decryptionNonce,
    Value<int>? createdAt,
    Value<int>? date,
    Value<String>? fromAddress,
    Value<String>? subject,
    Value<String>? bodyPlain,
    Value<int>? rowid,
  }) {
    return EmailsCompanion(
      id: id ?? this.id,
      senderPubkey: senderPubkey ?? this.senderPubkey,
      recipientPubkey: recipientPubkey ?? this.recipientPubkey,
      isPublic: isPublic ?? this.isPublic,
      isBridged: isBridged ?? this.isBridged,
      lightMimeText: lightMimeText ?? this.lightMimeText,
      blossomHash: blossomHash ?? this.blossomHash,
      decryptionKey: decryptionKey ?? this.decryptionKey,
      decryptionNonce: decryptionNonce ?? this.decryptionNonce,
      createdAt: createdAt ?? this.createdAt,
      date: date ?? this.date,
      fromAddress: fromAddress ?? this.fromAddress,
      subject: subject ?? this.subject,
      bodyPlain: bodyPlain ?? this.bodyPlain,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (senderPubkey.present) {
      map['sender_pubkey'] = Variable<String>(senderPubkey.value);
    }
    if (recipientPubkey.present) {
      map['recipient_pubkey'] = Variable<String>(recipientPubkey.value);
    }
    if (isPublic.present) {
      map['is_public'] = Variable<bool>(isPublic.value);
    }
    if (isBridged.present) {
      map['is_bridged'] = Variable<bool>(isBridged.value);
    }
    if (lightMimeText.present) {
      map['light_mime_text'] = Variable<String>(lightMimeText.value);
    }
    if (blossomHash.present) {
      map['blossom_hash'] = Variable<String>(blossomHash.value);
    }
    if (decryptionKey.present) {
      map['decryption_key'] = Variable<String>(decryptionKey.value);
    }
    if (decryptionNonce.present) {
      map['decryption_nonce'] = Variable<String>(decryptionNonce.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (fromAddress.present) {
      map['from_address'] = Variable<String>(fromAddress.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (bodyPlain.present) {
      map['body_plain'] = Variable<String>(bodyPlain.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmailsCompanion(')
          ..write('id: $id, ')
          ..write('senderPubkey: $senderPubkey, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('isPublic: $isPublic, ')
          ..write('isBridged: $isBridged, ')
          ..write('lightMimeText: $lightMimeText, ')
          ..write('blossomHash: $blossomHash, ')
          ..write('decryptionKey: $decryptionKey, ')
          ..write('decryptionNonce: $decryptionNonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('date: $date, ')
          ..write('fromAddress: $fromAddress, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Attachments extends Table with TableInfo<Attachments, AttachmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Attachments(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _emailIdMeta = const VerificationMeta(
    'emailId',
  );
  late final GeneratedColumn<String> emailId = GeneratedColumn<String>(
    'email_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES emails(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _contentIdMeta = const VerificationMeta(
    'contentId',
  );
  late final GeneratedColumn<String> contentId = GeneratedColumn<String>(
    'content_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    emailId,
    position,
    filename,
    contentType,
    size,
    sha256,
    contentId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('email_id')) {
      context.handle(
        _emailIdMeta,
        emailId.isAcceptableOrUnknown(data['email_id']!, _emailIdMeta),
      );
    } else if (isInserting) {
      context.missing(_emailIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('content_id')) {
      context.handle(
        _contentIdMeta,
        contentId.isAcceptableOrUnknown(data['content_id']!, _contentIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {emailId, position};
  @override
  AttachmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachmentRow(
      emailId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      ),
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      contentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_id'],
      ),
    );
  }

  @override
  Attachments createAlias(String alias) {
    return Attachments(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(email_id, position)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class AttachmentRow extends DataClass implements Insertable<AttachmentRow> {
  final String emailId;
  final int position;
  final String? filename;
  final String contentType;
  final int size;
  final String sha256;
  final String? contentId;
  const AttachmentRow({
    required this.emailId,
    required this.position,
    this.filename,
    required this.contentType,
    required this.size,
    required this.sha256,
    this.contentId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['email_id'] = Variable<String>(emailId);
    map['position'] = Variable<int>(position);
    if (!nullToAbsent || filename != null) {
      map['filename'] = Variable<String>(filename);
    }
    map['content_type'] = Variable<String>(contentType);
    map['size'] = Variable<int>(size);
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || contentId != null) {
      map['content_id'] = Variable<String>(contentId);
    }
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      emailId: Value(emailId),
      position: Value(position),
      filename: filename == null && nullToAbsent
          ? const Value.absent()
          : Value(filename),
      contentType: Value(contentType),
      size: Value(size),
      sha256: Value(sha256),
      contentId: contentId == null && nullToAbsent
          ? const Value.absent()
          : Value(contentId),
    );
  }

  factory AttachmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachmentRow(
      emailId: serializer.fromJson<String>(json['email_id']),
      position: serializer.fromJson<int>(json['position']),
      filename: serializer.fromJson<String?>(json['filename']),
      contentType: serializer.fromJson<String>(json['content_type']),
      size: serializer.fromJson<int>(json['size']),
      sha256: serializer.fromJson<String>(json['sha256']),
      contentId: serializer.fromJson<String?>(json['content_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'email_id': serializer.toJson<String>(emailId),
      'position': serializer.toJson<int>(position),
      'filename': serializer.toJson<String?>(filename),
      'content_type': serializer.toJson<String>(contentType),
      'size': serializer.toJson<int>(size),
      'sha256': serializer.toJson<String>(sha256),
      'content_id': serializer.toJson<String?>(contentId),
    };
  }

  AttachmentRow copyWith({
    String? emailId,
    int? position,
    Value<String?> filename = const Value.absent(),
    String? contentType,
    int? size,
    String? sha256,
    Value<String?> contentId = const Value.absent(),
  }) => AttachmentRow(
    emailId: emailId ?? this.emailId,
    position: position ?? this.position,
    filename: filename.present ? filename.value : this.filename,
    contentType: contentType ?? this.contentType,
    size: size ?? this.size,
    sha256: sha256 ?? this.sha256,
    contentId: contentId.present ? contentId.value : this.contentId,
  );
  AttachmentRow copyWithCompanion(AttachmentsCompanion data) {
    return AttachmentRow(
      emailId: data.emailId.present ? data.emailId.value : this.emailId,
      position: data.position.present ? data.position.value : this.position,
      filename: data.filename.present ? data.filename.value : this.filename,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      size: data.size.present ? data.size.value : this.size,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      contentId: data.contentId.present ? data.contentId.value : this.contentId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentRow(')
          ..write('emailId: $emailId, ')
          ..write('position: $position, ')
          ..write('filename: $filename, ')
          ..write('contentType: $contentType, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('contentId: $contentId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    emailId,
    position,
    filename,
    contentType,
    size,
    sha256,
    contentId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachmentRow &&
          other.emailId == this.emailId &&
          other.position == this.position &&
          other.filename == this.filename &&
          other.contentType == this.contentType &&
          other.size == this.size &&
          other.sha256 == this.sha256 &&
          other.contentId == this.contentId);
}

class AttachmentsCompanion extends UpdateCompanion<AttachmentRow> {
  final Value<String> emailId;
  final Value<int> position;
  final Value<String?> filename;
  final Value<String> contentType;
  final Value<int> size;
  final Value<String> sha256;
  final Value<String?> contentId;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.emailId = const Value.absent(),
    this.position = const Value.absent(),
    this.filename = const Value.absent(),
    this.contentType = const Value.absent(),
    this.size = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.contentId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String emailId,
    required int position,
    this.filename = const Value.absent(),
    required String contentType,
    required int size,
    required String sha256,
    this.contentId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : emailId = Value(emailId),
       position = Value(position),
       contentType = Value(contentType),
       size = Value(size),
       sha256 = Value(sha256);
  static Insertable<AttachmentRow> custom({
    Expression<String>? emailId,
    Expression<int>? position,
    Expression<String>? filename,
    Expression<String>? contentType,
    Expression<int>? size,
    Expression<String>? sha256,
    Expression<String>? contentId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (emailId != null) 'email_id': emailId,
      if (position != null) 'position': position,
      if (filename != null) 'filename': filename,
      if (contentType != null) 'content_type': contentType,
      if (size != null) 'size': size,
      if (sha256 != null) 'sha256': sha256,
      if (contentId != null) 'content_id': contentId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? emailId,
    Value<int>? position,
    Value<String?>? filename,
    Value<String>? contentType,
    Value<int>? size,
    Value<String>? sha256,
    Value<String?>? contentId,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      emailId: emailId ?? this.emailId,
      position: position ?? this.position,
      filename: filename ?? this.filename,
      contentType: contentType ?? this.contentType,
      size: size ?? this.size,
      sha256: sha256 ?? this.sha256,
      contentId: contentId ?? this.contentId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (emailId.present) {
      map['email_id'] = Variable<String>(emailId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (contentId.present) {
      map['content_id'] = Variable<String>(contentId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('emailId: $emailId, ')
          ..write('position: $position, ')
          ..write('filename: $filename, ')
          ..write('contentType: $contentType, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('contentId: $contentId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Labels extends Table with TableInfo<Labels, LabelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Labels(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _emailIdMeta = const VerificationMeta(
    'emailId',
  );
  late final GeneratedColumn<String> emailId = GeneratedColumn<String>(
    'email_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _labelEventIdMeta = const VerificationMeta(
    'labelEventId',
  );
  late final GeneratedColumn<String> labelEventId = GeneratedColumn<String>(
    'label_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _recipientPubkeyMeta = const VerificationMeta(
    'recipientPubkey',
  );
  late final GeneratedColumn<String> recipientPubkey = GeneratedColumn<String>(
    'recipient_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    emailId,
    label,
    labelEventId,
    timestamp,
    recipientPubkey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'labels';
  @override
  VerificationContext validateIntegrity(
    Insertable<LabelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('email_id')) {
      context.handle(
        _emailIdMeta,
        emailId.isAcceptableOrUnknown(data['email_id']!, _emailIdMeta),
      );
    } else if (isInserting) {
      context.missing(_emailIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('label_event_id')) {
      context.handle(
        _labelEventIdMeta,
        labelEventId.isAcceptableOrUnknown(
          data['label_event_id']!,
          _labelEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_labelEventIdMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('recipient_pubkey')) {
      context.handle(
        _recipientPubkeyMeta,
        recipientPubkey.isAcceptableOrUnknown(
          data['recipient_pubkey']!,
          _recipientPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientPubkeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {emailId, label};
  @override
  LabelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LabelRow(
      emailId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      labelEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label_event_id'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      recipientPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_pubkey'],
      )!,
    );
  }

  @override
  Labels createAlias(String alias) {
    return Labels(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(email_id, label)'];
  @override
  bool get dontWriteConstraints => true;
}

class LabelRow extends DataClass implements Insertable<LabelRow> {
  final String emailId;
  final String label;
  final String labelEventId;
  final int timestamp;
  final String recipientPubkey;
  const LabelRow({
    required this.emailId,
    required this.label,
    required this.labelEventId,
    required this.timestamp,
    required this.recipientPubkey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['email_id'] = Variable<String>(emailId);
    map['label'] = Variable<String>(label);
    map['label_event_id'] = Variable<String>(labelEventId);
    map['timestamp'] = Variable<int>(timestamp);
    map['recipient_pubkey'] = Variable<String>(recipientPubkey);
    return map;
  }

  LabelsCompanion toCompanion(bool nullToAbsent) {
    return LabelsCompanion(
      emailId: Value(emailId),
      label: Value(label),
      labelEventId: Value(labelEventId),
      timestamp: Value(timestamp),
      recipientPubkey: Value(recipientPubkey),
    );
  }

  factory LabelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LabelRow(
      emailId: serializer.fromJson<String>(json['email_id']),
      label: serializer.fromJson<String>(json['label']),
      labelEventId: serializer.fromJson<String>(json['label_event_id']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      recipientPubkey: serializer.fromJson<String>(json['recipient_pubkey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'email_id': serializer.toJson<String>(emailId),
      'label': serializer.toJson<String>(label),
      'label_event_id': serializer.toJson<String>(labelEventId),
      'timestamp': serializer.toJson<int>(timestamp),
      'recipient_pubkey': serializer.toJson<String>(recipientPubkey),
    };
  }

  LabelRow copyWith({
    String? emailId,
    String? label,
    String? labelEventId,
    int? timestamp,
    String? recipientPubkey,
  }) => LabelRow(
    emailId: emailId ?? this.emailId,
    label: label ?? this.label,
    labelEventId: labelEventId ?? this.labelEventId,
    timestamp: timestamp ?? this.timestamp,
    recipientPubkey: recipientPubkey ?? this.recipientPubkey,
  );
  LabelRow copyWithCompanion(LabelsCompanion data) {
    return LabelRow(
      emailId: data.emailId.present ? data.emailId.value : this.emailId,
      label: data.label.present ? data.label.value : this.label,
      labelEventId: data.labelEventId.present
          ? data.labelEventId.value
          : this.labelEventId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      recipientPubkey: data.recipientPubkey.present
          ? data.recipientPubkey.value
          : this.recipientPubkey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LabelRow(')
          ..write('emailId: $emailId, ')
          ..write('label: $label, ')
          ..write('labelEventId: $labelEventId, ')
          ..write('timestamp: $timestamp, ')
          ..write('recipientPubkey: $recipientPubkey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(emailId, label, labelEventId, timestamp, recipientPubkey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LabelRow &&
          other.emailId == this.emailId &&
          other.label == this.label &&
          other.labelEventId == this.labelEventId &&
          other.timestamp == this.timestamp &&
          other.recipientPubkey == this.recipientPubkey);
}

class LabelsCompanion extends UpdateCompanion<LabelRow> {
  final Value<String> emailId;
  final Value<String> label;
  final Value<String> labelEventId;
  final Value<int> timestamp;
  final Value<String> recipientPubkey;
  final Value<int> rowid;
  const LabelsCompanion({
    this.emailId = const Value.absent(),
    this.label = const Value.absent(),
    this.labelEventId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.recipientPubkey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LabelsCompanion.insert({
    required String emailId,
    required String label,
    required String labelEventId,
    required int timestamp,
    required String recipientPubkey,
    this.rowid = const Value.absent(),
  }) : emailId = Value(emailId),
       label = Value(label),
       labelEventId = Value(labelEventId),
       timestamp = Value(timestamp),
       recipientPubkey = Value(recipientPubkey);
  static Insertable<LabelRow> custom({
    Expression<String>? emailId,
    Expression<String>? label,
    Expression<String>? labelEventId,
    Expression<int>? timestamp,
    Expression<String>? recipientPubkey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (emailId != null) 'email_id': emailId,
      if (label != null) 'label': label,
      if (labelEventId != null) 'label_event_id': labelEventId,
      if (timestamp != null) 'timestamp': timestamp,
      if (recipientPubkey != null) 'recipient_pubkey': recipientPubkey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LabelsCompanion copyWith({
    Value<String>? emailId,
    Value<String>? label,
    Value<String>? labelEventId,
    Value<int>? timestamp,
    Value<String>? recipientPubkey,
    Value<int>? rowid,
  }) {
    return LabelsCompanion(
      emailId: emailId ?? this.emailId,
      label: label ?? this.label,
      labelEventId: labelEventId ?? this.labelEventId,
      timestamp: timestamp ?? this.timestamp,
      recipientPubkey: recipientPubkey ?? this.recipientPubkey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (emailId.present) {
      map['email_id'] = Variable<String>(emailId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (labelEventId.present) {
      map['label_event_id'] = Variable<String>(labelEventId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (recipientPubkey.present) {
      map['recipient_pubkey'] = Variable<String>(recipientPubkey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LabelsCompanion(')
          ..write('emailId: $emailId, ')
          ..write('label: $label, ')
          ..write('labelEventId: $labelEventId, ')
          ..write('timestamp: $timestamp, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GiftWraps extends Table with TableInfo<GiftWraps, GiftWrapRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GiftWraps(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _recipientPubkeyMeta = const VerificationMeta(
    'recipientPubkey',
  );
  late final GeneratedColumn<String> recipientPubkey = GeneratedColumn<String>(
    'recipient_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _eventMeta = const VerificationMeta('event');
  late final GeneratedColumn<String> event = GeneratedColumn<String>(
    'event',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sealMeta = const VerificationMeta('seal');
  late final GeneratedColumn<String> seal = GeneratedColumn<String>(
    'seal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _rumorMeta = const VerificationMeta('rumor');
  late final GeneratedColumn<String> rumor = GeneratedColumn<String>(
    'rumor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _rumorIdMeta = const VerificationMeta(
    'rumorId',
  );
  late final GeneratedColumn<String> rumorId = GeneratedColumn<String>(
    'rumor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _failureMeta = const VerificationMeta(
    'failure',
  );
  late final GeneratedColumn<String> failure = GeneratedColumn<String>(
    'failure',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recipientPubkey,
    event,
    seal,
    rumor,
    rumorId,
    stage,
    attempts,
    failure,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gift_wraps';
  @override
  VerificationContext validateIntegrity(
    Insertable<GiftWrapRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recipient_pubkey')) {
      context.handle(
        _recipientPubkeyMeta,
        recipientPubkey.isAcceptableOrUnknown(
          data['recipient_pubkey']!,
          _recipientPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientPubkeyMeta);
    }
    if (data.containsKey('event')) {
      context.handle(
        _eventMeta,
        event.isAcceptableOrUnknown(data['event']!, _eventMeta),
      );
    } else if (isInserting) {
      context.missing(_eventMeta);
    }
    if (data.containsKey('seal')) {
      context.handle(
        _sealMeta,
        seal.isAcceptableOrUnknown(data['seal']!, _sealMeta),
      );
    }
    if (data.containsKey('rumor')) {
      context.handle(
        _rumorMeta,
        rumor.isAcceptableOrUnknown(data['rumor']!, _rumorMeta),
      );
    }
    if (data.containsKey('rumor_id')) {
      context.handle(
        _rumorIdMeta,
        rumorId.isAcceptableOrUnknown(data['rumor_id']!, _rumorIdMeta),
      );
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('failure')) {
      context.handle(
        _failureMeta,
        failure.isAcceptableOrUnknown(data['failure']!, _failureMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GiftWrapRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GiftWrapRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recipientPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_pubkey'],
      )!,
      event: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event'],
      )!,
      seal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}seal'],
      ),
      rumor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rumor'],
      ),
      rumorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rumor_id'],
      ),
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      failure: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure'],
      ),
    );
  }

  @override
  GiftWraps createAlias(String alias) {
    return GiftWraps(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GiftWrapRow extends DataClass implements Insertable<GiftWrapRow> {
  final String id;
  final String recipientPubkey;
  final String event;
  final String? seal;
  final String? rumor;
  final String? rumorId;
  final String stage;
  final int attempts;
  final String? failure;
  const GiftWrapRow({
    required this.id,
    required this.recipientPubkey,
    required this.event,
    this.seal,
    this.rumor,
    this.rumorId,
    required this.stage,
    required this.attempts,
    this.failure,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recipient_pubkey'] = Variable<String>(recipientPubkey);
    map['event'] = Variable<String>(event);
    if (!nullToAbsent || seal != null) {
      map['seal'] = Variable<String>(seal);
    }
    if (!nullToAbsent || rumor != null) {
      map['rumor'] = Variable<String>(rumor);
    }
    if (!nullToAbsent || rumorId != null) {
      map['rumor_id'] = Variable<String>(rumorId);
    }
    map['stage'] = Variable<String>(stage);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || failure != null) {
      map['failure'] = Variable<String>(failure);
    }
    return map;
  }

  GiftWrapsCompanion toCompanion(bool nullToAbsent) {
    return GiftWrapsCompanion(
      id: Value(id),
      recipientPubkey: Value(recipientPubkey),
      event: Value(event),
      seal: seal == null && nullToAbsent ? const Value.absent() : Value(seal),
      rumor: rumor == null && nullToAbsent
          ? const Value.absent()
          : Value(rumor),
      rumorId: rumorId == null && nullToAbsent
          ? const Value.absent()
          : Value(rumorId),
      stage: Value(stage),
      attempts: Value(attempts),
      failure: failure == null && nullToAbsent
          ? const Value.absent()
          : Value(failure),
    );
  }

  factory GiftWrapRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GiftWrapRow(
      id: serializer.fromJson<String>(json['id']),
      recipientPubkey: serializer.fromJson<String>(json['recipient_pubkey']),
      event: serializer.fromJson<String>(json['event']),
      seal: serializer.fromJson<String?>(json['seal']),
      rumor: serializer.fromJson<String?>(json['rumor']),
      rumorId: serializer.fromJson<String?>(json['rumor_id']),
      stage: serializer.fromJson<String>(json['stage']),
      attempts: serializer.fromJson<int>(json['attempts']),
      failure: serializer.fromJson<String?>(json['failure']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recipient_pubkey': serializer.toJson<String>(recipientPubkey),
      'event': serializer.toJson<String>(event),
      'seal': serializer.toJson<String?>(seal),
      'rumor': serializer.toJson<String?>(rumor),
      'rumor_id': serializer.toJson<String?>(rumorId),
      'stage': serializer.toJson<String>(stage),
      'attempts': serializer.toJson<int>(attempts),
      'failure': serializer.toJson<String?>(failure),
    };
  }

  GiftWrapRow copyWith({
    String? id,
    String? recipientPubkey,
    String? event,
    Value<String?> seal = const Value.absent(),
    Value<String?> rumor = const Value.absent(),
    Value<String?> rumorId = const Value.absent(),
    String? stage,
    int? attempts,
    Value<String?> failure = const Value.absent(),
  }) => GiftWrapRow(
    id: id ?? this.id,
    recipientPubkey: recipientPubkey ?? this.recipientPubkey,
    event: event ?? this.event,
    seal: seal.present ? seal.value : this.seal,
    rumor: rumor.present ? rumor.value : this.rumor,
    rumorId: rumorId.present ? rumorId.value : this.rumorId,
    stage: stage ?? this.stage,
    attempts: attempts ?? this.attempts,
    failure: failure.present ? failure.value : this.failure,
  );
  GiftWrapRow copyWithCompanion(GiftWrapsCompanion data) {
    return GiftWrapRow(
      id: data.id.present ? data.id.value : this.id,
      recipientPubkey: data.recipientPubkey.present
          ? data.recipientPubkey.value
          : this.recipientPubkey,
      event: data.event.present ? data.event.value : this.event,
      seal: data.seal.present ? data.seal.value : this.seal,
      rumor: data.rumor.present ? data.rumor.value : this.rumor,
      rumorId: data.rumorId.present ? data.rumorId.value : this.rumorId,
      stage: data.stage.present ? data.stage.value : this.stage,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      failure: data.failure.present ? data.failure.value : this.failure,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GiftWrapRow(')
          ..write('id: $id, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('event: $event, ')
          ..write('seal: $seal, ')
          ..write('rumor: $rumor, ')
          ..write('rumorId: $rumorId, ')
          ..write('stage: $stage, ')
          ..write('attempts: $attempts, ')
          ..write('failure: $failure')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    recipientPubkey,
    event,
    seal,
    rumor,
    rumorId,
    stage,
    attempts,
    failure,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GiftWrapRow &&
          other.id == this.id &&
          other.recipientPubkey == this.recipientPubkey &&
          other.event == this.event &&
          other.seal == this.seal &&
          other.rumor == this.rumor &&
          other.rumorId == this.rumorId &&
          other.stage == this.stage &&
          other.attempts == this.attempts &&
          other.failure == this.failure);
}

class GiftWrapsCompanion extends UpdateCompanion<GiftWrapRow> {
  final Value<String> id;
  final Value<String> recipientPubkey;
  final Value<String> event;
  final Value<String?> seal;
  final Value<String?> rumor;
  final Value<String?> rumorId;
  final Value<String> stage;
  final Value<int> attempts;
  final Value<String?> failure;
  final Value<int> rowid;
  const GiftWrapsCompanion({
    this.id = const Value.absent(),
    this.recipientPubkey = const Value.absent(),
    this.event = const Value.absent(),
    this.seal = const Value.absent(),
    this.rumor = const Value.absent(),
    this.rumorId = const Value.absent(),
    this.stage = const Value.absent(),
    this.attempts = const Value.absent(),
    this.failure = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GiftWrapsCompanion.insert({
    required String id,
    required String recipientPubkey,
    required String event,
    this.seal = const Value.absent(),
    this.rumor = const Value.absent(),
    this.rumorId = const Value.absent(),
    required String stage,
    this.attempts = const Value.absent(),
    this.failure = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recipientPubkey = Value(recipientPubkey),
       event = Value(event),
       stage = Value(stage);
  static Insertable<GiftWrapRow> custom({
    Expression<String>? id,
    Expression<String>? recipientPubkey,
    Expression<String>? event,
    Expression<String>? seal,
    Expression<String>? rumor,
    Expression<String>? rumorId,
    Expression<String>? stage,
    Expression<int>? attempts,
    Expression<String>? failure,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recipientPubkey != null) 'recipient_pubkey': recipientPubkey,
      if (event != null) 'event': event,
      if (seal != null) 'seal': seal,
      if (rumor != null) 'rumor': rumor,
      if (rumorId != null) 'rumor_id': rumorId,
      if (stage != null) 'stage': stage,
      if (attempts != null) 'attempts': attempts,
      if (failure != null) 'failure': failure,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GiftWrapsCompanion copyWith({
    Value<String>? id,
    Value<String>? recipientPubkey,
    Value<String>? event,
    Value<String?>? seal,
    Value<String?>? rumor,
    Value<String?>? rumorId,
    Value<String>? stage,
    Value<int>? attempts,
    Value<String?>? failure,
    Value<int>? rowid,
  }) {
    return GiftWrapsCompanion(
      id: id ?? this.id,
      recipientPubkey: recipientPubkey ?? this.recipientPubkey,
      event: event ?? this.event,
      seal: seal ?? this.seal,
      rumor: rumor ?? this.rumor,
      rumorId: rumorId ?? this.rumorId,
      stage: stage ?? this.stage,
      attempts: attempts ?? this.attempts,
      failure: failure ?? this.failure,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recipientPubkey.present) {
      map['recipient_pubkey'] = Variable<String>(recipientPubkey.value);
    }
    if (event.present) {
      map['event'] = Variable<String>(event.value);
    }
    if (seal.present) {
      map['seal'] = Variable<String>(seal.value);
    }
    if (rumor.present) {
      map['rumor'] = Variable<String>(rumor.value);
    }
    if (rumorId.present) {
      map['rumor_id'] = Variable<String>(rumorId.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (failure.present) {
      map['failure'] = Variable<String>(failure.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GiftWrapsCompanion(')
          ..write('id: $id, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('event: $event, ')
          ..write('seal: $seal, ')
          ..write('rumor: $rumor, ')
          ..write('rumorId: $rumorId, ')
          ..write('stage: $stage, ')
          ..write('attempts: $attempts, ')
          ..write('failure: $failure, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Tombstones extends Table with TableInfo<Tombstones, TombstoneRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Tombstones(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _recipientPubkeyMeta = const VerificationMeta(
    'recipientPubkey',
  );
  late final GeneratedColumn<String> recipientPubkey = GeneratedColumn<String>(
    'recipient_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [eventId, recipientPubkey, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<TombstoneRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('recipient_pubkey')) {
      context.handle(
        _recipientPubkeyMeta,
        recipientPubkey.isAcceptableOrUnknown(
          data['recipient_pubkey']!,
          _recipientPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientPubkeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  TombstoneRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TombstoneRow(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      recipientPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_pubkey'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  Tombstones createAlias(String alias) {
    return Tombstones(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class TombstoneRow extends DataClass implements Insertable<TombstoneRow> {
  final String eventId;
  final String recipientPubkey;
  final int createdAt;
  const TombstoneRow({
    required this.eventId,
    required this.recipientPubkey,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['recipient_pubkey'] = Variable<String>(recipientPubkey);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TombstonesCompanion toCompanion(bool nullToAbsent) {
    return TombstonesCompanion(
      eventId: Value(eventId),
      recipientPubkey: Value(recipientPubkey),
      createdAt: Value(createdAt),
    );
  }

  factory TombstoneRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TombstoneRow(
      eventId: serializer.fromJson<String>(json['event_id']),
      recipientPubkey: serializer.fromJson<String>(json['recipient_pubkey']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'event_id': serializer.toJson<String>(eventId),
      'recipient_pubkey': serializer.toJson<String>(recipientPubkey),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  TombstoneRow copyWith({
    String? eventId,
    String? recipientPubkey,
    int? createdAt,
  }) => TombstoneRow(
    eventId: eventId ?? this.eventId,
    recipientPubkey: recipientPubkey ?? this.recipientPubkey,
    createdAt: createdAt ?? this.createdAt,
  );
  TombstoneRow copyWithCompanion(TombstonesCompanion data) {
    return TombstoneRow(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      recipientPubkey: data.recipientPubkey.present
          ? data.recipientPubkey.value
          : this.recipientPubkey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TombstoneRow(')
          ..write('eventId: $eventId, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(eventId, recipientPubkey, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TombstoneRow &&
          other.eventId == this.eventId &&
          other.recipientPubkey == this.recipientPubkey &&
          other.createdAt == this.createdAt);
}

class TombstonesCompanion extends UpdateCompanion<TombstoneRow> {
  final Value<String> eventId;
  final Value<String> recipientPubkey;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TombstonesCompanion({
    this.eventId = const Value.absent(),
    this.recipientPubkey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TombstonesCompanion.insert({
    required String eventId,
    required String recipientPubkey,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       recipientPubkey = Value(recipientPubkey),
       createdAt = Value(createdAt);
  static Insertable<TombstoneRow> custom({
    Expression<String>? eventId,
    Expression<String>? recipientPubkey,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (recipientPubkey != null) 'recipient_pubkey': recipientPubkey,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TombstonesCompanion copyWith({
    Value<String>? eventId,
    Value<String>? recipientPubkey,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return TombstonesCompanion(
      eventId: eventId ?? this.eventId,
      recipientPubkey: recipientPubkey ?? this.recipientPubkey,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (recipientPubkey.present) {
      map['recipient_pubkey'] = Variable<String>(recipientPubkey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TombstonesCompanion(')
          ..write('eventId: $eventId, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Settings extends Table with TableInfo<Settings, SettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [pubkey, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pubkey};
  @override
  SettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsRow(
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class SettingsRow extends DataClass implements Insertable<SettingsRow> {
  final String pubkey;
  final String json;
  const SettingsRow({required this.pubkey, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pubkey'] = Variable<String>(pubkey);
    map['json'] = Variable<String>(json);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(pubkey: Value(pubkey), json: Value(json));
  }

  factory SettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsRow(
      pubkey: serializer.fromJson<String>(json['pubkey']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pubkey': serializer.toJson<String>(pubkey),
      'json': serializer.toJson<String>(json),
    };
  }

  SettingsRow copyWith({String? pubkey, String? json}) =>
      SettingsRow(pubkey: pubkey ?? this.pubkey, json: json ?? this.json);
  SettingsRow copyWithCompanion(SettingsCompanion data) {
    return SettingsRow(
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('pubkey: $pubkey, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pubkey, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.pubkey == this.pubkey &&
          other.json == this.json);
}

class SettingsCompanion extends UpdateCompanion<SettingsRow> {
  final Value<String> pubkey;
  final Value<String> json;
  final Value<int> rowid;
  const SettingsCompanion({
    this.pubkey = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String pubkey,
    required String json,
    this.rowid = const Value.absent(),
  }) : pubkey = Value(pubkey),
       json = Value(json);
  static Insertable<SettingsRow> custom({
    Expression<String>? pubkey,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pubkey != null) 'pubkey': pubkey,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? pubkey,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      pubkey: pubkey ?? this.pubkey,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('pubkey: $pubkey, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class EmailState extends DataClass {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final bool isPublic;
  final bool isBridged;
  final String lightMimeText;
  final String? blossomHash;
  final String? decryptionKey;
  final String? decryptionNonce;
  final int createdAt;
  final int date;
  final String fromAddress;
  final String subject;
  final String bodyPlain;
  final String folder;
  final bool isRead;
  final bool isStarred;
  const EmailState({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.isPublic,
    required this.isBridged,
    required this.lightMimeText,
    this.blossomHash,
    this.decryptionKey,
    this.decryptionNonce,
    required this.createdAt,
    required this.date,
    required this.fromAddress,
    required this.subject,
    required this.bodyPlain,
    required this.folder,
    required this.isRead,
    required this.isStarred,
  });
  factory EmailState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmailState(
      id: serializer.fromJson<String>(json['id']),
      senderPubkey: serializer.fromJson<String>(json['sender_pubkey']),
      recipientPubkey: serializer.fromJson<String>(json['recipient_pubkey']),
      isPublic: serializer.fromJson<bool>(json['is_public']),
      isBridged: serializer.fromJson<bool>(json['is_bridged']),
      lightMimeText: serializer.fromJson<String>(json['light_mime_text']),
      blossomHash: serializer.fromJson<String?>(json['blossom_hash']),
      decryptionKey: serializer.fromJson<String?>(json['decryption_key']),
      decryptionNonce: serializer.fromJson<String?>(json['decryption_nonce']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      date: serializer.fromJson<int>(json['date']),
      fromAddress: serializer.fromJson<String>(json['from_address']),
      subject: serializer.fromJson<String>(json['subject']),
      bodyPlain: serializer.fromJson<String>(json['body_plain']),
      folder: serializer.fromJson<String>(json['folder']),
      isRead: serializer.fromJson<bool>(json['is_read']),
      isStarred: serializer.fromJson<bool>(json['is_starred']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sender_pubkey': serializer.toJson<String>(senderPubkey),
      'recipient_pubkey': serializer.toJson<String>(recipientPubkey),
      'is_public': serializer.toJson<bool>(isPublic),
      'is_bridged': serializer.toJson<bool>(isBridged),
      'light_mime_text': serializer.toJson<String>(lightMimeText),
      'blossom_hash': serializer.toJson<String?>(blossomHash),
      'decryption_key': serializer.toJson<String?>(decryptionKey),
      'decryption_nonce': serializer.toJson<String?>(decryptionNonce),
      'created_at': serializer.toJson<int>(createdAt),
      'date': serializer.toJson<int>(date),
      'from_address': serializer.toJson<String>(fromAddress),
      'subject': serializer.toJson<String>(subject),
      'body_plain': serializer.toJson<String>(bodyPlain),
      'folder': serializer.toJson<String>(folder),
      'is_read': serializer.toJson<bool>(isRead),
      'is_starred': serializer.toJson<bool>(isStarred),
    };
  }

  EmailState copyWith({
    String? id,
    String? senderPubkey,
    String? recipientPubkey,
    bool? isPublic,
    bool? isBridged,
    String? lightMimeText,
    Value<String?> blossomHash = const Value.absent(),
    Value<String?> decryptionKey = const Value.absent(),
    Value<String?> decryptionNonce = const Value.absent(),
    int? createdAt,
    int? date,
    String? fromAddress,
    String? subject,
    String? bodyPlain,
    String? folder,
    bool? isRead,
    bool? isStarred,
  }) => EmailState(
    id: id ?? this.id,
    senderPubkey: senderPubkey ?? this.senderPubkey,
    recipientPubkey: recipientPubkey ?? this.recipientPubkey,
    isPublic: isPublic ?? this.isPublic,
    isBridged: isBridged ?? this.isBridged,
    lightMimeText: lightMimeText ?? this.lightMimeText,
    blossomHash: blossomHash.present ? blossomHash.value : this.blossomHash,
    decryptionKey: decryptionKey.present
        ? decryptionKey.value
        : this.decryptionKey,
    decryptionNonce: decryptionNonce.present
        ? decryptionNonce.value
        : this.decryptionNonce,
    createdAt: createdAt ?? this.createdAt,
    date: date ?? this.date,
    fromAddress: fromAddress ?? this.fromAddress,
    subject: subject ?? this.subject,
    bodyPlain: bodyPlain ?? this.bodyPlain,
    folder: folder ?? this.folder,
    isRead: isRead ?? this.isRead,
    isStarred: isStarred ?? this.isStarred,
  );
  @override
  String toString() {
    return (StringBuffer('EmailState(')
          ..write('id: $id, ')
          ..write('senderPubkey: $senderPubkey, ')
          ..write('recipientPubkey: $recipientPubkey, ')
          ..write('isPublic: $isPublic, ')
          ..write('isBridged: $isBridged, ')
          ..write('lightMimeText: $lightMimeText, ')
          ..write('blossomHash: $blossomHash, ')
          ..write('decryptionKey: $decryptionKey, ')
          ..write('decryptionNonce: $decryptionNonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('date: $date, ')
          ..write('fromAddress: $fromAddress, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('folder: $folder, ')
          ..write('isRead: $isRead, ')
          ..write('isStarred: $isStarred')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    senderPubkey,
    recipientPubkey,
    isPublic,
    isBridged,
    lightMimeText,
    blossomHash,
    decryptionKey,
    decryptionNonce,
    createdAt,
    date,
    fromAddress,
    subject,
    bodyPlain,
    folder,
    isRead,
    isStarred,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmailState &&
          other.id == this.id &&
          other.senderPubkey == this.senderPubkey &&
          other.recipientPubkey == this.recipientPubkey &&
          other.isPublic == this.isPublic &&
          other.isBridged == this.isBridged &&
          other.lightMimeText == this.lightMimeText &&
          other.blossomHash == this.blossomHash &&
          other.decryptionKey == this.decryptionKey &&
          other.decryptionNonce == this.decryptionNonce &&
          other.createdAt == this.createdAt &&
          other.date == this.date &&
          other.fromAddress == this.fromAddress &&
          other.subject == this.subject &&
          other.bodyPlain == this.bodyPlain &&
          other.folder == this.folder &&
          other.isRead == this.isRead &&
          other.isStarred == this.isStarred);
}

class EmailStates extends ViewInfo<EmailStates, EmailState>
    implements HasResultSet {
  final String? _alias;
  @override
  final _$NostrMailDatabase attachedDatabase;
  EmailStates(this.attachedDatabase, [this._alias]);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    senderPubkey,
    recipientPubkey,
    isPublic,
    isBridged,
    lightMimeText,
    blossomHash,
    decryptionKey,
    decryptionNonce,
    createdAt,
    date,
    fromAddress,
    subject,
    bodyPlain,
    folder,
    isRead,
    isStarred,
  ];
  @override
  String get aliasedName => _alias ?? entityName;
  @override
  String get entityName => 'email_states';
  @override
  Map<SqlDialect, String> get createViewStatements => {
    SqlDialect.sqlite:
        'CREATE VIEW email_states AS SELECT e.*, COALESCE((SELECT substr(l.label, 8) FROM labels AS l WHERE l.email_id = e.id AND l.recipient_pubkey = e.recipient_pubkey AND l.label LIKE \'folder:%\' ORDER BY l.timestamp DESC LIMIT 1), CASE WHEN e.sender_pubkey = e.recipient_pubkey THEN \'sent\' ELSE \'inbox\' END) AS folder, EXISTS (SELECT 1 FROM labels AS l WHERE l.email_id = e.id AND l.recipient_pubkey = e.recipient_pubkey AND l.label = \'state:read\') AS is_read, EXISTS (SELECT 1 FROM labels AS l WHERE l.email_id = e.id AND l.recipient_pubkey = e.recipient_pubkey AND l.label = \'flag:starred\') AS is_starred FROM emails AS e',
  };
  @override
  EmailStates get asDslTable => this;
  @override
  EmailState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmailState(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      senderPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_pubkey'],
      )!,
      recipientPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_pubkey'],
      )!,
      isPublic: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_public'],
      )!,
      isBridged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_bridged'],
      )!,
      lightMimeText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}light_mime_text'],
      )!,
      blossomHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blossom_hash'],
      ),
      decryptionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decryption_key'],
      ),
      decryptionNonce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decryption_nonce'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      fromAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_address'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      bodyPlain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_plain'],
      )!,
      folder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder'],
      )!,
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      isStarred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_starred'],
      )!,
    );
  }

  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> senderPubkey = GeneratedColumn<String>(
    'sender_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> recipientPubkey = GeneratedColumn<String>(
    'recipient_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<bool> isPublic = GeneratedColumn<bool>(
    'is_public',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_public" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<bool> isBridged = GeneratedColumn<bool>(
    'is_bridged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_bridged" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<String> lightMimeText = GeneratedColumn<String>(
    'light_mime_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> blossomHash = GeneratedColumn<String>(
    'blossom_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> decryptionKey = GeneratedColumn<String>(
    'decryption_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> decryptionNonce = GeneratedColumn<String>(
    'decryption_nonce',
    aliasedName,
    true,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
  );
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
  );
  late final GeneratedColumn<String> fromAddress = GeneratedColumn<String>(
    'from_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> bodyPlain = GeneratedColumn<String>(
    'body_plain',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<String> folder = GeneratedColumn<String>(
    'folder',
    aliasedName,
    false,
    type: DriftSqlType.string,
  );
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
  );
  late final GeneratedColumn<bool> isStarred = GeneratedColumn<bool>(
    'is_starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_starred" IN (0, 1))',
    ),
  );
  @override
  EmailStates createAlias(String alias) {
    return EmailStates(attachedDatabase, alias);
  }

  @override
  Query? get query => null;
  @override
  Set<String> get readTables => const {'emails', 'labels'};
}

class EmailSearch extends Table
    with
        TableInfo<EmailSearch, EmailSearchData>,
        VirtualTableInfo<EmailSearch, EmailSearchData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EmailSearch(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fromAddressMeta = const VerificationMeta(
    'fromAddress',
  );
  late final GeneratedColumn<String> fromAddress = GeneratedColumn<String>(
    'from_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _bodyPlainMeta = const VerificationMeta(
    'bodyPlain',
  );
  late final GeneratedColumn<String> bodyPlain = GeneratedColumn<String>(
    'body_plain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [fromAddress, subject, bodyPlain];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'email_search';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmailSearchData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('from_address')) {
      context.handle(
        _fromAddressMeta,
        fromAddress.isAcceptableOrUnknown(
          data['from_address']!,
          _fromAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromAddressMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('body_plain')) {
      context.handle(
        _bodyPlainMeta,
        bodyPlain.isAcceptableOrUnknown(data['body_plain']!, _bodyPlainMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyPlainMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  EmailSearchData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmailSearchData(
      fromAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_address'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      bodyPlain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_plain'],
      )!,
    );
  }

  @override
  EmailSearch createAlias(String alias) {
    return EmailSearch(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(from_address, subject, body_plain, content=\'emails\', content_rowid=\'rowid\', tokenize=\'unicode61\')';
}

class EmailSearchData extends DataClass implements Insertable<EmailSearchData> {
  final String fromAddress;
  final String subject;
  final String bodyPlain;
  const EmailSearchData({
    required this.fromAddress,
    required this.subject,
    required this.bodyPlain,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['from_address'] = Variable<String>(fromAddress);
    map['subject'] = Variable<String>(subject);
    map['body_plain'] = Variable<String>(bodyPlain);
    return map;
  }

  EmailSearchCompanion toCompanion(bool nullToAbsent) {
    return EmailSearchCompanion(
      fromAddress: Value(fromAddress),
      subject: Value(subject),
      bodyPlain: Value(bodyPlain),
    );
  }

  factory EmailSearchData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmailSearchData(
      fromAddress: serializer.fromJson<String>(json['from_address']),
      subject: serializer.fromJson<String>(json['subject']),
      bodyPlain: serializer.fromJson<String>(json['body_plain']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'from_address': serializer.toJson<String>(fromAddress),
      'subject': serializer.toJson<String>(subject),
      'body_plain': serializer.toJson<String>(bodyPlain),
    };
  }

  EmailSearchData copyWith({
    String? fromAddress,
    String? subject,
    String? bodyPlain,
  }) => EmailSearchData(
    fromAddress: fromAddress ?? this.fromAddress,
    subject: subject ?? this.subject,
    bodyPlain: bodyPlain ?? this.bodyPlain,
  );
  EmailSearchData copyWithCompanion(EmailSearchCompanion data) {
    return EmailSearchData(
      fromAddress: data.fromAddress.present
          ? data.fromAddress.value
          : this.fromAddress,
      subject: data.subject.present ? data.subject.value : this.subject,
      bodyPlain: data.bodyPlain.present ? data.bodyPlain.value : this.bodyPlain,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmailSearchData(')
          ..write('fromAddress: $fromAddress, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fromAddress, subject, bodyPlain);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmailSearchData &&
          other.fromAddress == this.fromAddress &&
          other.subject == this.subject &&
          other.bodyPlain == this.bodyPlain);
}

class EmailSearchCompanion extends UpdateCompanion<EmailSearchData> {
  final Value<String> fromAddress;
  final Value<String> subject;
  final Value<String> bodyPlain;
  final Value<int> rowid;
  const EmailSearchCompanion({
    this.fromAddress = const Value.absent(),
    this.subject = const Value.absent(),
    this.bodyPlain = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmailSearchCompanion.insert({
    required String fromAddress,
    required String subject,
    required String bodyPlain,
    this.rowid = const Value.absent(),
  }) : fromAddress = Value(fromAddress),
       subject = Value(subject),
       bodyPlain = Value(bodyPlain);
  static Insertable<EmailSearchData> custom({
    Expression<String>? fromAddress,
    Expression<String>? subject,
    Expression<String>? bodyPlain,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fromAddress != null) 'from_address': fromAddress,
      if (subject != null) 'subject': subject,
      if (bodyPlain != null) 'body_plain': bodyPlain,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmailSearchCompanion copyWith({
    Value<String>? fromAddress,
    Value<String>? subject,
    Value<String>? bodyPlain,
    Value<int>? rowid,
  }) {
    return EmailSearchCompanion(
      fromAddress: fromAddress ?? this.fromAddress,
      subject: subject ?? this.subject,
      bodyPlain: bodyPlain ?? this.bodyPlain,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fromAddress.present) {
      map['from_address'] = Variable<String>(fromAddress.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (bodyPlain.present) {
      map['body_plain'] = Variable<String>(bodyPlain.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmailSearchCompanion(')
          ..write('fromAddress: $fromAddress, ')
          ..write('subject: $subject, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$NostrMailDatabase extends GeneratedDatabase {
  _$NostrMailDatabase(QueryExecutor e) : super(e);
  $NostrMailDatabaseManager get managers => $NostrMailDatabaseManager(this);
  late final Emails emails = Emails(this);
  late final Index emailsRecipientDate = Index(
    'emails_recipient_date',
    'CREATE INDEX emails_recipient_date ON emails (recipient_pubkey, date)',
  );
  late final Attachments attachments = Attachments(this);
  late final Labels labels = Labels(this);
  late final Index labelsRecipientLabel = Index(
    'labels_recipient_label',
    'CREATE INDEX labels_recipient_label ON labels (recipient_pubkey, label)',
  );
  late final GiftWraps giftWraps = GiftWraps(this);
  late final Index giftWrapsRumorId = Index(
    'gift_wraps_rumor_id',
    'CREATE INDEX gift_wraps_rumor_id ON gift_wraps (rumor_id)',
  );
  late final Index giftWrapsRecipientStage = Index(
    'gift_wraps_recipient_stage',
    'CREATE INDEX gift_wraps_recipient_stage ON gift_wraps (recipient_pubkey, stage)',
  );
  late final Tombstones tombstones = Tombstones(this);
  late final Settings settings = Settings(this);
  late final EmailStates emailStates = EmailStates(this);
  late final EmailSearch emailSearch = EmailSearch(this);
  late final Trigger emailsAi = Trigger(
    'CREATE TRIGGER emails_ai AFTER INSERT ON emails BEGIN INSERT INTO email_search ("rowid", from_address, subject, body_plain) VALUES (new."rowid", new.from_address, new.subject, new.body_plain);END',
    'emails_ai',
  );
  late final Trigger emailsAd = Trigger(
    'CREATE TRIGGER emails_ad AFTER DELETE ON emails BEGIN INSERT INTO email_search (email_search, "rowid", from_address, subject, body_plain) VALUES (\'delete\', old."rowid", old.from_address, old.subject, old.body_plain);END',
    'emails_ad',
  );
  late final Trigger emailsAu = Trigger(
    'CREATE TRIGGER emails_au AFTER UPDATE ON emails BEGIN INSERT INTO email_search (email_search, "rowid", from_address, subject, body_plain) VALUES (\'delete\', old."rowid", old.from_address, old.subject, old.body_plain);INSERT INTO email_search ("rowid", from_address, subject, body_plain) VALUES (new."rowid", new.from_address, new.subject, new.body_plain);END',
    'emails_au',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    emails,
    emailsRecipientDate,
    attachments,
    labels,
    labelsRecipientLabel,
    giftWraps,
    giftWrapsRumorId,
    giftWrapsRecipientStage,
    tombstones,
    settings,
    emailStates,
    emailSearch,
    emailsAi,
    emailsAd,
    emailsAu,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'emails',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('attachments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'emails',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('email_search', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'emails',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('email_search', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'emails',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('email_search', kind: UpdateKind.insert)],
    ),
  ]);
}

typedef $EmailsCreateCompanionBuilder =
    EmailsCompanion Function({
      required String id,
      required String senderPubkey,
      required String recipientPubkey,
      required bool isPublic,
      required bool isBridged,
      required String lightMimeText,
      Value<String?> blossomHash,
      Value<String?> decryptionKey,
      Value<String?> decryptionNonce,
      required int createdAt,
      required int date,
      required String fromAddress,
      required String subject,
      required String bodyPlain,
      Value<int> rowid,
    });
typedef $EmailsUpdateCompanionBuilder =
    EmailsCompanion Function({
      Value<String> id,
      Value<String> senderPubkey,
      Value<String> recipientPubkey,
      Value<bool> isPublic,
      Value<bool> isBridged,
      Value<String> lightMimeText,
      Value<String?> blossomHash,
      Value<String?> decryptionKey,
      Value<String?> decryptionNonce,
      Value<int> createdAt,
      Value<int> date,
      Value<String> fromAddress,
      Value<String> subject,
      Value<String> bodyPlain,
      Value<int> rowid,
    });

final class $EmailsReferences
    extends BaseReferences<_$NostrMailDatabase, Emails, EmailRow> {
  $EmailsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Attachments, List<AttachmentRow>>
  _attachmentsRefsTable(_$NostrMailDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.attachments,
        aliasName: 'emails__id__attachments__email_id',
      );

  $AttachmentsProcessedTableManager get attachmentsRefs {
    final manager = $AttachmentsTableManager(
      $_db,
      $_db.attachments,
    ).filter((f) => f.emailId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_attachmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $EmailsFilterComposer extends Composer<_$NostrMailDatabase, Emails> {
  $EmailsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderPubkey => $composableBuilder(
    column: $table.senderPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPublic => $composableBuilder(
    column: $table.isPublic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBridged => $composableBuilder(
    column: $table.isBridged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lightMimeText => $composableBuilder(
    column: $table.lightMimeText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blossomHash => $composableBuilder(
    column: $table.blossomHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decryptionKey => $composableBuilder(
    column: $table.decryptionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decryptionNonce => $composableBuilder(
    column: $table.decryptionNonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromAddress => $composableBuilder(
    column: $table.fromAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> attachmentsRefs(
    Expression<bool> Function($AttachmentsFilterComposer f) f,
  ) {
    final $AttachmentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.emailId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AttachmentsFilterComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $EmailsOrderingComposer extends Composer<_$NostrMailDatabase, Emails> {
  $EmailsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderPubkey => $composableBuilder(
    column: $table.senderPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPublic => $composableBuilder(
    column: $table.isPublic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBridged => $composableBuilder(
    column: $table.isBridged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lightMimeText => $composableBuilder(
    column: $table.lightMimeText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blossomHash => $composableBuilder(
    column: $table.blossomHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decryptionKey => $composableBuilder(
    column: $table.decryptionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decryptionNonce => $composableBuilder(
    column: $table.decryptionNonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromAddress => $composableBuilder(
    column: $table.fromAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnOrderings(column),
  );
}

class $EmailsAnnotationComposer extends Composer<_$NostrMailDatabase, Emails> {
  $EmailsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get senderPubkey => $composableBuilder(
    column: $table.senderPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPublic =>
      $composableBuilder(column: $table.isPublic, builder: (column) => column);

  GeneratedColumn<bool> get isBridged =>
      $composableBuilder(column: $table.isBridged, builder: (column) => column);

  GeneratedColumn<String> get lightMimeText => $composableBuilder(
    column: $table.lightMimeText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blossomHash => $composableBuilder(
    column: $table.blossomHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get decryptionKey => $composableBuilder(
    column: $table.decryptionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get decryptionNonce => $composableBuilder(
    column: $table.decryptionNonce,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get fromAddress => $composableBuilder(
    column: $table.fromAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get bodyPlain =>
      $composableBuilder(column: $table.bodyPlain, builder: (column) => column);

  Expression<T> attachmentsRefs<T extends Object>(
    Expression<T> Function($AttachmentsAnnotationComposer a) f,
  ) {
    final $AttachmentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.emailId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AttachmentsAnnotationComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $EmailsTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          Emails,
          EmailRow,
          $EmailsFilterComposer,
          $EmailsOrderingComposer,
          $EmailsAnnotationComposer,
          $EmailsCreateCompanionBuilder,
          $EmailsUpdateCompanionBuilder,
          (EmailRow, $EmailsReferences),
          EmailRow,
          PrefetchHooks Function({bool attachmentsRefs})
        > {
  $EmailsTableManager(_$NostrMailDatabase db, Emails table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $EmailsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $EmailsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $EmailsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> senderPubkey = const Value.absent(),
                Value<String> recipientPubkey = const Value.absent(),
                Value<bool> isPublic = const Value.absent(),
                Value<bool> isBridged = const Value.absent(),
                Value<String> lightMimeText = const Value.absent(),
                Value<String?> blossomHash = const Value.absent(),
                Value<String?> decryptionKey = const Value.absent(),
                Value<String?> decryptionNonce = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> date = const Value.absent(),
                Value<String> fromAddress = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> bodyPlain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmailsCompanion(
                id: id,
                senderPubkey: senderPubkey,
                recipientPubkey: recipientPubkey,
                isPublic: isPublic,
                isBridged: isBridged,
                lightMimeText: lightMimeText,
                blossomHash: blossomHash,
                decryptionKey: decryptionKey,
                decryptionNonce: decryptionNonce,
                createdAt: createdAt,
                date: date,
                fromAddress: fromAddress,
                subject: subject,
                bodyPlain: bodyPlain,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String senderPubkey,
                required String recipientPubkey,
                required bool isPublic,
                required bool isBridged,
                required String lightMimeText,
                Value<String?> blossomHash = const Value.absent(),
                Value<String?> decryptionKey = const Value.absent(),
                Value<String?> decryptionNonce = const Value.absent(),
                required int createdAt,
                required int date,
                required String fromAddress,
                required String subject,
                required String bodyPlain,
                Value<int> rowid = const Value.absent(),
              }) => EmailsCompanion.insert(
                id: id,
                senderPubkey: senderPubkey,
                recipientPubkey: recipientPubkey,
                isPublic: isPublic,
                isBridged: isBridged,
                lightMimeText: lightMimeText,
                blossomHash: blossomHash,
                decryptionKey: decryptionKey,
                decryptionNonce: decryptionNonce,
                createdAt: createdAt,
                date: date,
                fromAddress: fromAddress,
                subject: subject,
                bodyPlain: bodyPlain,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Emails, EmailRow>(table),
                  $EmailsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({attachmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (attachmentsRefs) db.attachments],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (attachmentsRefs)
                    await $_getPrefetchedData<EmailRow, Emails, AttachmentRow>(
                      currentTable: table,
                      referencedTable: $EmailsReferences._attachmentsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $EmailsReferences(db, table, p0).attachmentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.emailId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $EmailsProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      Emails,
      EmailRow,
      $EmailsFilterComposer,
      $EmailsOrderingComposer,
      $EmailsAnnotationComposer,
      $EmailsCreateCompanionBuilder,
      $EmailsUpdateCompanionBuilder,
      (EmailRow, $EmailsReferences),
      EmailRow,
      PrefetchHooks Function({bool attachmentsRefs})
    >;
typedef $AttachmentsCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String emailId,
      required int position,
      Value<String?> filename,
      required String contentType,
      required int size,
      required String sha256,
      Value<String?> contentId,
      Value<int> rowid,
    });
typedef $AttachmentsUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> emailId,
      Value<int> position,
      Value<String?> filename,
      Value<String> contentType,
      Value<int> size,
      Value<String> sha256,
      Value<String?> contentId,
      Value<int> rowid,
    });

final class $AttachmentsReferences
    extends BaseReferences<_$NostrMailDatabase, Attachments, AttachmentRow> {
  $AttachmentsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Emails _emailIdTable(_$NostrMailDatabase db) =>
      db.emails.createAlias('attachments__email_id__emails__id');

  $EmailsProcessedTableManager get emailId {
    final $_column = $_itemColumn<String>('email_id')!;

    final manager = $EmailsTableManager(
      $_db,
      $_db.emails,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_emailIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $AttachmentsFilterComposer
    extends Composer<_$NostrMailDatabase, Attachments> {
  $AttachmentsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnFilters(column),
  );

  $EmailsFilterComposer get emailId {
    final $EmailsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.emailId,
      referencedTable: $db.emails,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $EmailsFilterComposer(
            $db: $db,
            $table: $db.emails,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $AttachmentsOrderingComposer
    extends Composer<_$NostrMailDatabase, Attachments> {
  $AttachmentsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnOrderings(column),
  );

  $EmailsOrderingComposer get emailId {
    final $EmailsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.emailId,
      referencedTable: $db.emails,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $EmailsOrderingComposer(
            $db: $db,
            $table: $db.emails,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $AttachmentsAnnotationComposer
    extends Composer<_$NostrMailDatabase, Attachments> {
  $AttachmentsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get contentId =>
      $composableBuilder(column: $table.contentId, builder: (column) => column);

  $EmailsAnnotationComposer get emailId {
    final $EmailsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.emailId,
      referencedTable: $db.emails,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $EmailsAnnotationComposer(
            $db: $db,
            $table: $db.emails,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $AttachmentsTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          Attachments,
          AttachmentRow,
          $AttachmentsFilterComposer,
          $AttachmentsOrderingComposer,
          $AttachmentsAnnotationComposer,
          $AttachmentsCreateCompanionBuilder,
          $AttachmentsUpdateCompanionBuilder,
          (AttachmentRow, $AttachmentsReferences),
          AttachmentRow,
          PrefetchHooks Function({bool emailId})
        > {
  $AttachmentsTableManager(_$NostrMailDatabase db, Attachments table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $AttachmentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $AttachmentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $AttachmentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> emailId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String?> contentId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                emailId: emailId,
                position: position,
                filename: filename,
                contentType: contentType,
                size: size,
                sha256: sha256,
                contentId: contentId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String emailId,
                required int position,
                Value<String?> filename = const Value.absent(),
                required String contentType,
                required int size,
                required String sha256,
                Value<String?> contentId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                emailId: emailId,
                position: position,
                filename: filename,
                contentType: contentType,
                size: size,
                sha256: sha256,
                contentId: contentId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Attachments, AttachmentRow>(table),
                  $AttachmentsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({emailId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (emailId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.emailId,
                                referencedTable: $AttachmentsReferences
                                    ._emailIdTable(db),
                                referencedColumn: $AttachmentsReferences
                                    ._emailIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $AttachmentsProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      Attachments,
      AttachmentRow,
      $AttachmentsFilterComposer,
      $AttachmentsOrderingComposer,
      $AttachmentsAnnotationComposer,
      $AttachmentsCreateCompanionBuilder,
      $AttachmentsUpdateCompanionBuilder,
      (AttachmentRow, $AttachmentsReferences),
      AttachmentRow,
      PrefetchHooks Function({bool emailId})
    >;
typedef $LabelsCreateCompanionBuilder =
    LabelsCompanion Function({
      required String emailId,
      required String label,
      required String labelEventId,
      required int timestamp,
      required String recipientPubkey,
      Value<int> rowid,
    });
typedef $LabelsUpdateCompanionBuilder =
    LabelsCompanion Function({
      Value<String> emailId,
      Value<String> label,
      Value<String> labelEventId,
      Value<int> timestamp,
      Value<String> recipientPubkey,
      Value<int> rowid,
    });

class $LabelsFilterComposer extends Composer<_$NostrMailDatabase, Labels> {
  $LabelsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get emailId => $composableBuilder(
    column: $table.emailId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get labelEventId => $composableBuilder(
    column: $table.labelEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnFilters(column),
  );
}

class $LabelsOrderingComposer extends Composer<_$NostrMailDatabase, Labels> {
  $LabelsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get emailId => $composableBuilder(
    column: $table.emailId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get labelEventId => $composableBuilder(
    column: $table.labelEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $LabelsAnnotationComposer extends Composer<_$NostrMailDatabase, Labels> {
  $LabelsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get emailId =>
      $composableBuilder(column: $table.emailId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get labelEventId => $composableBuilder(
    column: $table.labelEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => column,
  );
}

class $LabelsTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          Labels,
          LabelRow,
          $LabelsFilterComposer,
          $LabelsOrderingComposer,
          $LabelsAnnotationComposer,
          $LabelsCreateCompanionBuilder,
          $LabelsUpdateCompanionBuilder,
          (LabelRow, BaseReferences<_$NostrMailDatabase, Labels, LabelRow>),
          LabelRow,
          PrefetchHooks Function()
        > {
  $LabelsTableManager(_$NostrMailDatabase db, Labels table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LabelsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LabelsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LabelsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> emailId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> labelEventId = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<String> recipientPubkey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LabelsCompanion(
                emailId: emailId,
                label: label,
                labelEventId: labelEventId,
                timestamp: timestamp,
                recipientPubkey: recipientPubkey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String emailId,
                required String label,
                required String labelEventId,
                required int timestamp,
                required String recipientPubkey,
                Value<int> rowid = const Value.absent(),
              }) => LabelsCompanion.insert(
                emailId: emailId,
                label: label,
                labelEventId: labelEventId,
                timestamp: timestamp,
                recipientPubkey: recipientPubkey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Labels, LabelRow>(table),
                  BaseReferences<_$NostrMailDatabase, Labels, LabelRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LabelsProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      Labels,
      LabelRow,
      $LabelsFilterComposer,
      $LabelsOrderingComposer,
      $LabelsAnnotationComposer,
      $LabelsCreateCompanionBuilder,
      $LabelsUpdateCompanionBuilder,
      (LabelRow, BaseReferences<_$NostrMailDatabase, Labels, LabelRow>),
      LabelRow,
      PrefetchHooks Function()
    >;
typedef $GiftWrapsCreateCompanionBuilder =
    GiftWrapsCompanion Function({
      required String id,
      required String recipientPubkey,
      required String event,
      Value<String?> seal,
      Value<String?> rumor,
      Value<String?> rumorId,
      required String stage,
      Value<int> attempts,
      Value<String?> failure,
      Value<int> rowid,
    });
typedef $GiftWrapsUpdateCompanionBuilder =
    GiftWrapsCompanion Function({
      Value<String> id,
      Value<String> recipientPubkey,
      Value<String> event,
      Value<String?> seal,
      Value<String?> rumor,
      Value<String?> rumorId,
      Value<String> stage,
      Value<int> attempts,
      Value<String?> failure,
      Value<int> rowid,
    });

class $GiftWrapsFilterComposer
    extends Composer<_$NostrMailDatabase, GiftWraps> {
  $GiftWrapsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get event => $composableBuilder(
    column: $table.event,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seal => $composableBuilder(
    column: $table.seal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rumor => $composableBuilder(
    column: $table.rumor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rumorId => $composableBuilder(
    column: $table.rumorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failure => $composableBuilder(
    column: $table.failure,
    builder: (column) => ColumnFilters(column),
  );
}

class $GiftWrapsOrderingComposer
    extends Composer<_$NostrMailDatabase, GiftWraps> {
  $GiftWrapsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get event => $composableBuilder(
    column: $table.event,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seal => $composableBuilder(
    column: $table.seal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rumor => $composableBuilder(
    column: $table.rumor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rumorId => $composableBuilder(
    column: $table.rumorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failure => $composableBuilder(
    column: $table.failure,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GiftWrapsAnnotationComposer
    extends Composer<_$NostrMailDatabase, GiftWraps> {
  $GiftWrapsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get event =>
      $composableBuilder(column: $table.event, builder: (column) => column);

  GeneratedColumn<String> get seal =>
      $composableBuilder(column: $table.seal, builder: (column) => column);

  GeneratedColumn<String> get rumor =>
      $composableBuilder(column: $table.rumor, builder: (column) => column);

  GeneratedColumn<String> get rumorId =>
      $composableBuilder(column: $table.rumorId, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get failure =>
      $composableBuilder(column: $table.failure, builder: (column) => column);
}

class $GiftWrapsTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          GiftWraps,
          GiftWrapRow,
          $GiftWrapsFilterComposer,
          $GiftWrapsOrderingComposer,
          $GiftWrapsAnnotationComposer,
          $GiftWrapsCreateCompanionBuilder,
          $GiftWrapsUpdateCompanionBuilder,
          (
            GiftWrapRow,
            BaseReferences<_$NostrMailDatabase, GiftWraps, GiftWrapRow>,
          ),
          GiftWrapRow,
          PrefetchHooks Function()
        > {
  $GiftWrapsTableManager(_$NostrMailDatabase db, GiftWraps table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GiftWrapsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GiftWrapsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GiftWrapsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> recipientPubkey = const Value.absent(),
                Value<String> event = const Value.absent(),
                Value<String?> seal = const Value.absent(),
                Value<String?> rumor = const Value.absent(),
                Value<String?> rumorId = const Value.absent(),
                Value<String> stage = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> failure = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GiftWrapsCompanion(
                id: id,
                recipientPubkey: recipientPubkey,
                event: event,
                seal: seal,
                rumor: rumor,
                rumorId: rumorId,
                stage: stage,
                attempts: attempts,
                failure: failure,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String recipientPubkey,
                required String event,
                Value<String?> seal = const Value.absent(),
                Value<String?> rumor = const Value.absent(),
                Value<String?> rumorId = const Value.absent(),
                required String stage,
                Value<int> attempts = const Value.absent(),
                Value<String?> failure = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GiftWrapsCompanion.insert(
                id: id,
                recipientPubkey: recipientPubkey,
                event: event,
                seal: seal,
                rumor: rumor,
                rumorId: rumorId,
                stage: stage,
                attempts: attempts,
                failure: failure,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<GiftWraps, GiftWrapRow>(table),
                  BaseReferences<_$NostrMailDatabase, GiftWraps, GiftWrapRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GiftWrapsProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      GiftWraps,
      GiftWrapRow,
      $GiftWrapsFilterComposer,
      $GiftWrapsOrderingComposer,
      $GiftWrapsAnnotationComposer,
      $GiftWrapsCreateCompanionBuilder,
      $GiftWrapsUpdateCompanionBuilder,
      (
        GiftWrapRow,
        BaseReferences<_$NostrMailDatabase, GiftWraps, GiftWrapRow>,
      ),
      GiftWrapRow,
      PrefetchHooks Function()
    >;
typedef $TombstonesCreateCompanionBuilder =
    TombstonesCompanion Function({
      required String eventId,
      required String recipientPubkey,
      required int createdAt,
      Value<int> rowid,
    });
typedef $TombstonesUpdateCompanionBuilder =
    TombstonesCompanion Function({
      Value<String> eventId,
      Value<String> recipientPubkey,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $TombstonesFilterComposer
    extends Composer<_$NostrMailDatabase, Tombstones> {
  $TombstonesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $TombstonesOrderingComposer
    extends Composer<_$NostrMailDatabase, Tombstones> {
  $TombstonesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $TombstonesAnnotationComposer
    extends Composer<_$NostrMailDatabase, Tombstones> {
  $TombstonesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get recipientPubkey => $composableBuilder(
    column: $table.recipientPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $TombstonesTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          Tombstones,
          TombstoneRow,
          $TombstonesFilterComposer,
          $TombstonesOrderingComposer,
          $TombstonesAnnotationComposer,
          $TombstonesCreateCompanionBuilder,
          $TombstonesUpdateCompanionBuilder,
          (
            TombstoneRow,
            BaseReferences<_$NostrMailDatabase, Tombstones, TombstoneRow>,
          ),
          TombstoneRow,
          PrefetchHooks Function()
        > {
  $TombstonesTableManager(_$NostrMailDatabase db, Tombstones table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $TombstonesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $TombstonesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $TombstonesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> recipientPubkey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TombstonesCompanion(
                eventId: eventId,
                recipientPubkey: recipientPubkey,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String recipientPubkey,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TombstonesCompanion.insert(
                eventId: eventId,
                recipientPubkey: recipientPubkey,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Tombstones, TombstoneRow>(table),
                  BaseReferences<_$NostrMailDatabase, Tombstones, TombstoneRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $TombstonesProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      Tombstones,
      TombstoneRow,
      $TombstonesFilterComposer,
      $TombstonesOrderingComposer,
      $TombstonesAnnotationComposer,
      $TombstonesCreateCompanionBuilder,
      $TombstonesUpdateCompanionBuilder,
      (
        TombstoneRow,
        BaseReferences<_$NostrMailDatabase, Tombstones, TombstoneRow>,
      ),
      TombstoneRow,
      PrefetchHooks Function()
    >;
typedef $SettingsCreateCompanionBuilder =
    SettingsCompanion Function({
      required String pubkey,
      required String json,
      Value<int> rowid,
    });
typedef $SettingsUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> pubkey,
      Value<String> json,
      Value<int> rowid,
    });

class $SettingsFilterComposer extends Composer<_$NostrMailDatabase, Settings> {
  $SettingsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $SettingsOrderingComposer
    extends Composer<_$NostrMailDatabase, Settings> {
  $SettingsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SettingsAnnotationComposer
    extends Composer<_$NostrMailDatabase, Settings> {
  $SettingsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $SettingsTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          Settings,
          SettingsRow,
          $SettingsFilterComposer,
          $SettingsOrderingComposer,
          $SettingsAnnotationComposer,
          $SettingsCreateCompanionBuilder,
          $SettingsUpdateCompanionBuilder,
          (
            SettingsRow,
            BaseReferences<_$NostrMailDatabase, Settings, SettingsRow>,
          ),
          SettingsRow,
          PrefetchHooks Function()
        > {
  $SettingsTableManager(_$NostrMailDatabase db, Settings table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SettingsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SettingsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SettingsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pubkey = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(pubkey: pubkey, json: json, rowid: rowid),
          createCompanionCallback:
              ({
                required String pubkey,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                pubkey: pubkey,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Settings, SettingsRow>(table),
                  BaseReferences<_$NostrMailDatabase, Settings, SettingsRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SettingsProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      Settings,
      SettingsRow,
      $SettingsFilterComposer,
      $SettingsOrderingComposer,
      $SettingsAnnotationComposer,
      $SettingsCreateCompanionBuilder,
      $SettingsUpdateCompanionBuilder,
      (SettingsRow, BaseReferences<_$NostrMailDatabase, Settings, SettingsRow>),
      SettingsRow,
      PrefetchHooks Function()
    >;
typedef $EmailSearchCreateCompanionBuilder =
    EmailSearchCompanion Function({
      required String fromAddress,
      required String subject,
      required String bodyPlain,
      Value<int> rowid,
    });
typedef $EmailSearchUpdateCompanionBuilder =
    EmailSearchCompanion Function({
      Value<String> fromAddress,
      Value<String> subject,
      Value<String> bodyPlain,
      Value<int> rowid,
    });

class $EmailSearchFilterComposer
    extends Composer<_$NostrMailDatabase, EmailSearch> {
  $EmailSearchFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fromAddress => $composableBuilder(
    column: $table.fromAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnFilters(column),
  );
}

class $EmailSearchOrderingComposer
    extends Composer<_$NostrMailDatabase, EmailSearch> {
  $EmailSearchOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fromAddress => $composableBuilder(
    column: $table.fromAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnOrderings(column),
  );
}

class $EmailSearchAnnotationComposer
    extends Composer<_$NostrMailDatabase, EmailSearch> {
  $EmailSearchAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fromAddress => $composableBuilder(
    column: $table.fromAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get bodyPlain =>
      $composableBuilder(column: $table.bodyPlain, builder: (column) => column);
}

class $EmailSearchTableManager
    extends
        RootTableManager<
          _$NostrMailDatabase,
          EmailSearch,
          EmailSearchData,
          $EmailSearchFilterComposer,
          $EmailSearchOrderingComposer,
          $EmailSearchAnnotationComposer,
          $EmailSearchCreateCompanionBuilder,
          $EmailSearchUpdateCompanionBuilder,
          (
            EmailSearchData,
            BaseReferences<_$NostrMailDatabase, EmailSearch, EmailSearchData>,
          ),
          EmailSearchData,
          PrefetchHooks Function()
        > {
  $EmailSearchTableManager(_$NostrMailDatabase db, EmailSearch table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $EmailSearchFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $EmailSearchOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $EmailSearchAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fromAddress = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> bodyPlain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmailSearchCompanion(
                fromAddress: fromAddress,
                subject: subject,
                bodyPlain: bodyPlain,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fromAddress,
                required String subject,
                required String bodyPlain,
                Value<int> rowid = const Value.absent(),
              }) => EmailSearchCompanion.insert(
                fromAddress: fromAddress,
                subject: subject,
                bodyPlain: bodyPlain,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<EmailSearch, EmailSearchData>(table),
                  BaseReferences<
                    _$NostrMailDatabase,
                    EmailSearch,
                    EmailSearchData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $EmailSearchProcessedTableManager =
    ProcessedTableManager<
      _$NostrMailDatabase,
      EmailSearch,
      EmailSearchData,
      $EmailSearchFilterComposer,
      $EmailSearchOrderingComposer,
      $EmailSearchAnnotationComposer,
      $EmailSearchCreateCompanionBuilder,
      $EmailSearchUpdateCompanionBuilder,
      (
        EmailSearchData,
        BaseReferences<_$NostrMailDatabase, EmailSearch, EmailSearchData>,
      ),
      EmailSearchData,
      PrefetchHooks Function()
    >;

class $NostrMailDatabaseManager {
  final _$NostrMailDatabase _db;
  $NostrMailDatabaseManager(this._db);
  $EmailsTableManager get emails => $EmailsTableManager(_db, _db.emails);
  $AttachmentsTableManager get attachments =>
      $AttachmentsTableManager(_db, _db.attachments);
  $LabelsTableManager get labels => $LabelsTableManager(_db, _db.labels);
  $GiftWrapsTableManager get giftWraps =>
      $GiftWrapsTableManager(_db, _db.giftWraps);
  $TombstonesTableManager get tombstones =>
      $TombstonesTableManager(_db, _db.tombstones);
  $SettingsTableManager get settings =>
      $SettingsTableManager(_db, _db.settings);
  $EmailSearchTableManager get emailSearch =>
      $EmailSearchTableManager(_db, _db.emailSearch);
}
