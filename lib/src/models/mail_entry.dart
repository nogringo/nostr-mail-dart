/// A user folder or a user tag, as the private settings name it
/// ([Nostr Mail Settings](https://github.com/nogringo/protocols/blob/main/nostr-mail-settings.md)).
///
/// An email carries it as a `folder:<id>` or `tag:<id>` label, or is held by
/// its [match] without any label. Fields this version does not know are kept
/// and written back, as the spec requires of a client rewriting an entry.
class MailEntry {
  /// 16 lowercase hex characters, drawn once and never changed.
  final String id;
  final String name;

  /// `#RRGGBB`. When absent, derive one from [id].
  final String? color;

  /// Sort key, ascending. An entry without one sorts last, see [sortEntries].
  final int? position;
  final MailMatch? match;

  final Map<String, dynamic> _extra;

  const MailEntry({
    required this.id,
    required this.name,
    this.color,
    this.position,
    this.match,
  }) : _extra = const {};

  const MailEntry._({
    required this.id,
    required this.name,
    this.color,
    this.position,
    this.match,
    required this._extra,
  });

  factory MailEntry.fromJson(Map<String, dynamic> json) {
    final match = json['match'];
    return MailEntry._(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String?,
      position: (json['position'] as num?)?.toInt(),
      match: match is Map<String, dynamic> ? MailMatch.fromJson(match) : null,
      extra: Map.of(json)..removeWhere((key, _) => _fields.contains(key)),
    );
  }

  static const _fields = {'id', 'name', 'color', 'position', 'match'};

  Map<String, dynamic> toJson() => {
    ..._extra,
    'id': id,
    'name': name,
    'color': ?color,
    'position': ?position,
    if (match != null) 'match': match!.toJson(),
  };

  MailEntry copyWith({
    String? name,
    String? color,
    int? position,
    MailMatch? match,
    bool clearColor = false,
    bool clearPosition = false,
    bool clearMatch = false,
  }) => MailEntry._(
    id: id,
    name: name ?? this.name,
    color: clearColor ? null : (color ?? this.color),
    position: clearPosition ? null : (position ?? this.position),
    match: clearMatch ? null : (match ?? this.match),
    extra: _extra,
  );

  @override
  String toString() => 'MailEntry(id: $id, name: $name)';
}

/// The condition under which a [MailEntry] holds an email without any label
/// event. Fields combine with AND, the entries of one field with OR, and a
/// match with no field matches nothing.
class MailMatch {
  /// Sender addresses or domains: `github.com` matches `a@github.com` and
  /// `a@mail.github.com`, not `a@notgithub.com`.
  final List<String>? from;

  /// Substrings of the subject.
  final List<String>? subject;
  final bool? hasAttachment;

  final Map<String, dynamic> _extra;

  const MailMatch({this.from, this.subject, this.hasAttachment})
    : _extra = const {};

  const MailMatch._({
    this.from,
    this.subject,
    this.hasAttachment,
    required this._extra,
  });

  factory MailMatch.fromJson(Map<String, dynamic> json) => MailMatch._(
    from: _strings(json['from']),
    subject: _strings(json['subject']),
    hasAttachment: json['has_attachment'] as bool?,
    extra: Map.of(json)..removeWhere((key, _) => _fields.contains(key)),
  );

  static const _fields = {'from', 'subject', 'has_attachment'};

  static List<String>? _strings(Object? value) =>
      (value as List<dynamic>?)?.map((e) => e as String).toList();

  Map<String, dynamic> toJson() => {
    ..._extra,
    'from': ?from,
    'subject': ?subject,
    'has_attachment': ?hasAttachment,
  };

  MailMatch copyWith({
    List<String>? from,
    List<String>? subject,
    bool? hasAttachment,
    bool clearFrom = false,
    bool clearSubject = false,
    bool clearHasAttachment = false,
  }) => MailMatch._(
    from: clearFrom ? null : (from ?? this.from),
    subject: clearSubject ? null : (subject ?? this.subject),
    hasAttachment: clearHasAttachment
        ? null
        : (hasAttachment ?? this.hasAttachment),
    extra: _extra,
  );

  bool matches({
    required String from,
    required String subject,
    required bool hasAttachment,
  }) {
    if (this.from == null &&
        this.subject == null &&
        this.hasAttachment == null) {
      return false;
    }
    if (this.from != null) {
      final address = from.toLowerCase();
      final matched = this.from!.any((entry) {
        final e = entry.toLowerCase();
        return address == e ||
            address.endsWith('@$e') ||
            address.endsWith('.$e');
      });
      if (!matched) return false;
    }
    if (this.subject != null) {
      final text = subject.toLowerCase();
      if (!this.subject!.any((e) => text.contains(e.toLowerCase()))) {
        return false;
      }
    }
    if (this.hasAttachment != null && this.hasAttachment != hasAttachment) {
      return false;
    }
    return true;
  }
}

/// [entries] in display order: by [MailEntry.position], entries without one
/// last, ties broken by name.
List<MailEntry> sortEntries(Iterable<MailEntry> entries) =>
    entries.toList()..sort((a, b) {
      final byPosition = switch ((a.position, b.position)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (final x?, final y?) => x.compareTo(y),
      };
      return byPosition != 0 ? byPosition : a.name.compareTo(b.name);
    });
