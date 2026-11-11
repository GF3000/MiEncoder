import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  // Nombre histórico del archivo: no cambiarlo o se pierden los datos ya
  // guardados en los dispositivos (la app se llamó "velocoach" al principio).
  return databaseFactoryIo.openDatabase(p.join(dir.path, 'velocoach.db'));
}
