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
}
