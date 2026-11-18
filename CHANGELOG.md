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
