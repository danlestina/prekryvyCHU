# Historie změn – Překryvy chráněných území ČR

## 18. 11. 2026 – úprava veřejné dokumentace

- `README.md` přepracován na stručnější úvod do účelu, principu a použití projektu.
- Plný obsah předchozího `README.md` přesunut níže do historického archivu; nic z původních instrukcí nebylo vypuštěno.
- Licence MIT původního kódu zachována, doplněno oddělení externích dat AOPK ČR a ČÚZK (CC BY 4.0).
- Historický archiv níže může obsahovat starší příkazy a neaktuální omezení; pro běžné použití platí současný README a kód.

## v0.6.5.1–v0.6.5.8 – dokončování diagnostiky a veřejného webu

- **v0.6.5.1:** opraveno povinné vytváření listu `Nesoulady_po_uzemich` a kontroly diagnostického Excelu; místní test `overeni_v063.R` následně prošel.
- **v0.6.5.2:** hromadné ovládání voleb, rozbalení obsahu buněk, oprava víceúrovňových záhlaví a formátovanější klientský export XLSX.
- **v0.6.5.3:** hierarchická zaškrtávátka pro výběr řádků i kategorií překryvů včetně společných voleb sloupců.
- **v0.6.5.4:** kompaktnější rozložení formuláře; `OP VZCHÚ` nahrazeno jednotlivou kategorií `OP NP`.
- **v0.6.5.5:** logické výchozí pořadí kategorií a řazení kliknutím na záhlaví všech sloupců, včetně exportu v aktuálním pořadí.
- **v0.6.5.6:** jednotnější zaokrouhlování celkových ploch a procent OOP a obnovení barevného členění kategorií.
- **v0.6.5.7:** oprava číselných formátů v exportu XLSX tak, aby u celých čísel nezůstávala osamocená desetinná čárka; numerické hodnoty zůstávají číselné.
- **v0.6.5.8:** SCHÚ a vojenské újezdy mají ve formuláři oddělené skupinové boxy.

---

## v0.6.5.1 – oprava diagnostického souhrnu a testu

- List `Nesoulady_po_uzemich` se vytváří vždy (i prázdný), nikoli jen při splnění tiché podmínky.
- Pokud chybějí potřebné sloupce v `katalog_nesouladu.xlsx`, skript skončí s přesným seznamem chybějících a přítomných sloupců; nevytvoří neúplný souhrnný Excel.
- Test uvádí konkrétní chybějící listy a odstraňuje se neškodné varování `grepl()` ve webovém generátoru.
- Výpočet překryvů a OOP je beze změn. Ověřeno staticky, nikoli během R.

## v0.6.3 – srozumitelnost OOP, mikrofragmenty, cache (neověřeno běžícím R)

- Veřejný OOP souhrn ignoruje současně <1 m² a <0,001 %; detailní geometrie zůstává.
- Interní stavy a vysvětlení porovnání OOP DR ÚSOP vs. geometrie, bez přebírání evidovaného OOP do výpočtu.
- Popisné české hlavičky Excelů se strojovým názvem v hranatých závorkách.
- Souhrn geometrických nesouladů podle území a názvy diagnostických vrstev.
- Datum poslední změny ručního exportu DR ÚSOP a jasné upozornění na jeho omezení.
- GitHub Actions: omezená obnovitelná cache s online ověřením zdroje a konzervativním obnovením při chybě změnových metadat.

## v0.6.2 (11. 11. 2026)
- Opraveno: `--diagnostic-dir` se vytváří před prvním diagnostickým zápisem.
- XLSX/GPKG se sestavují v lokálním dočasném adresáři mimo Nextcloud.
- Hotový soubor se bezpečně předá do cílového adresáře; při zámku zůstane nový výstup pod alternativním názvem.
- `diagnostika/` uvnitř pracovního repozitáře zůstává výchozím trvalým úložištěm.
- Žádný výpočet nebyl v tomto prostředí spouštěn (R není dostupné).

## v0.6.1 – oprava zamykani Windows / Nextcloud
- Bezpecny zapis internich XLSX/GPKG se tremi pokusy a nahradnim jedinecnym jmenem pri zamku; zachovani predchoziho souboru.
- Souhrn diagnostiky nacita skutecne vytvorene cesty, GPKG topologie je identifikovan v listu Informace.
- Hlavni verejny vypocet a jeho format beze zmeny.

## v0.6.0 – 11. 11. 2026

- Samostatný veřejný a interní Excel, bez sloupců či listů DR ÚSOP v publikaci.
- Interní diagnostika vzájemných překryvů MZCHÚ, VZCHÚ a EVL v tabulkách a GeoPackage.
- Sdružený diagnostický XLSX včetně hlášení neznámého data ručního exportu DR ÚSOP.
- Diagnostika celé ČR nezávislá na testovacím vzorku; veřejný GitHub Actions běh zůstává bez interních dat.
- Neověřeno spuštěním R v tomto prostředí; vyžaduje lokální test.

# v0.5.9 (11. 11. 2026)

- Nový výchozí import jednoho `drusop_oop.txt` ze všech evidencí, CP1250/TSV; kontrola patičky COUNT.
- Párování KÓD ÚSOP + KATEGORIE, včetně ověření názvů; ochranná pásma a vojenské újezdy mají explicitní stav bez samostatného záznamu.
- Srovnání sad několika OOP, normalizace základních úředních variant názvů, přehled úřadů jen ve zdroji vs. jen v GIS.
- Čitelný protokol importu a test `tests/overeni_jednotneho_DRUSOP.R`.
- Nezveřejňovat zdrojový TXT v repozitáři (.gitignore).
- GIS geometrické výpočty, CRS EPSG:5514 i jejich metodika z v0.5.8 jsou beze změny.

# v0.5.8 – 10. 11. 2026

- OOP: zabránění věcně nepřípustného přiřazení krajského úřadu uvnitř kategorií CHKO, NPR, NPP a jejich relevantních OP, NP/OP_NP, bez plošného filtru; diagnostický GPkg pro kandidátní fragmenty.
- Geometrie vs. numerika: při plošně téměř úplném překryvu kontrola skutečného rozdílu polygonů; explicitní stav přesnosti v souhrnu kategorií.
- DR ÚSOP: import hromadných exportních tabulek podle ÚSOP kódu, místo neúspěšného procházení jednotlivých HTML detailů; duplicita URL odstraněna.
- Excel: čitelnější pastelové bloky kategorií, 25bodová výška řádků, tučné záhlaví a první dva sloupce, zmrazení C2 a užší druhý sloupec.
- Testy: testy XLSX a parseru exportů v samostatných R skriptech.

## Nehotové

Automatické HTTP stažení výstupu z PHP exportního formuláře DR ÚSOP nebylo ověřeno; v této verzi se používá ručně vyexportovaná tabulka. Všechny nové R části vyžadují lokální spuštění, prostředí tvorby nemá R.

## v0.6.4 – interaktivní veřejný přehled
- Samostatný HTML (lokální otevření i GitHub Pages); filtry řádků a sloupců; klientský XLSX export vybraného pohledu.
- Kód ÚSOP jako první sloupec; zúžení číselných sloupců.

## v0.6.5 – 4 platné číslice
- HTML zobrazení a XLSX export uživatelského výběru: sjednocené zaokrouhlení na 4 platné číslice, nikdy na desítky a hrubší.
- XLSX export obsahuje skutečné numerické buňky s odpovídajícím formátem až do 30 desetinných míst (pro extrémní rozsahy text).
- R funkce pro zobrazované plochy v ha a procenta sjednoceny se stejným pravidlem.
- Přiložen samostatný celostátní HTML náhled z posledního dostupného výpočtu a návod po návratu.

---

## Archiv původního `README.md` (obsah před přepracováním, beze změn)

> **Historický dokument.** Následující text je úplná kopie dřívějšího README. Je určen pro dohledání změn a starších provozních doporučení, nikoli jako aktuální úvodní návod.

# Překryvy chráněných území – v0.6.3 (k ověření v R)

## Novinky v0.6.3

- **Geometrické OOP a DR ÚSOP zůstávají nezávislé.** Evidence nikdy nepřepisuje GIS. Souhrnný počet OOP a řetězec `OOP_souhrn` nyní vynechává mikrofragmenty (`plocha < 1 m²` **a současně** `< 0,001 % plochy území`). Přesná výměra těchto fragmentů zůstává v detailním listu `OOP_podle_uradu` a v interní `DRUSOP_kontrola`.
- Interní stavy: `SHODA`, `MIKROFRAGMENT`, `DILCI_PUSOBNOST`, `ROZDIL_K_PROVERENI`, další stavy pro chybějící export. `DILCI_PUSOBNOST` pouze znamená, že geometricky existuje další významný OOP vedle evidovaného; skutečný právní důvod se musí ověřit. Případy PUOS **nevyhodnocujeme**.
- **Dlouhé české hlavičky v Excelu**: původní strojový název každého pole zůstává v `[hranatých závorkách]`. Mění se pouze hlavičky exportu, ne názvy proměnných ani veřejné JSON API. Návazné externí skripty čtoucí Excel podle přesného názvu původního sloupce je potřeba upravit.
- Interní `Nesoulady_po_uzemich`: součet ploch a počet fragmentů za území a typ geometrického nesouladu. Opraveny názvy vrstev v diagnostice přesahů.
- Datum DR ÚSOP: bez explicitního parametru použijeme z vlastnosti souboru **datum poslední změny**, nikoli doložené datum exportu. Kopírování jej může změnit. Ruční export je nadále třeba aktualizovat.
- GitHub: obnovitelná ověřená mezipaměť, horní limit uloženého objemu 250 MiB. Před použitím cache se ověří `editingInfo.lastEditDate` nebo `zmenaG` a identifikátory. Pokud žádný spolehlivý změnový údaj služba neposkytuje, vrstva se plně stáhne. Starší nevyužité verze cache nechává uklidit GitHub. GitHub Actions i bez cache musí fungovat.
- Pro offline otevření webu nadále platí samostatný lokální HTML export z minulé verze; standardní `site/index.html` používá JSON a vyžaduje HTTP server nebo GitHub Pages.

### Příkazy v Git Bash (Windows)

```bash
Rscript -e "invisible(parse(file='prekryvy_uzemi.R')); cat('SYNTAXE OK\n')"
Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true --drusop-file=drusop_oop.txt --out=test_v063.xlsx
Rscript tests/overeni_v063.R test_v063.xlsx diagnostika/diagnostika_aktualni.xlsx
```

**Před prvním testem zavřete otevřené Excely diagnostiky**; při uzamčení Nextcloud je nový soubor uložen s příponou `_pripraveno_...xlsx` a pro třetí příkaz se musí použít tento skutečný název. Neprovádět automaticky plný běh, dokud test neprojde.

### GitHub

GitHub Actions běží jen s `--mode=public` a nikdy nesmí publikovat `diagnostika/` ani `drusop_oop.txt`. Cache je kontrolována proti zdroji; absence změnového údaje automaticky znamená nové stažení. Nasazení na GitHubu je třeba jednou ověřit ručně.

---

# Oprava v0.6.2 – Nextcloud je cílové úložiště

Výchozí adresář diagnostiky je stále `diagnostika/` uvnitř repozitáře na Nextcloudu. `C:/GIS_diagnostika` není potřebný, automaticky se nečistí a nemusí se vůbec používat. Program nyní předem vytváří cílovou složku a ověřuje její existenci. Pracovní soubory XLSX/GPKG vznikají v místním systémovém `tempdir()` mimo Nextcloud. Až po jejich úplném dokončení je program kopíruje do jedinečně pojmenovaného hotového souboru v cílové složce a pokouší se nahradit stabilní název. Pokud jej Windows/Nextcloud blokuje, nová verze zůstane uložená pod jednoznačným náhradním názvem a její cestu program vypíše. Starý stabilní soubor se pak nepovažuje za aktuální. Lokální pracovní soubory program po úspěšném předání odstraňuje. Pro veřejné XLSX nadále platí předchozí mechanismus zápisu, proto jej při otevřeném Excelu zavřít.

Doporučený test v Git Bash, v existující složce `~/Nextcloud/git/prekryvy_uzemi`:

```bash
Rscript -e "invisible(parse(file='prekryvy_uzemi.R')); cat('SYNTAXE OK\n')"
Rscript prekryvy_uzemi.R --mode=diagnostic
```

Výstup: `diagnostika/diagnostika_aktualni.xlsx` a diagnostické GPKG, případně jiné názvy výslovně vypsané při konfliktu. V tomto režimu se **nekontroluje DRÚSOP ani geometrické přiřazení OOP** – ty vyžadují `--mode=both`. V případě potřeby druhý test:

```bash
Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true --drusop-file=drusop_oop.txt --out=test_v062.xlsx
Rscript tests/overeni_v060.R test_v062.xlsx diagnostika/diagnostika_aktualni.xlsx
```

U obou příkazů zachovat již vytvořenou cache; čas získání podkladů se řídí stávajícím pravidlem. V R není zde v prostředí dostupný interpret, proto vyžadují skutečné ověření na Windows.

## Historie předchozích verzí

Výchozí provozní režim počítá překryvy všech území se všemi; testovací režim vybírá 10 cílů z každé kategorie proti úplným referenčním vrstvám. Interní diagnostika zachovává původní geometrie. Všechny GIS operace probíhají v EPSG:5514. Při chybě povinných vrstev se finální XLSX nevytvoří.

## Oprava v0.6.1 – Nextcloud a uzamcene diagnosticke soubory

Na Windows muze Nextcloud, Excel ci GIS docasne uzamknout cilovy XLSX/GPKG. Skript se pokusi o bezpecnou vymenu 3x. Pokud cil stale nelze prepsat, novy **interni** soubor ulozi pod jedinecnym nazvem do `diagnostika/`, vypise `ZAMENY SOUBORU` a **stary soubor s nazvem `*_aktualni` neni aktualni**. Interni souhrn cte skutecne nove soubory a uvadi skutecne jmeno GPKG topologie. Nezamenujte tedy vychozi stary soubor s novym. Pri prvnim overeni doporucujeme vypnout synchronizaci nebo pouzit lokalni diagnosticky adresar mimo Nextcloud: `--diagnostic-dir=C:/GIS_diagnostika` (parametry se pisou s pomlckami; pomocny parser je prevadi na podtrzitka).

## Novinky v0.6.0 – oddělení publikace od diagnostiky

- `--mode=public`: pouze veřejný Excel a `site/`; žádná kontrola DR ÚSOP ani interní geometrie. Veřejný souhrn neobsahuje `OOP_DRUSOP`, `OOP_shoda`, `DRUSOP_*`, `OOP_pouze_*` ani listy `DRUSOP_kontrola` a `OOP_kontrola`. Geometricky vypočítané OOP a jejich podíly zůstávají.
- `--mode=both`: navíc interní `diagnostika/diagnostika_aktualni.xlsx` s kontrolami DR ÚSOP, stavem geometrického modelu OOP, neplatnými geometriemi, dalšími nesoulady a třemi topologickými kontrolami; související geometrie jsou v oddělených GeoPackage souborech.
- `--mode=diagnostic`: pouze interní kontrola geometrií a vzájemných překryvů všech evidovaných území bez veřejného výsledku. Kontrola DR ÚSOP / geografického OOP v tomto zrychleném režimu neprobíhá, protože se nepřepočítává model OOP; pro tuto kontrolu použít `both`.
- Topologie: `Prekryvy_MZCHU` (NPR/NPP/PR/PP), `Prekryvy_VZCHU` (NP/CHKO), `Prekryvy_EVL` (EVL). Srovnává se každá dvojice odlišných území bez ohledu na vzorkování cílů; společná hranice bez plochy se nezapisuje. Rozlišení mikropřekryvů lze měnit `--diagnostic-min-area-m2` (výchozí 0,01 m²). Nález automaticky neznamená právní chybu.
- **Datum exportu DR ÚSOP je ruční údaj**: předejte `--drusop-export-date=YYYY-MM-DD` (den pořízení exportu, nikoli den importu). Není-li uvedeno, bude `NEZJISTENO`. Interní list `Informace` výslovně upozorňuje, že se export automaticky neaktualizuje.
- Dosavadní jednotlivé soubory interních kontrol zůstávají pro mapovou diagnostiku; `diagnostika_aktualni.xlsx` je jejich společný tabulkový rozcestník.

Příklad lokálního testu:

```bash
Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true \
  --drusop-file=drusop_oop.txt --drusop-export-date=2026-11-11 --out=test_v060.xlsx
Rscript tests/overeni_v060.R test_v060.xlsx diagnostika/diagnostika_aktualni.xlsx
```

**GitHub:** existující `.github/workflows/tydenni-vypocet.yml` již obsahuje pondělní automatický běh `--mode=public` a přímé publikování artefaktu z `site/` na GitHub Pages. Není nutné přepínat Pages na `/docs`; v nastavení Pages zvolte zdroj **GitHub Actions**. Před prvním zveřejněním zkontrolujte veřejné soubory a spusťte plný výpočet.

**Omezení ověření:** zde nebylo dostupné R/Rscript; změny vyžadují spuštění výše uvedených testů v prostředí s R, sf a ostatními knihovnami. Verze zatím není validovaná provozním během.

## Novinky v0.5.9

- **Jediný společný soubor DR ÚSOP:** uložit `drusop_oop.txt` do pracovní složky, spustit `--drusop=true` (nebo výslovně `--drusop-file=drusop_oop.txt`). Skript načte všechny kategorie v jednom exportu; kontroluje počty přes `COUNT:`, rozlišuje kód **i kategorii**, srovnává více OOP a eviduje odlišné pojmenování. Vypočtený geografický OOP nikdy nepřepisuje. Starý režim s 5 exporty zůstává jako alternativa, pokud `drusop_oop.txt` ve WD není.
- **Třetí strana pro kontrolu:** `tests/overeni_jednotneho_DRUSOP.R` lze spustit bez GIS a internetu, aby se chyba vstupního souboru projevila před několikahodinovým výpočtem.

## Ostatní změny z v0.5.8

- **OOP podle věcné příslušnosti:** krajský úřad se nikdy nesmí objevit jako OOP pro CHKO, NPR, NPP, OP_NPR, OP_NPP, NP nebo OP_NP. Nejde o potlačení podle malé velikosti. Nepřiřazené fragmenty se nevydávají za jiný úřad. Je-li v testovaném cíli nalezen geometrický kandidát KÚ, ale jeho přiřazení je podle kategorie nepřípustné, uloží se v režimu `both` do `diagnostika/nepripustne_OOP_kraje.gpkg` k mapové kontrole. Není-li fragment viditelný, nemusí být chybně vyhlášeno území; může jít o numerický mikrozbytek.
- **Blízkost 100 %:** při velmi těsné shodě výměr se dodatečně prověří rozdíl skutečných geometrií. V listu `Souhrn_po_kategoriich` je `presnost_vypoctu`: geometricky úplné pokrytí s numerickým rozdílem výměry vs. skutečný rozdílový polygon. Velmi malé polygony se neoznačují automaticky jako chyby jen proto, že jsou malé. V detailních listech zůstávají nezaokrouhlené hodnoty.
- **Excel:** první řádek a první dva sloupce tučně, řádky stejné výšky 25 bodů, první řádek a první dva sloupce ukotveny, druhý sloupec zúžen na šířku 29 znaků. Každý blok kategorie má odlišné čitelné tlumené podbarvení, včetně všech pokračovacích sloupců. URL na kartu DR ÚSOP je jen jednou.
- **DR ÚSOP:** místo nefunkčního čtení OOP z jednotlivých karet používáme **hromadné tabulkové exporty** se sloupci `Kód` a `Orgán(y) ochrany přírody`. Tyto údaje jsou zcela nezávislé na GIS modelu OOP.

## Rychlý test v RStudiu / Git Bash

```bash
Rscript -e "invisible(parse(file='prekryvy_uzemi.R')); cat('SYNTAXE OK\n')"
Rscript tests/overeni_jednotneho_DRUSOP.R drusop_oop.txt
Rscript prekryvy_uzemi.R --self-test-geometrie=true
Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true --out=test_v059.xlsx
Rscript tests/overeni_v059.R test_v059.xlsx
```

### OOP z DR ÚSOP – JEDINÝ celostátní TXT (doporučeno)

1. Ulož soubor `drusop_oop.txt` do stejné pracovní složky, v níž spouštíš `Rscript` (`getwd()` v RStudiu); není nutné jej převádět do UTF-8. Původní export je CP1250, oddělený tabulátory.
2. Ověř čistě lokální import: `Rscript tests/overeni_jednotneho_DRUSOP.R drusop_oop.txt`.
3. Spusť úplný test: `Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true --drusop-file=drusop_oop.txt --out=test_v059.xlsx`.
4. Kontrolu XLSX: `Rscript tests/overeni_v059.R test_v059.xlsx`.

**Ještě rychlejší kontrola bez nového GIS výpočtu:** pro už hotový `test_v058.xlsx` je připraven samostatný pomocný skript:

```bash
Rscript kontrola_drusop_z_xlsx.R --in=test_v058.xlsx --drusop-file=drusop_oop.txt --out=kontrola_drusop_v058.xlsx
```

Výsledek je nový menší XLSX s porovnáním OOP všech 130 testovaných území. Původní soubor zůstane beze změny. Tento skript potřebuje jen `openxlsx` a nepotřebuje GIS ani internet. V aktuálním dodaném exportu: 67 shod, 17 rozdílů k prověření a 46 bez samostatného záznamu (ověřeno nezávislou kontrolou souborů).

Import ignoruje památné stromy pro náš polygonový model, ale ověřuje počet všech řádků v exportu. V samotném XLSX pro ochranná pásma a vojenské újezdy vypíše `BEZ_SAMOSTATNEHO_ZAZNAMU`, nikoliv neexistující OOP. Exportované informace mohou být starší než živá GIS data; kódy, které už v exportu nejsou, dostanou stav `KOD_NENALEZEN_V_EXPORTU` a **nepřepisují** geografický výpočet. Další položky `OOP_pouze_DRUSOP` a `OOP_pouze_geo` pomáhají konkrétně lokalizovat rozdíl.

Při publikaci na veřejném GitHubu je soubor `drusop_oop.txt` výslovně uveden v `.gitignore`; před případným publikováním hromadného exportu je třeba prověřit licenční podmínky.

### Starší možnost: exporty oddělené podle evidencí

1. V jednotlivých přehledech DR ÚSOP (EVL, PO, MZCHÚ, VZCHÚ, SCHÚ) zvolte `Export` → `Vše`, zaškrtněte minimálně **Kód** a **Orgán ochrany přírody**, uložte ve formátu `Excel (Tabbed)` (nebo `xlsx/csv`). Ideálně také `Kategorie`, pokud existuje.
2. Nerozbalené exportní tabulky dejte do `drusop_exporty/` s názvy obsahujícími `EVL`, `PO`, `MZCHU`, `VZCHU`, `SCHU` (např. `EVL.xls`, `PO.xls`). U `Excel (Tabbed)` může jít o tabulátory oddělený text, i když má soubor příponu `.xls`.
3. Spusťte:

```bash
Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true --drusop-export-dir=drusop_exporty --out=test_v058_drusop.xlsx
Rscript tests/overeni_v059.R test_v058_drusop.xlsx
```

Pokud export chybí, stav OOP v DR ÚSOP bude `EXPORT_CHYBI`, nikdy domyšlená hodnota. Duplicitní kódy v jednom exportu nebo absence povinných sloupců způsobí chybu. Nejdříve je nutné vždy ověřit, zda export skutečně obsahuje všechny záznamy, a nikoliv jen aktuální stránku. Počty exportů skript vypisuje do terminálu.

**Přímé automatické stažení z webového formuláře zatím není dokončené.** AOPK dokumentuje interaktivní export, nikoli stabilní HTTP API, a dostupný webový nástroj mi neposkytl samotnou odpověď po stisku tlačítka Exportovat. Neslibuji, že lze použít adresu s `EXPORT_ALL_step=1` jako přímý soubor. Pro automatizaci budeme potřebovat zachytit skutečný exportní HTTP požadavek (například v DevTools → Network → Copy as cURL) a ověřit, zda nepotřebuje cookies/session.

### Další metodická upozornění

PUOS mimo vojenské újezdy stále nejsou zahrnuty. Území se ořezávají podle sjednocení krajů ČÚZK, jejichž geometrie je pracovním referenčním podkladem, nikoli právně rozhodujícím hraničním dokumentárním dílem. Drobné mezery mezi maskou AOPK a RP nejsou samostatným OOP; jejich geometrii ukládáme pro interní analýzu. Diagnostické GPKG nikdy nezveřejňujte automaticky na veřejném GitHubu. Kontrola aktualizací podle `ZMENA_G` ještě není implementována; používá se ověřená časová cache.

**Status:** v prostředí tvorby nebylo dostupné R, takže nová verze ještě nebyla spuštěna nad skutečnými daty a je určena nejprve k lokálnímu testu.

## Nový veřejný web (v0.6.4)
Po běhu s `--mode=public` nebo `--mode=both` vzniká `site/index.html` s plnými daty přímo v souboru. Lze otevřít dvojklikem bez lokálního serveru. Nad tabulkou lze filtrovat řádky (kategorie, seznam názvů/kódů oddělený středníky), zapínat skupiny sloupců a exportovat aktuální výběr do XLSX. Export zahrnuje i řádky mimo aktuální stránku tabulky. Webová šablona se nachází v `web/index_template.html` a musí zůstat ve složce projektu.

**Test bez opětovného plného výpočtu:** samostatný demonstrační `index.html` z minulé verze dat lze otestovat nezávisle. Nová šablona se automaticky použije při dalším běhu R skriptu.

## v0.6.5
Pravidlo zaokrouhlování a přesné příkazy: `PO_NAVRATU_POKRACOVAT_ZDE.md`.
