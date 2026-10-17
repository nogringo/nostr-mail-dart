import 'dart:convert';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/domain_layer/entities/nip_01_event.dart';

import 'mail_entry.dart';
import 'signature.dart';

/// Private user settings that are synced across devices.
///
/// These settings are stored as encrypted NIP-78 (kind 30078) events
/// and decrypted using NIP-44.
class PrivateSettings {
  /// The source Nostr event that these settings were decrypted from.
  ///
  /// This allows consumers to inspect the event metadata (created_at, id, pubkey,
  /// relay provenance, signature verification, etc.) without storing a copy
  /// separately.
  final Nip01Event? sourceEvent;

  /// Default "From" address — convenience getter for [identities.first].
  MailAddress? get defaultAddress => identities?.first;

  /// Plain text signature appended to every outgoing email, as long as
  /// [signatures] is null.
  final String? signature;

  /// HTML signatures, chosen per identity by [signatureFor].
  final List<Signature>? signatures;

  /// The choice of an identity absent from [identitySignatures], and of each
  /// field its choice leaves null.
  final SignatureChoice? defaultSignature;

  /// Choices keyed by the exact string of an entry of [identities], as
  /// [identityKey] gives it.
  final Map<String, SignatureChoice>? identitySignatures;

  /// List of preferred bridge domains
  final List<String>? bridges;

  /// List of user-defined "From" identities in RFC 5322 format.
  ///
  /// Each entry can be used directly in the `From:` header without any transformation.
  /// Examples:
  /// - `"Alice Real <npub1abc...@nostr.mail>"` — name + address
  /// - `"npub1abc...@bridge.com"` — address only (no name)
  /// - `"Pseudo <alice@example.com>"` — custom name + legacy email
  ///
  /// If empty or absent, clients SHOULD auto-generate available addresses
  /// from `npub@nostr` and configured bridges.
  /// The **first identity** (index 0) is the default "From" address.
  final List<MailAddress>? identities;

  /// The strings [identities] were read from, written back as they were:
  /// [identitySignatures] is keyed by them.
  final List<String>? _identityStrings;

  /// User folders, see [MailEntry]. Order them with [sortEntries].
  final List<MailEntry>? folders;

  /// User tags, see [MailEntry]. Order them with [sortEntries].
  final List<MailEntry>? tags;

  /// Fields this version does not know, written back untouched: the spec
  /// requires a client to keep what it does not change.
  final Map<String, dynamic> _extra;

  const PrivateSettings({
    this.sourceEvent,
    this.signature,
    this.signatures,
    this.defaultSignature,
    this.identitySignatures,
    this.bridges,
    this.identities,
    this.folders,
    this.tags,
  }) : _identityStrings = null,
       _extra = const {};

  const PrivateSettings._({
    this.sourceEvent,
    this.signature,
    this.signatures,
    this.defaultSignature,
    this.identitySignatures,
    this.bridges,
    this.identities,
    required this._identityStrings,
    this.folders,
    this.tags,
    required this._extra,
  });

  /// Create from decrypted JSON content and its source event.
  factory PrivateSettings.fromJson(String json, {Nip01Event? sourceEvent}) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final identityStrings = (map['identities'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList();
    final defaultSignature = map['default_signature'];
    return PrivateSettings._(
      sourceEvent: sourceEvent,
      signature: map['signature'] as String?,
      signatures: (map['signatures'] as List<dynamic>?)
          ?.map((e) => Signature.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultSignature: defaultSignature is Map<String, dynamic>
          ? SignatureChoice.fromJson(defaultSignature)
          : null,
      identitySignatures: (map['identity_signatures'] as Map<String, dynamic>?)
          ?.map(
            (key, value) => MapEntry(
              key,
              SignatureChoice.fromJson(value as Map<String, dynamic>),
            ),
          ),
      bridges: (map['bridges'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      identities: identityStrings?.map(MailAddress.parse).toList(),
      identityStrings: identityStrings,
      folders: _entries(map['folders']),
      tags: _entries(map['tags']),
      extra: Map.of(map)..removeWhere((key, _) => _fields.contains(key)),
    );
  }

  static const _fields = {
    'signature',
    'signatures',
    'default_signature',
    'identity_signatures',
    'bridges',
    'identities',
    'folders',
    'tags',
  };

  static List<MailEntry>? _entries(Object? value) => (value as List<dynamic>?)
      ?.map((e) => MailEntry.fromJson(e as Map<String, dynamic>))
      .toList();

  /// The string of the entry of [identities] that is [identity], same address
  /// and same name, as [identitySignatures] keys it. Null when [identity] is
  /// not one of them.
  String? identityKey(MailAddress identity) {
    final list = identities;
    if (list == null) return null;
    final index = list.indexWhere((e) => _sameAddress(e, identity));
    if (index < 0) return null;
    return _identityStrings?[index] ?? _format(list[index]);
  }

  /// The signature to insert in an email sent from [from], a new one or a
  /// [reply] (or a forward). Null for no signature, and always null while
  /// [signatures] is: [signature] then goes as plain text on every email.
  Signature? signatureFor(MailAddress from, {bool reply = false}) {
    final list = signatures;
    if (list == null) return null;
    final key = identityKey(from);
    final id =
        identitySignatures?[key]?.idFor(reply: reply) ??
        defaultSignature?.idFor(reply: reply);
    if (id == null || id.isEmpty) return null;
    for (final s in list) {
      if (s.id == id) return s;
    }
    return null;
  }

  static bool _sameAddress(MailAddress a, MailAddress b) =>
      a.email.toLowerCase() == b.email.toLowerCase() &&
      (a.personalName ?? '') == (b.personalName ?? '');

  static final _special = RegExp(r'[()<>\[\]:;@\\,."]');

  /// RFC 5322 text of an identity this version adds, left unencoded: the
  /// settings are JSON, not a header.
  static String _format(MailAddress address) {
    final name = address.personalName;
    if (name == null || name.isEmpty) return address.email;
    final quoted = _special.hasMatch(name)
        ? '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"'
        : name;
    return '$quoted <${address.email}>';
  }

  /// The strings of [identities], keeping the one each address was read from.
  List<String>? _identityStringsFor(List<MailAddress>? identities) {
    if (identities == null) return null;
    return [
      for (final address in identities)
        identityKey(address) ?? _format(address),
    ];
  }

  /// Serialize to JSON for encryption
  String toJson() {
    final map = <String, dynamic>{..._extra};
    if (signature != null) map['signature'] = signature;
    if (signatures != null) {
      map['signatures'] = signatures!.map((e) => e.toJson()).toList();
    }
    if (defaultSignature != null) {
      map['default_signature'] = defaultSignature!.toJson();
    }
    if (identitySignatures != null) {
      map['identity_signatures'] = identitySignatures!.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
    }
    if (bridges != null) map['bridges'] = bridges;
    if (identities != null) {
      map['identities'] = _identityStrings ?? identities!.map(_format).toList();
    }
    if (folders != null) {
      map['folders'] = folders!.map((e) => e.toJson()).toList();
    }
    if (tags != null) map['tags'] = tags!.map((e) => e.toJson()).toList();
    return jsonEncode(map);
  }

  /// Copy with updated fields.
  ///
  /// [sourceEvent] is always cleared since the resulting settings
  /// have not been published yet.
  PrivateSettings copyWith({
    String? signature,
    List<Signature>? signatures,
    SignatureChoice? defaultSignature,
    Map<String, SignatureChoice>? identitySignatures,
    List<String>? bridges,
    List<MailAddress>? identities,
    List<MailEntry>? folders,
    List<MailEntry>? tags,
    bool clearSignature = false,
    bool clearSignatures = false,
    bool clearDefaultSignature = false,
    bool clearIdentitySignatures = false,
    bool clearBridges = false,
    bool clearIdentities = false,
    bool clearFolders = false,
    bool clearTags = false,
  }) {
    return PrivateSettings._(
      sourceEvent: null, // stale after mutation
      signature: clearSignature ? null : (signature ?? this.signature),
      signatures: clearSignatures ? null : (signatures ?? this.signatures),
      defaultSignature: clearDefaultSignature
          ? null
          : (defaultSignature ?? this.defaultSignature),
      identitySignatures: clearIdentitySignatures
          ? null
          : (identitySignatures ?? this.identitySignatures),
      bridges: clearBridges ? null : (bridges ?? this.bridges),
      identities: clearIdentities ? null : (identities ?? this.identities),
      identityStrings: clearIdentities
          ? null
          : identities == null
          ? _identityStrings
          : _identityStringsFor(identities),
      folders: clearFolders ? null : (folders ?? this.folders),
      tags: clearTags ? null : (tags ?? this.tags),
      extra: _extra,
    );
  }

  /// The same settings, as published in [event].
  PrivateSettings withSource(Nip01Event event) => PrivateSettings._(
    sourceEvent: event,
    signature: signature,
    signatures: signatures,
    defaultSignature: defaultSignature,
    identitySignatures: identitySignatures,
    bridges: bridges,
    identities: identities,
    identityStrings: _identityStrings,
    folders: folders,
    tags: tags,
    extra: _extra,
  );

  @override
  String toString() =>
      'PrivateSettings(defaultAddress: $defaultAddress, signature: $signature, signatures: $signatures, bridges: $bridges, identities: $identities, folders: $folders, tags: $tags)';
}
