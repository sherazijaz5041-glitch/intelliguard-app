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
/// Status transitions are strictly forward-only (Detected -> In Progress -> Resolved),
/// matching the Supabase ig_advance_event constraint. A resolved event cannot be reverted.
List<String> selectableStatuses(String current) {
  final index = eventStatuses.indexOf(current);
  if (index < 0) return List.unmodifiable(eventStatuses);
  return List.unmodifiable(eventStatuses.sublist(index));
}

/// Checks if transitioning from [from] status to [to] status is allowed.
/// Forward-only: Detected -> In Progress -> Resolved.
bool isStatusTransitionAllowed(String from, String to) {
  final fromIndex = eventStatuses.indexOf(from);
  final toIndex = eventStatuses.indexOf(to);
  if (fromIndex < 0 || toIndex < 0) return false;
  return toIndex >= fromIndex;
}

/// Checks if [status] is a valid event status.
bool isValidStatus(String status) => eventStatuses.contains(status);
