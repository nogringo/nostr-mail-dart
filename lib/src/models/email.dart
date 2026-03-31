import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../utils/html_utils.dart';

class Email {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final String rawContent;
  final DateTime createdAt;

  late final MimeMessage _mimeMessage;

  /// Access the underlying [MimeMessage] for rich email data.
  MimeMessage get mime => _mimeMessage;

  /// Get the raw RFC 2822 MIME string.
  String get rawMime => rawContent;

  Email({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.rawContent,
    required this.createdAt,
    MimeMessage? mimeMessage,
  }) {
    _mimeMessage = mimeMessage ?? MimeMessage.parseFromText(rawContent);
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
      'rawContent': rawContent,
    };
  }

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    id: json['id'] as String,
    senderPubkey: json['senderPubkey'] as String,
    recipientPubkey: json['recipientPubkey'] as String? ?? '',
    rawContent: json['rawContent'] as String,
    createdAt: DateTime.parse(
      json['createdAt'] as String? ?? json['date'] as String,
    ),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Email && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
