const eventStatuses = ['Detected', 'In Progress', 'Resolved'];

String mergeEventStatus(String local, String remote) {
  final left = eventStatuses.indexOf(local);
  final right = eventStatuses.indexOf(remote);
  if (left < 0 || right < 0) throw ArgumentError('Unknown event status');
  return eventStatuses[left >= right ? left : right];
}

/// Returns the next status in the progression, or null if already at the end.
/// Used internally for sync conflict resolution.
String? nextEventStatus(String current) {
  final index = eventStatuses.indexOf(current);
  if (index < 0) throw ArgumentError('Unknown event status');
  return index == eventStatuses.length - 1 ? null : eventStatuses[index + 1];
}

/// Returns all statuses that can be selected for a given current status.
/// Unlike [nextEventStatus], this allows going back (e.g. Resolved -> Detected).
List<String> selectableStatuses(String current) => List.unmodifiable(eventStatuses);

/// Checks if [status] is a valid event status.
bool isValidStatus(String status) => eventStatuses.contains(status);
