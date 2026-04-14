import 'dart:convert';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/domain_layer/entities/nip_01_event.dart';

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

  const PrivateSettings({
    this.sourceEvent,
    this.signature,
    this.bridges,
    this.identities,
  });

  /// Create from decrypted JSON content and its source event.
  factory PrivateSettings.fromJson(String json, {Nip01Event? sourceEvent}) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PrivateSettings(
      sourceEvent: sourceEvent,
      signature: map['signature'] as String?,
      bridges: (map['bridges'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      identities: (map['identities'] as List<dynamic>?)
          ?.map((e) => MailAddress.parse(e as String))
          .toList(),
    );
  }

  /// Serialize to JSON for encryption
  String toJson() {
    final map = <String, dynamic>{};
    if (signature != null) map['signature'] = signature;
    if (bridges != null) map['bridges'] = bridges;
    if (identities != null) {
      map['identities'] = identities!.map((e) => e.encode()).toList();
    }
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
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
  }) {
    return PrivateSettings(
      sourceEvent: null, // stale after mutation
      signature: clearSignature ? null : (signature ?? this.signature),
      bridges: clearBridges ? null : (bridges ?? this.bridges),
      identities: clearIdentities ? null : (identities ?? this.identities),
    );
  }

  @override
  String toString() =>
      'PrivateSettings(defaultAddress: $defaultAddress, signature: $signature, bridges: $bridges, identities: $identities)';
}
