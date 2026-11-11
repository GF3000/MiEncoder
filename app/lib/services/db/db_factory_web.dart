import 'package:sembast_web/sembast_web.dart';

Future<Database> openAppDatabase() =>
    // Nombre histórico: no cambiarlo (perdería los datos guardados).
    databaseFactoryWeb.openDatabase('velocoach');
