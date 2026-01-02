class Email {
  final String id;
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime date;
  final String senderPubkey;
  final String rawContent;

  Email({
    required this.id,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.date,
    required this.senderPubkey,
    required this.rawContent,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'subject': subject,
    'body': body,
    'date': date.toIso8601String(),
    'senderPubkey': senderPubkey,
    'rawContent': rawContent,
  };

  factory Email.fromJson(Map<String, dynamic> json) => Email(
    id: json['id'] as String,
    from: json['from'] as String,
    to: json['to'] as String,
    subject: json['subject'] as String,
    body: json['body'] as String,
    date: DateTime.parse(json['date'] as String),
    senderPubkey: json['senderPubkey'] as String,
    rawContent: json['rawContent'] as String,
  );

  @override
  String toString() =>
      'Email(id: $id, from: $from, to: $to, subject: $subject)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Email && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
