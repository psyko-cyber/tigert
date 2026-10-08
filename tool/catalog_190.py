"""Ampliamento del catalogo alimenti (v1.9.0).

- alimenti base in più (valori medi per 100 g a crudo / come venduti, da tabelle CREA ed etichette);
- prodotti di marca comuni (valori d'etichetta: indicativi, le ricette cambiano);
- altri piatti composti, calcolati dagli ingredienti del catalogo come in dishes.py.

Si può rilanciare: le voci già presenti restano come sono, i piatti si ricalcolano.

Uso (da tigert/):
  python tool/catalog_190.py
"""
import json
import re
import unicodedata

PATH = 'assets/data/foods.json'


def slug(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+', '-', s).strip('-')


def num(x):
    x = round(float(x), 1)
    return int(x) if x == int(x) else x


# Righe: nome [@ marca] | kcal | proteine | carboidrati | grassi | fibre | porzioni (etichetta:grammi; ...) [| ck]
# "ck" = si cuoce: sulla scheda compare la scelta senza olio / con olio / fritto.
BASE = {
    'Carne': '''
Sovracosce di pollo senza pelle (crude) | 120 | 19.5 | 0 | 4.5 | 0 | sovracoscia:120 | ck
Sovracosce di pollo con pelle (crude) | 190 | 17 | 0 | 13.5 | 0 | sovracoscia:150 | ck
Fusi di pollo con pelle (crudi) | 160 | 18 | 0 | 9.5 | 0 | fuso:100 | ck
Ali di pollo (crude) | 190 | 18 | 0 | 13 | 0 | ala:50 | ck
Pollo intero con pelle (crudo) | 170 | 19 | 0 | 10.5 | 0 | porzione:200 | ck
Macinato di pollo (crudo) | 140 | 18.5 | 0 | 7 | 0 | porzione:150 | ck
Hamburger di pollo | 160 | 16 | 3 | 9 | 0.5 | hamburger:100 | ck
Macinato di tacchino (crudo) | 150 | 19 | 0 | 8 | 0 | porzione:150 | ck
Cosce di tacchino senza pelle (crude) | 115 | 20 | 0 | 3.5 | 0 | porzione:150 | ck
Salsiccia di pollo e tacchino | 190 | 15 | 1 | 14 | 0 | salsiccia:80 | ck
Fettine di manzo magre | 110 | 22 | 0 | 2.5 | 0 | fettina:120 | ck
Costata di manzo | 180 | 20 | 0 | 11 | 0 | porzione:250 | ck
Spezzatino di manzo (crudo) | 130 | 21 | 0 | 5 | 0 | porzione:150 | ck
Carpaccio di manzo | 110 | 21.5 | 0 | 2.5 | 0 | porzione:100
Braciola di maiale | 160 | 20 | 0 | 9 | 0 | braciola:180 | ck
Filetto di maiale | 120 | 21.5 | 0 | 3.5 | 0 | porzione:150 | ck
Polpette di carne (crude) | 200 | 16 | 6 | 12 | 0.5 | polpetta:30 | ck
Cordon bleu | 230 | 13 | 13 | 14 | 1 | pezzo:125 | ck
Arrosticini (crudi) | 215 | 17 | 0 | 16 | 0 | arrosticino:25 | ck
Carne di kebab | 215 | 18 | 4 | 14 | 0.5 | porzione:150
Carne in scatola @ Simmenthal | 61 | 11 | 0.2 | 1.5 | 0 | scatoletta:90
Wudy classico @ AIA | 240 | 15 | 0 | 20 | 0 | wurstel:25
Spinacine @ AIA | 235 | 13 | 12 | 15 | 1.5 | pezzo:110 | ck
''',
    'Salumi': '''
Prosciutto crudo sgrassato | 160 | 27 | 0 | 5.5 | 0 | fetta:15
Petto di pollo arrosto affettato | 105 | 21 | 1.5 | 1.5 | 0 | fetta:20
Roast beef affettato | 120 | 22 | 0.5 | 3.5 | 0 | fetta:20
Coppa | 400 | 24 | 0.5 | 33 | 0 | fetta:12
Porchetta | 280 | 22 | 0.5 | 21 | 0 | fetta:50
Cotechino | 310 | 17 | 0.5 | 26.5 | 0 | fetta:50
Bacon a fette | 330 | 15 | 0.5 | 30 | 0 | fetta:15
''',
    'Pesce': '''
Tonno fresco | 130 | 23 | 0 | 4 | 0 | trancio:150 | ck
Platessa | 80 | 16.5 | 0 | 1.5 | 0 | filetto:120 | ck
Sogliola | 83 | 17 | 0 | 1.5 | 0 | filetto:120 | ck
Nasello | 71 | 17 | 0 | 0.3 | 0 | filetto:150 | ck
Pangasio | 75 | 15 | 0 | 1.5 | 0 | filetto:150 | ck
Persico | 85 | 18 | 0 | 1.2 | 0 | filetto:130 | ck
Seppie | 72 | 14 | 0.7 | 1.5 | 0 | porzione:200 | ck
Capesante | 80 | 15 | 3 | 0.8 | 0 | porzione:100 | ck
Sgombro al naturale (sgocciolato) | 180 | 21 | 0 | 10.5 | 0 | scatoletta:90
Sgombro sott'olio (sgocciolato) | 220 | 21 | 0 | 15 | 0 | scatoletta:90
Acciughe sott'olio (sgocciolate) | 205 | 26 | 0 | 11 | 0 | filetto:4
Insalata di mare | 90 | 13 | 2 | 3 | 0 | porzione:150
''',
    'Latte e yogurt': '''
Latte senza lattosio parzialmente scremato | 46 | 3.3 | 5 | 1.6 | 0 | tazza:250; bicchiere:200
Latte proteico | 52 | 7.6 | 4.5 | 0.3 | 0 | bottiglia:330
Latte al cioccolato | 70 | 3.3 | 10.5 | 1.7 | 0.3 | brick:200
Bevanda di riso | 52 | 0.3 | 10.5 | 1 | 0 | tazza:250
Yogurt greco 0% alla frutta | 78 | 8 | 11 | 0.2 | 0.2 | vasetto:150
Yogurt proteico bianco | 58 | 10 | 4 | 0.2 | 0 | vasetto:160
Yogurt di soia | 50 | 4 | 2.5 | 2.3 | 0.5 | vasetto:125
Yogurt da bere | 75 | 2.9 | 12 | 1.5 | 0 | bottiglietta:200
Panna montata | 260 | 2.2 | 9 | 24 | 0 | ciuffo:15
Yogurt greco Total 0% @ Fage | 54 | 10.3 | 3 | 0 | 0 | vasetto:170
Yogurt greco Total 2% @ Fage | 70 | 9.9 | 3 | 2 | 0 | vasetto:170
Yogurt greco Total 5% @ Fage | 93 | 9 | 3 | 5 | 0 | vasetto:150
HiPro bianco @ Danone | 56 | 9.4 | 3.9 | 0.2 | 0 | vasetto:160
HiPro da bere @ Danone | 51 | 7.6 | 4.9 | 0.1 | 0 | bottiglia:330
Activia bianco @ Danone | 72 | 4.3 | 5.6 | 3.5 | 0 | vasetto:125
Actimel @ Danone | 70 | 2.7 | 11 | 1.5 | 0 | bottiglietta:100
''',
    'Formaggi': '''
Asiago | 365 | 24 | 0.5 | 30 | 0 | fetta:30
Burrata | 245 | 10 | 1.5 | 22 | 0 | burrata:125
Primosale | 265 | 18 | 1 | 21 | 0 | porzione:100
Brie | 330 | 20 | 0.5 | 28 | 0 | porzione:40
Camembert | 297 | 20 | 0.5 | 24 | 0 | porzione:40
Cheddar | 403 | 25 | 1.3 | 33 | 0 | fetta:25
Gouda | 356 | 25 | 2 | 27.5 | 0 | fetta:25
Halloumi | 320 | 22 | 2 | 25 | 0 | porzione:80
Quark magro | 67 | 12 | 4 | 0.2 | 0 | porzione:150
Philadelphia Classico @ Philadelphia | 230 | 5.4 | 4.2 | 21 | 0 | cucchiaio:20
Philadelphia Light @ Philadelphia | 150 | 7.4 | 5.1 | 11 | 0 | cucchiaio:20
Jocca fiocchi di latte @ Jocca | 97 | 10 | 3.5 | 4.5 | 0 | vasetto:175
''',
    'Verdure': '''
Bietole | 17 | 1.3 | 2.8 | 0.1 | 1.2 | porzione:200 | ck
Cicoria | 15 | 1.4 | 1.5 | 0.2 | 3 | porzione:200 | ck
Cime di rapa | 22 | 2.9 | 2 | 0.3 | 2.9 | porzione:200 | ck
Verza | 24 | 2 | 3 | 0.1 | 2.8 | porzione:150 | ck
Porri | 30 | 2.1 | 5.2 | 0.1 | 2.9 | porro:150 | ck
Funghi porcini | 26 | 3.9 | 1 | 0.7 | 2.5 | porzione:150 | ck
Friggitelli | 22 | 1 | 4 | 0.3 | 1.8 | porzione:150 | ck
Misto di verdure surgelate | 40 | 2.5 | 5.5 | 0.4 | 3 | porzione:200 | ck
Germogli di soia | 49 | 6.2 | 3 | 1.4 | 1 | porzione:80 | ck
Ravanelli | 13 | 0.8 | 1.8 | 0.1 | 1.3 | porzione:80
Valeriana | 21 | 2 | 2.5 | 0.4 | 1.5 | porzione:50
Scarola / indivia | 17 | 1.3 | 2 | 0.2 | 1.6 | porzione:100 | ck
''',
    'Frutta': '''
Clementina | 47 | 0.9 | 10.5 | 0.2 | 1.7 | clementina:70
Nettarina | 42 | 1 | 9 | 0.3 | 1.7 | nettarina:140
Papaya | 39 | 0.5 | 9 | 0.2 | 1.7 | porzione:150
Frutti di bosco surgelati | 45 | 1 | 9 | 0.4 | 4 | porzione:125
Macedonia di frutta | 54 | 0.6 | 12.5 | 0.2 | 1.5 | coppetta:200
Purea di frutta | 55 | 0.3 | 13 | 0.2 | 1.5 | vasetto:100
Cocco fresco | 364 | 3.5 | 9.4 | 35 | 9 | pezzo:30
Castagne | 190 | 3 | 40 | 1.8 | 5 | 10 castagne:80
Fichi secchi | 255 | 3.5 | 55 | 2.5 | 10 | fico:20
''',
    'Frutta secca e semi': '''
Noci pecan | 691 | 9 | 4 | 72 | 9.5 | manciata:30
Noci di macadamia | 718 | 8 | 5 | 76 | 8.5 | manciata:30
Noci brasiliane | 660 | 14 | 4 | 67 | 7.5 | noce:5
Pinoli | 680 | 14 | 5 | 68 | 4 | cucchiaio:10
Mix di frutta secca | 600 | 18 | 12 | 53 | 8 | manciata:30
Semi di canapa | 580 | 31 | 4 | 49 | 4 | cucchiaio:10
Tahina | 615 | 20 | 7 | 56 | 9 | cucchiaio:15
Crema 100% nocciole | 655 | 15 | 7 | 63 | 8 | cucchiaio:15
Farina di mandorle | 590 | 21 | 7 | 53 | 11 | cucchiaio:10
''',
    'Legumi e proteine vegetali': '''
Lenticchie in scatola (sgocciolate) | 90 | 6.5 | 12 | 0.6 | 5 | scatola:240
Fagioli rossi in scatola | 105 | 7.5 | 14 | 0.6 | 6.5 | scatola:240
Piselli in scatola (sgocciolati) | 75 | 5.3 | 10.5 | 0.6 | 5 | scatoletta:140
Fagioli cannellini secchi | 310 | 23 | 46 | 1.6 | 17 | porzione:50
Lupini | 115 | 16 | 7 | 2.5 | 5 | porzione:50
Granulare di soia | 340 | 50 | 22 | 1.5 | 15 | porzione:40
Farina di ceci | 365 | 21 | 54 | 5.5 | 11 | cucchiaio:10
Cotoletta vegetale | 220 | 14 | 16 | 11 | 4 | cotoletta:90 | ck
Falafel | 300 | 12 | 28 | 15 | 6 | falafel:20
''',
    'Cereali e pasta': '''
Riso parboiled (crudo) | 355 | 7.5 | 79 | 1 | 1.2 | porzione:150
Riso jasmine (crudo) | 350 | 7 | 78 | 0.7 | 1 | porzione:150
Pasta senza glutine (cruda) | 357 | 6.5 | 78 | 1.5 | 1.5 | porzione:200
Pasta proteica (cruda) | 355 | 20 | 60 | 2.5 | 7 | porzione:200
Pasta di farro (cruda) | 350 | 13 | 68 | 2.2 | 5 | porzione:200
Noodles di riso (crudi) | 360 | 6 | 80 | 0.6 | 1.5 | porzione:80
Noodles istantanei | 450 | 9.5 | 60 | 18 | 2.5 | confezione:80
Spaghetti di soia (crudi) | 340 | 0.2 | 84 | 0.1 | 0.5 | porzione:80
Bulgur (crudo) | 340 | 12.3 | 63 | 1.3 | 12.5 | porzione:70
Miglio (crudo) | 360 | 11 | 69 | 4 | 3.5 | porzione:70
Grano saraceno (crudo) | 343 | 13 | 62 | 3.4 | 10 | porzione:70
Crusca d'avena | 365 | 17 | 47 | 8 | 15 | cucchiaio:10
Farina d'avena | 375 | 13 | 60 | 7 | 9 | porzione:40
Cereali al cioccolato | 385 | 7 | 78 | 4 | 4 | tazza:30
Fiocchi integrali | 360 | 10 | 68 | 2.5 | 10 | tazza:30
Special K Classic @ Kellogg's | 392 | 8 | 84 | 1.3 | 2.5 | tazza:30
Nesquik cereali @ Nestlé | 369 | 8.4 | 75.8 | 1.7 | 6 | tazza:30
''',
    'Pane e prodotti da forno': '''
Cornetto integrale | 380 | 8 | 45 | 18 | 4 | cornetto:50
Cornetto al cioccolato | 420 | 7 | 48 | 22 | 2 | cornetto:70
Cornetto alla marmellata | 390 | 6.5 | 50 | 18 | 1.5 | cornetto:70
Cornetto al pistacchio | 430 | 8 | 46 | 24 | 2 | cornetto:75
Cornetto vegano | 400 | 7 | 48 | 20 | 2 | cornetto:50
Pain au chocolat | 430 | 8 | 46 | 24 | 2.5 | pezzo:65
Krapfen alla crema | 380 | 6.5 | 46 | 19 | 1.5 | pezzo:80
Ciambella fritta / donut | 420 | 5.5 | 48 | 23 | 1.5 | pezzo:60
Ciambellone | 370 | 6.5 | 55 | 14 | 1.2 | fetta:60
Torta al cioccolato | 420 | 6 | 50 | 22 | 2.5 | fetta:80
Torta di mele | 270 | 4 | 42 | 10 | 1.5 | fetta:100
Cheesecake | 320 | 5.5 | 28 | 21 | 0.5 | fetta:100
Brownie | 455 | 6 | 52 | 25 | 2.5 | pezzo:50
Cantucci | 450 | 10 | 62 | 18 | 3 | cantuccio:10
Savoiardi | 390 | 9 | 73 | 6.5 | 1 | savoiardo:8
Biscotti al cioccolato | 490 | 6.5 | 64 | 23 | 3 | biscotto:12
Waffle | 440 | 6 | 52 | 23 | 1.5 | waffle:50
Crêpe | 190 | 7 | 24 | 7.5 | 0.8 | crêpe:60
Pane ai cereali | 265 | 10 | 44 | 4.5 | 6 | fetta:40
Panino al latte | 300 | 9 | 50 | 7 | 2 | panino:40
Pane per hamburger | 280 | 9 | 49 | 5 | 2.5 | panino:80
Pane carasau | 370 | 11 | 78 | 1.5 | 3 | foglio:20
Friselle | 360 | 12 | 72 | 2 | 4 | frisella:50
Crostini | 410 | 11 | 70 | 9 | 3.5 | porzione:30
Pane croccante di segale | 340 | 9 | 64 | 1.5 | 15 | fetta:10
Pinsa (base) | 240 | 8 | 46 | 2.5 | 2 | base:230
Base per pizza | 250 | 8 | 48 | 2.5 | 2 | base:250
Pizzetta rossa | 260 | 7.5 | 38 | 8.5 | 2 | pizzetta:60
Pasta sfoglia | 390 | 5.5 | 36 | 25 | 1.5 | rotolo:230
Pasta brisée | 420 | 6 | 40 | 26 | 1.5 | rotolo:230
Pan di Stelle @ Mulino Bianco | 483 | 7.5 | 65 | 20.5 | 3.5 | biscotto:8
Macine @ Mulino Bianco | 482 | 6 | 68.2 | 20 | 2.5 | biscotto:11
Abbracci @ Mulino Bianco | 491 | 7 | 60.9 | 23.5 | 2.5 | biscotto:10
Gocciole @ Pavesi | 477 | 6.7 | 65.5 | 20.5 | 3 | biscotto:12
Oro Saiwa @ Saiwa | 433 | 8.5 | 77 | 9.3 | 3 | biscotto:6
Oreo @ Oreo | 480 | 5 | 69 | 20 | 2.5 | biscotto:11
''',
    'Oli, grassi e condimenti': '''
Burro chiarificato | 880 | 0.3 | 0 | 99 | 0 | cucchiaino:5
Besciamella | 150 | 4 | 9 | 11 | 0.3 | porzione:100
Maionese light | 290 | 1 | 8 | 28 | 0 | cucchiaio:15
Salsa tzatziki | 110 | 4 | 4 | 8.5 | 0.5 | cucchiaio:20
Guacamole | 155 | 2 | 4 | 14 | 5 | cucchiaio:20
Pesto rosso | 325 | 5 | 8 | 30 | 3 | cucchiaio:15
Salsa teriyaki | 90 | 6 | 16 | 0 | 0 | cucchiaio:15
Glassa di aceto balsamico | 185 | 1 | 44 | 0 | 0 | cucchiaino:8
Brodo | 6 | 0.3 | 0.5 | 0.3 | 0 | tazza:250
Nutella @ Ferrero | 539 | 6.3 | 57.5 | 30.9 | 3.4 | cucchiaino:15
''',
    'Dolci e snack': '''
Cioccolato bianco | 545 | 6 | 58 | 32 | 0 | quadratino:10
Cioccolato fondente 85% | 590 | 10 | 20 | 50 | 12 | quadratino:10
Cioccolato alle nocciole | 558 | 8 | 48 | 37 | 3 | quadratino:10
Cioccolatino | 540 | 6 | 50 | 35 | 3 | cioccolatino:12
Crema di pistacchio | 580 | 9 | 48 | 39 | 2 | cucchiaino:15
Cono gelato confezionato | 290 | 3.5 | 35 | 15 | 1 | cono:75
Gelato su stecco ricoperto | 305 | 3.6 | 29 | 19.5 | 1 | stecco:80
Ghiacciolo | 80 | 0 | 20 | 0 | 0 | ghiacciolo:60
Sorbetto alla frutta | 130 | 0.5 | 32 | 0.3 | 0.5 | coppetta:100
Panna cotta | 250 | 2.5 | 22 | 17 | 0 | porzione:120
Crème caramel | 137 | 4.5 | 22 | 3.5 | 0 | vasetto:100
Mousse al cioccolato | 187 | 4.5 | 22 | 9 | 1 | vasetto:90
Crema pasticcera | 141 | 4 | 20 | 5 | 0 | porzione:100
Cannolo siciliano | 365 | 8 | 38 | 20 | 1 | cannolo:100
Crostatina confezionata | 412 | 5 | 62 | 16 | 1.5 | crostatina:40
Torrone | 476 | 10 | 55 | 24 | 3 | pezzo:30
Meringhe | 388 | 5 | 92 | 0 | 0 | meringa:10
Caramelle dure | 390 | 0 | 97 | 0 | 0 | caramella:5
Barretta energetica | 445 | 10 | 45 | 25 | 5 | barretta:35
Barretta al cioccolato | 485 | 5 | 62 | 24 | 1.5 | barretta:45
Nachos | 485 | 7 | 60 | 24 | 4.5 | porzione:30
Salatini | 476 | 9 | 65 | 20 | 3 | porzione:30
Snack di mais al formaggio | 518 | 7 | 55 | 30 | 1.5 | busta:25
Cornetto Classico (gelato) @ Algida | 295 | 3.6 | 34 | 16 | 1 | cono:75
Magnum Classico (gelato) @ Algida | 302 | 3.6 | 29.1 | 18.6 | 1.2 | stecco:79
Kinder Bueno @ Ferrero | 572 | 8.6 | 49.5 | 37.3 | 2 | barretta:21.5
Kinder Cioccolato @ Ferrero | 566 | 8.7 | 53.5 | 35 | 0.8 | barretta:12.5
Kinder Fetta al Latte @ Ferrero | 421 | 7.9 | 34 | 27.9 | 0.5 | pezzo:28
Kinder Pinguì @ Ferrero | 450 | 7 | 37.8 | 29.7 | 1 | pezzo:30
Ferrero Rocher @ Ferrero | 603 | 8.2 | 44.4 | 42.7 | 3.5 | pezzo:12.5
M&M's Peanut @ Mars | 512 | 9.4 | 60 | 25.6 | 2.5 | bustina:45
Snickers @ Mars | 481 | 8.6 | 60 | 23 | 1.5 | barretta:50
Mars @ Mars | 449 | 4 | 70 | 17 | 1 | barretta:51
Twix @ Mars | 494 | 4.5 | 65 | 24 | 1.5 | confezione:50
KitKat @ Nestlé | 515 | 8.2 | 58.5 | 26.9 | 2 | confezione:41.5
Milka Latte Alpino @ Milka | 539 | 6.5 | 57 | 31 | 1.8 | pezzo:25
Pringles Original @ Pringles | 534 | 5.9 | 56 | 31 | 3 | porzione:30
''',
    'Bevande': '''
Acqua tonica | 35 | 0 | 8.5 | 0 | 0 | lattina:330
Limonata | 40 | 0 | 10 | 0 | 0 | lattina:330
Chinotto | 44 | 0 | 11 | 0 | 0 | lattina:330
Succo 100% arancia | 43 | 0.7 | 9.5 | 0.1 | 0.2 | bicchiere:200
Succo ACE | 45 | 0.3 | 10.5 | 0 | 0.3 | bicchiere:200
Frullato di frutta | 55 | 0.6 | 12 | 0.3 | 1 | bicchiere:250
Frappè | 110 | 3.3 | 17 | 3.2 | 0 | bicchiere:300
Latte macchiato | 48 | 3.2 | 4.8 | 1.8 | 0 | bicchiere:250
Cioccolata calda | 93 | 3.5 | 13 | 3 | 0.8 | tazza:200
Caffè al ginseng | 85 | 0.5 | 14 | 2.8 | 0 | tazzina:50
Birra analcolica | 25 | 0.3 | 5.5 | 0 | 0 | bottiglia:330
Birra doppio malto | 62 | 0.5 | 4.5 | 0 | 0 | bottiglia:330
Negroni | 200 | 0 | 7 | 0 | 0 | bicchiere:90
Mojito | 80 | 0 | 10 | 0 | 0 | bicchiere:200
Gin tonic | 72 | 0 | 6.8 | 0 | 0 | bicchiere:200
Amaro | 240 | 0 | 22 | 0 | 0 | bicchierino:40
Coca-Cola @ Coca-Cola | 42 | 0 | 10.6 | 0 | 0 | lattina:330; bottiglietta:500
Coca-Cola Zero @ Coca-Cola | 0 | 0 | 0 | 0 | 0 | lattina:330; bottiglietta:500
Red Bull @ Red Bull | 46 | 0 | 11 | 0 | 0 | lattina:250
Monster Energy @ Monster | 47 | 0 | 11.5 | 0 | 0 | lattina:500
''',
    'Integratori': '''
Creatina monoidrato | 0 | 0 | 0 | 0 | 0 | dose:3
Destrosio | 365 | 0 | 91 | 0 | 0 | dose:30
Gel energetico | 250 | 0 | 62 | 0 | 0 | gel:40
''',
    'Piatti pronti': '''
Pizza margherita surgelata | 235 | 9.5 | 30 | 8 | 2 | pizza:330
Sofficini pomodoro e mozzarella @ Findus | 232 | 7.7 | 25 | 11 | 1.5 | sofficino:65 | ck
Big Mac @ McDonald's | 234 | 12.1 | 19.5 | 11.6 | 1.5 | panino:215
Cheeseburger @ McDonald's | 257 | 13.7 | 25.6 | 11.1 | 1.5 | panino:117
McChicken @ McDonald's | 240 | 9.7 | 24 | 11.4 | 1.5 | panino:175
Crispy McBacon @ McDonald's | 310 | 16.5 | 22 | 17 | 1.2 | panino:164
Patatine fritte @ McDonald's | 296 | 3.3 | 37 | 15 | 3.5 | medie:114; piccole:80; grandi:150
Chicken McNuggets @ McDonald's | 255 | 16 | 16 | 14 | 1 | 6 pezzi:100; 9 pezzi:150
''',
}

P200 = [{'l': 'porzione', 'g': 200}]
P150 = [{'l': 'porzione', 'g': 150}]
EGGS = [{'l': '2 uova', 'g': 100}, {'l': '3 uova', 'g': 150}]
PASTA = 'Pasta di semola (cruda)'
RISO = 'Riso bianco (crudo)'
OLIO = "Olio extravergine d'oliva"
PARM = 'Parmigiano Reggiano'
PEC = 'Pecorino romano'
GNOCCHI = 'Gnocchi di patate'
POLLO = 'Petto di pollo (crudo)'


def por(label, g):
    return [{'l': label, 'g': g}]


# (nome, categoria, base, porzioni, [(ingrediente del catalogo, grammi per grammo di base, facoltativo)])
# La prima parte è la base (r = 1). Il facoltativo è sempre un formaggio, spento di default.
DISHES = [
    # --- primi con pasta di semola
    ('Pasta alla norma', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Melanzane', 1), ('Passata di pomodoro', 0.8), (OLIO, 0.12), (PEC, 0.08, True)]),
    ('Pasta alla puttanesca', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Pomodori pelati', 0.8), ('Olive nere', 0.15), ("Acciughe sott'olio (sgocciolate)", 0.05), (OLIO, 0.08)]),
    ("Pasta all'arrabbiata", 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Pomodori pelati', 0.8), (OLIO, 0.1), ('Aglio', 0.02), (PEC, 0.05, True)]),
    ('Pasta al forno', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Ragù alla bolognese pronto', 0.6), ('Besciamella', 0.5), ('Mozzarella', 0.3), (PARM, 0.1)]),
    ('Pasta e patate', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Patate', 1.5), ('Cipolla', 0.1), (OLIO, 0.08), (PARM, 0.08, True)]),
    ('Pasta e lenticchie', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Lenticchie in scatola (sgocciolate)', 1.2), ('Passata di pomodoro', 0.2), ('Cipolla', 0.1), (OLIO, 0.08)]),
    ('Pasta con i broccoli', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Broccoli', 1.5), (OLIO, 0.1), ('Aglio', 0.02), (PEC, 0.05, True)]),
    ('Pasta con la salsiccia', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Salsiccia di maiale', 0.5), ('Passata di pomodoro', 0.6), (OLIO, 0.03), (PARM, 0.05, True)]),
    ('Pasta allo scoglio', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Cozze (sgusciate)', 0.3), ('Vongole (sgusciate)', 0.3), ('Gamberi', 0.3), ('Calamari', 0.3), ('Pomodorini', 0.5), (OLIO, 0.12)]),
    ('Pasta ai quattro formaggi', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Gorgonzola', 0.2), ('Fontina', 0.2), ('Emmental', 0.15), (PARM, 0.1), ('Panna da cucina', 0.2)]),
    ('Pasta alla boscaiola', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Funghi champignon', 0.8), ('Salsiccia di maiale', 0.4), ('Panna da cucina', 0.4), (PARM, 0.05, True)]),
    ('Pasta fredda', 'Piatti pronti', 'pasta cruda', P200,
     [(PASTA, 1), ('Pomodorini', 0.8), ('Mozzarella', 0.5), ("Tonno sott'olio (sgocciolato)", 0.4), ('Olive nere', 0.1), (OLIO, 0.1)]),
    ('Pastina in brodo', 'Piatti pronti', 'pastina cruda', por('porzione', 80),
     [(PASTA, 1), ('Brodo', 3.5), (PARM, 0.1, True)]),
    # --- gnocchi e pasta ripiena
    ('Gnocchi al ragù', 'Piatti pronti', 'gnocchi crudi', por('porzione', 250),
     [(GNOCCHI, 1), ('Ragù alla bolognese pronto', 0.4), (PARM, 0.04, True)]),
    ('Gnocchi alla sorrentina', 'Piatti pronti', 'gnocchi crudi', por('porzione', 250),
     [(GNOCCHI, 1), ('Sugo al pomodoro pronto', 0.4), ('Mozzarella', 0.25), (PARM, 0.04)]),
    ('Gnocchi al pesto', 'Piatti pronti', 'gnocchi crudi', por('porzione', 250),
     [(GNOCCHI, 1), ('Pesto alla genovese', 0.12), (PARM, 0.04, True)]),
    ('Tortellini panna e prosciutto', 'Piatti pronti', 'tortellini crudi', por('porzione', 150),
     [('Tortellini di carne freschi', 1), ('Panna da cucina', 0.3), ('Prosciutto cotto', 0.2), (PARM, 0.05, True)]),
    ('Tortellini in brodo', 'Piatti pronti', 'tortellini crudi', por('porzione', 125),
     [('Tortellini di carne freschi', 1), ('Brodo', 2.5), (PARM, 0.05, True)]),
    # --- riso e cereali
    ('Risotto alla zucca', 'Piatti pronti', 'riso crudo', P150,
     [(RISO, 1), ('Zucca', 1.5), ('Burro', 0.08), (PARM, 0.1), ('Cipolla', 0.1)]),
    ('Risotto agli asparagi', 'Piatti pronti', 'riso crudo', P150,
     [(RISO, 1), ('Asparagi', 1), ('Burro', 0.08), (PARM, 0.1), ('Cipolla', 0.1)]),
    ('Risotto ai frutti di mare', 'Piatti pronti', 'riso crudo', P150,
     [(RISO, 1), ('Cozze (sgusciate)', 0.3), ('Vongole (sgusciate)', 0.3), ('Gamberi', 0.3), ('Calamari', 0.3), ('Pomodorini', 0.3), (OLIO, 0.1)]),
    ('Risotto con la salsiccia', 'Piatti pronti', 'riso crudo', P150,
     [(RISO, 1), ('Salsiccia di maiale', 0.5), ('Burro', 0.05), (PARM, 0.1), ('Cipolla', 0.1)]),
    ('Riso e pollo', 'Piatti pronti', 'riso crudo', P150,
     [(RISO, 1), (POLLO, 1.5), (OLIO, 0.08)]),
    ('Riso al tonno', 'Piatti pronti', 'riso crudo', P150,
     [(RISO, 1), ('Tonno al naturale (sgocciolato)', 0.7), (OLIO, 0.08)]),
    ('Pollo al curry con riso', 'Piatti pronti', 'riso crudo', P150,
     [('Riso basmati (crudo)', 1), (POLLO, 1.2), ('Panna da cucina', 0.3), ('Cipolla', 0.2), (OLIO, 0.05)]),
    ('Polenta al ragù', 'Piatti pronti', 'farina cruda', por('porzione', 80),
     [('Farina di mais / polenta (cruda)', 1), ('Ragù alla bolognese pronto', 1.2), (PARM, 0.1, True)]),
    ('Zuppa di lenticchie', 'Piatti pronti', 'lenticchie secche', por('porzione', 80),
     [('Lenticchie secche', 1), ('Passata di pomodoro', 0.5), ('Carote', 0.4), ('Cipolla', 0.3), ('Sedano', 0.2), (OLIO, 0.12)]),
    ("Porridge d'avena", 'Piatti pronti', "fiocchi d'avena", por('porzione', 50),
     [("Fiocchi d'avena", 1), ('Latte parzialmente scremato', 4)]),
    ('Porridge con banana e miele', 'Piatti pronti', "fiocchi d'avena", por('porzione', 50),
     [("Fiocchi d'avena", 1), ('Latte parzialmente scremato', 4), ('Banana', 2), ('Miele', 0.2)]),
    ('Cereali e latte', 'Piatti pronti', 'cereali', por('tazza', 30),
     [('Corn flakes', 1), ('Latte parzialmente scremato', 6.5)]),
    # --- secondi
    ('Cosce di pollo in padella', 'Piatti pronti', 'cosce crude', [{'l': 'coscia', 'g': 150}, {'l': '2 cosce', 'g': 300}],
     [('Cosce di pollo con pelle (crude)', 1), ('Burro', 0.04), (OLIO, 0.03)]),
    ('Pollo alla cacciatora', 'Piatti pronti', 'pollo crudo', por('porzione', 200),
     [('Cosce di pollo senza pelle (crude)', 1), ('Pomodori pelati', 0.5), ('Cipolla', 0.15), ('Olive nere', 0.08), (OLIO, 0.06)]),
    ('Scaloppine di pollo al limone', 'Piatti pronti', 'pollo crudo', P150,
     [(POLLO, 1), ('Farina 00', 0.08), ('Burro', 0.06), (OLIO, 0.03)]),
    ('Straccetti di manzo con rucola e grana', 'Piatti pronti', 'manzo crudo', P150,
     [('Fettine di manzo magre', 1), ('Rucola', 0.25), ('Grana Padano', 0.12), (OLIO, 0.07)]),
    ('Spezzatino con patate', 'Piatti pronti', 'carne cruda', P150,
     [('Spezzatino di manzo (crudo)', 1), ('Patate', 1), ('Passata di pomodoro', 0.3), ('Cipolla', 0.2), ('Carote', 0.2), (OLIO, 0.07)]),
    ('Chili con carne', 'Piatti pronti', 'carne cruda', P150,
     [('Macinato di manzo 15% grassi', 1), ('Fagioli rossi in scatola', 0.8), ('Passata di pomodoro', 0.8), ('Cipolla', 0.2), (OLIO, 0.05)]),
    ('Salsiccia e friarielli', 'Piatti pronti', 'salsiccia cruda', P150,
     [('Salsiccia di maiale', 1), ('Cime di rapa', 1), (OLIO, 0.08)]),
    ('Salmone al forno con patate', 'Piatti pronti', 'salmone crudo', P150,
     [('Salmone fresco', 1), ('Patate', 1.2), (OLIO, 0.07)]),
    ('Insalata di polpo e patate', 'Piatti pronti', 'polpo crudo', por('porzione', 200),
     [('Polpo', 1), ('Patate', 0.8), (OLIO, 0.08)]),
    ('Tonno e fagioli', 'Piatti pronti', 'tonno sgocciolato', por('porzione', 80),
     [("Tonno sott'olio (sgocciolato)", 1), ('Fagioli cannellini in scatola', 2), ('Cipolla', 0.3), (OLIO, 0.1)]),
    ('Bresaola, rucola e grana', 'Piatti pronti', 'bresaola', por('porzione', 80),
     [('Bresaola', 1), ('Rucola', 0.4), ('Grana Padano', 0.25), (OLIO, 0.1)]),
    ('Prosciutto e melone', 'Piatti pronti', 'prosciutto', por('porzione', 60),
     [('Prosciutto crudo', 1), ('Melone', 3)]),
    # --- uova
    ('Uova strapazzate', 'Uova', 'uova', EGGS,
     [('Uovo intero', 1), ('Burro', 0.06)]),
    ('Frittata di zucchine', 'Uova', 'uova', EGGS,
     [('Uovo intero', 1), ('Zucchine', 1), (OLIO, 0.08), (PARM, 0.1, True)]),
    ('Omelette prosciutto e formaggio', 'Uova', 'uova', EGGS,
     [('Uovo intero', 1), ('Prosciutto cotto', 0.3), ('Emmental', 0.25), ('Burro', 0.05)]),
    ('Uova al pomodoro', 'Uova', 'uova', EGGS,
     [('Uovo intero', 1), ('Passata di pomodoro', 1), (OLIO, 0.08)]),
    # --- insalate, contorni e panini
    ('Insalata mista condita', 'Piatti pronti', 'insalata', por('porzione', 100),
     [('Lattuga / insalata', 1), ('Pomodori', 0.8), ('Carote', 0.3), (OLIO, 0.1)]),
    ('Insalata di pollo', 'Piatti pronti', 'pollo crudo', P150,
     [(POLLO, 1), ('Lattuga / insalata', 0.6), ('Pomodorini', 0.5), ('Mais dolce in scatola', 0.2), (OLIO, 0.07)]),
    ('Insalata greca', 'Piatti pronti', 'pomodori', P150,
     [('Pomodori', 1), ('Cetrioli', 0.7), ('Feta', 0.5), ('Olive nere', 0.15), ('Cipolla', 0.15), (OLIO, 0.1)]),
    ('Caesar salad', 'Piatti pronti', 'insalata', por('porzione', 120),
     [('Lattuga / insalata', 1), (POLLO, 1), ('Crostini', 0.2), (PARM, 0.15), ('Maionese', 0.15)]),
    ('Purè di patate', 'Piatti pronti', 'patate crude', por('porzione', 250),
     [('Patate', 1), ('Latte intero', 0.25), ('Burro', 0.06), (PARM, 0.04, True)]),
    ('Bruschetta al pomodoro', 'Piatti pronti', 'pane', por('2 fette', 80),
     [('Pane comune', 1), ('Pomodori', 1), (OLIO, 0.12)]),
    ('Piadina crudo, stracchino e rucola', 'Piatti pronti', 'piadina', por('piadina', 90),
     [('Piadina', 1), ('Prosciutto crudo', 0.55), ('Stracchino / crescenza', 0.55), ('Rucola', 0.2)]),
    ('Piadina cotto e fontina', 'Piatti pronti', 'piadina', por('piadina', 90),
     [('Piadina', 1), ('Prosciutto cotto', 0.6), ('Fontina', 0.4)]),
    ('Wrap di pollo', 'Piatti pronti', 'tortilla', por('wrap', 60),
     [('Tortilla / wrap', 1), (POLLO, 1.5), ('Lattuga / insalata', 0.5), ('Maionese', 0.2)]),
    ('Avocado toast con uovo', 'Piatti pronti', 'pane', por('2 fette', 80),
     [('Pane integrale', 1), ('Avocado', 1), ('Uovo intero', 0.65), (OLIO, 0.05)]),
    ('Pane, burro e marmellata', 'Piatti pronti', 'pane', por('2 fette', 50),
     [('Pane comune', 1), ('Burro', 0.2), ('Marmellata / confettura', 0.4)]),
    ('Pane e Nutella', 'Piatti pronti', 'pane', por('2 fette', 50),
     [('Pane comune', 1), ('Nutella', 0.4)]),
    ('Yogurt greco, noci e miele', 'Piatti pronti', 'yogurt', por('vasetto', 170),
     [('Yogurt greco 0%', 1), ('Noci', 0.12), ('Miele', 0.06)]),
]

foods = json.load(open(PATH, encoding='utf-8'))
ids = {f['id'] for f in foods}


def insert(item):
    idx = max((i for i, f in enumerate(foods) if f['cat'] == item['cat']), default=len(foods) - 1)
    foods.insert(idx + 1, item)
    ids.add(item['id'])


added = 0
for cat, rows in BASE.items():
    for row in rows.strip().splitlines():
        c = [x.strip() for x in row.split('|')]
        assert len(c) in (7, 8), row
        name, _, brand = c[0].partition(' @ ')
        item = {'id': 's:' + slug(name if not brand or slug(brand) in slug(name) else f'{name} {brand}'), 'n': name}
        if item['id'] in ids:
            continue
        if brand:
            item['brand'] = brand
        k, p, cb, f = (float(x) for x in c[1:5])
        # i valori devono tornare con le calorie (fibre a 2 kcal/g, alcol escluso)
        est = 4 * p + 4 * cb + 9 * f + 2 * float(c[5])
        assert cat == 'Bevande' or k == 0 or abs(est - k) <= max(25, k * 0.08), (name, k, round(est))
        item.update({'cat': cat, 'k': num(k), 'p': num(p), 'c': num(cb), 'f': num(f), 'fi': num(c[5])})
        item['por'] = [{'l': l.strip(), 'g': num(g)} for l, g in (x.split(':') for x in c[6].split(';'))]
        if len(c) == 8:
            assert c[7] == 'ck', row
            item['ck'] = True
        insert(item)
        added += 1

by_name = {f['n']: f for f in foods}
dishes = 0
for name, cat, base, portions, parts in DISHES:
    did = 's:' + slug(name)
    d = next((f for f in foods if f['id'] == did), None)
    if d is None:
        d = {'id': did, 'n': name, 'cat': cat}
        insert(d)
        by_name[name] = d
        added += 1
    tot = {k: 0.0 for k in ('k', 'p', 'c', 'f', 'fi')}
    out = []
    for part in parts:
        pname, r, opt = part[0], part[1], len(part) > 2 and part[2]
        src = by_name[pname]
        assert 'base' not in src, (name, pname)
        if not opt:
            for k in tot:
                tot[k] += src.get(k, 0) * r
        o = {'n': src['n'], 'r': r, 'k': src['k'], 'p': src['p'], 'c': src['c'], 'f': src['f']}
        if opt:
            o['o'] = True
        out.append(o)
    assert out[0]['r'] == 1 and 'o' not in out[0], name
    assert sum('o' in o for o in out) <= 1, name
    for k, v in tot.items():
        d[k] = num(v)
    d.update({'por': portions, 'base': base, 'parts': out})
    d.pop('ck', None)
    dishes += 1

assert len({f['id'] for f in foods}) == len(foods), 'id doppi'
assert len({(f['n'], f.get('brand')) for f in foods}) == len(foods), 'nomi doppi'
json.dump(foods, open(PATH, 'w', encoding='utf-8', newline=''), ensure_ascii=False, separators=(',', ':'))
print(len(foods), 'alimenti:', added, 'nuovi,', dishes, 'piatti di questo giro,', sum('brand' in f for f in foods), 'di marca')
