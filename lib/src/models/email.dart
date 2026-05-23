import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../utils/html_utils.dart';
import 'attachment_ref.dart';

/// A parsed email.
///
/// Attachment payloads are not held here; their bytes live in the local
/// blob cache. This object only carries [attachmentRefs] (filename, size,
/// sha256) and a light MIME envelope whose attachment parts have empty
/// bodies, so constructing and using an [Email] never decodes megabytes.
///
/// To load attachment bytes on demand, use
/// `NostrMailClient.getAttachmentBytes(email, ref)`.
class Email {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final bool isPublic;
  final DateTime createdAt;

  /// MIME with attachment bodies emptied. Parsable by
  /// `MimeMessage.parseFromText`; typically a few KB.
  final String lightMimeText;

  /// One ref per attachment, in original MIME tree order.
  final List<AttachmentRef> attachmentRefs;

  /// sha256 of the encrypted Blossom blob (the source-of-truth full MIME).
  /// `null` for inline emails (their full MIME is the rumor's `content`).
  final String? blossomHash;

  /// AES-GCM key for the blob. `null` for inline emails.
  final String? decryptionKey;

  /// AES-GCM nonce for the blob. `null` for inline emails.
  final String? decryptionNonce;

  late final MimeMessage _mimeMessage;

  /// The parsed MIME message. Attachment parts are present in the tree
  /// (with intact headers including filename, content-type, content-id)
  /// but their bodies are empty. To get the bytes of an attachment, use
  /// the matching [AttachmentRef] from [attachmentRefs] and call
  /// `client.getAttachmentBytes(email, ref)`.
  MimeMessage get mime => _mimeMessage;

  Email({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.lightMimeText,
    required this.attachmentRefs,
    required this.createdAt,
    this.blossomHash,
    this.decryptionKey,
    this.decryptionNonce,
    this.isPublic = false,
    MimeMessage? mimeMessage,
  }) {
    _mimeMessage = mimeMessage ?? MimeMessage.parseFromText(lightMimeText);
  }

  /// Get the email subject.
  String? get subject => _mimeMessage.decodeSubject();

  /// Get the email date from MIME, falling back to Nostr event creation date.
  DateTime get date => _mimeMessage.decodeDate() ?? createdAt;

  /// Get the plain text body, falling back to stripped HTML if empty.
  String get body {
    final text = textBody;
    if (text != null && text.isNotEmpty) return text;

    final html = htmlBody;
    if (html == null || html.isEmpty) return '';

    return stripHtmlTags(html);
  }

  /// Get the HTML body content.
  String? get htmlBody => _mimeMessage.decodeTextHtmlPart();

  /// Get the plain text body content.
  String? get textBody => _mimeMessage.decodeTextPlainPart();

  /// Get the sender's address.
  MailAddress? get sender =>
      _mimeMessage.sender ??
      (_mimeMessage.from != null && _mimeMessage.from!.isNotEmpty
          ? _mimeMessage.from!.first
          : null);

  /// Check if this email was relayed through a bridge.
  ///
  /// Returns `true` if:
  /// - The sender address cannot be parsed (legacy email)
  /// - The pubkey extracted from the sender address differs from [senderPubkey]
  ///
  /// Returns `false` if the email was sent directly (e.g., @nostr address).
  bool get isBridged {
    // Try to get sender address from MIME headers
    final senderAddress = sender?.email;
    if (senderAddress == null || !senderAddress.contains('@')) {
      // No sender address or invalid format - consider as bridged
      return true;
    }

    // Extract pubkey from sender address (npub1...@domain or hex@domain)
    final localPart = senderAddress.split('@').first;
    String? contactPubkey;

    if (localPart.startsWith('npub1')) {
      try {
        contactPubkey = Nip19.decode(localPart);
      } catch (_) {
        return true; // Invalid npub - consider as bridged
      }
    } else if (localPart.length == 64 &&
        RegExp(r'^[a-fA-F0-9]+$').hasMatch(localPart)) {
      contactPubkey = localPart.toLowerCase();
    }

    // If no pubkey could be extracted, it's a legacy email (bridged)
    if (contactPubkey == null) {
      return true;
    }

    // Compare extracted pubkey with actual sender pubkey
    return contactPubkey != senderPubkey;
  }

  Map<String, dynamic> toJson() {
    final fromAddresses = _mimeMessage.from;
    String? from;

    if (_mimeMessage.sender != null) {
      from = _mimeMessage.sender!.encode();
    } else if (fromAddresses != null && fromAddresses.isNotEmpty) {
      from = fromAddresses.first.encode();
    }

    final subject = _mimeMessage.decodeSubject();

    return {
      'id': id,
      'from': ?from,
      'subject': ?subject,
      'body': body,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'senderPubkey': senderPubkey,
      'recipientPubkey': recipientPubkey,
      'lightMimeText': lightMimeText,
      'attachmentRefs': attachmentRefs.map((r) => r.toJson()).toList(),
      if (blossomHash != null) 'blossomHash': blossomHash,
      if (decryptionKey != null) 'decryptionKey': decryptionKey,
      if (decryptionNonce != null) 'decryptionNonce': decryptionNonce,
      'isPublic': isPublic,
    };
  }

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    id: json['id'] as String,
    senderPubkey: json['senderPubkey'] as String,
    recipientPubkey: json['recipientPubkey'] as String? ?? '',
    lightMimeText: json['lightMimeText'] as String,
    attachmentRefs:
        (json['attachmentRefs'] as List<dynamic>?)
            ?.map((e) => AttachmentRef.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    blossomHash: json['blossomHash'] as String?,
    decryptionKey: json['decryptionKey'] as String?,
    decryptionNonce: json['decryptionNonce'] as String?,
    createdAt: DateTime.parse(
      json['createdAt'] as String? ?? json['date'] as String,
    ),
    isPublic: json['isPublic'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Email && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
