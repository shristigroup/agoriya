/// A failure as one short line for the server: the error, then the first few
/// frames of its stack trace, so a failure seen only in Firestore can be
/// traced to the line that threw it. Capped at [maxLength] characters.
String failureText(Object error, StackTrace stack, {int maxLength = 600, int frames = 4}) {
  final top = stack
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(frames)
      .join(' | ');
  final text = top.isEmpty ? error.toString() : '${error.toString()} @ $top';
  return text.length > maxLength ? text.substring(0, maxLength) : text;
}
