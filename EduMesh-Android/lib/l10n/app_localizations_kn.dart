// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class AppLocalizationsKn extends AppLocalizations {
  AppLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get appTitle => 'Project Lumina';

  @override
  String get materialAppTitle => 'Edu-Mesh Scholar';

  @override
  String get bottomNavDashboard => 'ಡ್ಯಾಶ್‌ಬೋರ್ಡ್';

  @override
  String get bottomNavBrowse => 'ಬ್ರೌಸ್';

  @override
  String get bottomNavSaved => 'ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get bottomNavProfile => 'ಪ್ರೊಫೈಲ್';

  @override
  String get doubleBackToExitMessage => 'ನಿರ್ಗಮಿಸಲು ಮತ್ತೆ ಹಿಂದಕ್ಕೆ ಒತ್ತಿರಿ';

  @override
  String get exitButtonLabel => 'ನಿರ್ಗಮಿಸು';

  @override
  String get welcomeTitle => 'ಲರ್ನಿಂಗ್ ಹಬ್‌ಗೆ ಸಂಪರ್ಕಿಸಲಾಗಿದೆ';

  @override
  String get welcomeSubtitle =>
      'ಇಂಟರ್ನೆಟ್ ಅಗತ್ಯವಿಲ್ಲ. ಸಾವಿರಾರು ಪುಸ್ತಕಗಳು ಮತ್ತು ಕೋರ್ಸ್‌ಗಳನ್ನು ಸ್ಥಳೀಯವಾಗಿ ಪ್ರವೇಶಿಸಿ.';

  @override
  String get illustrationBadgeNoInternet => 'ಇಂಟರ್ನೆಟ್ ಸಂಪರ್ಕದ ಅಗತ್ಯವಿಲ್ಲ!';

  @override
  String get languageSectionHeader => 'ಭಾಷೆ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get languageEnglish => 'ಇಂಗ್ಲಿಷ್';

  @override
  String get languageHindi => 'ಹಿಂದಿ';

  @override
  String get languageKannada => 'ಕನ್ನಡ';

  @override
  String get languageFrench => 'ಫ್ರೆಂಚ್';

  @override
  String get languageKiswahili => 'ಸ್ವಾಹಿಲಿ';

  @override
  String get languageMore => 'ಇನ್ನಷ್ಟು...';

  @override
  String get settingsLanguagePickerTitle => 'ಭಾಷೆ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get ctaEnterPortal => 'ಪೋರ್ಟಲ್ ಪ್ರವೇಶಿಸಿ';

  @override
  String get hubStrengthChecking => 'ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...';

  @override
  String get hubStrengthOffline => 'ಆಫ್‌ಲೈನ್';

  @override
  String get hubStrengthExcellent => 'ಅತ್ಯುತ್ತಮ';

  @override
  String get hubStrengthGood => 'ಉತ್ತಮ';

  @override
  String get hubStrengthFair => 'ಸಮಂಜಸ';

  @override
  String get statusHubStrength => 'ಹಬ್ ಸಾಮರ್ಥ್ಯ';

  @override
  String get statusLocalStorage => 'ಸ್ಥಳೀಯ ಸಂಗ್ರಹ';

  @override
  String get storageCalculating => 'ಲೆಕ್ಕಾಚಾರ ಮಾಡಲಾಗುತ್ತಿದೆ...';

  @override
  String get storageUnknown => 'ತಿಳಿದಿಲ್ಲ';

  @override
  String storageMbUsed(String size) {
    return '$size MB ಬಳಕೆ';
  }

  @override
  String storageGbUsed(String size) {
    return '$size GB ಬಳಕೆ';
  }

  @override
  String storageTotalCapacity(String size) {
    return '$size GB ಒಟ್ಟು';
  }

  @override
  String storageUsedLabel(String size) {
    return '$size GB ಬಳಕೆ';
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
  String get storageLegendOtherLabel => 'ಇತರ ಅಪ್ಲಿಕೇಶನ್‌ಗಳು';

  @override
  String get storageLegendFreeLabel => 'ಖಾಲಿ';

  @override
  String get serverStatusChecking => 'ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...';

  @override
  String get serverStatusConnected => 'ಸಂಪರ್ಕಿಸಲಾಗಿದೆ';

  @override
  String get serverStatusDisconnected => 'ಸಂಪರ್ಕ ಕಡಿತಗೊಂಡಿದೆ';

  @override
  String get searchBarHint => 'ಎಲ್ಲಾ ಸಂಪನ್ಮೂಲಗಳನ್ನು ಹುಡುಕಿ...';

  @override
  String get titleRegisterMode => 'ಸ್ಕಾಲರ್\nಗುರುತನ್ನು ರಚಿಸಿ';

  @override
  String get titleLoginMode => 'ಸ್ಕಾಲರ್\nಲಾಗಿನ್';

  @override
  String get subtitleRegisterMode =>
      'Lumina Mesh‌ನಲ್ಲಿ ನಿಮ್ಮ ಪ್ರಯಾಣ ಪ್ರಾರಂಭಿಸಿ';

  @override
  String get subtitleLoginMode => 'ಯಾವುದೇ ಸಾಧನದಿಂದ ನಿಮ್ಮ ಪಾಠಗಳನ್ನು ಪ್ರವೇಶಿಸಿ';

  @override
  String get labelUsername => 'ಬಳಕೆದಾರ ಹೆಸರು';

  @override
  String get hintUsername => 'ಉದಾ. john_doe';

  @override
  String get labelPassword => 'ಪಾಸ್‌ವರ್ಡ್';

  @override
  String get labelCurrentPassword => 'ಪ್ರಸ್ತುತ ಪಾಸ್‌ವರ್ಡ್';

  @override
  String get labelNewPassword => 'ಹೊಸ ಪಾಸ್‌ವರ್ಡ್';

  @override
  String get labelConfirmPassword => 'ಪಾಸ್‌ವರ್ಡ್ ದೃಢೀಕರಿಸಿ';

  @override
  String get hintPasswordRequirements =>
      '8+ ಅಕ್ಷರಗಳು, ದೊಡ್ಡಕ್ಷರ, ಸಣ್ಣಕ್ಷರ ಮತ್ತು ಒಂದು ಅಂಕೆಯ ಅಗತ್ಯವಿದೆ';

  @override
  String get buttonRegister => 'ನೋಂದಣಿ ಮತ್ತು ಸಿಂಕ್';

  @override
  String get buttonLogin => 'ಲಾಗಿನ್ ಮತ್ತು ಸಿಂಕ್';

  @override
  String get toggleToLogin => 'ಈಗಾಗಲೇ ಖಾತೆ ಇದೆಯೇ? ಲಾಗಿನ್ ಮಾಡಿ';

  @override
  String get toggleToRegister => 'ಖಾತೆ ಇಲ್ಲವೇ? ನೋಂದಣಿ ಮಾಡಿ';

  @override
  String get badgeHubConnected => 'ಹಬ್‌ಗೆ ಸಂಪರ್ಕಿಸಲಾಗಿದೆ';

  @override
  String get badgeWaitingForHub => 'ಹಬ್‌ಗಾಗಿ ಕಾಯಲಾಗುತ್ತಿದೆ...';

  @override
  String get buttonSetPassword => 'ಪಾಸ್‌ವರ್ಡ್ ಹೊಂದಿಸಿ';

  @override
  String get buttonCancel => 'ರದ್ದುಮಾಡಿ';

  @override
  String get dialogPasswordResetTitle => 'ಪಾಸ್‌ವರ್ಡ್ ಮರುಹೊಂದಿಸುವಿಕೆ ಅಗತ್ಯವಿದೆ';

  @override
  String get dialogPasswordResetBody =>
      'ನಿಮ್ಮ ಪಾಸ್‌ವರ್ಡ್ ಅನ್ನು ಶಿಕ್ಷಕರು ಮರುಹೊಂದಿಸಿದ್ದಾರೆ. ನಿಮ್ಮ ಪ್ರಸ್ತುತ ಪಾಸ್‌ವರ್ಡ್ ನಮೂದಿಸಿ ಮತ್ತು ಹೊಸದನ್ನು ಹೊಂದಿಸಿ.';

  @override
  String get errorFillAllFields => 'ದಯವಿಟ್ಟು ಎಲ್ಲಾ ಕ್ಷೇತ್ರಗಳನ್ನು ಭರ್ತಿ ಮಾಡಿ';

  @override
  String get errorPasswordStrength =>
      'ಪಾಸ್‌ವರ್ಡ್ 8+ ಅಕ್ಷರಗಳು, ದೊಡ್ಡಕ್ಷರ, ಸಣ್ಣಕ್ಷರ ಮತ್ತು ಅಂಕೆಯನ್ನು ಹೊಂದಿರಬೇಕು';

  @override
  String get errorRegistrationFailed =>
      'ನೋಂದಣಿ ವಿಫಲವಾಗಿದೆ. ಹಬ್ ಸಂಪರ್ಕ ಪರಿಶೀಲಿಸಿ.';

  @override
  String get snackbarOfflineLogin =>
      'ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಲಾಗಿನ್ ಮಾಡಲಾಗಿದೆ — ಸರ್ವರ್ ಸಿಂಕ್ ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get errorLoginFailed =>
      'ಲಾಗಿನ್ ವಿಫಲವಾಗಿದೆ. ಹೆಸರು ಅಥವಾ ಪಾಸ್‌ವರ್ಡ್ ತಪ್ಪಾಗಿದೆ.';

  @override
  String get errorCurrentPasswordRequired => 'ಪ್ರಸ್ತುತ ಪಾಸ್‌ವರ್ಡ್ ಅಗತ್ಯವಿದೆ.';

  @override
  String get errorPasswordMinLength => 'ಪಾಸ್‌ವರ್ಡ್ ಕನಿಷ್ಠ 8 ಅಕ್ಷರಗಳಾಗಿರಬೇಕು.';

  @override
  String get errorPasswordsDoNotMatch => 'ಪಾಸ್‌ವರ್ಡ್‌ಗಳು ಹೊಂದಿಕೆಯಾಗುವುದಿಲ್ಲ.';

  @override
  String get errorPasswordComplexity =>
      'ಪಾಸ್‌ವರ್ಡ್ ದೊಡ್ಡಕ್ಷರ, ಸಣ್ಣಕ್ಷರ ಮತ್ತು ಅಂಕೆಯನ್ನು ಹೊಂದಿರಬೇಕು.';

  @override
  String get errorPasswordChangeFailed =>
      'ಪಾಸ್‌ವರ್ಡ್ ಹೊಂದಿಸಲು ವಿಫಲವಾಗಿದೆ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get dialogChangePasswordTitle => 'ಪಾಸ್‌ವರ್ಡ್ ಬದಲಾಯಿಸಿ';

  @override
  String get dialogChangePasswordBody =>
      'ನಿಮ್ಮ ಪ್ರಸ್ತುತ ಪಾಸ್‌ವರ್ಡ್ ಮತ್ತು ಹೊಸ ಪಾಸ್‌ವರ್ಡ್ ನಮೂದಿಸಿ.';

  @override
  String get buttonUpdatePassword => 'ಪಾಸ್‌ವರ್ಡ್ ಅಪ್‌ಡೇಟ್ ಮಾಡಿ';

  @override
  String get snackbarPasswordChanged => 'ಪಾಸ್‌ವರ್ಡ್ ಯಶಸ್ವಿಯಾಗಿ ಬದಲಾಯಿಸಲಾಗಿದೆ';

  @override
  String get loginConnectToHub =>
      'ನೋಂದಣಿ ಅಥವಾ ಲಾಗಿನ್‌ಗಾಗಿ Lumina Hub‌ಗೆ ಸಂಪರ್ಕಿಸಿ.';

  @override
  String get profileSetupTitle => 'ಸ್ವಾಗತ!';

  @override
  String get profileSetupSubtitle => 'ನಿಮ್ಮ ಪ್ರೊಫೈಲ್ ಹೊಂದಿಸೋಣ';

  @override
  String get labelDisplayName => 'ಪ್ರದರ್ಶನ ಹೆಸರು';

  @override
  String get buttonContinue => 'ಮುಂದುವರಿಸಿ';

  @override
  String get sectionRecentlyViewed => 'ಇತ್ತೀಚೆಗೆ ವೀಕ್ಷಿಸಲಾಗಿದೆ';

  @override
  String get sectionSubjectCategories => 'ವಿಷಯ ವರ್ಗಗಳು';

  @override
  String get emptyNoSubjects => 'ಯಾವುದೇ ವಿಷಯಗಳು ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get sectionLocalStorage => 'ಸ್ಥಳೀಯ ಸಂಗ್ರಹ';

  @override
  String get pageTitleBrowseResources => 'ಸಂಪನ್ಮೂಲಗಳನ್ನು ಬ್ರೌಸ್ ಮಾಡಿ';

  @override
  String get searchFieldHint => 'ಶೀರ್ಷಿಕೆ, ವಿಷಯ ಅಥವಾ ತರಗತಿಯಿಂದ ಹುಡುಕಿ...';

  @override
  String get filtersActiveLabel => 'ಫಿಲ್ಟರ್‌ಗಳು ಸಕ್ರಿಯ';

  @override
  String filtersActiveSorted(String sortBy) {
    return 'ಫಿಲ್ಟರ್‌ಗಳು ಸಕ್ರಿಯ · ವಿಂಗಡಿಸಲಾಗಿದೆ: $sortBy';
  }

  @override
  String get clearFiltersButton => 'ಫಿಲ್ಟರ್‌ಗಳನ್ನು ತೆರವುಗೊಳಿಸಿ';

  @override
  String get sectionAllResources => 'ಎಲ್ಲಾ ಸಂಪನ್ಮೂಲಗಳು';

  @override
  String get sectionRecommendedForYou => 'ನಿಮಗಾಗಿ ಶಿಫಾರಸು ಮಾಡಲಾಗಿದೆ';

  @override
  String get emptyNoResources => 'ಹಬ್‌ನಲ್ಲಿ ಯಾವುದೇ ಸಂಪನ್ಮೂಲಗಳು ಲಭ್ಯವಿಲ್ಲ.';

  @override
  String get emptyNoSearchResults => 'ಯಾವುದೇ ಫಲಿತಾಂಶಗಳಿಲ್ಲ.';

  @override
  String get errorNoServerNoCache =>
      'ಸರ್ವರ್ ತಲುಪಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ. ಯಾವುದೇ ಕ್ಯಾಶ್ ಮಾಡಿದ ಸಂಪನ್ಮೂಲಗಳಿಲ್ಲ.';

  @override
  String get errorRetryButton => 'ಮರುಪ್ರಯತ್ನಿಸಿ';

  @override
  String get badgeKiwixWiki => 'ವಿಕಿ';

  @override
  String get filterSheetTitle => 'ಫಿಲ್ಟರ್';

  @override
  String get filterResourceTypeHeader => 'ಸಂಪನ್ಮೂಲ ಪ್ರಕಾರ';

  @override
  String get filterShowLabel => 'ತೋರಿಸು:';

  @override
  String get filterMyGrade => 'ನನ್ನ ತರಗತಿ';

  @override
  String get filterAllGrades => 'ಎಲ್ಲಾ ತರಗತಿಗಳು';

  @override
  String get filterGradeHeader => 'ತರಗತಿ';

  @override
  String get filterSubjectHeader => 'ವಿಷಯ';

  @override
  String get filterSubjectHint => 'ವಿಷಯದಿಂದ ಫಿಲ್ಟರ್ ಮಾಡಿ...';

  @override
  String get filterSortByHeader => 'ವಿಂಗಡಿಸಿ';

  @override
  String get sortTitleAsc => 'ಶೀರ್ಷಿಕೆ A-Z';

  @override
  String get sortTitleDesc => 'ಶೀರ್ಷಿಕೆ Z-A';

  @override
  String get sortByType => 'ಪ್ರಕಾರ';

  @override
  String get sortByGrade => 'ತರಗತಿ';

  @override
  String get filterResetButton => 'ಮರುಹೊಂದಿಸಿ';

  @override
  String get filterApplyButton => 'ಅನ್ವಯಿಸು';

  @override
  String get snackbarAddedToQueueOffline =>
      'ಕ್ಯೂಗೆ ಸೇರಿಸಲಾಗಿದೆ — ಸರ್ವರ್ ತಲುಪಿದಾಗ ಡೌನ್‌ಲೋಡ್ ಆಗುತ್ತದೆ';

  @override
  String get snackbarAddedToQueue => 'ಡೌನ್‌ಲೋಡ್ ಕ್ಯೂಗೆ ಸೇರಿಸಲಾಗಿದೆ';

  @override
  String get snackbarDownloadComplete => 'ಡೌನ್‌ಲೋಡ್ ಪೂರ್ಣಗೊಂಡಿದೆ';

  @override
  String get snackbarDownloadFailed => 'ಡೌನ್‌ಲೋಡ್ ವಿಫಲವಾಗಿದೆ';

  @override
  String get snackbarDownloadRemoved => 'ಡೌನ್‌ಲೋಡ್ ತೆಗೆದುಹಾಕಲಾಗಿದೆ';

  @override
  String get snackbarRemovedFromSaved => 'ಉಳಿಸಿದವುಗಳಿಂದ ತೆಗೆದುಹಾಕಲಾಗಿದೆ';

  @override
  String get snackbarAddedToSaved => 'ಉಳಿಸಿದವುಗಳಿಗೆ ಸೇರಿಸಲಾಗಿದೆ';

  @override
  String snackbarNotDownloaded(String title) {
    return '\"$title\" ಡೌನ್‌ಲೋಡ್ ಆಗಿಲ್ಲ. ಆಫ್‌ಲೈನ್ ಪ್ರವೇಶಕ್ಕಾಗಿ ಡೌನ್‌ಲೋಡ್ ಬಟನ್‌ನಿಂದ ಸೇರಿಸಿ.';
  }

  @override
  String get snackbarQueueAction => 'ಕ್ಯೂ';

  @override
  String get dialogDownloadTitle => 'ಡೌನ್‌ಲೋಡ್';

  @override
  String dialogDownloadContent(String fileName, String sizeLabel) {
    return '\"$fileName\" ಡೌನ್‌ಲೋಡ್ ಮಾಡಬೇಕೆ?\n\nಗಾತ್ರ: $sizeLabel';
  }

  @override
  String get dialogDownloadButton => 'ಡೌನ್‌ಲೋಡ್';

  @override
  String get fileSizeUnavailable => 'ಗಾತ್ರ ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get fileSizeUnknownFallback => 'ತಿಳಿದಿಲ್ಲ';

  @override
  String pageTitleDetail(String title, String subject) {
    return '$title — $subject';
  }

  @override
  String emptyNoResourcesForType(String title) {
    return 'ಯಾವುದೇ $title ಲಭ್ಯವಿಲ್ಲ';
  }

  @override
  String emptyNoResourcesDetail(String subject, String grade) {
    return '$subject ನಲ್ಲಿ $grade ಗೆ ಯಾವುದೇ ಸಂಪನ್ಮೂಲಗಳಿಲ್ಲ.';
  }

  @override
  String get emptyRefreshButton => 'ರಿಫ್ರೆಶ್';

  @override
  String resourceSubtitle(String subject, String grade) {
    return '$subject • $grade';
  }

  @override
  String get resourceTypeTextbooks => 'ಪಠ್ಯಪುಸ್ತಕಗಳು';

  @override
  String get resourceTypeTextbooksSubtitle =>
      'ಅಧ್ಯಾಯವಾರು PDF ಮತ್ತು ಅಧ್ಯಯನ ಸಾಮಗ್ರಿ';

  @override
  String get resourceTypeVideos => 'ವೀಡಿಯೊಗಳು';

  @override
  String get resourceTypeVideosSubtitle =>
      'ಪಾಠಗಳು ಮತ್ತು ಪರಿಕಲ್ಪನೆ ವಿವರಣೆಗಳನ್ನು ವೀಕ್ಷಿಸಿ';

  @override
  String get resourceTypePyqs => 'ಹಿಂದಿನ ವರ್ಷದ ಪ್ರಶ್ನೆಗಳು';

  @override
  String get resourceTypePyqsSubtitle =>
      'ಹಿಂದಿನ ವರ್ಷದ ಪ್ರಶ್ನೆಪತ್ರಿಕೆಗಳು ಮತ್ತು ಅಭ್ಯಾಸ ಸೆಟ್‌ಗಳು';

  @override
  String get resourceTypeNotes => 'ಟಿಪ್ಪಣಿಗಳು';

  @override
  String get resourceTypeNotesSubtitle =>
      'ತ್ವರಿತ ಪುನರಾವರ್ತನೆ ಟಿಪ್ಪಣಿಗಳು ಮತ್ತು ಸಾರಾಂಶಗಳು';

  @override
  String get resourceCardOpenButton => 'ತೆರೆಯಿರಿ';

  @override
  String get savedResourcesTitle => 'ಉಳಿಸಿದ ಸಂಪನ್ಮೂಲಗಳು';

  @override
  String get tabAll => 'ಎಲ್ಲಾ';

  @override
  String get tabTextbooks => 'ಪಠ್ಯಪುಸ್ತಕಗಳು';

  @override
  String get tabVideos => 'ವೀಡಿಯೊಗಳು';

  @override
  String get tabPyqs => 'ಪ್ರಶ್ನೆಗಳು';

  @override
  String get tabNotes => 'ಟಿಪ್ಪಣಿಗಳು';

  @override
  String get emptyStateAll => 'ಇನ್ನೂ ಯಾವುದೇ ಸಂಪನ್ಮೂಲಗಳನ್ನು ಉಳಿಸಲಾಗಿಲ್ಲ.';

  @override
  String emptyStateByType(String type) {
    return 'ಯಾವುದೇ $type ಉಳಿಸಲಾಗಿಲ್ಲ.';
  }

  @override
  String get headerMyProfile => 'ನನ್ನ ಪ್ರೊಫೈಲ್';

  @override
  String get headerAnalytics => 'ವಿಶ್ಲೇಷಣೆ';

  @override
  String get roleBadgeStudent => 'ವಿದ್ಯಾರ್ಥಿ';

  @override
  String get initialsFallback => '?';

  @override
  String get editProfileSheetTitle => 'ಪ್ರೊಫೈಲ್ ಸಂಪಾದಿಸಿ';

  @override
  String get editProfileLabelName => 'ಪೂರ್ಣ ಹೆಸರು';

  @override
  String get editProfileLabelGrade => 'ತರಗತಿ';

  @override
  String get editProfileGradeHint => 'ತರಗತಿ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get editProfileLabelStudentId => 'ವಿದ್ಯಾರ್ಥಿ ಐಡಿ';

  @override
  String editProfileErrorSnackbar(String error) {
    return 'ಪ್ರೊಫೈಲ್ ಅಪ್‌ಡೇಟ್ ವಿಫಲ: $error';
  }

  @override
  String get editProfileSaveButton => 'ಬದಲಾವಣೆಗಳನ್ನು ಉಳಿಸಿ';

  @override
  String get statCardToday => 'ಇಂದು';

  @override
  String get statCardThisWeek => 'ಈ ವಾರ';

  @override
  String get statCardSaved => 'ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get statCardStreak => 'ಸ್ಟ್ರೀಕ್';

  @override
  String get sectionSubjectBreakdown => 'ವಿಷಯದ ಪ್ರಕಾರ ಅಧ್ಯಯನ ಸಮಯ';

  @override
  String get sectionRecentActivity => 'ಇತ್ತೀಚಿನ ಚಟುವಟಿಕೆ';

  @override
  String get emptyStateSubjectBreakdown =>
      'ಇನ್ನೂ ಯಾವುದೇ ದತ್ತಾಂಶವಿಲ್ಲ.\nನೀವು ಅಪ್ಲಿಕೇಶನ್ ಬಳಸಿದಂತೆ ನಿಮ್ಮ ವಿಷಯ ಸಮಯ ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತದೆ.';

  @override
  String get emptyStateRecentActivity =>
      'ಇನ್ನೂ ಯಾವುದೇ ಚಟುವಟಿಕೆಯಿಲ್ಲ.\nಸಂಪನ್ಮೂಲಗಳನ್ನು ಬ್ರೌಸ್ ಮಾಡಲು ಪ್ರಾರಂಭಿಸಿ.';

  @override
  String get toggleShowLess => 'ಕಡಿಮೆ ತೋರಿಸು';

  @override
  String toggleShowAll(int count) {
    return 'ಎಲ್ಲವನ್ನು ತೋರಿಸು ($count)';
  }

  @override
  String get suffixMinutes => 'ನಿ';

  @override
  String get suffixHours => 'ಗಂ';

  @override
  String get suffixDays => ' ದಿ';

  @override
  String get suffixPercent => '%';

  @override
  String get activityVerbViewed => 'ವೀಕ್ಷಿಸಲಾಗಿದೆ';

  @override
  String get activityVerbSearched => 'ಹುಡುಕಲಾಗಿದೆ';

  @override
  String get activityVerbDownloaded => 'ಡೌನ್‌ಲೋಡ್ ಮಾಡಲಾಗಿದೆ';

  @override
  String get activityVerbWatched => 'ವೀಕ್ಷಿಸಲಾಗಿದೆ';

  @override
  String get activityVerbSaved => 'ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get activityVerbOpened => 'ತೆರೆಯಲಾಗಿದೆ';

  @override
  String get activityVerbCompleted => 'ಪೂರ್ಣಗೊಳಿಸಲಾಗಿದೆ';

  @override
  String activityTitleFallback(String verb) {
    return '$verb ಒಂದು ಸಂಪನ್ಮೂಲ';
  }

  @override
  String get relativeTimeJustNow => 'ಈಗಲೇ';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    return '$minutes ನಿಮಿಷ ಹಿಂದೆ';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ಗಂಟೆಗಳ ಹಿಂದೆ',
      one: '$hours ಗಂಟೆ ಹಿಂದೆ',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days ದಿನಗಳ ಹಿಂದೆ',
      one: '$days ದಿನ ಹಿಂದೆ',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeMonthsAgo(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months ತಿಂಗಳುಗಳ ಹಿಂದೆ',
      one: '$months ತಿಂಗಳ ಹಿಂದೆ',
    );
    return '$_temp0';
  }

  @override
  String get settingsSheetTitle => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get settingsLanguageTitle => 'ಭಾಷೆ';

  @override
  String get settingsLanguageSubtitle =>
      'ಅಪ್ಲಿಕೇಶನ್ ಪ್ರದರ್ಶನ ಭಾಷೆಯನ್ನು ಬದಲಾಯಿಸಿ';

  @override
  String get darkModeLabel => 'ಡಾರ್ಕ್ ಮೋಡ್';

  @override
  String get lightModeLabel => 'ಲೈಟ್ ಮೋಡ್';

  @override
  String get switchToLightThemeSubtitle => 'ಲೈಟ್ ಥೀಮ್‌ಗೆ ಬದಲಾಯಿಸಿ';

  @override
  String get switchToDarkThemeSubtitle => 'ಡಾರ್ಕ್ ಥೀಮ್‌ಗೆ ಬದಲಾಯಿಸಿ';

  @override
  String get appIconLabel => 'ಡಾರ್ಕ್ ಅಪ್ಲಿಕೇಶನ್ ಐಕಾನ್';

  @override
  String get appIconLightLabel => 'ಲೈಟ್ ಅಪ್ಲಿಕೇಶನ್ ಐಕಾನ್';

  @override
  String get appIconDarkSubtitle => 'ಡಾರ್ಕ್ ಲಾಂಚರ್ ಐಕಾನ್ ಬಳಸಿ';

  @override
  String get appIconLightSubtitle => 'ಲೈಟ್ ಲಾಂಚರ್ ಐಕಾನ್ ಬಳಸಿ';

  @override
  String get storageOfflineLibraryTitle => 'ಸಂಗ್ರಹ ಮತ್ತು ಆಫ್‌ಲೈನ್ ಗ್ರಂಥಾಲಯ';

  @override
  String get storageOfflineLibrarySubtitle =>
      'ಡೌನ್‌ಲೋಡ್ ಮಾಡಿದ ವಿಷಯವನ್ನು ನಿರ್ವಹಿಸಿ';

  @override
  String get networkSettingsTitle => 'ನೆಟ್‌ವರ್ಕ್ ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get networkSettingsSubtitle => 'ಹಬ್ ಸಂಪರ್ಕವನ್ನು ಕಾನ್ಫಿಗರ್ ಮಾಡಿ';

  @override
  String get logOutButtonLabel => 'ಲಾಗ್ ಔಟ್';

  @override
  String get settingsAccountTitle => 'ಖಾತೆ ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get settingsAccountSubtitleOnline => 'ನಿಮ್ಮ ಪಾಸ್‌ವರ್ಡ್ ಬದಲಾಯಿಸಿ';

  @override
  String get settingsAccountSubtitleOffline =>
      'ಖಾತೆ ನಿರ್ವಹಣೆಗಾಗಿ ಹಬ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ';

  @override
  String get offlineLibraryAppBarTitle => 'ಆಫ್‌ಲೈನ್ ಗ್ರಂಥಾಲಯ';

  @override
  String get emptyOfflineLibraryMessage =>
      'ಯಾವುದೇ ಡೌನ್‌ಲೋಡ್ ಮಾಡಿದ ಸಂಪನ್ಮೂಲಗಳಿಲ್ಲ';

  @override
  String get deleteDownloadDialogTitle => 'ಡೌನ್‌ಲೋಡ್ ಅಳಿಸಿ';

  @override
  String deleteDownloadConfirmation(String title) {
    return 'ಆಫ್‌ಲೈನ್ ಸಂಗ್ರಹದಿಂದ \"$title\" ಅಳಿಸಬೇಕೆ?';
  }

  @override
  String get deleteConfirmButtonLabel => 'ಅಳಿಸು';

  @override
  String get downloadChannelName => 'ಡೌನ್‌ಲೋಡ್‌ಗಳು';

  @override
  String get downloadChannelDescription => 'ಡೌನ್‌ಲೋಡ್ ಪೂರ್ಣಗೊಂಡ ಅಧಿಸೂಚನೆಗಳು';

  @override
  String get downloadCompleteNotificationTitle => 'ಡೌನ್‌ಲೋಡ್ ಪೂರ್ಣಗೊಂಡಿದೆ';

  @override
  String downloadCompleteNotificationBody(String title) {
    return '\"$title\" ಡೌನ್‌ಲೋಡ್ ಆಗಿ ಆಫ್‌ಲೈನ್ ಸಂಗ್ರಹಕ್ಕೆ ಉಳಿಸಲಾಗಿದೆ.';
  }

  @override
  String get downloadFailedNotificationTitle => 'ಡೌನ್‌ಲೋಡ್ ವಿಫಲವಾಗಿದೆ';

  @override
  String downloadFailedNotificationBody(String title) {
    return '\"$title\" ಡೌನ್‌ಲೋಡ್ ಆಗಲು ವಿಫಲವಾಗಿದೆ. ಸಂಪರ್ಕವನ್ನು ಪರಿಶೀಲಿಸಿ ಮತ್ತು ಮರುಪ್ರಯತ್ನಿಸಿ.';
  }

  @override
  String get stepperStepWelcome => 'ಸ್ವಾಗತ';

  @override
  String get stepperStepLoginRegister => 'ಲಾಗಿನ್/ನೋಂದಣಿ';

  @override
  String get stepperStepAccess => 'ಪ್ರವೇಶ';

  @override
  String pdfPageOfLabel(int currentPage, int totalPages) {
    return 'ಪು $currentPage / $totalPages';
  }

  @override
  String get pdfEnterPageNumberHint => 'ಪುಟ ಸಂಖ್ಯೆ ನಮೂದಿಸಿ';

  @override
  String get pdfGoButton => 'ಹೋಗು';

  @override
  String get pdfTapToJumpLabel => 'ಪುಟಕ್ಕೆ ಹೋಗಲು ಟ್ಯಾಪ್ ಮಾಡಿ';

  @override
  String pdfZoomPercent(String zoomLevel) {
    return '$zoomLevel%';
  }

  @override
  String get videoLocalFileNotFound => 'ಸ್ಥಳೀಯ ಫೈಲ್ ಕಂಡುಬಂದಿಲ್ಲ';

  @override
  String videoFailedToLoad(String error) {
    return 'ವೀಡಿಯೊ ಲೋಡ್ ವಿಫಲ: $error';
  }

  @override
  String get videoMiniPlayerTooltip => 'ಮಿನಿ ಪ್ಲೇಯರ್';

  @override
  String get kiwixDefaultTitle => 'ಜ್ಞಾನಕೋಶ';

  @override
  String get thumbnailWikiLabel => 'ವಿಕಿ';

  @override
  String get zimAppBarTitle => 'ವಿಕಿಪೀಡಿಯ';

  @override
  String get zimSearchHint => 'ವಿಕಿಪೀಡಿಯ ಲೇಖನಗಳನ್ನು ಹುಡುಕಿ...';

  @override
  String get zimNoArticlesEmpty => 'ಸರ್ವರ್‌ನಲ್ಲಿ ಯಾವುದೇ ಲೇಖನಗಳು ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get zimNoResultsEmpty => 'ಯಾವುದೇ ಫಲಿತಾಂಶಗಳಿಲ್ಲ';

  @override
  String get zimUntitledArticleFallback => 'ಶೀರ್ಷಿಕೆ ಇಲ್ಲ';

  @override
  String zimFailedToLoadArticles(String error) {
    return 'ಲೇಖನಗಳನ್ನು ಲೋಡ್ ಮಾಡಲು ವಿಫಲ: $error';
  }

  @override
  String zimSearchFailed(String error) {
    return 'ಹುಡುಕಾಟ ವಿಫಲ: $error';
  }

  @override
  String zimFailedToLoadArticle(String error) {
    return 'ಲೇಖನ ಲೋಡ್ ಮಾಡಲು ವಿಫಲ: $error';
  }

  @override
  String get dialogSetNameTitle => 'ನಿಮ್ಮ ಹೆಸರನ್ನು ಹೊಂದಿಸಿ';

  @override
  String get dialogSetNameBody =>
      'ದಯವಿಟ್ಟು ನಿಮ್ಮ ಅನುಭವವನ್ನು ವೈಯಕ್ತೀಕರಿಸಲು ಹೆಸರನ್ನು ನಮೂದಿಸಿ.';

  @override
  String get buttonSave => 'ಉಳಿಸು';

  @override
  String get buttonSkip => 'ಬಿಟ್ಟುಬಿಡಿ';

  @override
  String get bottomNavStudents => 'ವಿದ್ಯಾರ್ಥಿಗಳು';

  @override
  String get zimArticleNotFound => 'ಲೇಖನ ಕಂಡುಬಂದಿಲ್ಲ';

  @override
  String get teacherPageTitle => 'ವಿದ್ಯಾರ್ಥಿಗಳು';

  @override
  String get teacherFilterByGrade => 'ತರಗತಿಯಿಂದ ಫಿಲ್ಟರ್ ಮಾಡಿ';

  @override
  String get teacherAllGrades => 'ಎಲ್ಲಾ ತರಗತಿಗಳು';

  @override
  String get teacherCouldNotLoadStudents =>
      'ವಿದ್ಯಾರ್ಥಿಗಳನ್ನು ಲೋಡ್ ಮಾಡಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ';

  @override
  String get teacherCheckHubConnection =>
      'ಹಬ್ ಸಂಪರ್ಕ ಪರಿಶೀಲಿಸಿ ಮತ್ತು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get teacherRetry => 'ಮರುಪ್ರಯತ್ನಿಸಿ';

  @override
  String get teacherSearchStudentsHint => 'ವಿದ್ಯಾರ್ಥಿಗಳನ್ನು ಹುಡುಕಿ...';

  @override
  String get teacherNoStudentsMatchSearch =>
      'ನಿಮ್ಮ ಹುಡುಕಾಟಕ್ಕೆ ಹೊಂದುವ ಯಾವುದೇ ವಿದ್ಯಾರ್ಥಿಗಳಿಲ್ಲ.';

  @override
  String get teacherNoStudentsFound => 'ಯಾವುದೇ ವಿದ್ಯಾರ್ಥಿಗಳು ಕಂಡುಬಂದಿಲ್ಲ.';

  @override
  String teacherShowing(String grade) {
    return 'ತೋರಿಸಲಾಗುತ್ತಿದೆ: $grade';
  }

  @override
  String get teacherLabelToday => 'ಇಂದು';

  @override
  String get teacherLabelStreak => 'ಸ್ಟ್ರೀಕ್';

  @override
  String get teacherLabelSaved => 'ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get teacherLabelDownloaded => 'ಡೌನ್‌ಲೋಡ್';

  @override
  String get teacherOverview => 'ಅವಲೋಕನ';

  @override
  String get teacherThisMonth => 'ಈ ತಿಂಗಳು';

  @override
  String teacherShowMore(int remaining) {
    return 'ಇನ್ನಷ್ಟು ತೋರಿಸು ($remaining ಉಳಿದಿವೆ)';
  }

  @override
  String get teacherCouldNotLoadAnalytics =>
      'ವಿಶ್ಲೇಷಣೆ ಲೋಡ್ ಮಾಡಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ';

  @override
  String get teacherNoActivityRecorded => 'ಇನ್ನೂ ಯಾವುದೇ ಚಟುವಟಿಕೆ ದಾಖಲಾಗಿಲ್ಲ.';

  @override
  String get sectionSubjects => 'ವಿಷಯಗಳು';

  @override
  String get sectionSubjectsEmpty => 'ಯಾವುದೇ ವಿಷಯಗಳು ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get resourcePageResources => 'ಸಂಪನ್ಮೂಲಗಳು';

  @override
  String get showPassword => 'ಪಾಸ್‌ವರ್ಡ್ ತೋರಿಸಿ';

  @override
  String get hidePassword => 'ಪಾಸ್‌ವರ್ಡ್ ಮರೆಮಾಡಿ';

  @override
  String get semanticsSettings => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get semanticsSearchResources => 'ಸಂಪನ್ಮೂಲಗಳನ್ನು ಹುಡುಕಿ';

  @override
  String get semanticsFilterResources => 'ಸಂಪನ್ಮೂಲಗಳನ್ನು ಫಿಲ್ಟರ್ ಮಾಡಿ';

  @override
  String semanticsSelectLanguage(String label) {
    return 'ಭಾಷೆ ಆಯ್ಕೆಮಾಡಿ: $label';
  }

  @override
  String get semanticsOpenVideoPlayer => 'ವೀಡಿಯೊ ಪ್ಲೇಯರ್ ತೆರೆಯಿರಿ';

  @override
  String get semanticsCloseMiniPlayer => 'ಮಿನಿ ಪ್ಲೇಯರ್ ಮುಚ್ಚಿರಿ';

  @override
  String get semanticsTogglePlay => 'ಪ್ಲೇ ಟಾಗಲ್ ಮಾಡಿ';

  @override
  String get tooltipBackToResource => 'ಸಂಪನ್ಮೂಲಕ್ಕೆ ಹಿಂತಿರುಗಿ';

  @override
  String tooltipDeleteDownload(String title) {
    return '$title ಅಳಿಸಿ';
  }

  @override
  String get connectionOfflineBanner =>
      'ಆಫ್‌ಲೈನ್ — ಕೆಲವು ವೈಶಿಷ್ಟ್ಯಗಳು ಲಭ್ಯವಿಲ್ಲದಿರಬಹುದು';

  @override
  String get notificationDownloadFailedTitle => 'ಡೌನ್‌ಲೋಡ್ ವಿಫಲವಾಗಿದೆ';

  @override
  String notificationDownloadFailedBody(String title) {
    return '$title ಡೌನ್‌ಲೋಡ್ ಆಗಲಿಲ್ಲ. ನಿಮ್ಮ ಸಂಪರ್ಕ ಪರಿಶೀಲಿಸಿ ಮತ್ತು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';
  }

  @override
  String get studentNameUnknown => 'ತಿಳಿದಿಲ್ಲ';

  @override
  String activityPastTense(String verb) {
    return '$verbಲಾಗಿದೆ';
  }

  @override
  String storageAppSize(String size) {
    return '$size MB';
  }

  @override
  String get hubStrengthCalculating => 'ಲೆಕ್ಕಾಚಾರ ಮಾಡಲಾಗುತ್ತಿದೆ...';

  @override
  String get resourceFallbackTitle => 'Untitled';

  @override
  String get subjectFallbackGeneral => 'General';

  @override
  String get subjectNameUnknown => 'Unknown';
}
