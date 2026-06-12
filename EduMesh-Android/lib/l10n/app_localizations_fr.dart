// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Project Lumina';

  @override
  String get materialAppTitle => 'Edu-Mesh Scholar';

  @override
  String get bottomNavDashboard => 'Tableau de bord';

  @override
  String get bottomNavBrowse => 'Parcourir';

  @override
  String get bottomNavSaved => 'Enregistré';

  @override
  String get bottomNavProfile => 'Profil';

  @override
  String get doubleBackToExitMessage => 'Appuyez à nouveau pour quitter';

  @override
  String get exitButtonLabel => 'Quitter';

  @override
  String get welcomeTitle => 'Connecté au Hub d\'apprentissage';

  @override
  String get welcomeSubtitle =>
      'Pas d\'Internet nécessaire. Accédez localement à des milliers de livres et cours.';

  @override
  String get illustrationBadgeNoInternet =>
      'Aucune connexion Internet requise !';

  @override
  String get languageSectionHeader => 'CHOISIR LA LANGUE';

  @override
  String get languageEnglish => 'Anglais';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageKannada => 'Kannada';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageKiswahili => 'Swahili';

  @override
  String get languageMore => 'Plus...';

  @override
  String get settingsLanguagePickerTitle => 'Choisir la langue';

  @override
  String get ctaEnterPortal => 'Entrer dans le portail';

  @override
  String get hubStrengthChecking => 'Vérification...';

  @override
  String get hubStrengthOffline => 'Hors ligne';

  @override
  String get hubStrengthExcellent => 'Excellent';

  @override
  String get hubStrengthGood => 'Bon';

  @override
  String get hubStrengthFair => 'Moyen';

  @override
  String get statusHubStrength => 'Puissance du Hub';

  @override
  String get statusLocalStorage => 'Stockage local';

  @override
  String get storageCalculating => 'Calcul...';

  @override
  String get storageUnknown => 'Inconnu';

  @override
  String storageMbUsed(String size) {
    return '$size Mo utilisés';
  }

  @override
  String storageGbUsed(String size) {
    return '$size Go utilisés';
  }

  @override
  String storageTotalCapacity(String size) {
    return '$size Go total';
  }

  @override
  String storageUsedLabel(String size) {
    return '$size Go utilisés';
  }

  @override
  String get unitMegabytes => ' Mo';

  @override
  String get unitGigabytes => ' Go';

  @override
  String get unitBytes => ' o';

  @override
  String get unitKilobytes => ' Ko';

  @override
  String get storageLegendAppLabel => 'EduMesh';

  @override
  String get storageLegendOtherLabel => 'Autres apps';

  @override
  String get storageLegendFreeLabel => 'Libre';

  @override
  String get serverStatusChecking => 'Vérification...';

  @override
  String get serverStatusConnected => 'Connecté';

  @override
  String get serverStatusDisconnected => 'Déconnecté';

  @override
  String get searchBarHint => 'Rechercher toutes les ressources...';

  @override
  String get titleRegisterMode => 'Créer une\nidentité Scholar';

  @override
  String get titleLoginMode => 'Connexion\nScholar';

  @override
  String get subtitleRegisterMode =>
      'Commencez votre parcours sur le Lumina Mesh';

  @override
  String get subtitleLoginMode =>
      'Accédez à vos leçons depuis n\'importe quel appareil';

  @override
  String get labelUsername => 'Nom d\'utilisateur';

  @override
  String get hintUsername => 'ex. john_doe';

  @override
  String get labelPassword => 'Mot de passe';

  @override
  String get labelCurrentPassword => 'Mot de passe actuel';

  @override
  String get labelNewPassword => 'Nouveau mot de passe';

  @override
  String get labelConfirmPassword => 'Confirmer le mot de passe';

  @override
  String get hintPasswordRequirements =>
      '8+ caractères, majuscule, minuscule et un chiffre';

  @override
  String get buttonRegister => 'S\'inscrire et synchroniser';

  @override
  String get buttonLogin => 'Connexion et synchronisation';

  @override
  String get toggleToLogin => 'Déjà un compte ? Connectez-vous';

  @override
  String get toggleToRegister => 'Pas de compte ? Inscrivez-vous';

  @override
  String get badgeHubConnected => 'Hub connecté';

  @override
  String get badgeWaitingForHub => 'En attente du Hub...';

  @override
  String get buttonSetPassword => 'Définir le mot de passe';

  @override
  String get buttonCancel => 'Annuler';

  @override
  String get dialogPasswordResetTitle =>
      'Réinitialisation du mot de passe requise';

  @override
  String get dialogPasswordResetBody =>
      'Votre mot de passe a été réinitialisé par un enseignant. Entrez votre mot de passe actuel et définissez-en un nouveau.';

  @override
  String get errorFillAllFields => 'Veuillez remplir tous les champs';

  @override
  String get errorPasswordStrength =>
      'Le mot de passe doit faire 8+ caractères avec majuscule, minuscule et chiffre';

  @override
  String get errorRegistrationFailed =>
      'Échec de l\'inscription. Vérifiez la connexion au Hub.';

  @override
  String get snackbarOfflineLogin =>
      'Connecté hors ligne — synchronisation serveur indisponible';

  @override
  String get errorLoginFailed =>
      'Échec de connexion. Nom ou mot de passe invalide.';

  @override
  String get errorCurrentPasswordRequired =>
      'Le mot de passe actuel est requis.';

  @override
  String get errorPasswordMinLength =>
      'Le mot de passe doit comporter au moins 8 caractères.';

  @override
  String get errorPasswordsDoNotMatch =>
      'Les mots de passe ne correspondent pas.';

  @override
  String get errorPasswordComplexity =>
      'Le mot de passe doit contenir majuscule, minuscule et chiffre.';

  @override
  String get errorPasswordChangeFailed =>
      'Échec de la définition du mot de passe. Réessayez.';

  @override
  String get dialogChangePasswordTitle => 'Changer le mot de passe';

  @override
  String get dialogChangePasswordBody =>
      'Entrez votre mot de passe actuel et un nouveau.';

  @override
  String get buttonUpdatePassword => 'Mettre à jour';

  @override
  String get snackbarPasswordChanged => 'Mot de passe modifié avec succès';

  @override
  String get loginConnectToHub =>
      'Connectez-vous au Lumina Hub pour vous inscrire ou vous connecter.';

  @override
  String get profileSetupTitle => 'Bienvenue !';

  @override
  String get profileSetupSubtitle => 'Configurons votre profil';

  @override
  String get labelDisplayName => 'Nom d\'affichage';

  @override
  String get buttonContinue => 'Continuer';

  @override
  String get sectionRecentlyViewed => 'Récemment consulté';

  @override
  String get sectionSubjectCategories => 'Catégories de matières';

  @override
  String get emptyNoSubjects => 'Aucune matière disponible';

  @override
  String get sectionLocalStorage => 'Stockage local';

  @override
  String get pageTitleBrowseResources => 'Parcourir les ressources';

  @override
  String get searchFieldHint => 'Rechercher par titre, matière ou niveau...';

  @override
  String get filtersActiveLabel => 'Filtres actifs';

  @override
  String filtersActiveSorted(String sortBy) {
    return 'Filtres actifs · Trié : $sortBy';
  }

  @override
  String get clearFiltersButton => 'Effacer les filtres';

  @override
  String get sectionAllResources => 'Toutes les ressources';

  @override
  String get sectionRecommendedForYou => 'Recommandé pour vous';

  @override
  String get emptyNoResources => 'Aucune ressource disponible sur le Hub.';

  @override
  String get emptyNoSearchResults => 'Aucun résultat trouvé.';

  @override
  String get errorNoServerNoCache =>
      'Impossible d\'atteindre le serveur. Aucune ressource en cache disponible.';

  @override
  String get errorRetryButton => 'Réessayer';

  @override
  String get badgeKiwixWiki => 'WIKI';

  @override
  String get filterSheetTitle => 'Filtres';

  @override
  String get filterResourceTypeHeader => 'Type de ressource';

  @override
  String get filterShowLabel => 'Afficher :';

  @override
  String get filterMyGrade => 'Mon niveau';

  @override
  String get filterAllGrades => 'Tous les niveaux';

  @override
  String get filterGradeHeader => 'Niveau';

  @override
  String get filterSubjectHeader => 'Matière';

  @override
  String get filterSubjectHint => 'Filtrer par matière...';

  @override
  String get filterSortByHeader => 'Trier par';

  @override
  String get sortTitleAsc => 'Titre A-Z';

  @override
  String get sortTitleDesc => 'Titre Z-A';

  @override
  String get sortByType => 'Type';

  @override
  String get sortByGrade => 'Niveau';

  @override
  String get filterResetButton => 'Réinitialiser';

  @override
  String get filterApplyButton => 'Appliquer';

  @override
  String get snackbarAddedToQueueOffline =>
      'Ajouté à la file d\'attente — sera téléchargé quand le serveur sera accessible';

  @override
  String get snackbarAddedToQueue => 'Ajouté à la file de téléchargement';

  @override
  String get snackbarDownloadComplete => 'Téléchargement terminé';

  @override
  String get snackbarDownloadFailed => 'Échec du téléchargement';

  @override
  String get snackbarDownloadRemoved => 'Téléchargement supprimé';

  @override
  String get snackbarRemovedFromSaved => 'Retiré des enregistrements';

  @override
  String get snackbarAddedToSaved => 'Ajouté aux enregistrements';

  @override
  String snackbarNotDownloaded(String title) {
    return '\"$title\" n\'est pas téléchargé. Ajoutez-le depuis le bouton de téléchargement pour un accès hors ligne.';
  }

  @override
  String get snackbarQueueAction => 'File';

  @override
  String get dialogDownloadTitle => 'Téléchargement';

  @override
  String dialogDownloadContent(String fileName, String sizeLabel) {
    return 'Télécharger \"$fileName\" ?\n\nTaille : $sizeLabel';
  }

  @override
  String get dialogDownloadButton => 'Télécharger';

  @override
  String get fileSizeUnavailable => 'taille indisponible';

  @override
  String get fileSizeUnknownFallback => 'inconnue';

  @override
  String pageTitleDetail(String title, String subject) {
    return '$title — $subject';
  }

  @override
  String emptyNoResourcesForType(String title) {
    return 'Aucun $title disponible';
  }

  @override
  String emptyNoResourcesDetail(String subject, String grade) {
    return 'Aucune ressource trouvée pour $subject en $grade.';
  }

  @override
  String get emptyRefreshButton => 'Actualiser';

  @override
  String resourceSubtitle(String subject, String grade) {
    return '$subject • $grade';
  }

  @override
  String get resourceTypeTextbooks => 'Manuels scolaires';

  @override
  String get resourceTypeTextbooksSubtitle =>
      'PDF par chapitre et supports d\'étude';

  @override
  String get resourceTypeVideos => 'Vidéos';

  @override
  String get resourceTypeVideosSubtitle =>
      'Regardez des leçons et des explications de concepts';

  @override
  String get resourceTypePyqs => 'Annales';

  @override
  String get resourceTypePyqsSubtitle =>
      'Sujets d\'examens antérieurs et exercices';

  @override
  String get resourceTypeNotes => 'Notes';

  @override
  String get resourceTypeNotesSubtitle => 'Notes de révision rapide et résumés';

  @override
  String get resourceCardOpenButton => 'Ouvrir';

  @override
  String get savedResourcesTitle => 'Ressources enregistrées';

  @override
  String get tabAll => 'Tout';

  @override
  String get tabTextbooks => 'Manuels';

  @override
  String get tabVideos => 'Vidéos';

  @override
  String get tabPyqs => 'Annales';

  @override
  String get tabNotes => 'Notes';

  @override
  String get emptyStateAll => 'Aucune ressource enregistrée pour l\'instant.';

  @override
  String emptyStateByType(String type) {
    return 'Aucun $type enregistré trouvé.';
  }

  @override
  String get headerMyProfile => 'Mon profil';

  @override
  String get headerAnalytics => 'Analytiques';

  @override
  String get roleBadgeStudent => 'Étudiant';

  @override
  String get initialsFallback => '?';

  @override
  String get editProfileSheetTitle => 'Modifier le profil';

  @override
  String get editProfileLabelName => 'Nom complet';

  @override
  String get editProfileLabelGrade => 'Niveau';

  @override
  String get editProfileGradeHint => 'Sélectionnez le niveau';

  @override
  String get editProfileLabelStudentId => 'ID étudiant';

  @override
  String editProfileErrorSnackbar(String error) {
    return 'Échec de la mise à jour du profil : $error';
  }

  @override
  String get editProfileSaveButton => 'Enregistrer les modifications';

  @override
  String get statCardToday => 'Aujourd\'hui';

  @override
  String get statCardThisWeek => 'Cette semaine';

  @override
  String get statCardSaved => 'Enregistré';

  @override
  String get statCardStreak => 'Série';

  @override
  String get sectionSubjectBreakdown => 'Temps d\'étude par matière';

  @override
  String get sectionRecentActivity => 'Activité récente';

  @override
  String get emptyStateSubjectBreakdown =>
      'Aucune donnée d\'étude pour l\'instant.\nVotre temps par matière apparaîtra ici.';

  @override
  String get emptyStateRecentActivity =>
      'Aucune activité récente pour l\'instant.\nCommencez à parcourir les ressources.';

  @override
  String get toggleShowLess => 'Afficher moins';

  @override
  String toggleShowAll(int count) {
    return 'Tout afficher ($count)';
  }

  @override
  String get suffixMinutes => 'm';

  @override
  String get suffixHours => 'h';

  @override
  String get suffixDays => ' j';

  @override
  String get suffixPercent => '%';

  @override
  String get activityVerbViewed => 'Consulté';

  @override
  String get activityVerbSearched => 'Recherché';

  @override
  String get activityVerbDownloaded => 'Téléchargé';

  @override
  String get activityVerbWatched => 'Regardé';

  @override
  String get activityVerbSaved => 'Enregistré';

  @override
  String get activityVerbOpened => 'Ouvert';

  @override
  String get activityVerbCompleted => 'Terminé';

  @override
  String activityTitleFallback(String verb) {
    return '$verb une ressource';
  }

  @override
  String get relativeTimeJustNow => 'À l\'instant';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    return 'Il y a $minutes min';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours heures',
      one: '$hours heure',
    );
    return 'Il y a $_temp0';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours',
      one: '$days jour',
    );
    return 'Il y a $_temp0';
  }

  @override
  String relativeTimeMonthsAgo(int months) {
    return 'Il y a $months mois';
  }

  @override
  String get settingsSheetTitle => 'Paramètres';

  @override
  String get settingsLanguageTitle => 'Langue';

  @override
  String get settingsLanguageSubtitle => 'Modifier la langue d\'affichage';

  @override
  String get darkModeLabel => 'Mode sombre';

  @override
  String get lightModeLabel => 'Mode clair';

  @override
  String get switchToLightThemeSubtitle => 'Passer au thème clair';

  @override
  String get switchToDarkThemeSubtitle => 'Passer au thème sombre';

  @override
  String get appIconLabel => 'Icône sombre';

  @override
  String get appIconLightLabel => 'Icône claire';

  @override
  String get appIconDarkSubtitle => 'Utiliser l\'icône sombre';

  @override
  String get appIconLightSubtitle => 'Utiliser l\'icône claire';

  @override
  String get storageOfflineLibraryTitle =>
      'Stockage et bibliothèque hors ligne';

  @override
  String get storageOfflineLibrarySubtitle => 'Gérer le contenu téléchargé';

  @override
  String get networkSettingsTitle => 'Paramètres réseau';

  @override
  String get networkSettingsSubtitle => 'Configurer la connectivité du Hub';

  @override
  String get logOutButtonLabel => 'Déconnexion';

  @override
  String get settingsAccountTitle => 'Paramètres du compte';

  @override
  String get settingsAccountSubtitleOnline => 'Modifier votre mot de passe';

  @override
  String get settingsAccountSubtitleOffline =>
      'Connectez-vous au Hub pour gérer le compte';

  @override
  String get offlineLibraryAppBarTitle => 'Bibliothèque hors ligne';

  @override
  String get emptyOfflineLibraryMessage => 'Aucune ressource téléchargée';

  @override
  String get deleteDownloadDialogTitle => 'Supprimer le téléchargement';

  @override
  String deleteDownloadConfirmation(String title) {
    return 'Supprimer \"$title\" du stockage hors ligne ?';
  }

  @override
  String get deleteConfirmButtonLabel => 'Supprimer';

  @override
  String get downloadChannelName => 'Téléchargements';

  @override
  String get downloadChannelDescription =>
      'Notifications de fin de téléchargement';

  @override
  String get downloadCompleteNotificationTitle => 'Téléchargement terminé';

  @override
  String downloadCompleteNotificationBody(String title) {
    return '\"$title\" a été téléchargé et sauvegardé dans le stockage hors ligne.';
  }

  @override
  String get downloadFailedNotificationTitle => 'Échec du téléchargement';

  @override
  String downloadFailedNotificationBody(String title) {
    return '\"$title\" n\'a pas pu être téléchargé. Vérifiez la connexion et réessayez.';
  }

  @override
  String get stepperStepWelcome => 'Bienvenue';

  @override
  String get stepperStepLoginRegister => 'Connexion/Inscription';

  @override
  String get stepperStepAccess => 'Accès';

  @override
  String pdfPageOfLabel(int currentPage, int totalPages) {
    return 'P. $currentPage sur $totalPages';
  }

  @override
  String get pdfEnterPageNumberHint => 'Entrez le numéro de page';

  @override
  String get pdfGoButton => 'Aller';

  @override
  String get pdfTapToJumpLabel => 'Appuyez pour aller à la page';

  @override
  String pdfZoomPercent(String zoomLevel) {
    return '$zoomLevel%';
  }

  @override
  String get videoLocalFileNotFound => 'Fichier local introuvable';

  @override
  String videoFailedToLoad(String error) {
    return 'Échec du chargement de la vidéo : $error';
  }

  @override
  String get videoMiniPlayerTooltip => 'Mini lecteur';

  @override
  String get kiwixDefaultTitle => 'BASE DE CONNAISSANCES';

  @override
  String get thumbnailWikiLabel => 'WIKI';

  @override
  String get zimAppBarTitle => 'Wikipédia';

  @override
  String get zimSearchHint => 'Rechercher des articles Wikipédia...';

  @override
  String get zimNoArticlesEmpty => 'Aucun article disponible sur le serveur';

  @override
  String get zimNoResultsEmpty => 'Aucun résultat trouvé';

  @override
  String get zimUntitledArticleFallback => 'Sans titre';

  @override
  String zimFailedToLoadArticles(String error) {
    return 'Échec du chargement des articles : $error';
  }

  @override
  String zimSearchFailed(String error) {
    return 'Échec de la recherche : $error';
  }

  @override
  String zimFailedToLoadArticle(String error) {
    return 'Échec du chargement de l\'article : $error';
  }

  @override
  String get dialogSetNameTitle => 'Définir votre nom';

  @override
  String get dialogSetNameBody =>
      'Veuillez entrer votre nom pour personnaliser votre expérience.';

  @override
  String get buttonSave => 'Enregistrer';

  @override
  String get buttonSkip => 'Passer';

  @override
  String get bottomNavStudents => 'Étudiants';

  @override
  String get zimArticleNotFound => 'Article introuvable';

  @override
  String get teacherPageTitle => 'Étudiants';

  @override
  String get teacherFilterByGrade => 'Filtrer par niveau';

  @override
  String get teacherAllGrades => 'Tous les niveaux';

  @override
  String get teacherCouldNotLoadStudents =>
      'Impossible de charger les étudiants';

  @override
  String get teacherCheckHubConnection =>
      'Vérifiez la connexion au Hub et réessayez.';

  @override
  String get teacherRetry => 'Réessayer';

  @override
  String get teacherSearchStudentsHint => 'Rechercher des étudiants...';

  @override
  String get teacherNoStudentsMatchSearch =>
      'Aucun étudiant ne correspond à votre recherche.';

  @override
  String get teacherNoStudentsFound => 'Aucun étudiant trouvé.';

  @override
  String teacherShowing(String grade) {
    return 'Affichage : $grade';
  }

  @override
  String get teacherLabelToday => 'aujourd\'hui';

  @override
  String get teacherLabelStreak => 'série';

  @override
  String get teacherLabelSaved => 'enregistré';

  @override
  String get teacherLabelDownloaded => 'téléchargé';

  @override
  String get teacherOverview => 'Aperçu';

  @override
  String get teacherThisMonth => 'Ce mois';

  @override
  String teacherShowMore(int remaining) {
    return 'Afficher plus ($remaining restants)';
  }

  @override
  String get teacherCouldNotLoadAnalytics =>
      'Impossible de charger les analytiques';

  @override
  String get teacherNoActivityRecorded =>
      'Aucune activité enregistrée pour l\'instant.';

  @override
  String get sectionSubjects => 'Matières';

  @override
  String get sectionSubjectsEmpty => 'Aucune matière disponible';

  @override
  String get resourcePageResources => 'Ressources';

  @override
  String get showPassword => 'Afficher le mot de passe';

  @override
  String get hidePassword => 'Masquer le mot de passe';

  @override
  String get semanticsSettings => 'Paramètres';

  @override
  String get semanticsSearchResources => 'Rechercher des ressources';

  @override
  String get semanticsFilterResources => 'Filtrer les ressources';

  @override
  String semanticsSelectLanguage(String label) {
    return 'Sélectionnez la langue : $label';
  }

  @override
  String get semanticsOpenVideoPlayer => 'Ouvrir le lecteur vidéo';

  @override
  String get semanticsCloseMiniPlayer => 'Fermer le mini lecteur';

  @override
  String get semanticsTogglePlay => 'Lecture/Pause';

  @override
  String get tooltipBackToResource => 'Retour à la ressource';

  @override
  String tooltipDeleteDownload(String title) {
    return 'Supprimer $title';
  }

  @override
  String get connectionOfflineBanner =>
      'Hors ligne — certaines fonctionnalités peuvent être indisponibles';

  @override
  String get notificationDownloadFailedTitle => 'Échec du téléchargement';

  @override
  String notificationDownloadFailedBody(String title) {
    return '$title n\'a pas pu être téléchargé. Vérifiez votre connexion et réessayez.';
  }

  @override
  String get studentNameUnknown => 'Inconnu';

  @override
  String activityPastTense(String verb) {
    return '${verb}e';
  }

  @override
  String storageAppSize(String size) {
    return '$size Mo';
  }

  @override
  String get hubStrengthCalculating => 'Calcul en cours...';

  @override
  String get resourceFallbackTitle => 'Untitled';

  @override
  String get subjectFallbackGeneral => 'General';

  @override
  String get subjectNameUnknown => 'Unknown';
}
