// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Project Lumina';

  @override
  String get materialAppTitle => 'Edu-Mesh Scholar';

  @override
  String get bottomNavDashboard => 'Dashboard';

  @override
  String get bottomNavBrowse => 'Browse';

  @override
  String get bottomNavSaved => 'Saved';

  @override
  String get bottomNavProfile => 'Profile';

  @override
  String get doubleBackToExitMessage => 'Press back again to exit';

  @override
  String get exitButtonLabel => 'Exit';

  @override
  String get welcomeTitle => 'Connected to Learning Hub';

  @override
  String get welcomeSubtitle =>
      'No Internet Needed. Access thousands of books and courses locally.';

  @override
  String get illustrationBadgeNoInternet => 'No Internet Connection Required!';

  @override
  String get languageSectionHeader => 'SELECT LANGUAGE';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageKannada => 'Kannada';

  @override
  String get languageFrench => 'French';

  @override
  String get languageKiswahili => 'Kiswahili';

  @override
  String get languageMore => 'More...';

  @override
  String get settingsLanguagePickerTitle => 'Select Language';

  @override
  String get ctaEnterPortal => 'Enter Portal';

  @override
  String get hubStrengthChecking => 'Checking...';

  @override
  String get hubStrengthOffline => 'Offline';

  @override
  String get hubStrengthExcellent => 'Excellent';

  @override
  String get hubStrengthGood => 'Good';

  @override
  String get hubStrengthFair => 'Fair';

  @override
  String get statusHubStrength => 'Hub Strength';

  @override
  String get statusLocalStorage => 'Local Storage';

  @override
  String get storageCalculating => 'Calculating...';

  @override
  String get storageUnknown => 'Unknown';

  @override
  String storageMbUsed(String size) {
    return '$size MB Used';
  }

  @override
  String storageGbUsed(String size) {
    return '$size GB Used';
  }

  @override
  String storageTotalCapacity(String size) {
    return '$size GB Total';
  }

  @override
  String storageUsedLabel(String size) {
    return '$size GB used';
  }

  @override
  String get unitMegabytes => ' MB';

  @override
  String get unitGigabytes => ' GB';

  @override
  String get unitBytes => ' B';

  @override
  String get unitKilobytes => ' KB';

  @override
  String get storageLegendAppLabel => 'EduMesh';

  @override
  String get storageLegendOtherLabel => 'Other Apps';

  @override
  String get storageLegendFreeLabel => 'Free';

  @override
  String get serverStatusChecking => 'Checking...';

  @override
  String get serverStatusConnected => 'Connected';

  @override
  String get serverStatusDisconnected => 'Disconnected';

  @override
  String get searchBarHint => 'Search all resources...';

  @override
  String get titleRegisterMode => 'Create Scholar\nIdentity';

  @override
  String get titleLoginMode => 'Scholar\nLogin';

  @override
  String get subtitleRegisterMode => 'Start your journey on the Lumina Mesh';

  @override
  String get subtitleLoginMode => 'Access your lessons from any device';

  @override
  String get labelUsername => 'Username';

  @override
  String get hintUsername => 'e.g. john_doe';

  @override
  String get labelPassword => 'Password';

  @override
  String get labelCurrentPassword => 'Current Password';

  @override
  String get labelNewPassword => 'New Password';

  @override
  String get labelConfirmPassword => 'Confirm Password';

  @override
  String get hintPasswordRequirements =>
      '8+ characters, with uppercase, lowercase, and a digit';

  @override
  String get buttonRegister => 'Register & Sync';

  @override
  String get buttonLogin => 'Login & Sync';

  @override
  String get toggleToLogin => 'Already have an account? Login';

  @override
  String get toggleToRegister => 'Don\'t have an account? Register';

  @override
  String get badgeHubConnected => 'Hub Connected';

  @override
  String get badgeWaitingForHub => 'Waiting for Hub...';

  @override
  String get buttonSetPassword => 'Set Password';

  @override
  String get buttonCancel => 'Cancel';

  @override
  String get dialogPasswordResetTitle => 'Password Reset Required';

  @override
  String get dialogPasswordResetBody =>
      'A teacher reset your password. Enter your current password and set a new one.';

  @override
  String get errorFillAllFields => 'Please fill all fields';

  @override
  String get errorPasswordStrength =>
      'Password must be 8 or more characters with capital letters, small letters, and a number';

  @override
  String get errorRegistrationFailed =>
      'Registration failed. Check Hub connection.';

  @override
  String get snackbarOfflineLogin =>
      'Logged in offline — cannot connect to hub to save changes';

  @override
  String get errorLoginFailed => 'Login failed. Invalid name or password.';

  @override
  String get errorCurrentPasswordRequired => 'Current password is required.';

  @override
  String get errorPasswordMinLength =>
      'Password must be at least 8 characters.';

  @override
  String get errorPasswordsDoNotMatch => 'Passwords do not match.';

  @override
  String get errorPasswordComplexity =>
      'Password must contain upper, lower, and digit.';

  @override
  String get errorPasswordChangeFailed => 'Failed to set password. Try again.';

  @override
  String get dialogChangePasswordTitle => 'Change Password';

  @override
  String get dialogChangePasswordBody =>
      'Enter your current password and a new one.';

  @override
  String get buttonUpdatePassword => 'Update Password';

  @override
  String get snackbarPasswordChanged => 'Password changed successfully';

  @override
  String get loginConnectToHub =>
      'Connect to the Lumina Hub to register or log in.';

  @override
  String get profileSetupTitle => 'Welcome!';

  @override
  String get profileSetupSubtitle => 'Let\'s set up your profile';

  @override
  String get labelDisplayName => 'Display Name';

  @override
  String get buttonContinue => 'Continue';

  @override
  String get sectionRecentlyViewed => 'Recently Viewed';

  @override
  String get sectionSubjectCategories => 'Subject Categories';

  @override
  String get emptyNoSubjects => 'No subjects available';

  @override
  String get sectionLocalStorage => 'Local Storage';

  @override
  String get pageTitleBrowseResources => 'Browse Resources';

  @override
  String get searchFieldHint => 'Search by title, subject, or grade...';

  @override
  String get filtersActiveLabel => 'Filters active';

  @override
  String filtersActiveSorted(String sortBy) {
    return 'Filters active · Sorted: $sortBy';
  }

  @override
  String get clearFiltersButton => 'Clear filters';

  @override
  String get sectionAllResources => 'All Resources';

  @override
  String get sectionRecommendedForYou => 'Recommended for You';

  @override
  String get emptyNoResources => 'No resources available on the hub.';

  @override
  String get emptyNoSearchResults => 'No results found.';

  @override
  String get errorNoServerNoCache =>
      'Could not reach server. No cached resources available.';

  @override
  String get errorRetryButton => 'Retry';

  @override
  String get badgeKiwixWiki => 'WIKI';

  @override
  String get filterSheetTitle => 'Filters';

  @override
  String get filterResourceTypeHeader => 'Resource Type';

  @override
  String get filterShowLabel => 'Show:';

  @override
  String get filterMyGrade => 'My Grade';

  @override
  String get filterAllGrades => 'All Grades';

  @override
  String get filterGradeHeader => 'Grade';

  @override
  String get filterSubjectHeader => 'Subject';

  @override
  String get filterSubjectHint => 'Filter by subject...';

  @override
  String get filterSortByHeader => 'Sort By';

  @override
  String get sortTitleAsc => 'Title A-Z';

  @override
  String get sortTitleDesc => 'Title Z-A';

  @override
  String get sortByType => 'Type';

  @override
  String get sortByGrade => 'Grade';

  @override
  String get filterResetButton => 'Reset';

  @override
  String get filterApplyButton => 'Apply';

  @override
  String get snackbarAddedToQueueOffline =>
      'Added to queue — will download when server is reachable';

  @override
  String get snackbarAddedToQueue => 'Added to download queue';

  @override
  String get snackbarDownloadComplete => 'Download complete';

  @override
  String get snackbarDownloadFailed => 'Download failed';

  @override
  String get snackbarDownloadRemoved => 'Download removed';

  @override
  String get snackbarRemovedFromSaved => 'Removed from Saved';

  @override
  String get snackbarAddedToSaved => 'Added to Saved';

  @override
  String snackbarNotDownloaded(String title) {
    return '\"$title\" is not downloaded. Add it from the download button to save for offline access.';
  }

  @override
  String get snackbarQueueAction => 'Queue';

  @override
  String get dialogDownloadTitle => 'Download';

  @override
  String dialogDownloadContent(String fileName, String sizeLabel) {
    return 'Download \"$fileName\"?\n\nSize: $sizeLabel';
  }

  @override
  String get dialogDownloadButton => 'Download';

  @override
  String get fileSizeUnavailable => 'size unavailable';

  @override
  String get fileSizeUnknownFallback => 'unknown';

  @override
  String pageTitleDetail(String title, String subject) {
    return '$title — $subject';
  }

  @override
  String emptyNoResourcesForType(String title) {
    return 'No $title available';
  }

  @override
  String emptyNoResourcesDetail(String subject, String grade) {
    return 'No resources found for $subject in $grade.';
  }

  @override
  String get emptyRefreshButton => 'Refresh';

  @override
  String resourceSubtitle(String subject, String grade) {
    return '$subject • $grade';
  }

  @override
  String get resourceTypeTextbooks => 'Textbooks';

  @override
  String get resourceTypeTextbooksSubtitle =>
      'Chapter-wise PDFs and study materials';

  @override
  String get resourceTypeVideos => 'Videos';

  @override
  String get resourceTypeVideosSubtitle =>
      'Watch lessons and concept explanations';

  @override
  String get resourceTypePyqs => 'PYQs';

  @override
  String get resourceTypePyqsSubtitle =>
      'Previous year papers and practice sets';

  @override
  String get resourceTypeNotes => 'Notes';

  @override
  String get resourceTypeNotesSubtitle => 'Quick revision notes and summaries';

  @override
  String get resourceCardOpenButton => 'Open';

  @override
  String get savedResourcesTitle => 'Saved Resources';

  @override
  String get tabAll => 'All';

  @override
  String get tabTextbooks => 'Textbooks';

  @override
  String get tabVideos => 'Videos';

  @override
  String get tabPyqs => 'PYQs';

  @override
  String get tabNotes => 'Notes';

  @override
  String get emptyStateAll => 'No saved resources yet.';

  @override
  String emptyStateByType(String type) {
    return 'No saved $type found.';
  }

  @override
  String get headerMyProfile => 'My Profile';

  @override
  String get headerAnalytics => 'Analytics';

  @override
  String get roleBadgeStudent => 'Student';

  @override
  String get initialsFallback => '?';

  @override
  String get editProfileSheetTitle => 'Edit Profile';

  @override
  String get editProfileLabelName => 'Full Name';

  @override
  String get editProfileLabelGrade => 'Grade';

  @override
  String get editProfileGradeHint => 'Select grade';

  @override
  String get editProfileLabelStudentId => 'Student ID';

  @override
  String editProfileErrorSnackbar(String error) {
    return 'Failed to update profile: $error';
  }

  @override
  String get editProfileSaveButton => 'Save Changes';

  @override
  String get statCardToday => 'Today';

  @override
  String get statCardThisWeek => 'This Week';

  @override
  String get statCardSaved => 'Saved';

  @override
  String get statCardStreak => 'Streak';

  @override
  String get sectionSubjectBreakdown => 'Study Time by Subject';

  @override
  String get sectionRecentActivity => 'Recent Activity';

  @override
  String get emptyStateSubjectBreakdown =>
      'No study data yet.\nYour subject time will appear here as you use the app.';

  @override
  String get emptyStateRecentActivity =>
      'No recent activity yet.\nStart browsing resources to see your activity here.';

  @override
  String get toggleShowLess => 'Show Less';

  @override
  String toggleShowAll(int count) {
    return 'Show All ($count)';
  }

  @override
  String get suffixMinutes => 'm';

  @override
  String get suffixHours => 'h';

  @override
  String get suffixDays => ' d';

  @override
  String get suffixPercent => '%';

  @override
  String get activityVerbViewed => 'Viewed';

  @override
  String get activityVerbSearched => 'Searched';

  @override
  String get activityVerbDownloaded => 'Downloaded';

  @override
  String get activityVerbWatched => 'Watched';

  @override
  String get activityVerbSaved => 'Saved';

  @override
  String get activityVerbOpened => 'Opened';

  @override
  String get activityVerbCompleted => 'Completed';

  @override
  String activityTitleFallback(String verb) {
    return '$verb a resource';
  }

  @override
  String get relativeTimeJustNow => 'Just now';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours ago',
      one: '$hours hour ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '$days day ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeMonthsAgo(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months ago',
      one: '$months month ago',
    );
    return '$_temp0';
  }

  @override
  String get settingsSheetTitle => 'Settings';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Change app display language';

  @override
  String get darkModeLabel => 'Dark Mode';

  @override
  String get lightModeLabel => 'Light Mode';

  @override
  String get switchToLightThemeSubtitle => 'Switch to light theme';

  @override
  String get switchToDarkThemeSubtitle => 'Switch to dark theme';

  @override
  String get appIconLabel => 'Dark App Icon';

  @override
  String get appIconLightLabel => 'Light App Icon';

  @override
  String get appIconDarkSubtitle => 'Use dark launcher icon';

  @override
  String get appIconLightSubtitle => 'Use light launcher icon';

  @override
  String get storageOfflineLibraryTitle => 'Storage & Offline Library';

  @override
  String get storageOfflineLibrarySubtitle => 'Manage downloaded content';

  @override
  String get networkSettingsTitle => 'Network Settings';

  @override
  String get networkSettingsSubtitle => 'Configure Hub connectivity';

  @override
  String get logOutButtonLabel => 'Log Out';

  @override
  String get settingsAccountTitle => 'Account Settings';

  @override
  String get settingsAccountSubtitleOnline => 'Change your password';

  @override
  String get settingsAccountSubtitleOffline =>
      'Connect to Hub to manage account';

  @override
  String get offlineLibraryAppBarTitle => 'Offline Library';

  @override
  String get emptyOfflineLibraryMessage => 'No downloaded resources';

  @override
  String get deleteDownloadDialogTitle => 'Delete Download';

  @override
  String deleteDownloadConfirmation(String title) {
    return 'Delete \"$title\" from offline storage?';
  }

  @override
  String get deleteConfirmButtonLabel => 'Delete';

  @override
  String get downloadChannelName => 'Downloads';

  @override
  String get downloadChannelDescription => 'Download completion notifications';

  @override
  String get downloadCompleteNotificationTitle => 'Download Complete';

  @override
  String downloadCompleteNotificationBody(String title) {
    return '\"$title\" has been downloaded and saved to offline storage.';
  }

  @override
  String get downloadFailedNotificationTitle => 'Download Failed';

  @override
  String downloadFailedNotificationBody(String title) {
    return '\"$title\" could not be downloaded. Check the server connection and try again.';
  }

  @override
  String get stepperStepWelcome => 'Welcome';

  @override
  String get stepperStepLoginRegister => 'Login/Register';

  @override
  String get stepperStepAccess => 'Access';

  @override
  String pdfPageOfLabel(int currentPage, int totalPages) {
    return 'Pg $currentPage of $totalPages';
  }

  @override
  String get pdfEnterPageNumberHint => 'Enter page number';

  @override
  String get pdfGoButton => 'Go';

  @override
  String get pdfTapToJumpLabel => 'Tap to jump to page';

  @override
  String pdfZoomPercent(String zoomLevel) {
    return '$zoomLevel%';
  }

  @override
  String get videoLocalFileNotFound => 'Local file not found';

  @override
  String videoFailedToLoad(String error) {
    return 'Failed to load video: $error';
  }

  @override
  String get videoMiniPlayerTooltip => 'Mini player';

  @override
  String get kiwixDefaultTitle => 'KNOWLEDGE BASE';

  @override
  String get thumbnailWikiLabel => 'WIKI';

  @override
  String get zimAppBarTitle => 'Wikipedia';

  @override
  String get zimSearchHint => 'Search Wikipedia articles...';

  @override
  String get zimNoArticlesEmpty => 'No articles available on the server';

  @override
  String get zimNoResultsEmpty => 'No results found';

  @override
  String get zimUntitledArticleFallback => 'Untitled';

  @override
  String zimFailedToLoadArticles(String error) {
    return 'Failed to load articles: $error';
  }

  @override
  String zimSearchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String zimFailedToLoadArticle(String error) {
    return 'Failed to load article: $error';
  }

  @override
  String get dialogSetNameTitle => 'Set Your Name';

  @override
  String get dialogSetNameBody =>
      'Please enter your name to personalize your experience.';

  @override
  String get buttonSave => 'Save';

  @override
  String get buttonSkip => 'Skip';

  @override
  String get bottomNavStudents => 'Students';

  @override
  String get zimArticleNotFound => 'Article not found';

  @override
  String get teacherPageTitle => 'Students';

  @override
  String get teacherFilterByGrade => 'Filter by grade';

  @override
  String get teacherAllGrades => 'All Grades';

  @override
  String get teacherCouldNotLoadStudents => 'Could not load students';

  @override
  String get teacherCheckHubConnection => 'Check hub connection and try again.';

  @override
  String get teacherRetry => 'Retry';

  @override
  String get teacherSearchStudentsHint => 'Search students...';

  @override
  String get teacherNoStudentsMatchSearch => 'No students match your search.';

  @override
  String get teacherNoStudentsFound => 'No students found.';

  @override
  String teacherShowing(String grade) {
    return 'Showing: $grade';
  }

  @override
  String get teacherLabelToday => 'today';

  @override
  String get teacherLabelStreak => 'streak';

  @override
  String get teacherLabelSaved => 'saved';

  @override
  String get teacherLabelDownloaded => 'downloaded';

  @override
  String get teacherOverview => 'Overview';

  @override
  String get teacherThisMonth => 'This Month';

  @override
  String teacherShowMore(int remaining) {
    return 'Show More ($remaining remaining)';
  }

  @override
  String get teacherCouldNotLoadAnalytics => 'Could not load analytics';

  @override
  String get teacherNoActivityRecorded => 'No activity recorded yet.';

  @override
  String get sectionSubjects => 'Subjects';

  @override
  String get sectionSubjectsEmpty => 'No subjects available';

  @override
  String get resourcePageResources => 'Resources';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get semanticsSettings => 'Settings';

  @override
  String get semanticsSearchResources => 'Search resources';

  @override
  String get semanticsFilterResources => 'Filter resources';

  @override
  String semanticsSelectLanguage(String label) {
    return 'Select language: $label';
  }

  @override
  String get semanticsOpenVideoPlayer => 'Open video player';

  @override
  String get semanticsCloseMiniPlayer => 'Close mini player';

  @override
  String get semanticsTogglePlay => 'Toggle play';

  @override
  String get tooltipBackToResource => 'Back to resource';

  @override
  String tooltipDeleteDownload(String title) {
    return 'Delete $title';
  }

  @override
  String get connectionOfflineBanner =>
      'Offline — some features may be unavailable';

  @override
  String get notificationDownloadFailedTitle => 'Download Failed';

  @override
  String notificationDownloadFailedBody(String title) {
    return '$title could not be downloaded. Check your connection and try again.';
  }

  @override
  String get studentNameUnknown => 'Unknown';

  @override
  String activityPastTense(String verb) {
    return '${verb}ed';
  }

  @override
  String storageAppSize(String size) {
    return '$size MB';
  }

  @override
  String get hubStrengthCalculating => 'Calculating...';

  @override
  String get resourceFallbackTitle => 'Untitled';

  @override
  String get subjectFallbackGeneral => 'General';

  @override
  String get subjectNameUnknown => 'Unknown';
}
