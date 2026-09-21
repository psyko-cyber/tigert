import 'dart:math' as math;

/// Formattazione numeri e date in italiano (senza dipendenze esterne).

String fInt(num v) {
  final n = v.round();
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// Decimale con virgola. Se [trim] toglie ",0".
String fDec(num v, [int digits = 1, bool trim = false]) {
  final neg = v < 0;
  var s = v.abs().toStringAsFixed(digits);
  if (trim && s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  final parts = s.split('.');
  final intPart = fInt(int.parse(parts[0]));
  final r = parts.length > 1 ? '$intPart,${parts[1]}' : intPart;
  final isZero = double.tryParse(s) == 0;
  return neg && !isZero ? '-$r' : r;
}

/// Chili: 60 -> "60", 62.5 -> "62,5", 63.45 -> "63,45"
String fKg(num v) => fDec(v, 2, true);

/// Grammi arrotondati.
String fG(num v) => v >= 10 ? fInt(v) : fDec(v, 1, true);

String fSigned(num v, [int digits = 1]) => (v > 0 ? '+' : v < 0 ? '−' : '±') + fDec(v.abs(), digits, true);

double? parseNum(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String fDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int x) => x.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String fMinutes(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- date

const giorni = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];
const giorniBrevi = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
const giorniSigla = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'];
const mesi = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
];
const mesiBrevi = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => dateOnly(DateTime.now());

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String todayKey() => dayKey(DateTime.now());

DateTime fromKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String addDaysKey(String k, int days) => dayKey(fromKey(k).add(Duration(days: days)));

/// Differenza in giorni di calendario (b - a).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// "Martedì 14 ottobre"
String longDate(DateTime d) => '${giorni[d.weekday - 1]} ${d.day} ${mesi[d.month - 1]}';

/// "14 ott"
String shortDate(DateTime d) => '${d.day} ${mesiBrevi[d.month - 1]}';

/// "14 ott 2026" se anno diverso da quello corrente.
String shortDateY(DateTime d) => d.year == DateTime.now().year ? shortDate(d) : '${shortDate(d)} ${d.year}';

String relDay(DateTime d) {
  final diff = daysBetween(today(), d);
  if (diff == 0) return 'Oggi';
  if (diff == -1) return 'Ieri';
  if (diff == 1) return 'Domani';
  return '${giorniBrevi[d.weekday - 1]} ${shortDate(d)}';
}

String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Normalizza per ricerche: minuscolo senza accenti.
String fold(String s) {
  const from = 'àáâäãèéêëìíîïòóôöõùúûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

double clamp01(double v) => math.max(0, math.min(1, v));
