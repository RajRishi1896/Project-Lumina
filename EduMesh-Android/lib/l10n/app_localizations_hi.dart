// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'Project Lumina';

  @override
  String get materialAppTitle => 'Edu-Mesh Scholar';

  @override
  String get bottomNavDashboard => 'डैशबोर्ड';

  @override
  String get bottomNavBrowse => 'ब्राउज़ करें';

  @override
  String get bottomNavSaved => 'सहेजा गया';

  @override
  String get bottomNavProfile => 'प्रोफ़ाइल';

  @override
  String get doubleBackToExitMessage => 'बाहर निकलने के लिए फिर से पीछे दबाएं';

  @override
  String get exitButtonLabel => 'बाहर निकलें';

  @override
  String get welcomeTitle => 'लर्निंग हब से जुड़ा';

  @override
  String get welcomeSubtitle =>
      'इंटरनेट की ज़रूरत नहीं। हज़ारों किताबें और पाठ्यक्रम स्थानीय रूप से उपलब्ध।';

  @override
  String get illustrationBadgeNoInternet => 'इंटरनेट कनेक्शन की आवश्यकता नहीं!';

  @override
  String get languageSectionHeader => 'भाषा चुनें';

  @override
  String get languageEnglish => 'अंग्रेज़ी';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageKannada => 'कन्नड़';

  @override
  String get languageFrench => 'फ़्रेंच';

  @override
  String get languageKiswahili => 'स्वाहिली';

  @override
  String get languageMore => 'और...';

  @override
  String get settingsLanguagePickerTitle => 'भाषा चुनें';

  @override
  String get ctaEnterPortal => 'पोर्टल में प्रवेश करें';

  @override
  String get hubStrengthChecking => 'जाँच हो रही है...';

  @override
  String get hubStrengthOffline => 'ऑफ़लाइन';

  @override
  String get hubStrengthExcellent => 'उत्कृष्ट';

  @override
  String get hubStrengthGood => 'अच्छा';

  @override
  String get hubStrengthFair => 'ठीक';

  @override
  String get statusHubStrength => 'हब की क्षमता';

  @override
  String get statusLocalStorage => 'स्थानीय भंडारण';

  @override
  String get storageCalculating => 'गणना हो रही है...';

  @override
  String get storageUnknown => 'अज्ञात';

  @override
  String storageMbUsed(String size) {
    return '$size MB उपयोग';
  }

  @override
  String storageGbUsed(String size) {
    return '$size GB उपयोग';
  }

  @override
  String storageTotalCapacity(String size) {
    return '$size GB कुल';
  }

  @override
  String storageUsedLabel(String size) {
    return '$size GB उपयोग';
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
  String get storageLegendOtherLabel => 'अन्य ऐप्स';

  @override
  String get storageLegendFreeLabel => 'खाली';

  @override
  String get serverStatusChecking => 'जाँच हो रही है...';

  @override
  String get serverStatusConnected => 'जुड़ा';

  @override
  String get serverStatusDisconnected => 'डिस्कनेक्ट';

  @override
  String get searchBarHint => 'सभी संसाधन खोजें...';

  @override
  String get titleRegisterMode => 'स्कॉलर\nपहचान बनाएं';

  @override
  String get titleLoginMode => 'स्कॉलर\nलॉगिन';

  @override
  String get subtitleRegisterMode => 'Lumina Mesh पर अपनी यात्रा शुरू करें';

  @override
  String get subtitleLoginMode => 'किसी भी डिवाइस से अपने पाठों तक पहुंचें';

  @override
  String get labelUsername => 'उपयोगकर्ता नाम';

  @override
  String get hintUsername => 'जैसे john_doe';

  @override
  String get labelPassword => 'पासवर्ड';

  @override
  String get labelCurrentPassword => 'वर्तमान पासवर्ड';

  @override
  String get labelNewPassword => 'नया पासवर्ड';

  @override
  String get labelConfirmPassword => 'पासवर्ड की पुष्टि करें';

  @override
  String get hintPasswordRequirements =>
      '8+ अक्षर, अपरकेस, लोअरकेस और एक अंक आवश्यक';

  @override
  String get buttonRegister => 'पंजीकरण और सिंक';

  @override
  String get buttonLogin => 'लॉगिन और सिंक';

  @override
  String get toggleToLogin => 'पहले से खाता है? लॉगिन करें';

  @override
  String get toggleToRegister => 'खाता नहीं है? पंजीकरण करें';

  @override
  String get badgeHubConnected => 'हब से जुड़ा';

  @override
  String get badgeWaitingForHub => 'हब का इंतज़ार...';

  @override
  String get buttonSetPassword => 'पासवर्ड सेट करें';

  @override
  String get buttonCancel => 'रद्द करें';

  @override
  String get dialogPasswordResetTitle => 'पासवर्ड रीसेट आवश्यक';

  @override
  String get dialogPasswordResetBody =>
      'आपका पासवर्ड शिक्षक द्वारा रीसेट किया गया। कृपया अपना वर्तमान पासवर्ड दर्ज करें और नया पासवर्ड सेट करें।';

  @override
  String get errorFillAllFields => 'कृपया सभी फ़ील्ड भरें';

  @override
  String get errorPasswordStrength =>
      'पासवर्ड 8+ अक्षर, अपरकेस, लोअरकेस और अंक के साथ होना चाहिए';

  @override
  String get errorRegistrationFailed => 'पंजीकरण विफल। हब कनेक्शन जांचें।';

  @override
  String get snackbarOfflineLogin => 'ऑफ़लाइन लॉगिन — सर्वर सिंक उपलब्ध नहीं';

  @override
  String get errorLoginFailed => 'लॉगिन विफल। नाम या पासवर्ड गलत।';

  @override
  String get errorCurrentPasswordRequired => 'वर्तमान पासवर्ड आवश्यक है।';

  @override
  String get errorPasswordMinLength =>
      'पासवर्ड कम से कम 8 अक्षर का होना चाहिए।';

  @override
  String get errorPasswordsDoNotMatch => 'पासवर्ड मेल नहीं खाते।';

  @override
  String get errorPasswordComplexity =>
      'पासवर्ड में अपरकेस, लोअरकेस और अंक होना चाहिए।';

  @override
  String get errorPasswordChangeFailed =>
      'पासवर्ड सेट करने में विफल। पुनः प्रयास करें।';

  @override
  String get dialogChangePasswordTitle => 'पासवर्ड बदलें';

  @override
  String get dialogChangePasswordBody =>
      'अपना वर्तमान पासवर्ड और नया पासवर्ड दर्ज करें।';

  @override
  String get buttonUpdatePassword => 'पासवर्ड अपडेट करें';

  @override
  String get snackbarPasswordChanged => 'पासवर्ड सफलतापूर्वक बदला गया';

  @override
  String get loginConnectToHub =>
      'पंजीकरण या लॉगिन के लिए Lumina Hub से जुड़ें।';

  @override
  String get profileSetupTitle => 'स्वागत है!';

  @override
  String get profileSetupSubtitle => 'आइए आपकी प्रोफ़ाइल सेट करें';

  @override
  String get labelDisplayName => 'प्रदर्शन नाम';

  @override
  String get buttonContinue => 'जारी रखें';

  @override
  String get sectionRecentlyViewed => 'हाल ही में देखा गया';

  @override
  String get sectionSubjectCategories => 'विषय श्रेणियाँ';

  @override
  String get emptyNoSubjects => 'कोई विषय उपलब्ध नहीं';

  @override
  String get sectionLocalStorage => 'स्थानीय भंडारण';

  @override
  String get pageTitleBrowseResources => 'संसाधन ब्राउज़ करें';

  @override
  String get searchFieldHint => 'शीर्षक, विषय या कक्षा द्वारा खोजें...';

  @override
  String get filtersActiveLabel => 'फ़िल्टर सक्रिय';

  @override
  String filtersActiveSorted(String sortBy) {
    return 'फ़िल्टर सक्रिय · क्रमबद्ध: $sortBy';
  }

  @override
  String get clearFiltersButton => 'फ़िल्टर साफ़ करें';

  @override
  String get sectionAllResources => 'सभी संसाधन';

  @override
  String get sectionRecommendedForYou => 'आपके लिए अनुशंसित';

  @override
  String get emptyNoResources => 'हब पर कोई संसाधन उपलब्ध नहीं।';

  @override
  String get emptyNoSearchResults => 'कोई परिणाम नहीं मिला।';

  @override
  String get errorNoServerNoCache =>
      'सर्वर तक नहीं पहुंचा जा सका। कोई कैश्ड संसाधन उपलब्ध नहीं।';

  @override
  String get errorRetryButton => 'पुनः प्रयास करें';

  @override
  String get badgeKiwixWiki => 'विकी';

  @override
  String get filterSheetTitle => 'फ़िल्टर';

  @override
  String get filterResourceTypeHeader => 'संसाधन प्रकार';

  @override
  String get filterShowLabel => 'दिखाएँ:';

  @override
  String get filterMyGrade => 'मेरी कक्षा';

  @override
  String get filterAllGrades => 'सभी कक्षाएँ';

  @override
  String get filterGradeHeader => 'कक्षा';

  @override
  String get filterSubjectHeader => 'विषय';

  @override
  String get filterSubjectHint => 'विषय द्वारा फ़िल्टर करें...';

  @override
  String get filterSortByHeader => 'क्रमबद्ध करें';

  @override
  String get sortTitleAsc => 'शीर्षक A-Z';

  @override
  String get sortTitleDesc => 'शीर्षक Z-A';

  @override
  String get sortByType => 'प्रकार';

  @override
  String get sortByGrade => 'कक्षा';

  @override
  String get filterResetButton => 'रीसेट';

  @override
  String get filterApplyButton => 'लागू करें';

  @override
  String get snackbarAddedToQueueOffline =>
      'कतार में जोड़ा — सर्वर से जुड़ने पर डाउनलोड होगा';

  @override
  String get snackbarAddedToQueue => 'डाउनलोड कतार में जोड़ा गया';

  @override
  String get snackbarDownloadComplete => 'डाउनलोड पूरा';

  @override
  String get snackbarDownloadFailed => 'डाउनलोड विफल';

  @override
  String get snackbarDownloadRemoved => 'डाउनलोड हटाया गया';

  @override
  String get snackbarRemovedFromSaved => 'सहेजे गए से हटाया गया';

  @override
  String get snackbarAddedToSaved => 'सहेजे गए में जोड़ा गया';

  @override
  String snackbarNotDownloaded(String title) {
    return '\"$title\" डाउनलोड नहीं है। ऑफ़लाइन उपयोग के लिए डाउनलोड बटन से जोड़ें।';
  }

  @override
  String get snackbarQueueAction => 'कतार';

  @override
  String get dialogDownloadTitle => 'डाउनलोड';

  @override
  String dialogDownloadContent(String fileName, String sizeLabel) {
    return '\"$fileName\" डाउनलोड करें?\n\nआकार: $sizeLabel';
  }

  @override
  String get dialogDownloadButton => 'डाउनलोड';

  @override
  String get fileSizeUnavailable => 'आकार उपलब्ध नहीं';

  @override
  String get fileSizeUnknownFallback => 'अज्ञात';

  @override
  String pageTitleDetail(String title, String subject) {
    return '$title — $subject';
  }

  @override
  String emptyNoResourcesForType(String title) {
    return 'कोई $title उपलब्ध नहीं';
  }

  @override
  String emptyNoResourcesDetail(String subject, String grade) {
    return '$subject में $grade के लिए कोई संसाधन नहीं मिला।';
  }

  @override
  String get emptyRefreshButton => 'रीफ़्रेश';

  @override
  String resourceSubtitle(String subject, String grade) {
    return '$subject • $grade';
  }

  @override
  String get resourceTypeTextbooks => 'पाठ्यपुस्तकें';

  @override
  String get resourceTypeTextbooksSubtitle => 'अध्यायवार PDF और अध्ययन सामग्री';

  @override
  String get resourceTypeVideos => 'वीडियो';

  @override
  String get resourceTypeVideosSubtitle => 'पाठ और अवधारणा स्पष्टीकरण देखें';

  @override
  String get resourceTypePyqs => 'पिछले वर्ष के प्रश्न';

  @override
  String get resourceTypePyqsSubtitle =>
      'पिछले वर्षों के प्रश्नपत्र और अभ्यास सेट';

  @override
  String get resourceTypeNotes => 'नोट्स';

  @override
  String get resourceTypeNotesSubtitle => 'त्वरित पुनरीक्षण नोट्स और सारांश';

  @override
  String get resourceCardOpenButton => 'खोलें';

  @override
  String get savedResourcesTitle => 'सहेजे गए संसाधन';

  @override
  String get tabAll => 'सभी';

  @override
  String get tabTextbooks => 'पाठ्यपुस्तकें';

  @override
  String get tabVideos => 'वीडियो';

  @override
  String get tabPyqs => 'पिछले प्रश्न';

  @override
  String get tabNotes => 'नोट्स';

  @override
  String get emptyStateAll => 'अभी तक कोई संसाधन सहेजा नहीं गया।';

  @override
  String emptyStateByType(String type) {
    return 'कोई $type सहेजा नहीं मिला।';
  }

  @override
  String get headerMyProfile => 'मेरी प्रोफ़ाइल';

  @override
  String get headerAnalytics => 'विश्लेषण';

  @override
  String get roleBadgeStudent => 'छात्र';

  @override
  String get initialsFallback => '?';

  @override
  String get editProfileSheetTitle => 'प्रोफ़ाइल संपादित करें';

  @override
  String get editProfileLabelName => 'पूरा नाम';

  @override
  String get editProfileLabelGrade => 'कक्षा';

  @override
  String get editProfileGradeHint => 'कक्षा चुनें';

  @override
  String get editProfileLabelStudentId => 'छात्र आईडी';

  @override
  String editProfileErrorSnackbar(String error) {
    return 'प्रोफ़ाइल अपडेट विफल: $error';
  }

  @override
  String get editProfileSaveButton => 'परिवर्तन सहेजें';

  @override
  String get statCardToday => 'आज';

  @override
  String get statCardThisWeek => 'इस सप्ताह';

  @override
  String get statCardSaved => 'सहेजा गया';

  @override
  String get statCardStreak => 'लगातार';

  @override
  String get sectionSubjectBreakdown => 'विषय के अनुसार अध्ययन समय';

  @override
  String get sectionRecentActivity => 'हाल की गतिविधि';

  @override
  String get emptyStateSubjectBreakdown =>
      'अभी तक कोई डेटा नहीं।\nआपके विषय का समय यहाँ दिखाई देगा।';

  @override
  String get emptyStateRecentActivity =>
      'अभी तक कोई गतिविधि नहीं।\nसंसाधन ब्राउज़ करना शुरू करें।';

  @override
  String get toggleShowLess => 'कम दिखाएँ';

  @override
  String toggleShowAll(int count) {
    return 'सभी दिखाएँ ($count)';
  }

  @override
  String get suffixMinutes => 'मि';

  @override
  String get suffixHours => 'घं';

  @override
  String get suffixDays => ' दिन';

  @override
  String get suffixPercent => '%';

  @override
  String get activityVerbViewed => 'देखा';

  @override
  String get activityVerbSearched => 'खोजा';

  @override
  String get activityVerbDownloaded => 'डाउनलोड किया';

  @override
  String get activityVerbWatched => 'देखा गया';

  @override
  String get activityVerbSaved => 'सहेजा';

  @override
  String get activityVerbOpened => 'खोला';

  @override
  String get activityVerbCompleted => 'पूरा किया';

  @override
  String activityTitleFallback(String verb) {
    return '$verb एक संसाधन';
  }

  @override
  String get relativeTimeJustNow => 'अभी';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    return '$minutes मिनट पहले';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    return '$hours घंटे पहले';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    return '$days दिन पहले';
  }

  @override
  String relativeTimeMonthsAgo(int months) {
    return '$months महीने पहले';
  }

  @override
  String get settingsSheetTitle => 'सेटिंग्स';

  @override
  String get settingsLanguageTitle => 'भाषा';

  @override
  String get settingsLanguageSubtitle => 'ऐप प्रदर्शन भाषा बदलें';

  @override
  String get darkModeLabel => 'डार्क मोड';

  @override
  String get lightModeLabel => 'लाइट मोड';

  @override
  String get switchToLightThemeSubtitle => 'लाइट थीम में बदलें';

  @override
  String get switchToDarkThemeSubtitle => 'डार्क थीम में बदलें';

  @override
  String get appIconLabel => 'डार्क ऐप आइकन';

  @override
  String get appIconLightLabel => 'लाइट ऐप आइकन';

  @override
  String get appIconDarkSubtitle => 'डार्क लॉन्चर आइकन का उपयोग करें';

  @override
  String get appIconLightSubtitle => 'लाइट लॉन्चर आइकन का उपयोग करें';

  @override
  String get storageOfflineLibraryTitle => 'भंडारण और ऑफ़लाइन लाइब्रेरी';

  @override
  String get storageOfflineLibrarySubtitle =>
      'डाउनलोड की गई सामग्री प्रबंधित करें';

  @override
  String get networkSettingsTitle => 'नेटवर्क सेटिंग्स';

  @override
  String get networkSettingsSubtitle => 'हब कनेक्टिविटी कॉन्फ़िगर करें';

  @override
  String get logOutButtonLabel => 'लॉग आउट';

  @override
  String get settingsAccountTitle => 'खाता सेटिंग्स';

  @override
  String get settingsAccountSubtitleOnline => 'अपना पासवर्ड बदलें';

  @override
  String get settingsAccountSubtitleOffline =>
      'खाता प्रबंधन के लिए हब से जुड़ें';

  @override
  String get offlineLibraryAppBarTitle => 'ऑफ़लाइन लाइब्रेरी';

  @override
  String get emptyOfflineLibraryMessage => 'कोई डाउनलोड किया गया संसाधन नहीं';

  @override
  String get deleteDownloadDialogTitle => 'डाउनलोड हटाएं';

  @override
  String deleteDownloadConfirmation(String title) {
    return 'ऑफ़लाइन स्टोरेज से \"$title\" हटाएं?';
  }

  @override
  String get deleteConfirmButtonLabel => 'हटाएं';

  @override
  String get downloadChannelName => 'डाउनलोड';

  @override
  String get downloadChannelDescription => 'डाउनलोड पूर्णता सूचनाएं';

  @override
  String get downloadCompleteNotificationTitle => 'डाउनलोड पूरा';

  @override
  String downloadCompleteNotificationBody(String title) {
    return '\"$title\" डाउनलोड होकर ऑफ़लाइन स्टोरेज में सहेजा गया।';
  }

  @override
  String get downloadFailedNotificationTitle => 'डाउनलोड विफल';

  @override
  String downloadFailedNotificationBody(String title) {
    return '\"$title\" डाउनलोड नहीं हो सका। कनेक्शन जाँचें और पुनः प्रयास करें।';
  }

  @override
  String get stepperStepWelcome => 'स्वागत';

  @override
  String get stepperStepLoginRegister => 'लॉगिन/पंजीकरण';

  @override
  String get stepperStepAccess => 'पहुंच';

  @override
  String pdfPageOfLabel(int currentPage, int totalPages) {
    return 'पृ $currentPage / $totalPages';
  }

  @override
  String get pdfEnterPageNumberHint => 'पृष्ठ संख्या दर्ज करें';

  @override
  String get pdfGoButton => 'जाएं';

  @override
  String get pdfTapToJumpLabel => 'पृष्ठ पर जाने के लिए टैप करें';

  @override
  String pdfZoomPercent(String zoomLevel) {
    return '$zoomLevel%';
  }

  @override
  String get videoLocalFileNotFound => 'स्थानीय फ़ाइल नहीं मिली';

  @override
  String videoFailedToLoad(String error) {
    return 'वीडियो लोड करने में विफल: $error';
  }

  @override
  String get videoMiniPlayerTooltip => 'मिनी प्लेयर';

  @override
  String get kiwixDefaultTitle => 'ज्ञानकोष';

  @override
  String get thumbnailWikiLabel => 'विकी';

  @override
  String get zimAppBarTitle => 'विकिपीडिया';

  @override
  String get zimSearchHint => 'विकिपीडिया लेख खोजें...';

  @override
  String get zimNoArticlesEmpty => 'सर्वर पर कोई लेख उपलब्ध नहीं';

  @override
  String get zimNoResultsEmpty => 'कोई परिणाम नहीं मिला';

  @override
  String get zimUntitledArticleFallback => 'शीर्षकहीन';

  @override
  String zimFailedToLoadArticles(String error) {
    return 'लेख लोड करने में विफल: $error';
  }

  @override
  String zimSearchFailed(String error) {
    return 'खोज विफल: $error';
  }

  @override
  String zimFailedToLoadArticle(String error) {
    return 'लेख लोड करने में विफल: $error';
  }

  @override
  String get dialogSetNameTitle => 'अपना नाम सेट करें';

  @override
  String get dialogSetNameBody =>
      'कृपया अपना अनुभव निजीकृत करने के लिए नाम दर्ज करें।';

  @override
  String get buttonSave => 'सहेजें';

  @override
  String get buttonSkip => 'छोड़ें';

  @override
  String get bottomNavStudents => 'छात्र';

  @override
  String get zimArticleNotFound => 'लेख नहीं मिला';

  @override
  String get teacherPageTitle => 'छात्र';

  @override
  String get teacherFilterByGrade => 'कक्षा द्वारा फ़िल्टर';

  @override
  String get teacherAllGrades => 'सभी कक्षाएँ';

  @override
  String get teacherCouldNotLoadStudents => 'छात्र लोड नहीं हो सके';

  @override
  String get teacherCheckHubConnection =>
      'हब कनेक्शन जांचें और पुनः प्रयास करें।';

  @override
  String get teacherRetry => 'पुनः प्रयास';

  @override
  String get teacherSearchStudentsHint => 'छात्र खोजें...';

  @override
  String get teacherNoStudentsMatchSearch =>
      'आपकी खोज से मेल खाने वाला कोई छात्र नहीं।';

  @override
  String get teacherNoStudentsFound => 'कोई छात्र नहीं मिला।';

  @override
  String teacherShowing(String grade) {
    return 'दिखाया: $grade';
  }

  @override
  String get teacherLabelToday => 'आज';

  @override
  String get teacherLabelStreak => 'लगातार';

  @override
  String get teacherLabelSaved => 'सहेजा';

  @override
  String get teacherLabelDownloaded => 'डाउनलोड';

  @override
  String get teacherOverview => 'अवलोकन';

  @override
  String get teacherThisMonth => 'इस महीने';

  @override
  String teacherShowMore(int remaining) {
    return 'और दिखाएँ ($remaining शेष)';
  }

  @override
  String get teacherCouldNotLoadAnalytics => 'विश्लेषण लोड नहीं हो सका';

  @override
  String get teacherNoActivityRecorded => 'अभी तक कोई गतिविधि दर्ज नहीं।';

  @override
  String get sectionSubjects => 'विषय';

  @override
  String get sectionSubjectsEmpty => 'कोई विषय उपलब्ध नहीं';

  @override
  String get resourcePageResources => 'संसाधन';

  @override
  String get showPassword => 'पासवर्ड दिखाएँ';

  @override
  String get hidePassword => 'पासवर्ड छुपाएँ';

  @override
  String get semanticsSettings => 'सेटिंग्स';

  @override
  String get semanticsSearchResources => 'संसाधन खोजें';

  @override
  String get semanticsFilterResources => 'संसाधन फ़िल्टर करें';

  @override
  String semanticsSelectLanguage(String label) {
    return 'भाषा चुनें: $label';
  }

  @override
  String get semanticsOpenVideoPlayer => 'वीडियो प्लेयर खोलें';

  @override
  String get semanticsCloseMiniPlayer => 'मिनी प्लेयर बंद करें';

  @override
  String get semanticsTogglePlay => 'चलाएँ/रोकें';

  @override
  String get tooltipBackToResource => 'संसाधन पर वापस जाएँ';

  @override
  String tooltipDeleteDownload(String title) {
    return '$title हटाएँ';
  }

  @override
  String get connectionOfflineBanner =>
      'ऑफ़लाइन — कुछ सुविधाएँ उपलब्ध नहीं हो सकतीं';

  @override
  String get notificationDownloadFailedTitle => 'डाउनलोड विफल';

  @override
  String notificationDownloadFailedBody(String title) {
    return '$title डाउनलोड नहीं हो सका। कनेक्शन जाँचें और फिर से कोशिश करें।';
  }

  @override
  String get studentNameUnknown => 'अज्ञात';

  @override
  String activityPastTense(String verb) {
    return '$verbा गया';
  }

  @override
  String storageAppSize(String size) {
    return '$size MB';
  }

  @override
  String get hubStrengthCalculating => 'गणना हो रही है...';

  @override
  String get resourceFallbackTitle => 'Untitled';

  @override
  String get subjectFallbackGeneral => 'General';

  @override
  String get subjectNameUnknown => 'Unknown';
}
