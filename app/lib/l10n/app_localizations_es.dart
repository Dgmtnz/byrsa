// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Byrsa';

  @override
  String get libraryTitle => 'Biblioteca';

  @override
  String get searchHint => 'Buscar dentro de tus documentos';

  @override
  String get noDocuments => 'Todavía no hay documentos. Escanea uno.';

  @override
  String get noResults => 'No hay coincidencias.';

  @override
  String get scan => 'Escanear';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get folderName => 'Nombre de la carpeta';

  @override
  String get rename => 'Renombrar';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get settings => 'Ajustes';

  @override
  String get exportPdf => 'Exportar PDF buscable';

  @override
  String get exportText => 'Exportar texto';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
      zero: 'Sin páginas',
    );
    return '$_temp0';
  }

  @override
  String get searchable => 'Buscable';

  @override
  String get notSearchable => 'Todavía no es buscable';

  @override
  String get runOcr => 'Reconocer texto';

  @override
  String get ocrEngine => 'Motor de reconocimiento';

  @override
  String get downloadModels => 'Descargar modelos de reconocimiento';

  @override
  String downloadModelsExplanation(int megabytes) {
    return 'Esta es la única vez que Byrsa usa la red. Descarga $megabytes MB de modelos desde una dirección fija y los verifica contra una huella conocida. Tus documentos no se suben nunca.';
  }

  @override
  String get download => 'Descargar';

  @override
  String get privacyHeading => 'Adónde van tus documentos';

  @override
  String get privacyBody =>
      'A ningún sitio. Todo ocurre en este dispositivo. La única petición de red que Byrsa puede hacer es descargar los modelos de reconocimiento, y solo cuando tú lo pides.';

  @override
  String exportedTo(String path) {
    return 'Guardado en $path';
  }

  @override
  String pageSemanticLabel(int position, int total) {
    return 'Página $position de $total';
  }

  @override
  String get cameraNeeded => 'Byrsa necesita la cámara';

  @override
  String get cameraNeededBody =>
      'El escaneo ocurre entero en este dispositivo. No se sube ninguna foto.';

  @override
  String get cameraDeniedBody =>
      'El acceso a la cámara está desactivado para Byrsa. Puedes volver a activarlo en los ajustes del sistema.';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get processing => 'Mejorando…';

  @override
  String get enhance => 'Mejorar páginas';

  @override
  String get enhanced => 'Mejorada';
}
