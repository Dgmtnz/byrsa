import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

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
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Byrsa'**
  String get appTitle;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search inside your documents'**
  String get searchHint;

  /// No description provided for @noDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents yet. Scan one.'**
  String get noDocuments;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing matched that.'**
  String get noResults;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @exportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export searchable PDF'**
  String get exportPdf;

  /// No description provided for @exportText.
  ///
  /// In en, this message translates to:
  /// **'Export text'**
  String get exportText;

  /// No description provided for @pageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pages} =1{1 page} other{{count} pages}}'**
  String pageCount(int count);

  /// No description provided for @searchable.
  ///
  /// In en, this message translates to:
  /// **'Searchable'**
  String get searchable;

  /// No description provided for @notSearchable.
  ///
  /// In en, this message translates to:
  /// **'Not searchable yet'**
  String get notSearchable;

  /// No description provided for @runOcr.
  ///
  /// In en, this message translates to:
  /// **'Recognise text'**
  String get runOcr;

  /// No description provided for @ocrEngine.
  ///
  /// In en, this message translates to:
  /// **'Recognition engine'**
  String get ocrEngine;

  /// No description provided for @downloadModels.
  ///
  /// In en, this message translates to:
  /// **'Download recognition models'**
  String get downloadModels;

  /// No description provided for @downloadModelsExplanation.
  ///
  /// In en, this message translates to:
  /// **'This is the only time Byrsa uses the network. It downloads {megabytes} MB of recognition models from a fixed address and checks them against a known fingerprint. Your documents are never uploaded.'**
  String downloadModelsExplanation(int megabytes);

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @privacyHeading.
  ///
  /// In en, this message translates to:
  /// **'Where your documents go'**
  String get privacyHeading;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'Nowhere. Everything happens on this device. The only network request Byrsa can make is downloading the recognition models, and only when you ask for it.'**
  String get privacyBody;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String exportedTo(String path);

  /// No description provided for @pageSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {position} of {total}'**
  String pageSemanticLabel(int position, int total);

  /// No description provided for @cameraNeeded.
  ///
  /// In en, this message translates to:
  /// **'Byrsa needs the camera'**
  String get cameraNeeded;

  /// No description provided for @cameraNeededBody.
  ///
  /// In en, this message translates to:
  /// **'Scanning happens entirely on this device. No photograph is uploaded.'**
  String get cameraNeededBody;

  /// No description provided for @cameraDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Camera access is turned off for Byrsa. You can turn it back on in the system settings.'**
  String get cameraDeniedBody;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Enhancing…'**
  String get processing;

  /// No description provided for @enhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance pages'**
  String get enhance;

  /// No description provided for @enhanced.
  ///
  /// In en, this message translates to:
  /// **'Enhanced'**
  String get enhanced;

  /// No description provided for @adjustCorners.
  ///
  /// In en, this message translates to:
  /// **'Adjust corners'**
  String get adjustCorners;

  /// No description provided for @adjustCornersHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners to the edges of the page.'**
  String get adjustCornersHelp;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @deletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get deletePage;

  /// No description provided for @movePageLeft.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get movePageLeft;

  /// No description provided for @movePageRight.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get movePageRight;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @filterColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get filterColour;

  /// No description provided for @filterGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get filterGrayscale;

  /// No description provided for @filterBlackAndWhite.
  ///
  /// In en, this message translates to:
  /// **'Black and white'**
  String get filterBlackAndWhite;

  /// No description provided for @deleteDocumentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this document? The scans go with it.'**
  String get deleteDocumentConfirm;

  /// No description provided for @autoCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture automatically'**
  String get autoCapture;

  /// No description provided for @autoCaptureBody.
  ///
  /// In en, this message translates to:
  /// **'Take the picture when the page is steady and in focus.'**
  String get autoCaptureBody;

  /// No description provided for @autoOcr.
  ///
  /// In en, this message translates to:
  /// **'Recognise text automatically'**
  String get autoOcr;

  /// No description provided for @autoOcrBody.
  ///
  /// In en, this message translates to:
  /// **'Run recognition on each page as soon as it is enhanced.'**
  String get autoOcrBody;

  /// No description provided for @importImage.
  ///
  /// In en, this message translates to:
  /// **'Import a photograph'**
  String get importImage;

  /// No description provided for @dewarp.
  ///
  /// In en, this message translates to:
  /// **'Flatten curved pages'**
  String get dewarp;

  /// No description provided for @dewarpBody.
  ///
  /// In en, this message translates to:
  /// **'A neural model that un-curves a page photographed in a book. {megabytes} MB, licence {license}.'**
  String dewarpBody(int megabytes, String license);

  /// No description provided for @dewarpReady.
  ///
  /// In en, this message translates to:
  /// **'Downloaded. Curved pages will be flattened.'**
  String get dewarpReady;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;
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
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
