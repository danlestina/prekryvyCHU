# Překryvy chráněných území ČR

**Otevřený nástroj pro výpočet a prohlížení prostorových překryvů chráněných území České republiky.** Z veřejných geografických dat AOPK ČR a ČÚZK sestavuje přehled, která území se překrývají, v jakém rozsahu a které orgány ochrany přírody na jejich plochách podle geometrického modelu působí. Současně umožňuje vyhledávat nesoulady v podkladových geometriích.

Projekt je **nezávislá analytická pomůcka, nikoli úřední evidence nebo závazný právní výklad**. Výsledky závisejí na aktuálnosti a přesnosti použitých dat i na zjednodušeních popsaných níže.

## Co lze zjistit

- **Překryvy území:** seznam překrývajících se lokalit, jejich počet, společnou plochu (ha) a podíl výměry cílového území (%). Plochy překryvů s celou kategorií jsou počítány z **geometrického sjednocení** jednotlivých průniků, aby se stejná plocha nezapočetla vícekrát.
- **Působnost OOP:** přehled orgánů ochrany přírody geometricky přiřazených k ploše daného území, včetně jejich podílů; nepřisuzuje se automaticky jediný úřad celé lokalitě.
- **Diagnostika dat:** neplatné geometrie, přesahy přes hranici ČR, mezery a nesoulady v geometrickém modelu OOP a vzájemné překryvy území, která se běžně překrývat nemají (MZCHÚ, VZCHÚ, EVL).
- **Veřejná webová tabulka:** výběr řádků podle kategorií nebo kódů/názvů, volba kategorií překryvů a zobrazovaných údajů, řazení podle sloupců, zobrazení celého obsahu buněk a export aktuálního pohledu do XLSX.

Zahrnuty jsou NPR, NPP, PR, PP, NP, CHKO, EVL, ptačí oblasti, ochranná pásma ZCHÚ, smluvně chráněná území a vojenské újezdy. Kategorie jsou v přehledech seskupeny zpravidla jako **MZCHÚ → VZCHÚ → Natura 2000 → ochranná pásma → SCHÚ → vojenské újezdy**.

## Jak výpočet funguje

1. **Načtení a ověření vstupů:** veřejné vrstvy chráněných území a působnosti regionálních pracovišť AOPK ČR se získávají z ArcGIS REST AOPK ČR; kraje a vojenské újezdy z dat ČÚZK/RÚIAN. Cache omezuje opakované stahování, ale nesmí nahrazovat kontrolu aktuálnosti a úplnosti zdroje.
2. **Sjednocení geometrií:** výpočty probíhají v **S-JTSK (EPSG:5514)**. Podkladové polygony se ořezávají na sjednocenou hranici krajů ČÚZK, aby se v českých výměrách nezapočítávaly přesahy do zahraničí. Neplatné geometrie se pro výpočet technicky opravují a zaznamenávají v diagnostice.
3. **Prostorové průniky:** každé cílové území se porovnává se všemi referenčními územími. Vedle detailních dvojic se počítají souhrny po kategoriích.
4. **Geometrický model OOP:** z příslušných polygonových vrstev se odvozují části lokalit spadající do působnosti újezdních úřadů, správ NP, AOPK ČR a krajských úřadů. Používá se prioritní přiřazování podle územní a věcné působnosti, aby se plocha nedvojila.
5. **Nezávislá interní kontrola:** při zadání ručního exportu `drusop_oop.txt` lze vypočtené OOP porovnat s evidovanými OOP v DR ÚSOP. **Evidence DR ÚSOP nepřepisuje geometrický výpočet** a rozdíl obou zdrojů sám o sobě neznamená chybu.

### Důležitá omezení

- **PUOS není do modelu zapracována.** Geometricky odvozený OOP proto nelze bez dalšího považovat za právně závazné určení příslušného úřadu.
- Hranice vycházejí z digitálních zdrojů; geometrický překryv nebo neplatnost polygonu automaticky nedokazuje nesprávné právní vyhlášení.
- Velmi malé vedlejší fragmenty OOP (současně méně než 1 m² a méně než 0,001 % lokality) se nezobrazují jako další významný OOP v hlavním souhrnu, ale zůstávají v detailních datech a diagnostice.
- Referenční DR ÚSOP je **ručně pořizovaný export**. V diagnostice se uvádí datum poslední změny jeho souboru, což nemusí být datum skutečného exportu.

## Výstupy

| Umístění | Účel |
|---|---|
| `prekryvy_aktualni.xlsx` (nebo cesta z `--out`) | Veřejná analytická tabulka; hlavní list `Souhrn_po_uzemich`, detaily průniků, souhrny kategorií, geometrické OOP, metodika a zdroje |
| `site/index.html` a související soubory | Veřejný interaktivní přehled, určený i pro publikaci na GitHub Pages |
| `diagnostika/diagnostika_aktualni.xlsx` | Interní souhrn kontroly geometrie, topologie a (v režimu `both`) DR ÚSOP |
| `diagnostika/*.gpkg` | Geometrie nesouladů pro kontrolu v GIS |
| `cache/` | Pomocná mezipaměť vstupních dat, nikoli archiv finálních výsledků |

V GitHub Actions je zamýšlen **týdenní veřejný výpočet** a zveřejnění stránky přes GitHub Pages; datované XLSX se mohou archivovat v GitHub Releases. Interní diagnostika ani ruční export DR ÚSOP se nemají publikovat. **Automatický běh je nutné ověřit prvním úspěšným spuštěním na GitHubu**; místní testy samy o sobě nezaručují běh na serveru GitHubu.

## Spuštění na vlastním počítači

Potřebujete R a knihovny `sf`, `dplyr`, `httr`, `jsonlite` a `openxlsx` (podle použitého režimu také další balíčky). Příkazy se spouštějí ve složce projektu v terminálu RStudia nebo Git Bash, **ne** v R Console.

```bash
# Rychlá kontrola syntaxe
Rscript -e "invisible(parse(file='prekryvy_uzemi.R')); cat('SYNTAXE OK\n')"

# Test: 10 cílových území z každé kategorie, proti všem referenčním územím
Rscript prekryvy_uzemi.R --test=true --sample-n=10 --mode=both --drusop=true --drusop-file=drusop_oop.txt --out=test_v0651.xlsx

# Kontrola struktury vytvořených Excelů
Rscript tests/overeni_v063.R test_v0651.xlsx diagnostika/diagnostika_aktualni.xlsx

# Úplný veřejný výstup bez interní diagnostiky / bez DR ÚSOP
Rscript prekryvy_uzemi.R --test=false --mode=public --out=prekryvy_aktualni.xlsx

# Úplný výstup včetně interní diagnostiky a kontroly DR ÚSOP
Rscript prekryvy_uzemi.R --test=false --mode=both --drusop=true --drusop-file=drusop_oop.txt --out=prekryvy_aktualni.xlsx

# Pouze geometrická/topologická diagnostika
Rscript prekryvy_uzemi.R --mode=diagnostic
```

Pokud Windows, Excel nebo Nextcloud při zápisu uzamkne diagnostický soubor, skript může uložit novou verzi s příponou `_pripraveno_...` a vypíše její cestu. Starý soubor pod stabilním názvem pak **nepovažujte za aktuální**.

## Datové zdroje, původ a licence

Výpočet používá především:

- **AOPK ČR – otevřené geografické vrstvy:** [Poskytování dat AOPK ČR](https://data.nature.cz/), [ArcGIS REST Opendata](https://gis.nature.cz/arcgis/rest/services/Aplikace/Opendata/MapServer). Příslušné otevřené datové sady jsou zveřejňovány pod **Creative Commons Uveďte původ 4.0 (CC BY 4.0)**; požadované označení původu je **© AOPK ČR**. Podmínky konkrétní vrstvy je třeba kontrolovat v její metadatové kartě.
- **ČÚZK – hranice krajů a vojenských újezdů z RÚIAN:** [Otevřená data ČÚZK](https://www.cuzk.gov.cz/Uvod/Produkty-a-sluzby/Otevrena-data/Otevrena-data-zakladni-informace.aspx), [licenční podmínky](https://www.cuzk.gov.cz/Predpisy/Podminky-poskytovani-prostor-dat-a-sitovych-sluzeb/Podminky-poskytovani-prostorovych-dat-CUZK.aspx). Otevřená prostorová data jsou poskytována pod **CC BY 4.0**; u výstupů se zdroj uvádí jako **„ČÚZK, [rok aktuálnosti dat]“**.

Data jsou **geometricky upravována** (ořez na ČR, opravy technicky neplatných geometrií, průniky, sjednocení a agregace); výsledky tedy nejsou nepozměněným přepisem zdrojových vrstev. Licence **MIT** v souboru [`LICENSE`](LICENSE) se týká **pouze původního programu a dokumentace**, nikoli podkladových dat AOPK/ČÚZK, případných výřezů těchto dat v testovacích souborech ani práv poskytovatelů k nim. Při šíření dat a odvozených výstupů je nutné dodržet podmínky příslušných datových sad včetně uvedení zdroje, licence, odkazu a provedených změn.

## Jak projekt vznikl

Nástroj vznikal **iterativní spoluprací zadavatele projektu s ChatGPT (OpenAI)**: zadavatel formuloval požadavky na GIS analýzu, metodiku OOP, formát Excelu, diagnostiku a web; ChatGPT pomáhal navrhovat a upravovat R skripty a webové rozhraní. Následovaly skutečné místní testy, kontrola výsledků a opakované opravy na základě zjištěných chyb a připomínek. Nejde tedy o jednorázově vygenerovaný kód bez ověřování, ale zároveň žádná taková spolupráce nenahrazuje odbornou validaci dat a právního významu výstupů.

Správu repozitáře, commity a publikaci provádí jeho vlastník; ChatGPT **nemá přístup k účtu GitHub ani oprávnění samostatně odesílat změny**. Přenos aktualizací probíhá typicky jako malý ZIP obsahující jen trvalé změněné soubory, který vlastník rozbalí, zkontroluje a sám commituje.

Podrobnosti o vývoji, změnách verzí a dřívějších provozních instrukcích jsou v [`CHANGELOG.md`](CHANGELOG.md).
