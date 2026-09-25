// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Byrsa';

  @override
  String get libraryTitle => 'Library';

  @override
  String get searchHint => 'Search inside your documents';

  @override
  String get noDocuments => 'No documents yet. Scan one.';

  @override
  String get noResults => 'Nothing matched that.';

  @override
  String get scan => 'Scan';

  @override
  String get newFolder => 'New folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get settings => 'Settings';

  @override
  String get exportPdf => 'Export searchable PDF';

  @override
  String get exportText => 'Export text';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
      zero: 'No pages',
    );
    return '$_temp0';
  }

  @override
  String get searchable => 'Searchable';

  @override
  String get notSearchable => 'Not searchable yet';

  @override
  String get runOcr => 'Recognise text';

  @override
  String get ocrEngine => 'Recognition engine';

  @override
  String get downloadModels => 'Download recognition models';

  @override
  String downloadModelsExplanation(int megabytes) {
    return 'This is the only time Byrsa uses the network. It downloads $megabytes MB of recognition models from a fixed address and checks them against a known fingerprint. Your documents are never uploaded.';
  }

  @override
  String get download => 'Download';

  @override
  String get privacyHeading => 'Where your documents go';

  @override
  String get privacyBody =>
      'Nowhere. Everything happens on this device. The only network request Byrsa can make is downloading the recognition models, and only when you ask for it.';

  @override
  String exportedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String pageSemanticLabel(int position, int total) {
    return 'Page $position of $total';
  }

  @override
  String get cameraNeeded => 'Byrsa needs the camera';

  @override
  String get cameraNeededBody =>
      'Scanning happens entirely on this device. No photograph is uploaded.';

  @override
  String get cameraDeniedBody =>
      'Camera access is turned off for Byrsa. You can turn it back on in the system settings.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get processing => 'Enhancing…';

  @override
  String get enhance => 'Enhance pages';

  @override
  String get enhanced => 'Enhanced';

  @override
  String get adjustCorners => 'Adjust corners';

  @override
  String get adjustCornersHelp => 'Drag the corners to the edges of the page.';

  @override
  String get reset => 'Reset';

  @override
  String get share => 'Share';

  @override
  String get deletePage => 'Delete page';

  @override
  String get movePageLeft => 'Move left';

  @override
  String get movePageRight => 'Move right';

  @override
  String get filter => 'Filter';

  @override
  String get filterColour => 'Colour';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get filterBlackAndWhite => 'Black and white';

  @override
  String get deleteDocumentConfirm =>
      'Delete this document? The scans go with it.';

  @override
  String get autoCapture => 'Capture automatically';

  @override
  String get autoCaptureBody =>
      'Take the picture when the page is steady and in focus.';

  @override
  String get autoOcr => 'Recognise text automatically';

  @override
  String get autoOcrBody =>
      'Run recognition on each page as soon as it is enhanced.';

  @override
  String get importImage => 'Import a photograph';

  @override
  String get dewarp => 'Flatten curved pages';

  @override
  String dewarpBody(int megabytes, String license) {
    return 'A neural model that un-curves a page photographed in a book. $megabytes MB, licence $license.';
  }

  @override
  String get dewarpReady => 'Downloaded. Curved pages will be flattened.';

  @override
  String get removeIntrusions => 'Remove fingers at the edge';

  @override
  String get removeIntrusionsBody =>
      'Erases a thumb, a finger or whatever else holds the page down at the edge, and fills the paper back in.';

  @override
  String get remove => 'Remove';

  @override
  String get hintNoDocument => 'Point at a document';

  @override
  String get hintTooFar => 'Move closer';

  @override
  String get hintCropped => 'Fit the whole page';

  @override
  String get hintMoving => 'Hold still';

  @override
  String get hintBlurry => 'Focusing…';

  @override
  String get hintTooDark => 'Not enough light';

  @override
  String get hintReady => 'Ready';

  @override
  String scanTitle(String timestamp) {
    return 'Scan $timestamp';
  }

  @override
  String importedTitle(String timestamp) {
    return 'Imported $timestamp';
  }
}
