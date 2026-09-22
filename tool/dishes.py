"""Revisione del database alimenti (v1.3.0): tutto a peso da crudo.

- toglie le voci cotte (c'è sempre la versione cruda);
- i primi piatti diventano piatti composti: quantità = peso da crudo della base,
  condimento stimato in proporzione (olio compreso), formaggio facoltativo;
- aggiunge altri piatti tipici;
- segna con "ck" gli alimenti che si cuociono (scelta senza olio / con olio / fritto);
- porzioni: pasta 200 g crudi, riso 150 g crudi.

Uso (da tigert/):
  git show aac20c5:assets/data/foods.json > foods_v120.json   # database della v1.2.0
  python tool/dishes.py foods_v120.json assets/data/foods.json
"""
import json
import re
import sys

SRC, DST = sys.argv[1], sys.argv[2]

REMOVE = {
    's:riso-bianco-cotto', 's:riso-integrale-cotto', 's:pasta-di-semola-cotta', 's:quinoa-cotta',
    's:polenta-cotta', 's:lenticchie-cotte', 's:petto-di-pollo-cotto', 's:petto-di-tacchino-cotto',
    's:patate-al-forno', 's:pollo-arrosto-con-pelle',
}

NEW_FOODS = [
    # valori medi da etichette e tabelle (per 100 g crudi / come venduti)
    {'id': 's:cosce-di-pollo-con-pelle-crude', 'n': 'Cosce di pollo con pelle (crude)', 'cat': 'Carne',
     'k': 210, 'p': 16.5, 'c': 0, 'f': 16, 'fi': 0, 'por': [{'l': 'coscia', 'g': 150}]},
    {'id': 's:casoncelli-freschi', 'n': 'Casoncelli freschi', 'cat': 'Cereali e pasta',
     'k': 290, 'p': 12, 'c': 40, 'f': 9, 'fi': 2, 'por': [{'l': 'porzione', 'g': 200}]},
    {'id': 's:pangrattato', 'n': 'Pangrattato', 'cat': 'Pane e prodotti da forno',
     'k': 395, 'p': 13.4, 'c': 72, 'f': 5.3, 'fi': 4.5, 'por': [{'l': 'cucchiaio', 'g': 10}]},
]

PASTA = 's:pasta-di-semola-cruda'
RISO = 's:riso-bianco-crudo'
OLIO = 's:olio-extravergine-d-oliva'
PARM = 's:parmigiano-reggiano'
P200 = [{'l': 'porzione', 'g': 200}]
P150 = [{'l': 'porzione', 'g': 150}]

# id: (nome, base, porzioni, [(id ingrediente, grammi per grammo di base, facoltativo)])
# La prima parte è la base (r = 1). I facoltativi (formaggio) sono spenti di default.
def dish(name, base, por, *parts):
    return (name, base, por, [(p[0], p[1], p[2] if len(p) > 2 else False) for p in parts])

DISHES = {
    # --- primi con pasta di semola
    's:pasta-al-pomodoro': dish('Pasta al pomodoro', 'pasta cruda', P200,
        (PASTA, 1), ('s:sugo-al-pomodoro-pronto', 0.8), (OLIO, 0.05), (PARM, 0.05, True)),
    's:pasta-al-ragu': dish('Pasta al ragù', 'pasta cruda', P200,
        (PASTA, 1), ('s:ragu-alla-bolognese-pronto', 0.5), (PARM, 0.05, True)),
    's:pasta-al-pesto': dish('Pasta al pesto', 'pasta cruda', P200,
        (PASTA, 1), ('s:pesto-alla-genovese', 0.25), (PARM, 0.05, True)),
    's:pasta-alla-carbonara': dish('Pasta alla carbonara', 'pasta cruda', P200,
        (PASTA, 1), ('s:guanciale', 0.35), ('s:tuorlo', 0.2), ('s:pecorino-romano', 0.15)),
    's:pasta-all-amatriciana': dish("Pasta all'amatriciana", 'pasta cruda', P200,
        (PASTA, 1), ('s:guanciale', 0.3), ('s:pomodori-pelati', 0.8), ('s:pecorino-romano', 0.1)),
    's:pasta-alla-gricia': dish('Pasta alla gricia', 'pasta cruda', P200,
        (PASTA, 1), ('s:guanciale', 0.35), ('s:pecorino-romano', 0.2)),
    's:pasta-cacio-e-pepe': dish('Pasta cacio e pepe', 'pasta cruda', P200,
        (PASTA, 1), ('s:pecorino-romano', 0.45)),
    's:pasta-aglio-olio-e-peperoncino': dish('Pasta aglio, olio e peperoncino', 'pasta cruda', P200,
        (PASTA, 1), (OLIO, 0.15), ('s:aglio', 0.03)),
    's:pasta-al-tonno': dish('Pasta al tonno', 'pasta cruda', P200,
        (PASTA, 1), ("s:tonno-sott-olio-sgocciolato", 0.4), ('s:passata-di-pomodoro', 0.8), (OLIO, 0.05)),
    's:pasta-e-fagioli': dish('Pasta e fagioli', 'pasta cruda', P200,
        (PASTA, 1), ('s:fagioli-borlotti-in-scatola', 1.2), ('s:passata-di-pomodoro', 0.4), ('s:cipolla', 0.1), (OLIO, 0.08), (PARM, 0.05, True)),
    's:pasta-e-ceci': dish('Pasta e ceci', 'pasta cruda', P200,
        (PASTA, 1), ('s:ceci-in-scatola-sgocciolati', 1.2), ('s:passata-di-pomodoro', 0.2), (OLIO, 0.08), (PARM, 0.05, True)),
    's:pasta-alle-zucchine': dish('Pasta alle zucchine', 'pasta cruda', P200,
        (PASTA, 1), ('s:zucchine', 1.5), (OLIO, 0.1), (PARM, 0.05, True)),
    's:pasta-ai-pomodorini': dish('Pasta ai pomodorini', 'pasta cruda', P200,
        (PASTA, 1), ('s:pomodorini', 1), (OLIO, 0.1), (PARM, 0.05, True)),
    's:pasta-al-salmone': dish('Pasta al salmone', 'pasta cruda', P200,
        (PASTA, 1), ('s:salmone-affumicato', 0.4), ('s:panna-da-cucina', 0.5)),
    's:pasta-alle-vongole': dish('Pasta alle vongole', 'pasta cruda', P200,
        (PASTA, 1), ('s:vongole-sgusciate', 0.4), (OLIO, 0.12), ('s:aglio', 0.02)),
    's:pasta-gamberi-e-zucchine': dish('Pasta gamberi e zucchine', 'pasta cruda', P200,
        (PASTA, 1), ('s:gamberi', 0.5), ('s:zucchine', 1), (OLIO, 0.1)),
    's:pasta-panna-e-prosciutto': dish('Pasta panna e prosciutto', 'pasta cruda', P200,
        (PASTA, 1), ('s:prosciutto-cotto', 0.35), ('s:panna-da-cucina', 0.5), (PARM, 0.05, True)),
    's:pasta-olio-e-parmigiano': dish('Pasta olio e parmigiano', 'pasta cruda', P200,
        (PASTA, 1), (OLIO, 0.1), (PARM, 0.1)),
    's:pasta-burro-e-parmigiano': dish('Pasta burro e parmigiano', 'pasta cruda', P200,
        (PASTA, 1), ('s:burro', 0.1), (PARM, 0.1)),
    # --- pasta all'uovo, gnocchi, pasta ripiena (peso come venduti, da crudi)
    's:tagliatelle-al-ragu': dish('Tagliatelle al ragù', "pasta all'uovo cruda", P200,
        ("s:pasta-all-uovo-cruda", 1), ('s:ragu-alla-bolognese-pronto', 0.5), (PARM, 0.05, True)),
    's:gnocchi-al-pomodoro': dish('Gnocchi al pomodoro', 'gnocchi crudi', [{'l': 'porzione', 'g': 250}],
        ('s:gnocchi-di-patate', 1), ('s:sugo-al-pomodoro-pronto', 0.4), (OLIO, 0.03), (PARM, 0.05, True)),
    's:casoncelli-burro-e-salvia': dish('Casoncelli burro e salvia', 'casoncelli crudi', P200,
        ('s:casoncelli-freschi', 1), ('s:burro', 0.1), ('s:pancetta', 0.1), ('s:grana-padano', 0.05, True)),
    's:ravioli-burro-e-salvia': dish('Ravioli burro e salvia', 'ravioli crudi', P200,
        ('s:ravioli-ricotta-e-spinaci-freschi', 1), ('s:burro', 0.1), (PARM, 0.05, True)),
    # --- riso e cereali
    's:risotto-ai-funghi': dish('Risotto ai funghi', 'riso crudo', P150,
        (RISO, 1), ('s:funghi-champignon', 1), (PARM, 0.1), ('s:burro', 0.08), ('s:cipolla', 0.1)),
    's:risotto-alla-milanese': dish('Risotto alla milanese', 'riso crudo', P150,
        (RISO, 1), ('s:burro', 0.1), (PARM, 0.1), ('s:cipolla', 0.1)),
    's:riso-cantonese': dish('Riso cantonese', 'riso crudo', P150,
        (RISO, 1), ('s:uovo-intero', 0.35), ('s:prosciutto-cotto', 0.3), ('s:piselli-surgelati', 0.3), ('s:olio-di-semi', 0.1)),
    's:insalata-di-riso': dish('Insalata di riso', 'riso crudo', P150,
        (RISO, 1), ("s:tonno-sott-olio-sgocciolato", 0.4), ('s:uovo-intero', 0.35), ('s:wurstel', 0.25), ('s:mais-dolce-in-scatola', 0.3), (OLIO, 0.08)),
    's:riso-olio-e-parmigiano': dish('Riso olio e parmigiano', 'riso crudo', P150,
        (RISO, 1), (OLIO, 0.08), (PARM, 0.1)),
    's:riso-e-piselli': dish('Riso e piselli', 'riso crudo', P150,
        (RISO, 1), ('s:piselli-surgelati', 0.8), ('s:cipolla', 0.1), (OLIO, 0.06), (PARM, 0.05, True)),
    's:farro-con-verdure': dish('Farro con verdure', 'farro crudo', [{'l': 'porzione', 'g': 100}],
        ('s:farro-crudo', 1), ('s:zucchine', 1), ('s:pomodorini', 0.6), (OLIO, 0.1)),
    's:couscous-con-verdure': dish('Couscous con verdure', 'couscous crudo', [{'l': 'porzione', 'g': 100}],
        ('s:couscous-crudo', 1), ('s:zucchine', 0.8), ('s:carote', 0.4), ('s:ceci-in-scatola-sgocciolati', 0.5), (OLIO, 0.1)),
    # --- secondi
    's:cotoletta-alla-milanese': dish('Cotoletta alla milanese', 'carne cruda', [{'l': 'fettina', 'g': 150}],
        ('s:fesa-di-vitello', 1), ('s:pangrattato', 0.15), ('s:uovo-intero', 0.12), (OLIO, 0.12)),
    's:frittata': dish('Frittata', 'uova', [{'l': '2 uova', 'g': 100}, {'l': '3 uova', 'g': 150}],
        ('s:uovo-intero', 1), (OLIO, 0.05), (PARM, 0.1, True)),
}
# categoria dei piatti nuovi (quelli già esistenti la mantengono)
NEW_DISH_CAT = {'s:frittata': 'Uova', 's:cotoletta-alla-milanese': 'Piatti pronti'}

# alimenti che si cuociono: scelta senza olio / con olio / fritto
NO_COOK = re.compile(r'sott.olio|al naturale|affumicat|surimi|passata|pelati|concentrato|in scatola|minestrone|olive|avocado|'
                     r'patatine fritte|aglio|secch|decorticat|hummus|tuorlo', re.I)
COOK_CATS = {'Carne', 'Pesce', 'Uova', 'Verdure', 'Legumi e proteine vegetali'}

PASTA_RE = re.compile(r'^pasta .*\(cruda\)$', re.I)
RISO_RE = re.compile(r'^riso .*\(crudo\)$', re.I)


def num(x):
    x = round(x, 1)
    return int(x) if x == int(x) else x


foods = [f for f in json.load(open(SRC, encoding='utf-8')) if f['id'] not in REMOVE]

# nuovi alimenti base, dopo l'ultimo della stessa categoria
def insert(item):
    idx = max((i for i, f in enumerate(foods) if f['cat'] == item['cat']), default=len(foods) - 1)
    foods.insert(idx + 1, item)

for f in NEW_FOODS:
    insert(dict(f))

by_id = {f['id']: f for f in foods}

for f in foods:
    if PASTA_RE.match(f['n']):
        f['por'] = P200
    elif RISO_RE.match(f['n']):
        f['por'] = P150

for dish_id, (name, base, por, parts) in DISHES.items():
    d = by_id.get(dish_id)
    if d is None:
        d = {'id': dish_id, 'n': name, 'cat': NEW_DISH_CAT.get(dish_id, 'Piatti pronti')}
        insert(d)
        by_id[dish_id] = d
    tot = {k: 0.0 for k in ('k', 'p', 'c', 'f', 'fi')}
    out = []
    for pid, r, opt in parts:
        src = by_id[pid]
        if not opt:
            for k in tot:
                tot[k] += src.get(k, 0) * r
        part = {'n': src['n'], 'r': r, 'k': src['k'], 'p': src['p'], 'c': src['c'], 'f': src['f']}
        if opt:
            part['o'] = True
        out.append(part)
    assert out[0]['r'] == 1
    for k, v in tot.items():
        d[k] = num(v)
    d['por'] = por
    d['base'] = base
    d['parts'] = out

for f in foods:
    f.pop('ck', None)
    if f['cat'] in COOK_CATS and 'base' not in f and not NO_COOK.search(f['n']):
        f['ck'] = True

json.dump(foods, open(DST, 'w', encoding='utf-8', newline=''), ensure_ascii=False, separators=(',', ':'))

print(len(foods), 'alimenti,', sum('base' in f for f in foods), 'piatti,', sum(bool(f.get('ck')) for f in foods), 'con cottura')
for f in foods:
    if 'base' in f:
        print(f"  {f['n']:<34} {f['k']:>6} kcal/100 g {f['base']}  P{f['p']} C{f['c']} G{f['f']}")
print('senza cottura:', [f['n'] for f in foods if f['cat'] in COOK_CATS and 'base' not in f and not f.get('ck')])
