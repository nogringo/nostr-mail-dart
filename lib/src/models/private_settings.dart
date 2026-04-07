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

  /// Default "From" address (e.g. `npub1...@bridge.com`)
  final MailAddress? defaultAddress;

  /// Email signature appended to outgoing emails
  final String? signature;

  /// List of preferred bridge domains
  final List<String>? bridges;

  const PrivateSettings({
    this.sourceEvent,
    this.defaultAddress,
    this.signature,
    this.bridges,
  });

  /// Create from decrypted JSON content and its source event.
  factory PrivateSettings.fromJson(String json, {Nip01Event? sourceEvent}) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    MailAddress? defaultAddress;
    if (map['default_address'] case String addrStr) {
      try {
        defaultAddress = MailAddress.parse(addrStr);
      } catch (_) {
        defaultAddress = null;
      }
    }
    return PrivateSettings(
      sourceEvent: sourceEvent,
      defaultAddress: defaultAddress,
      signature: map['signature'] as String?,
      bridges: (map['bridges'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  /// Serialize to JSON for encryption
  String toJson() {
    final map = <String, dynamic>{};
    if (defaultAddress != null) {
      map['default_address'] = defaultAddress!.encode();
    }
    if (signature != null) map['signature'] = signature;
    if (bridges != null) map['bridges'] = bridges;
    return jsonEncode(map);
  }

  /// Copy with updated fields.
  ///
  /// [sourceEvent] is always cleared since the resulting settings
  /// have not been published yet.
  PrivateSettings copyWith({
    MailAddress? defaultAddress,
    String? signature,
    List<String>? bridges,
    bool clearDefaultAddress = false,
    bool clearSignature = false,
    bool clearBridges = false,
  }) {
    return PrivateSettings(
      sourceEvent: null, // stale after mutation
      defaultAddress: clearDefaultAddress
          ? null
          : (defaultAddress ?? this.defaultAddress),
      signature: clearSignature ? null : (signature ?? this.signature),
      bridges: clearBridges ? null : (bridges ?? this.bridges),
    );
  }

  @override
  String toString() =>
      'PrivateSettings(defaultAddress: $defaultAddress, signature: $signature, bridges: $bridges)';
}
