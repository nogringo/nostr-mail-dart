import '../models/email.dart';

/// Events emitted by the mail client watch stream
sealed class MailEvent {
  final DateTime timestamp;

  MailEvent({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();
}

/// A new email was received
class EmailReceived extends MailEvent {
  final Email email;

  EmailReceived({
    required this.email,
    super.timestamp,
  });

  @override
  String toString() => 'EmailReceived(id: ${email.id}, from: ${email.mime.fromEmail})';
}

/// A label was added to an email
class LabelAdded extends MailEvent {
  final String emailId;
  final String label;
  final String labelEventId;

  LabelAdded({
    required this.emailId,
    required this.label,
    required this.labelEventId,
    super.timestamp,
  });

  @override
  String toString() => 'LabelAdded(emailId: $emailId, label: $label)';
}

/// A label was removed from an email
class LabelRemoved extends MailEvent {
  final String emailId;
  final String label;

  LabelRemoved({required this.emailId, required this.label, super.timestamp});

  @override
  String toString() => 'LabelRemoved(emailId: $emailId, label: $label)';
}

/// An email was deleted
class EmailDeleted extends MailEvent {
  final String emailId;

  EmailDeleted({required this.emailId, super.timestamp});

  @override
  String toString() => 'EmailDeleted(emailId: $emailId)';
}
