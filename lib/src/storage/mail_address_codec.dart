import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';

/// How address lists are held in the `to_addresses`, `cc_addresses` and
/// `bcc_addresses` columns: a JSON array of `{name, email}`.
///
/// JSON rather than the rendered header form, so reading a row back never
/// runs the address parser and a display name carrying a comma or an angle
/// bracket survives the round trip intact.

String encodeAddresses(List<MailAddress> addresses) => jsonEncode([
  for (final address in addresses)
    {
      'email': address.email,
      if (address.personalName != null) 'name': address.personalName,
    },
]);

List<MailAddress> decodeAddresses(String json) {
  if (json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final entry in decoded)
      if (entry is Map && entry['email'] is String)
        MailAddress(entry['name'] as String?, entry['email'] as String),
  ];
}
