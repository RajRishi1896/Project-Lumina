/// Regular expressions used to validate password strength.
///
/// Shared between the login page and the settings sheet so the complexity
/// rules stay in sync with each other.
library;

/// Matches an uppercase Latin letter.
final RegExp upperCaseRegExp = RegExp(r'[A-Z]');

/// Matches a lowercase Latin letter.
final RegExp lowerCaseRegExp = RegExp(r'[a-z]');

/// Matches a decimal digit.
final RegExp digitRegExp = RegExp(r'[0-9]');