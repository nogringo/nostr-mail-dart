import 'dart:convert';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/domain_layer/entities/nip_01_event.dart';

import 'mail_entry.dart';

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

  /// Email signature appended to outgoing emails
  final String? signature;

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
    this.bridges,
    this.identities,
    this.folders,
    this.tags,
  }) : _extra = const {};

  const PrivateSettings._({
    this.sourceEvent,
    this.signature,
    this.bridges,
    this.identities,
    this.folders,
    this.tags,
    required this._extra,
  });

  /// Create from decrypted JSON content and its source event.
  factory PrivateSettings.fromJson(String json, {Nip01Event? sourceEvent}) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PrivateSettings._(
      sourceEvent: sourceEvent,
      signature: map['signature'] as String?,
      bridges: (map['bridges'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      identities: (map['identities'] as List<dynamic>?)
          ?.map((e) => MailAddress.parse(e as String))
          .toList(),
      folders: _entries(map['folders']),
      tags: _entries(map['tags']),
      extra: Map.of(map)..removeWhere((key, _) => _fields.contains(key)),
    );
  }

  static const _fields = {
    'signature',
    'bridges',
    'identities',
    'folders',
    'tags',
  };

  static List<MailEntry>? _entries(Object? value) => (value as List<dynamic>?)
      ?.map((e) => MailEntry.fromJson(e as Map<String, dynamic>))
      .toList();

  /// Serialize to JSON for encryption
  String toJson() {
    final map = <String, dynamic>{..._extra};
    if (signature != null) map['signature'] = signature;
    if (bridges != null) map['bridges'] = bridges;
    if (identities != null) {
      map['identities'] = identities!.map((e) => e.encode()).toList();
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
    List<String>? bridges,
    List<MailAddress>? identities,
    List<MailEntry>? folders,
    List<MailEntry>? tags,
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
    bool clearFolders = false,
    bool clearTags = false,
  }) {
    return PrivateSettings._(
      sourceEvent: null, // stale after mutation
      signature: clearSignature ? null : (signature ?? this.signature),
      bridges: clearBridges ? null : (bridges ?? this.bridges),
      identities: clearIdentities ? null : (identities ?? this.identities),
      folders: clearFolders ? null : (folders ?? this.folders),
      tags: clearTags ? null : (tags ?? this.tags),
      extra: _extra,
    );
  }

  /// The same settings, as published in [event].
  PrivateSettings withSource(Nip01Event event) => PrivateSettings._(
    sourceEvent: event,
    signature: signature,
    bridges: bridges,
    identities: identities,
    folders: folders,
    tags: tags,
    extra: _extra,
  );

  @override
  String toString() =>
      'PrivateSettings(defaultAddress: $defaultAddress, signature: $signature, bridges: $bridges, identities: $identities, folders: $folders, tags: $tags)';
}
