// Prova di shellExecute fuori dall'app (solo Windows):
//   dart run tool/shell_probe.dart open cmd.exe "/c echo ok > C:\percorso\file.txt"
//   dart run tool/shell_probe.dart runas "C:\percorso\Tigert-Setup-x.y.z.exe" "/SILENT /NORESTART /RELAUNCH=1"
import 'dart:io';

import 'package:tigert/services/win_shell.dart';

void main(List<String> a) {
  final ok = shellExecute(a[0], a[1], a.length > 2 ? a[2] : '', hidden: a[0] == 'open');
  stdout.writeln(ok ? 'avviato' : 'rifiutato');
}
