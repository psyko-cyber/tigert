import '../core/fmt.dart';
import '../data/models.dart';

/// Integratori del profilo che oggi non sono ancora spuntati.
List<String> pendingSupplements(Profile p, HabitDay today) =>
    p.habitOn('supp') ? p.supplements.where((s) => !today.took(s)).toList() : const [];

/// Giorni consecutivi con l'integratore preso. Se oggi non è ancora spuntato
/// la serie parte da ieri (la giornata non è finita).
int supplementStreak(Map<String, HabitDay> byDate, String name, DateTime today) {
  bool took(DateTime d) => byDate[dayKey(d)]?.took(name) ?? false;
  // DateTime(y, m, d - 1) e non subtract(1 giorno): con l'ora legale un giorno può durare 23 ore
  var d = DateTime(today.year, today.month, today.day - (took(today) ? 0 : 1));
  var n = 0;
  while (took(d) && n < 3650) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// Ultimi [days] giorni, dal più vecchio a oggi: preso sì o no.
List<bool> supplementLastDays(Map<String, HabitDay> byDate, String name, DateTime today, {int days = 7}) => [
      for (var i = days - 1; i >= 0; i--) byDate[dayKey(DateTime(today.year, today.month, today.day - i))]?.took(name) ?? false,
    ];
