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

/// How to read an image of the signatures: an AES-GCM encrypted blob on the
/// account's Blossom servers, keyed in the settings by its SHA-256.
class SignatureImage {
  /// Always `aes-gcm` for now.
  final String encryptionAlgorithm;

  /// Base64.
  final String decryptionKey;

  /// Base64.
  final String decryptionNonce;

  /// Media type of the decrypted image, such as `image/png`.
  final String mimeType;

  /// Size of the encrypted blob in bytes.
  final int size;

  /// Pixel size of the decrypted image, as `<width>x<height>`.
  final String? dim;

  final Map<String, dynamic> _extra;

  const SignatureImage({
    this.encryptionAlgorithm = 'aes-gcm',
    required this.decryptionKey,
    required this.decryptionNonce,
    required this.mimeType,
    required this.size,
    this.dim,
  }) : _extra = const {};

  const SignatureImage._({
    required this.encryptionAlgorithm,
    required this.decryptionKey,
    required this.decryptionNonce,
    required this.mimeType,
    required this.size,
    this.dim,
    required this._extra,
  });

  factory SignatureImage.fromJson(Map<String, dynamic> json) =>
      SignatureImage._(
        encryptionAlgorithm: json['encryption_algorithm'] as String,
        decryptionKey: json['decryption_key'] as String,
        decryptionNonce: json['decryption_nonce'] as String,
        mimeType: json['mime_type'] as String,
        size: (json['size'] as num).toInt(),
        dim: json['dim'] as String?,
        extra: Map.of(json)..removeWhere((key, _) => _fields.contains(key)),
      );

  static const _fields = {
    'encryption_algorithm',
    'decryption_key',
    'decryption_nonce',
    'mime_type',
    'size',
    'dim',
  };

  Map<String, dynamic> toJson() => {
    ..._extra,
    'encryption_algorithm': encryptionAlgorithm,
    'decryption_key': decryptionKey,
    'decryption_nonce': decryptionNonce,
    'mime_type': mimeType,
    'size': size,
    'dim': ?dim,
  };

  @override
  String toString() => 'SignatureImage(mimeType: $mimeType, size: $size)';
}
