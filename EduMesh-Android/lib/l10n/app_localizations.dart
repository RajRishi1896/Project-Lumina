import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('kn')
  ];

  /// Application branding title shown in the app bar and task switcher
  ///
  /// In en, this message translates to:
  /// **'Project Lumina'**
  String get appTitle;

  /// MaterialApp title used as the application name in the OS task switcher
  ///
  /// In en, this message translates to:
  /// **'Edu-Mesh Scholar'**
  String get materialAppTitle;

  /// Bottom navigation tab label for the dashboard page
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get bottomNavDashboard;

  /// Bottom navigation tab label for the search/browse page
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get bottomNavBrowse;

  /// Bottom navigation tab label for the saved resources page
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get bottomNavSaved;

  /// Bottom navigation tab label for the student profile page
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get bottomNavProfile;

  /// SnackBar shown when user presses back once; instructs to press again to exit the app
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get doubleBackToExitMessage;

  /// SnackBar action button to force-exit the app immediately
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exitButtonLabel;

  /// Main heading on the welcome page
  ///
  /// In en, this message translates to:
  /// **'Connected to Learning Hub'**
  String get welcomeTitle;

  /// Subtitle below the main heading explaining offline access
  ///
  /// In en, this message translates to:
  /// **'No Internet Needed. Access thousands of books and courses locally.'**
  String get welcomeSubtitle;

  /// Badge on the welcome illustration indicating the app works offline
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection Required!'**
  String get illustrationBadgeNoInternet;

  /// Section header for the language selection grid
  ///
  /// In en, this message translates to:
  /// **'SELECT LANGUAGE'**
  String get languageSectionHeader;

  /// Language button label for English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Language button label for Hindi
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get languageHindi;

  /// Language button label for Kannada
  ///
  /// In en, this message translates to:
  /// **'Kannada'**
  String get languageKannada;

  /// Language button label for Swahili
  ///
  /// In en, this message translates to:
  /// **'Kiswahili'**
  String get languageKiswahili;

  /// Language button label indicating additional language options exist
  ///
  /// In en, this message translates to:
  /// **'More...'**
  String get languageMore;

  /// Title of the language picker bottom sheet in settings
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get settingsLanguagePickerTitle;

  /// Call-to-action button text that navigates to the login page
  ///
  /// In en, this message translates to:
  /// **'Enter Portal'**
  String get ctaEnterPortal;

  /// Default label shown for hub connection strength while initial check is in progress
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get hubStrengthChecking;

  /// Hub strength status label when device is not connected to the hub
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get hubStrengthOffline;

  /// Hub strength status label when latency is under 50ms
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get hubStrengthExcellent;

  /// Hub strength status label when latency is between 50ms and 150ms
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get hubStrengthGood;

  /// Hub strength status label when latency exceeds 150ms
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get hubStrengthFair;

  /// Label for the hub connection strength status indicator
  ///
  /// In en, this message translates to:
  /// **'Hub Strength'**
  String get statusHubStrength;

  /// Label for the local storage usage status indicator
  ///
  /// In en, this message translates to:
  /// **'Local Storage'**
  String get statusLocalStorage;

  /// Default display text for storage values while computing
  ///
  /// In en, this message translates to:
  /// **'Calculating...'**
  String get storageCalculating;

  /// Fallback text when storage calculation fails
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get storageUnknown;

  /// Local storage used display when total is under 1024 MB
  ///
  /// In en, this message translates to:
  /// **'{size} MB Used'**
  String storageMbUsed(String size);

  /// Local storage used display when total is 1024 MB or more
  ///
  /// In en, this message translates to:
  /// **'{size} GB Used'**
  String storageGbUsed(String size);

  /// Total device capacity label in the storage section
  ///
  /// In en, this message translates to:
  /// **'{size} GB Total'**
  String storageTotalCapacity(String size);

  /// Total storage used label
  ///
  /// In en, this message translates to:
  /// **'{size} GB used'**
  String storageUsedLabel(String size);

  /// Unit suffix for values displayed in megabytes
  ///
  /// In en, this message translates to:
  /// **' MB'**
  String get unitMegabytes;

  /// Unit suffix for values displayed in gigabytes
  ///
  /// In en, this message translates to:
  /// **' GB'**
  String get unitGigabytes;

  /// Unit suffix for file sizes displayed in bytes
  ///
  /// In en, this message translates to:
  /// **' B'**
  String get unitBytes;

  /// Unit suffix for file sizes displayed in kilobytes
  ///
  /// In en, this message translates to:
  /// **' KB'**
  String get unitKilobytes;

  /// Legend label for app (EduMesh) storage usage in the storage bar
  ///
  /// In en, this message translates to:
  /// **'EduMesh'**
  String get storageLegendAppLabel;

  /// Legend label for other apps storage usage in the storage bar
  ///
  /// In en, this message translates to:
  /// **'Other Apps'**
  String get storageLegendOtherLabel;

  /// Legend label for free storage space in the storage bar
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get storageLegendFreeLabel;

  /// Server status badge text while connection check is in progress
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get serverStatusChecking;

  /// Server status badge text when server is reachable
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get serverStatusConnected;

  /// Server status badge text when server is unreachable
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get serverStatusDisconnected;

  /// Search bar placeholder text on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Search all resources...'**
  String get searchBarHint;

  /// Page title shown when the form is in registration mode
  ///
  /// In en, this message translates to:
  /// **'Create Scholar\nIdentity'**
  String get titleRegisterMode;

  /// Page title shown when the form is in login mode
  ///
  /// In en, this message translates to:
  /// **'Scholar\nLogin'**
  String get titleLoginMode;

  /// Page subtitle shown when the form is in registration mode
  ///
  /// In en, this message translates to:
  /// **'Start your journey on the Lumina Mesh'**
  String get subtitleRegisterMode;

  /// Page subtitle shown when the form is in login mode
  ///
  /// In en, this message translates to:
  /// **'Access your lessons from any device'**
  String get subtitleLoginMode;

  /// Label above the username text field
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get labelUsername;

  /// Hint text inside the username text field
  ///
  /// In en, this message translates to:
  /// **'e.g. john_doe'**
  String get hintUsername;

  /// Label above the password text field and hint text inside it
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get labelPassword;

  /// Label for the current password text field in the password reset dialog
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get labelCurrentPassword;

  /// Label for the new password text field in the password reset dialog
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get labelNewPassword;

  /// Label for the confirm password text field in the password reset dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get labelConfirmPassword;

  /// Helper text below the new password field specifying password rules
  ///
  /// In en, this message translates to:
  /// **'8+ characters, with uppercase, lowercase, and a digit'**
  String get hintPasswordRequirements;

  /// Submit button label when the form is in registration mode
  ///
  /// In en, this message translates to:
  /// **'Register & Sync'**
  String get buttonRegister;

  /// Submit button label when the form is in login mode
  ///
  /// In en, this message translates to:
  /// **'Login & Sync'**
  String get buttonLogin;

  /// Toggle button text shown in register mode to switch to login
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Login'**
  String get toggleToLogin;

  /// Toggle button text shown in login mode to switch to registration
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Register'**
  String get toggleToRegister;

  /// Connection badge text shown when the device is connected to the hub
  ///
  /// In en, this message translates to:
  /// **'Hub Connected'**
  String get badgeHubConnected;

  /// Connection badge text shown when the device is not connected to the hub
  ///
  /// In en, this message translates to:
  /// **'Waiting for Hub...'**
  String get badgeWaitingForHub;

  /// Confirm button in the password reset dialog to submit the new password
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get buttonSetPassword;

  /// Generic cancel button label used in dialogs and bottom sheets
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get buttonCancel;

  /// Title of the password reset dialog shown after a teacher-initiated password reset
  ///
  /// In en, this message translates to:
  /// **'Password Reset Required'**
  String get dialogPasswordResetTitle;

  /// Body text of the password reset dialog explaining why a password change is required
  ///
  /// In en, this message translates to:
  /// **'Your password was reset by a teacher. Enter your current password and set a new one.'**
  String get dialogPasswordResetBody;

  /// Validation error shown when username or password fields are empty
  ///
  /// In en, this message translates to:
  /// **'Please fill all fields'**
  String get errorFillAllFields;

  /// Validation error shown when password does not meet complexity requirements during registration
  ///
  /// In en, this message translates to:
  /// **'Password must be 8+ chars with uppercase, lowercase, and digit'**
  String get errorPasswordStrength;

  /// Error shown when the registration API call fails
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Check Hub connection.'**
  String get errorRegistrationFailed;

  /// SnackBar message shown when login succeeds but only local authentication was available
  ///
  /// In en, this message translates to:
  /// **'Logged in offline — server sync unavailable'**
  String get snackbarOfflineLogin;

  /// Error shown when the login API call fails due to invalid credentials
  ///
  /// In en, this message translates to:
  /// **'Login failed. Invalid name or password.'**
  String get errorLoginFailed;

  /// Validation error in the password reset dialog when the current password field is empty
  ///
  /// In en, this message translates to:
  /// **'Current password is required.'**
  String get errorCurrentPasswordRequired;

  /// Validation error when the new password is too short
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get errorPasswordMinLength;

  /// Validation error when new and confirm passwords differ
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get errorPasswordsDoNotMatch;

  /// Validation error when password lacks uppercase, lowercase, or digit
  ///
  /// In en, this message translates to:
  /// **'Password must contain upper, lower, and digit.'**
  String get errorPasswordComplexity;

  /// Error shown when the change-password API call fails
  ///
  /// In en, this message translates to:
  /// **'Failed to set password. Try again.'**
  String get errorPasswordChangeFailed;

  /// Title of the change-password dialog in account settings
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get dialogChangePasswordTitle;

  /// Body text in the change-password dialog explaining what to do
  ///
  /// In en, this message translates to:
  /// **'Enter your current password and a new one.'**
  String get dialogChangePasswordBody;

  /// Submit button label in the change-password dialog
  ///
  /// In en, this message translates to:
  /// **'Update Password'**
  String get buttonUpdatePassword;

  /// Success snackbar after a successful password change
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get snackbarPasswordChanged;

  /// Offline guidance message shown below the form when the Hub is unreachable
  ///
  /// In en, this message translates to:
  /// **'Connect to the Lumina Hub to register or log in.'**
  String get loginConnectToHub;

  /// Heading at the top of the profile setup page
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get profileSetupTitle;

  /// Subtitle below the heading on the profile setup page
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your profile'**
  String get profileSetupSubtitle;

  /// Label for the display name text field on the profile setup page
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get labelDisplayName;

  /// Submit button on the profile setup page to save and proceed to the main app
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get buttonContinue;

  /// Section header for recently viewed resources list
  ///
  /// In en, this message translates to:
  /// **'Recently Viewed'**
  String get sectionRecentlyViewed;

  /// Section header for subject category grid
  ///
  /// In en, this message translates to:
  /// **'Subject Categories'**
  String get sectionSubjectCategories;

  /// Empty state text when no subject categories are loaded
  ///
  /// In en, this message translates to:
  /// **'No subjects available'**
  String get emptyNoSubjects;

  /// Section header for device storage usage display
  ///
  /// In en, this message translates to:
  /// **'Local Storage'**
  String get sectionLocalStorage;

  /// AppBar title on the search/browse page
  ///
  /// In en, this message translates to:
  /// **'Browse Resources'**
  String get pageTitleBrowseResources;

  /// Hint text in the search field on the browse page
  ///
  /// In en, this message translates to:
  /// **'Search by title, subject, or grade...'**
  String get searchFieldHint;

  /// Label shown below search bar when filters are applied with default sort
  ///
  /// In en, this message translates to:
  /// **'Filters active'**
  String get filtersActiveLabel;

  /// Label shown when filters are active with a non-default sort
  ///
  /// In en, this message translates to:
  /// **'Filters active · Sorted: {sortBy}'**
  String filtersActiveSorted(String sortBy);

  /// Button text to reset all active filters
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFiltersButton;

  /// Section header for the full resource list when no search query and no filters
  ///
  /// In en, this message translates to:
  /// **'All Resources'**
  String get sectionAllResources;

  /// Section header for personalized resource recommendations
  ///
  /// In en, this message translates to:
  /// **'Recommended for You'**
  String get sectionRecommendedForYou;

  /// Empty state text when no resources exist at all
  ///
  /// In en, this message translates to:
  /// **'No resources available on the hub.'**
  String get emptyNoResources;

  /// Empty state text when search or filter yields no matches
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
  String get emptyNoSearchResults;

  /// Error message when server is unreachable and no local cache exists
  ///
  /// In en, this message translates to:
  /// **'Could not reach server. No cached resources available.'**
  String get errorNoServerNoCache;

  /// Button to retry loading resources after an error
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get errorRetryButton;

  /// Badge label on Kiwix (Wikipedia) resources in the resource list
  ///
  /// In en, this message translates to:
  /// **'WIKI'**
  String get badgeKiwixWiki;

  /// Title of the filter bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filterSheetTitle;

  /// Section header for resource type filter chips
  ///
  /// In en, this message translates to:
  /// **'Resource Type'**
  String get filterResourceTypeHeader;

  /// Label before grade filter choice chips
  ///
  /// In en, this message translates to:
  /// **'Show:'**
  String get filterShowLabel;

  /// Choice chip to filter resources by the student's own grade
  ///
  /// In en, this message translates to:
  /// **'My Grade'**
  String get filterMyGrade;

  /// Choice chip to clear grade filter and show all grades
  ///
  /// In en, this message translates to:
  /// **'All Grades'**
  String get filterAllGrades;

  /// Section header for grade filter chips
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get filterGradeHeader;

  /// Section header for subject filter text field
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get filterSubjectHeader;

  /// Hint text in the subject filter text field
  ///
  /// In en, this message translates to:
  /// **'Filter by subject...'**
  String get filterSubjectHint;

  /// Section header for sort order choice chips
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get filterSortByHeader;

  /// Sort chip for alphabetical ascending order by title
  ///
  /// In en, this message translates to:
  /// **'Title A-Z'**
  String get sortTitleAsc;

  /// Sort chip for alphabetical descending order by title
  ///
  /// In en, this message translates to:
  /// **'Title Z-A'**
  String get sortTitleDesc;

  /// Sort chip for ordering by resource type
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sortByType;

  /// Sort chip for ordering by grade level
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get sortByGrade;

  /// Button to clear all filter selections
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get filterResetButton;

  /// Button to apply current filter selections
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get filterApplyButton;

  /// SnackBar shown when resource is queued for download while offline
  ///
  /// In en, this message translates to:
  /// **'Added to queue — will download when server is reachable'**
  String get snackbarAddedToQueueOffline;

  /// SnackBar confirming a resource was added to the download queue
  ///
  /// In en, this message translates to:
  /// **'Added to download queue'**
  String get snackbarAddedToQueue;

  /// SnackBar confirming a download finished successfully
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get snackbarDownloadComplete;

  /// SnackBar shown when a download encounters an error
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get snackbarDownloadFailed;

  /// SnackBar confirming a download was deleted
  ///
  /// In en, this message translates to:
  /// **'Download removed'**
  String get snackbarDownloadRemoved;

  /// SnackBar confirming a resource was removed from saved/bookmarked
  ///
  /// In en, this message translates to:
  /// **'Removed from Saved'**
  String get snackbarRemovedFromSaved;

  /// SnackBar confirming a resource was added to saved/bookmarked
  ///
  /// In en, this message translates to:
  /// **'Added to Saved'**
  String get snackbarAddedToSaved;

  /// SnackBar when user taps an undownloaded resource while offline
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is not downloaded. Add it from the download button to save for offline access.'**
  String snackbarNotDownloaded(String title);

  /// Action button in the offline snackbar to queue the resource for download
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get snackbarQueueAction;

  /// Title of the download confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get dialogDownloadTitle;

  /// Download confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'Download \"{fileName}\"?\n\nSize: {sizeLabel}'**
  String dialogDownloadContent(String fileName, String sizeLabel);

  /// Confirm/Download button in the download confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get dialogDownloadButton;

  /// Fallback text when file size cannot be determined before download
  ///
  /// In en, this message translates to:
  /// **'size unavailable'**
  String get fileSizeUnavailable;

  /// Fallback text in download dialog when sizeLabel is null
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get fileSizeUnknownFallback;

  /// AppBar title on the resource detail page
  ///
  /// In en, this message translates to:
  /// **'{title} — {subject}'**
  String pageTitleDetail(String title, String subject);

  /// Empty state title when no resources match the filter type
  ///
  /// In en, this message translates to:
  /// **'No {title} available'**
  String emptyNoResourcesForType(String title);

  /// Empty state subtitle with subject and grade context
  ///
  /// In en, this message translates to:
  /// **'No resources found for {subject} in {grade}.'**
  String emptyNoResourcesDetail(String subject, String grade);

  /// Button to reload resources from the empty state
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get emptyRefreshButton;

  /// Subtitle text on each resource list item
  ///
  /// In en, this message translates to:
  /// **'{subject} • {grade}'**
  String resourceSubtitle(String subject, String grade);

  /// Card title for the Textbooks resource category
  ///
  /// In en, this message translates to:
  /// **'Textbooks'**
  String get resourceTypeTextbooks;

  /// Card subtitle description for Textbooks category
  ///
  /// In en, this message translates to:
  /// **'Chapter-wise PDFs and study materials'**
  String get resourceTypeTextbooksSubtitle;

  /// Card title for the Videos resource category
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get resourceTypeVideos;

  /// Card subtitle description for Videos category
  ///
  /// In en, this message translates to:
  /// **'Watch lessons and concept explanations'**
  String get resourceTypeVideosSubtitle;

  /// Card title for the Previous Year Questions resource category
  ///
  /// In en, this message translates to:
  /// **'PYQs'**
  String get resourceTypePyqs;

  /// Card subtitle description for PYQs category
  ///
  /// In en, this message translates to:
  /// **'Previous year papers and practice sets'**
  String get resourceTypePyqsSubtitle;

  /// Card title for the Notes resource category
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get resourceTypeNotes;

  /// Card subtitle description for Notes category
  ///
  /// In en, this message translates to:
  /// **'Quick revision notes and summaries'**
  String get resourceTypeNotesSubtitle;

  /// Button label on each resource category card to open its resources
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get resourceCardOpenButton;

  /// AppBar title at top of saved resources page
  ///
  /// In en, this message translates to:
  /// **'Saved Resources'**
  String get savedResourcesTitle;

  /// Tab label showing all saved resources
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tabAll;

  /// Tab label filtering saved textbooks
  ///
  /// In en, this message translates to:
  /// **'Textbooks'**
  String get tabTextbooks;

  /// Tab label filtering saved videos
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get tabVideos;

  /// Tab label filtering saved PYQs
  ///
  /// In en, this message translates to:
  /// **'PYQs'**
  String get tabPyqs;

  /// Tab label filtering saved notes
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get tabNotes;

  /// Empty state when the All tab has no saved resources
  ///
  /// In en, this message translates to:
  /// **'No saved resources yet.'**
  String get emptyStateAll;

  /// Empty state when a specific type tab has no saved items
  ///
  /// In en, this message translates to:
  /// **'No saved {type}s found.'**
  String emptyStateByType(String type);

  /// Page header title displayed at top of profile screen
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get headerMyProfile;

  /// Page header secondary label, shown next to a bar chart icon
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get headerAnalytics;

  /// Role badge label in the profile card
  ///
  /// In en, this message translates to:
  /// **'Student'**
  String get roleBadgeStudent;

  /// Fallback character shown inside the profile avatar when the student's name is empty
  ///
  /// In en, this message translates to:
  /// **'?'**
  String get initialsFallback;

  /// Title of the bottom sheet for editing profile information
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileSheetTitle;

  /// Label above the full-name text field in the edit profile sheet
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get editProfileLabelName;

  /// Label above the grade dropdown in the edit profile sheet
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get editProfileLabelGrade;

  /// Placeholder hint text in the grade dropdown when no grade is loaded yet
  ///
  /// In en, this message translates to:
  /// **'Select grade'**
  String get editProfileGradeHint;

  /// Label above the read-only student-ID field in the edit profile sheet
  ///
  /// In en, this message translates to:
  /// **'Student ID'**
  String get editProfileLabelStudentId;

  /// SnackBar shown when the profile update API call fails
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile: {error}'**
  String editProfileErrorSnackbar(String error);

  /// Elevated button label to submit profile edits
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get editProfileSaveButton;

  /// Stat card label for today's study minutes
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get statCardToday;

  /// Stat card label for this week's study time
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get statCardThisWeek;

  /// Stat card label for the count of saved/bookmarked resources
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get statCardSaved;

  /// Stat card label for consecutive-day streak count
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get statCardStreak;

  /// Section header above the subject-breakdown chart
  ///
  /// In en, this message translates to:
  /// **'Study Time by Subject'**
  String get sectionSubjectBreakdown;

  /// Section header above the recent-activity timeline
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get sectionRecentActivity;

  /// Empty-state message in the subject-breakdown section when no activity is recorded
  ///
  /// In en, this message translates to:
  /// **'No study data yet.\nYour subject time will appear here as you use the app.'**
  String get emptyStateSubjectBreakdown;

  /// Empty-state message in the recent-activity section when no history exists
  ///
  /// In en, this message translates to:
  /// **'No recent activity yet.\nStart browsing resources to see your activity here.'**
  String get emptyStateRecentActivity;

  /// Toggle label to collapse the activity list back to 5 items
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get toggleShowLess;

  /// Toggle label to expand the activity list showing the total count
  ///
  /// In en, this message translates to:
  /// **'Show All ({count})'**
  String toggleShowAll(int count);

  /// Minutes suffix appended to numeric values in stat cards
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get suffixMinutes;

  /// Hours suffix appended to numeric values in stat cards and subject breakdown
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get suffixHours;

  /// Days suffix with leading space appended to the streak count in the stat card
  ///
  /// In en, this message translates to:
  /// **' d'**
  String get suffixDays;

  /// Percent sign appended to subject-breakdown percentage values
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get suffixPercent;

  /// Past-tense verb in the activity feed for a view action
  ///
  /// In en, this message translates to:
  /// **'Viewed'**
  String get activityVerbViewed;

  /// Past-tense verb in the activity feed for a search action
  ///
  /// In en, this message translates to:
  /// **'Searched'**
  String get activityVerbSearched;

  /// Past-tense verb in the activity feed for a download action
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get activityVerbDownloaded;

  /// Past-tense verb in the activity feed for a watch action
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get activityVerbWatched;

  /// Past-tense verb in the activity feed for a save action
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get activityVerbSaved;

  /// Past-tense verb in the activity feed for an open action
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get activityVerbOpened;

  /// Past-tense verb in the activity feed for a complete action
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get activityVerbCompleted;

  /// Fallback activity title when the resource title is missing
  ///
  /// In en, this message translates to:
  /// **'{verb} a resource'**
  String activityTitleFallback(String verb);

  /// Relative timestamp label for events less than 1 minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relativeTimeJustNow;

  /// Relative timestamp pattern for minutes ago
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String relativeTimeMinutesAgo(int minutes);

  /// Relative timestamp pattern for hours ago with conditional plural
  ///
  /// In en, this message translates to:
  /// **'{hours} hour(s) ago'**
  String relativeTimeHoursAgo(int hours);

  /// Relative timestamp pattern for days ago with conditional plural
  ///
  /// In en, this message translates to:
  /// **'{days} day(s) ago'**
  String relativeTimeDaysAgo(int days);

  /// Relative timestamp pattern for months ago with conditional plural
  ///
  /// In en, this message translates to:
  /// **'{months} month(s) ago'**
  String relativeTimeMonthsAgo(int months);

  /// Header/title of the settings bottom sheet panel
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsSheetTitle;

  /// ListTile title for the language picker in settings
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// ListTile subtitle for the language picker in settings
  ///
  /// In en, this message translates to:
  /// **'Change app display language'**
  String get settingsLanguageSubtitle;

  /// Label on the theme toggle tile when dark mode is active
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkModeLabel;

  /// Label on the theme toggle tile when light mode is active
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightModeLabel;

  /// Subtitle under the theme toggle when dark mode is active
  ///
  /// In en, this message translates to:
  /// **'Switch to light theme'**
  String get switchToLightThemeSubtitle;

  /// Subtitle under the theme toggle when light mode is active
  ///
  /// In en, this message translates to:
  /// **'Switch to dark theme'**
  String get switchToDarkThemeSubtitle;

  /// ListTile title navigating to the offline library page
  ///
  /// In en, this message translates to:
  /// **'Storage & Offline Library'**
  String get storageOfflineLibraryTitle;

  /// ListTile subtitle describing the storage/offline library action
  ///
  /// In en, this message translates to:
  /// **'Manage downloaded content'**
  String get storageOfflineLibrarySubtitle;

  /// ListTile title to open system WiFi settings
  ///
  /// In en, this message translates to:
  /// **'Network Settings'**
  String get networkSettingsTitle;

  /// ListTile subtitle describing the network settings action
  ///
  /// In en, this message translates to:
  /// **'Configure Hub connectivity'**
  String get networkSettingsSubtitle;

  /// Red-colored ListTile title that triggers the logout flow
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOutButtonLabel;

  /// ListTile title for the account settings section in the settings sheet
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get settingsAccountTitle;

  /// ListTile subtitle when the Hub is reachable, indicating password change is available
  ///
  /// In en, this message translates to:
  /// **'Change your password'**
  String get settingsAccountSubtitleOnline;

  /// ListTile subtitle when the Hub is unreachable, prompting connection
  ///
  /// In en, this message translates to:
  /// **'Connect to Hub to manage account'**
  String get settingsAccountSubtitleOffline;

  /// AppBar title for the offline library page
  ///
  /// In en, this message translates to:
  /// **'Offline Library'**
  String get offlineLibraryAppBarTitle;

  /// Empty state message shown when no resources have been downloaded
  ///
  /// In en, this message translates to:
  /// **'No downloaded resources'**
  String get emptyOfflineLibraryMessage;

  /// AlertDialog title shown when user taps delete on a downloaded resource
  ///
  /// In en, this message translates to:
  /// **'Delete Download'**
  String get deleteDownloadDialogTitle;

  /// AlertDialog body confirming deletion of a specific resource
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" from offline storage?'**
  String deleteDownloadConfirmation(String title);

  /// AlertDialog button to confirm deletion
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirmButtonLabel;

  /// Android notification channel name for download notifications
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadChannelName;

  /// Android notification channel description shown in system notification settings
  ///
  /// In en, this message translates to:
  /// **'Download completion notifications'**
  String get downloadChannelDescription;

  /// Title of the local notification shown when a download finishes
  ///
  /// In en, this message translates to:
  /// **'Download Complete'**
  String get downloadCompleteNotificationTitle;

  /// Body text of the download-complete notification
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" has been downloaded and saved to offline storage.'**
  String downloadCompleteNotificationBody(String title);

  /// Label for step 1 of the onboarding stepper
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get stepperStepWelcome;

  /// Label for step 2 of the onboarding stepper
  ///
  /// In en, this message translates to:
  /// **'Login/Register'**
  String get stepperStepLoginRegister;

  /// Label for step 3 of the onboarding stepper
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get stepperStepAccess;

  /// Label showing current page out of total pages in the PDF viewer
  ///
  /// In en, this message translates to:
  /// **'Pg {currentPage} of {totalPages}'**
  String pdfPageOfLabel(int currentPage, int totalPages);

  /// Hint text inside the page-jump text field
  ///
  /// In en, this message translates to:
  /// **'Enter page number'**
  String get pdfEnterPageNumberHint;

  /// Button label to navigate to a typed page number
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get pdfGoButton;

  /// Label below the page slider inviting user to tap for page picker
  ///
  /// In en, this message translates to:
  /// **'Tap to jump to page'**
  String get pdfTapToJumpLabel;

  /// Zoom level displayed as a percentage next to zoom +/- buttons
  ///
  /// In en, this message translates to:
  /// **'{zoomLevel}%'**
  String pdfZoomPercent(String zoomLevel);

  /// Error message when the local video file does not exist on disk
  ///
  /// In en, this message translates to:
  /// **'Local file not found'**
  String get videoLocalFileNotFound;

  /// Error message shown when video initialization fails
  ///
  /// In en, this message translates to:
  /// **'Failed to load video: {error}'**
  String videoFailedToLoad(String error);

  /// Tooltip on the picture-in-picture icon button in the app bar
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get videoMiniPlayerTooltip;

  /// Default app bar title when no title is provided for the Kiwix WebView
  ///
  /// In en, this message translates to:
  /// **'KNOWLEDGE BASE'**
  String get kiwixDefaultTitle;

  /// Fallback label shown on thumbnail for kiwix-type resources when no image is available
  ///
  /// In en, this message translates to:
  /// **'WIKI'**
  String get thumbnailWikiLabel;

  /// App bar title for the ZIM/Wikipedia browser page
  ///
  /// In en, this message translates to:
  /// **'Wikipedia'**
  String get zimAppBarTitle;

  /// Hint text in the search text field of the ZIM browser
  ///
  /// In en, this message translates to:
  /// **'Search Wikipedia articles...'**
  String get zimSearchHint;

  /// Empty state message when the initial article list has no content
  ///
  /// In en, this message translates to:
  /// **'No articles available on the server'**
  String get zimNoArticlesEmpty;

  /// Empty state message when a search returns no matching articles
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get zimNoResultsEmpty;

  /// Fallback display title when an article has no title in the API response
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get zimUntitledArticleFallback;

  /// Error message when the initial article list fails to load from the server
  ///
  /// In en, this message translates to:
  /// **'Failed to load articles: {error}'**
  String zimFailedToLoadArticles(String error);

  /// Error message when a search request fails
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String zimSearchFailed(String error);

  /// SnackBar error when opening an individual article fails
  ///
  /// In en, this message translates to:
  /// **'Failed to load article: {error}'**
  String zimFailedToLoadArticle(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'kn'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
