"""Genera l'indice del codice: per ogni file le righe e i simboli pubblici con la loro riga.

Serve a trovare subito dove mettere le mani senza cercare nel progetto.

Uso (da tigert/):
  python tool/mappa.py [file di uscita]      default: ../doc/mappa.md
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / 'doc' / 'mappa.md'

TYPE = re.compile(r'^(?:abstract |final |sealed |base |interface )*(?:class|enum|extension|mixin|typedef)\s+(\w+)')
VALUE = re.compile(r'^(?:late\s+)?(?:const|final|var)\s+(?:[\w<>?\[\], ()]+\s+)?(\w+)\s*(?:=|;)')
GETTER = re.compile(r'^[\w<>?\[\], ()]+\s+get\s+(\w+)\b')
FUNC = re.compile(r'^[A-Za-z_(\[][\w<>?\[\](){}, .]*?\s(\w+)\s*(?:<[^()]*>)?\(')  # le graffe: record con nomi
SKIP = ('import ', 'export ', 'part ', 'library', '//', '@', '}', ')', ']')


def dart_symbols(text):
    """Dichiarazioni a colonna 0 (quindi di primo livello), senza quelle private."""
    out, in_string = [], False
    for n, line in enumerate(text.split('\n'), 1):
        quotes = line.count("'''") + line.count('"""')
        if in_string or not line or line[0] in ' \t' or line.startswith(SKIP):
            if quotes % 2:
                in_string = not in_string
            continue
        if quotes % 2:
            in_string = True
        m = TYPE.match(line) or VALUE.match(line) or GETTER.match(line)
        if m is None and line.rstrip().endswith(('{', '=>', '(', ',', ';')):
            m = FUNC.match(line)
        if m and not m.group(1).startswith('_'):
            out.append(f'{m.group(1)}:{n}')
    return out


BANNER = re.compile(r'^\s*// [=-]{8,} ?([^=\-].*?)\s*$')


def sections(text):
    """Sezioni interne segnate da un commento-riga (// ===== nome, // ----- nome)."""
    return [f'{m.group(1)}:{n}' for n, line in enumerate(text.split('\n'), 1) if (m := BANNER.match(line))]


def lines(p):
    return p.read_text(encoding='utf-8', errors='replace').count('\n') + 1


def section(title, files, symbols=True):
    rows = [f'\n## {title}']
    for p in files:
        text = p.read_text(encoding='utf-8', errors='replace').replace('\r\n', '\n')
        row = f'- {p.name} ({text.count(chr(10)) + 1})'
        if symbols:
            s = dart_symbols(text)
            if s:
                row += ': ' + ' '.join(s)
            sec = sections(text)
            if sec:
                row += ' · sezioni: ' + ', '.join(sec)
        rows.append(row)
    return rows


out = [
    '# Mappa del codice',
    'Generata da `tigert/tool/mappa.py`: non modificarla a mano, rigenerala.',
    'Formato: `file (righe): Simbolo:riga · sezioni: nome:riga`. Solo i simboli pubblici di primo livello.',
    'Uso: Grep qui del nome di file o del simbolo, poi Read con offset su quel punto. Per i membri di una classe: Grep nel solo file.',
]
lib = ROOT / 'lib'
for d in sorted({p.parent for p in lib.rglob('*.dart')}):
    out += section('lib/' + d.relative_to(lib).as_posix() if d != lib else 'lib', sorted(d.glob('*.dart')))

out.append('\n## test (file: test scritti; screens_test li ripete per ogni schermata, su telefono e desktop)')
for p in sorted((ROOT / 'test').glob('*.dart')):
    t = p.read_text(encoding='utf-8', errors='replace')
    out.append(f'- {p.name} ({t.count(chr(10)) + 1}): {len(re.findall(r"^\s*(?:test|testWidgets)\(", t, re.M))}')

out.append('\n## Altro (file: righe)')
for rel in ['tool', 'windows/runner', 'android/app/src/main/kotlin/it/tigert/app', 'installer']:
    files = [p for p in sorted((ROOT / rel).glob('*')) if p.suffix in ('.py', '.dart', '.cpp', '.h', '.kt', '.iss')]
    out.append(f'- {rel}/: ' + ', '.join(f'{p.name} ({lines(p)})' for p in files))
out.append('- android/app/: build.gradle.kts, src/main/AndroidManifest.xml (permessi, Health Connect, FileProvider)')
data = ROOT / 'assets' / 'data'
out.append('- assets/data/: ' + ', '.join(f'{p.name} ({p.stat().st_size // 1024} KB, una riga)' for p in sorted(data.glob('*.json'))))

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text('\n'.join(out) + '\n', encoding='utf-8', newline='\n')
print(f'{OUT} ({OUT.stat().st_size} byte)')
