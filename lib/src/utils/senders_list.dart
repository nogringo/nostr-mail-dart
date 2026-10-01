import 'dart:convert';

import 'package:ndk/ndk.dart' show Nip01Event;

/// A `sender` entry of the senders list. [verdict] is kept as published: what
/// counts as one is decided when verdicts are resolved.
typedef SenderEntry = ({String key, String? verdict});

/// The `sender` entries [event] operates on: those of its tags and those of
/// its decrypted [plaintext], whose union the Append-Only Lists NIP defines.
/// A key named twice keeps its first entry.
List<SenderEntry> sendersListEntries(Nip01Event event, String plaintext) {
  final entries = <String, SenderEntry>{};
  for (final tag in [...event.tags, ..._tuples(plaintext)]) {
    if (tag.length < 2 || tag[0] != 'sender') continue;
    entries.putIfAbsent(
      tag[1],
      () => (key: tag[1], verdict: tag.length > 2 ? tag[2] : null),
    );
  }
  return entries.values.toList();
}

/// The plaintext of a senders list event carrying [entries], before NIP-44
/// encryption.
String sendersListContent(Iterable<SenderEntry> entries) => jsonEncode([
  for (final entry in entries) ['sender', entry.key, ?entry.verdict],
]);

List<List<String>> _tuples(String plaintext) {
  if (plaintext.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(plaintext);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  return [
    for (final tuple in decoded)
      if (tuple is List && tuple.every((element) => element is String))
        tuple.cast<String>(),
  ];
}
