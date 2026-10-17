/// An email signature, as the private settings name it
/// ([Nostr Mail Settings](https://github.com/nogringo/protocols/blob/main/nostr-mail-settings.md)).
///
/// Any signature can be used with any identity. Fields this version does not
/// know are kept and written back, as the spec requires of a client
/// rewriting an entry.
class Signature {
  /// 16 lowercase hex characters, drawn once and never changed.
  final String id;
  final String name;

  /// HTML fragment appended to the email. An `<img>` whose `src` is a key of
  /// the settings' `signature_images` shows that image.
  final String html;

  final Map<String, dynamic> _extra;

  const Signature({required this.id, required this.name, required this.html})
    : _extra = const {};

  const Signature._({
    required this.id,
    required this.name,
    required this.html,
    required this._extra,
  });

  factory Signature.fromJson(Map<String, dynamic> json) => Signature._(
    id: json['id'] as String,
    name: json['name'] as String,
    html: json['html'] as String,
    extra: Map.of(json)..removeWhere((key, _) => _fields.contains(key)),
  );

  static const _fields = {'id', 'name', 'html'};

  Map<String, dynamic> toJson() => {
    ..._extra,
    'id': id,
    'name': name,
    'html': html,
  };

  Signature copyWith({String? name, String? html}) => Signature._(
    id: id,
    name: name ?? this.name,
    html: html ?? this.html,
    extra: _extra,
  );

  @override
  String toString() => 'Signature(id: $id, name: $name)';
}

/// Which signature goes on a new email and which on a reply or a forward.
///
/// A field holds a [Signature.id], or an empty string for no signature. A
/// null field falls back to the same field of the default choice, and to no
/// signature when that one is null too.
class SignatureChoice {
  final String? newEmail;

  /// For a reply or a forward.
  final String? reply;

  final Map<String, dynamic> _extra;

  const SignatureChoice({this.newEmail, this.reply}) : _extra = const {};

  const SignatureChoice._({this.newEmail, this.reply, required this._extra});

  factory SignatureChoice.fromJson(Map<String, dynamic> json) =>
      SignatureChoice._(
        newEmail: json['new'] as String?,
        reply: json['reply'] as String?,
        extra: Map.of(json)..removeWhere((key, _) => _fields.contains(key)),
      );

  static const _fields = {'new', 'reply'};

  Map<String, dynamic> toJson() => {
    ..._extra,
    'new': ?newEmail,
    'reply': ?reply,
  };

  SignatureChoice copyWith({
    String? newEmail,
    String? reply,
    bool clearNewEmail = false,
    bool clearReply = false,
  }) => SignatureChoice._(
    newEmail: clearNewEmail ? null : (newEmail ?? this.newEmail),
    reply: clearReply ? null : (reply ?? this.reply),
    extra: _extra,
  );

  String? idFor({required bool reply}) => reply ? this.reply : newEmail;

  @override
  String toString() => 'SignatureChoice(new: $newEmail, reply: $reply)';
}
