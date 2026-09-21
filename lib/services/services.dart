import '../data/app_state.dart';
import 'desktop.dart';
import 'notifications.dart';
import 'sync.dart';

/// Servizi globali creati all'avvio.
class Services {
  static late AppState app;
  static late SyncService sync;
  static late NotificationService notif;
  static DesktopService? desktop;
}
