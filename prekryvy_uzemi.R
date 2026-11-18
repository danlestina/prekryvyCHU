#!/usr/bin/env Rscript
# ============================================================================
# PREKRYVY CHRANENYCH UZEMI — v0.6.3, 11. 11. 2026
# ============================================================================
# CO PROGRAM DELA (PRO CLOVEKA, KTERY R BEZNE NEPOUZIVA):
# 1) Nacte GIS polygony MZCHU, NP, CHKO, EVL, PO, smluvnich uzemi a voj. ujezdu.
# 2) PRED vypoctem orizne vsechny vrstvy hranici CR z 14 kraju CUZK.
# 3) Pro KAZDE uzemi vypocita prunik se VSEMI JINYMI evidovanymi uzemimi.
# 4) Vypocte plochu jednotlivych pruniku i sjednoceny podil dle kategorii.
# 5) KAZDEMU uzemi nezavisle priradi podily pusobnosti konkretnich OOP.
# 6) PROVOZ: zapise XLSX a jednoduchou verejnou vyhledavaci stranku.
# 7) DIAGNOSTIKA: vytvori soukromy GeoPackage s presnymi nesoulady.
#    Obe vetve pracuji se STEJNYMI podklady, diagnostika s puvodnimi tvary.
#
# NPR, NPP, PR, PP jsou samostatne kategorie. Kazde OP (krome CHKO)
# je take samostatnou kategorii, nikoliv skrytou podkategorii.
#
# TEST --test=true --sample-n=10: vybere 10 CILU na hlavni kategorii,
# jejich pruniky se vsak pocitaji se VSEMI referencnimi uzemimi CR.
# Zadani vlastni nove vstupni vrstvy NENI soucasti teto verze.
#
# DULEZITA VYHRADA: v rozdeleni pusobnosti OOP ZATIM IGNORUJEME PUOS
# mimo vojenske ujezdy. Neni to pravne definitivni mapa kompetenci.
# DRUHY DISCLAIMER: geometrie jsou oriznuty na uzemi CR podle VUSC CUZK.
# Plochy i procenta proto vyjadruji jen ceskou cast puvodnich evidenci.
#
# Prubezne vysvetlivky uvadeji co a PROC jednotlive kroky delaji.
# Licence MIT; zdroje geodat a podminky pripisovani viz README.
# ============================================================================

# Pri startu R stahne do pameti potrebne balicky ("library").
# suppressPackageStartupMessages pouze skryva jejich uvodni hlaseni;
# nema zadny vliv na hodnoty dat ani vypocty.
suppressPackageStartupMessages({
  library(sf)        # prace s polygonovymi geometriemi
  library(dplyr)     # prace s tabulkami
  library(httr)      # stahovani dat z ArcGIS REST
  library(jsonlite)  # cteni odpovedi serveru
  library(openxlsx)  # vytvoreni XLSX
  # xml2/readxl jsou volitelne jen pro nektere formaty exportu DR USOP.
})

# DVE adresy jsou ulozeny v promennych, abychom je nemuseli
# hledat na mnoha mistech kodu pri budoucich zmenach poskytovatele.
# AOPK_URL slouzi pro chranena uzemi a hranice RP AOPK.
AOPK_URL <- "https://gis.nature.cz/arcgis/rest/services/Aplikace/Opendata/MapServer"
# HRANICE VOJENSKYCH UJEZDU A KRAJU: OBA PODKLADY PRIMO Z CUZK/RUIAN.
# Namisto obrovskeho celostatniho ZIPu dotazujeme JEN DVE REST VRSTVY:
#  - vrstva 17 = 14 kraju (Vyssi uzemne samospravny celek),
#  - vrstva 12 = pouze 4 vojenske ujezdy (statuskod = 1).
# Ziskame jen potrebne polygony, nikoli vsechny obce a katastry v CR.
# Pri stahovani zkontrolujeme pocet, identifikatory i neprazdne geometrie.
# Overenou kopii ukladame do cache, ale pri pravidelnem refreshi ji obnovime.
# Kdyz dotaz selze a neexistuje platna cache, program se ZASTAVI.
# NIKDY sam neprejde na stazeni velkeho 1.zip nebo na cizi zdroj dat.
CUZK_REST_URL <- "https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/MapServer"
CUZK_KRAJE_LAYER <- 17L
CUZK_UJEZDY_LAYER <- 12L
# JEDINY povoleny souradnicovy system pro vsechny vstupy, cache a vystupy.
# ESRI wkid 102067 je starsi kod pro STEJNY system; latestWkid=5514.
# Nesmi se plest s historickou variantou Krovaka s jinymi osami.
TARGET_EPSG <- 5514L
SAME_ESRI_WKIDS <- c(102067L, 5514L)
# Jmena a kody znamych 4 vojenskych ujezdu (RUIAN).
VU_KODY <- c(Boletice = "545422", Brezina = "592935",
              Hradiste = "555177", Libava = "503941")
# Cisla jsou ID vrstev uvnitr sluzby AOPK; nekopiruji cisla zakonnych kategorii.
# Napr. MZCHU=2 => (.../MapServer/2), PO=7 => (.../MapServer/7).
LAYER_IDS <- c(MZCHU = 2L, VZCHU = 0L, SCHU = 4L, EVL = 6L,
               PO = 7L, OP_MZCHU = 3L, RP = 16L)
# Seznam HLAVNICH kategorii, ktere uzivatel uvidi v prehledu.
# NPR, NPP, PR a PP jsou samostatne kategorie; sdili zdroj MZCHU.
# Vystupni poradi kategorii. OP jsou samostatne kategorie take pro cilove uzemi.
DEFAULT_CATS <- c("NPR", "NPP", "PR", "PP", "EVL", "PO", "CHKO", "NP",
                  "OP_NPR", "OP_NPP", "OP_PR", "OP_PP", "OP_NP", "SCHU", "VOJ_UJEZD")
ALL_CATS <- DEFAULT_CATS
`%||%` <- function(x, y) if (is.null(x)) y else x

# Argumenty z terminalu jsou retezce --nazev=hodnota. Tato funkce
# je prevede do prehledneho seznamu; --sample-n se ulozi jako sample_n.
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!startsWith(a, "--")) stop("Parametr musi zacinat --: ", a)
    s <- strsplit(sub("^--", "", a), "=", fixed = TRUE)[[1]]
    key <- gsub("-", "_", s[1], fixed = TRUE)
    out[[key]] <- if (length(s) == 1L) "true" else paste(s[-1], collapse = "=")
  }
  out
}
opt <- parse_args(commandArgs(trailingOnly = TRUE))
# arg nacte jeden parametr nebo pouzije vychozi hodnotu.
arg <- function(key, default = NULL) opt[[key]] %||% default
# bool prijima jen true nebo false, aby preklepy nedelaly skryte problemy.
bool <- function(key, default) {
  v <- tolower(arg(key, default))
  if (!v %in% c("true", "false")) stop("--", gsub("_", "-", key), " musi byt true/false")
  identical(v, "true")
}
# Názvy v datovém modelu zůstávají strojově stabilní; uživatelské sešity
# mají samovysvětlující české hlavičky. Význam každé hlavičky je na
# samostatném listu Vysvetlivky_sloupcu.
popis_sloupce <- function(nm) {
  zaklad <- c(
    klic="Jedinečný identifikátor území (kategorie a kód)",
    kategorie="Kategorie chráněného území",
    podkategorie="Podkategorie chráněného území",
    kod="Evidenční kód území v ÚSOP",
    nazev="Název chráněného území",
    id_isop="Interní identifikátor ISOP",
    url_usop="Odkaz na evidenční kartu území v DR ÚSOP",
    plocha_m2="Plocha území nebo průniku (m²)",
    plocha_ha="Plocha území nebo průniku (ha)",
    plocha_km2="Plocha území nebo průniku (km²)",
    podil_pct="Podíl přiřazeného OOP na ploše celého území (%)",
    oop_typ="Typ orgánu ochrany přírody z geometrického modelu",
    oop_id="Identifikátor geograficky přiřazeného orgánu ochrany přírody",
    oop_nazev="Název orgánu ochrany přírody přiřazeného geograficky",
    OOP_pocet="Počet významných OOP v souhrnu (bez mikrofragmentů)",
    OOP_souhrn="Geometricky přiřazené významné OOP a podíly ploch území",
    mikrofragment_oop="Je plocha tohoto OOP mikrofragmentem (<1 m² a <0,001 %)?",
    uvaden_v_souhrnu="Uvádí se tento OOP v hlavním souhrnu území?",
    OOP_DRUSOP="OOP uvedené v ručním exportu DR ÚSOP pro celé území",
    OOP_shoda="Stav porovnání evidence DR ÚSOP s geometrickým výpočtem OOP",
    OOP_vysvetleni_rozdilu="Vysvětlení diagnostického stavu a potřebná kontrola",
    OOP_pouze_DRUSOP="OOP evidované pouze v DR ÚSOP, nikoli v geometrickém souhrnu",
    OOP_pouze_geo="Významné OOP přiřazené jen geometrií, nikoli v DR ÚSOP",
    OOP_geo_mikrofragmenty="Geometrické mikrofragmenty OOP: úřad, výměra a procento",
    OOP_geo_pocet_vsech="Počet všech geometrických OOP včetně mikrofragmentů",
    OOP_geo_pocet_v_souhrnu="Počet geometrických OOP vykazovaných v souhrnu",
    DRUSOP_stav="Stav nalezení samostatného záznamu v exportu DR ÚSOP",
    DRUSOP_kategorie="Kategorie objektu uvedená v exportu DR ÚSOP",
    DRUSOP_nazev="Název objektu uvedený v exportu DR ÚSOP",
    DRUSOP_overeno="Datum a čas importu exportu DR ÚSOP (nikoli datum dat)",
    DRUSOP_zdroj="Název souboru ručního exportu DR ÚSOP",
    klic_a="Jedinečný identifikátor prvního překrývajícího se území",
    klic_b="Jedinečný identifikátor druhého překrývajícího se území",
    nazev_a="Název prvního překrývajícího se území",
    nazev_b="Název druhého překrývajícího se území",
    kod_a="Evidenční kód prvního překrývajícího se území",
    kod_b="Evidenční kód druhého překrývajícího se území",
    kategorie_a="Kategorie prvního překrývajícího se území",
    kategorie_b="Kategorie druhého překrývajícího se území",
    plocha_pruniku_m2="Plocha skutečného průniku obou území (m²)",
    podil_na_a_pct="Podíl průniku z celkové plochy prvního území (%)",
    podil_na_b_pct="Podíl průniku z celkové plochy druhého území (%)",
    mozny_artefakt="Je průnik menší než 1 m² (možný geometrický artefakt)?",
    stav="Výsledek geometrické nebo evidenční kontroly",
    polozka="Sledovaná vlastnost nebo metodické pravidlo",
    hodnota="Hodnota nebo vysvětlení pravidla",
    vrstva="Název datové vrstvy",
    plocha="Výměra plochy",
    pocet="Počet záznamů",
    typ_chyby="Typ zjištěného geometrického nesouladu",
    plocha_m2="Plocha území nebo průniku (m²)",
    vrstva_gpkg="Název odpovídající vrstvy v interním GeoPackage")
  if (nm %in% names(zaklad)) return(unname(zaklad[[nm]]))
  if (grepl("^vsechny_prekryvy",nm)) return("Nezkrácený seznam všech překrývajících se území [pokračování při dlouhém textu]")
  if (grepl("_pocet$",nm)) return(paste0(sub("_pocet$","",nm)," – počet překrývajících se území"))
  if (grepl("_prekryv_pct$",nm)) return(paste0(sub("_prekryv_pct$","",nm)," – podíl území pokrytý překryvy (%)"))
  if (grepl("_prekryv_ha$",nm)) return(paste0(sub("_prekryv_ha$","",nm)," – plocha sjednocených překryvů (ha)"))
  if (grepl("_nazvy_a_plochy",nm)) return(paste0(sub("_nazvy_a_plochy.*$","",nm)," – názvy překrytých území a jejich plochy",if(grepl("_[0-9]+$",nm)) paste0(" (pokračování ",sub("^.*_([0-9]+)$","\\1",nm),")") else ""))
  if (nm == "pocet_fragmentu") return("Počet samostatných polygonových fragmentů geometrické chyby")
  if (nm == "celkova_plocha_fragmentu_m2") return("Celková plocha fragmentů daného území a typu chyby (m²)")
  gsub("_"," ",nm,fixed=TRUE)
}
popisne_hlavicky <- function(df) {
  df <- as.data.frame(df)
  original <- names(df)
  zmena <- vapply(original,popis_sloupce,character(1))
  # Originální název v závorce garantuje jednoznačnou dohledatelnost
  # i u opakujících se významů, například několik různých ploch.
  names(df) <- paste0(zmena," [",original,"]")
  df
}


if (bool("help", "false")) {
  cat(paste(
    "Pouziti: Rscript prekryvy_uzemi.R [--test=true] [--sample-n=10]",
    "[--seed=20261030] [--oop=true] [--out=prekryvy_v057.xlsx]",
    "[--mode=both|public|diagnostic] # verejny vypocet / interni diagnostika",
    "[--diagnostic-dir=diagnostika] [--diagnostic-min-area-m2=0.01]",
    "[--site-dir=site] # verejna webova stranka pro GitHub Pages",
    "[--drusop=true --drusop-file=drusop_oop.txt --drusop-export-date=YYYY-MM-DD]",
    "[--self-test-drusop=true] # pouze test parseru, bez internetu",
    "[--categories=NPR,NPP,PR,PP,EVL,PO,CHKO,NP,OP_NPR,OP_NPP,OP_PR,OP_PP,OP_NP,SCHU,VOJ_UJEZD]",
    "[--op-mzchu=true] [--op-vzchu=false] [--min-area-m2=1]",
    "[--max-rp-gap-m2=10000] [--max-rp-gap-pct=0.01]",
    "[--cache=true] [--refresh=false] [--cache-dir=cache] [--offline=false]",
    "[--oop-kraje=... --data-ujezdy=...] # moznost mistniho GPKG/SHP",
    "[--synthetic-data=false]  # JEN pro prilozene fiktivni testy",
    "[--self-test-geometrie=true]  # 10 lokalnich testu bez internetu",
    "[--max-cache-age-days=7] [--verify-cache-online=true]  # pro GitHub",
    "[--data-mzchu=...] [--data-vzchu=...] [--data-schu=...]",
    "[--data-evl=...] [--data-po=...] [--data-ujezdy=...]",
    "[--data-op-mzchu=...] [--oop-kraje=...] [--oop-rp=...]",
    "[--oop-mzchu=...] [--oop-vzchu=...] [--oop-ujezdy=...]",
    "TEST: jen cile jsou vzorkovane. Reference jsou VZDY UPLNE.",
    "OP_NPR, OP_NPP, OP_PR, OP_PP, OP_NP jsou rovnocenne cilove kategorie.",
    sep = "\n"))
  quit(save = "no")
}
# --mode=both: v jednom behu provozni XLSX/web A SOUKROMA diagnostika.
# --mode=public: pouze provozni vystup; pro GitHub Actions, bez internich dat.
# --mode=diagnostic: pouze diagnostika z uplnych vrstev, bez matic prekryvu.
# DIAGNOSTIKA VZDY pro vsechna uzemi, i pri --test=true.
mode <- tolower(arg("mode", "both"))
if (!mode %in% c("both", "public", "diagnostic"))
  stop("--mode musi byt both, public nebo diagnostic")
diagnostic_dir <- arg("diagnostic_dir", "diagnostika")
# Zabezpeceni proti docasnym zamkum Nextcloud / Windows
source("lib/bezpecny_zapis.R", local=FALSE, encoding="UTF-8")
if (mode != "public") diag_mkdir(diagnostic_dir)
site_dir <- arg("site_dir", "site")
diagnostic_min_area <- as.numeric(arg("diagnostic_min_area_m2", "0.01"))
if (!is.finite(diagnostic_min_area) || diagnostic_min_area < 0)
  stop("--diagnostic-min-area-m2 musi byt nezaporne cislo")
# Maximalni pripustny nepriradeny ZBYTEK pouze v masce pusobnosti RP.
# Hodnoty nejsou libovolnou toleranci pro vypadek dat: vetsi vada
# znamena STOP a zadny publikovany vysledek.
max_rp_gap_m2 <- as.numeric(arg("max_rp_gap_m2", "10000"))
max_rp_gap_pct <- as.numeric(arg("max_rp_gap_pct", "0.01"))
if (any(!is.finite(c(max_rp_gap_m2, max_rp_gap_pct))) ||
    any(c(max_rp_gap_m2, max_rp_gap_pct) < 0))
  stop("Neplatne limity --max-rp-gap-m2 / --max-rp-gap-pct")
# Pro rychly test nastavte --test=true; vsechny dalsi volby jsou volitelne.
test_mode <- bool("test", "false")
offline <- bool("offline", "false")
compute_oop <- bool("oop", "true") && mode != "diagnostic"
# Nezavisly doplnkovy dotaz na evidovany OOP v registru DR USOP.
# VYCHOZI false, protoze verejne HTML rozhrani nema dolozene stabilni API.
# U prvni zkousky zapnete --drusop=true; nikterak to nemení geograficky vypocet.
query_drusop <- bool("drusop", "false") && mode != "public"
if (mode == "public" && bool("drusop", "false")) message("DRUSOP: v rezimu public se kontrola neprovadi (interni diagnostika).")
self_test_drusop <- bool("self_test_drusop", "false")
drusop_max <- as.integer(arg("drusop_max", "100"))
drusop_cache_days <- as.numeric(arg("drusop_cache_days", "30"))
# Pokud do pracovni slozky (getwd()) ulozite drusop_oop.txt, skript
# jej uprednostni pred starym zpusobem s 5 soubory jednotlivych evidenci.
# --drusop-file=... umozni predat jinou cestu (bez kopirovani souboru).
drusop_file <- arg("drusop_file", if (file.exists("drusop_oop.txt")) "drusop_oop.txt" else "")
drusop_export_dir <- arg("drusop_export_dir", "drusop_exporty")
# Datum porizeni exportu MUSI zadat spravce; datum importu neni datem exportu.
drusop_export_date <- arg("drusop_export_date", "NEZJISTENO")
# Datum 'poslední změny souboru' je metadata souborového systému,
# NE doklad dne vzniku dat. Vlastní datum uživatel nemusí ručně zadávat.
if (drusop_export_date == "NEZJISTENO" && nzchar(drusop_file) && file.exists(drusop_file))
  drusop_export_date <- format(file.info(drusop_file)$mtime, "%Y-%m-%d")
if (drusop_export_date != "NEZJISTENO" && !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", drusop_export_date))
  stop("--drusop-export-date musi byt YYYY-MM-DD")
if (is.na(drusop_max) || drusop_max < 0L || !is.finite(drusop_cache_days) || drusop_cache_days < 0)
  stop("Parametry --drusop-max a --drusop-cache-days musi byt nezaporne")
include_op_mzchu <- bool("op_mzchu", "true")
include_op_vzchu <- bool("op_vzchu", "false")
use_cache <- bool("cache", "true")
refresh <- bool("refresh", "false")
synthetic_data <- bool("synthetic_data", "false")
self_test_geometrie <- bool("self_test_geometrie", "false")
max_cache_age_days <- as.numeric(arg("max_cache_age_days", "7"))
# V GitHub Actions musí být cache před každým použitím ověřena online.
verify_cache_online <- bool("verify_cache_online", "false")
if (!is.finite(max_cache_age_days) || max_cache_age_days < 0)
  stop("--max-cache-age-days musi byt nezaporne cislo")
cache_dir <- arg("cache_dir", "cache")
# Stare ZIP prepinace jsme zamerne ODSTRANILI: ZIP 1.zip uz nesmime stahovat.
# Pokud uzivatel pouzije stary prepinac, vypiseme chybu misto jeho ignorovani.
if (!is.null(arg("cuzk_download_method")) || !is.null(arg("cuzk_zip_dir")))
  stop("Parametry --cuzk-download-method a --cuzk-zip-dir byly zruseny. ",
       "CUZK se nyni nacita primo pres REST (14 kraju + 4 ujezdy). ",
       "Pro mistni data pouzijte --oop-kraje a --data-ujezdy.")
seed <- as.integer(arg("seed", "20261030"))
sample_n <- as.integer(arg("sample_n", "10"))
min_area <- as.numeric(arg("min_area_m2", "1"))
# KOREKCE NEDELAJEME. Mezery RP se nikdy neprirazuji nejblizsimu RP.
# Nepatrne zbytky nejsou OOP: odeberou se z dalsiho prirazovani,
# NEZOBRAZUJI se jako radek OOP, ale jsou presne v interni diagnostice.
if (synthetic_data && !offline) stop("--synthetic-data=true je povoleno JEN s --offline=true; nikdy pro ziva data!")
if (is.na(seed) || is.na(sample_n) || sample_n < 1L) stop("Neplatna hodnota seed nebo sample-n")
if (is.na(min_area) || !is.finite(min_area) || min_area < 0) stop("Neplatna min-area-m2")
categories <- unique(toupper(trimws(strsplit(arg("categories", paste(DEFAULT_CATS, collapse = ",")), ",", fixed = TRUE)[[1]])))
if (!length(categories) || any(!categories %in% ALL_CATS)) {
  stop("Neznama hlavni kategorie. Povolene: ", paste(ALL_CATS, collapse = ", "))
}
# OP maji samostatne vystupni kategorie i radky.
secondary_cats <- character(0)  # OP uz nejsou vedlejsi: maji vlastni kategorie.
reference_cats <- categories
outfile <- arg("out", "prekryvy_aktualni.xlsx")
# Soubor se stejnym nazvem se pri dokonceni BEHU prepise.
# Proto doporucujeme do --out zapisovat datum nebo verzi vypoctu.

# Pomocna funkce pro srovnavani nazvu sloupcu bez ohledu na diakritiku,
# mezery a mala/velka pismena. "Název_RP" a "nazev rp" se tak shodují.
# Nepouziva se k uprave nazvu, ktere se ukladaji do Excelu.
norm <- function(s) {
  s <- iconv(as.character(s), from = "", to = "ASCII//TRANSLIT", sub = "")
  toupper(gsub("[^A-Za-z0-9]", "", s))
}
# Ruzni poskytovatele pouzivaji pro stejny udaj ruzne nazvy sloupcu.
# column(names(x), c("NAZEV","NAME")) najde prvni existujici variantu.
# Pokud nenajde nic, zastavi se zretelnou chybovou hlaskou.
column <- function(nms, candidates, required = TRUE) {
  i <- match(norm(candidates), norm(nms)); i <- i[!is.na(i)]
  if (length(i)) return(nms[i[1]])
  if (required) stop("Chybi sloupec: ", paste(candidates, collapse = "/"),
                     ". Dostupne: ", paste(nms, collapse = ", "))
  NULL
}
# Jednotna a prisna kontrola CRS vstupnich dat.
# Nikdy automaticky NEPREVADIME z WGS84 nebo z jineho Krovaka.
# Kontrola EPSG identifikuje system, prostorova kontrola hlida tez
# prohozeni os a chybne OZNACENE geometrie, ktere sam EPSG kod neodhalil.
# Kontrolu geograficke polohy u fiktivnich autotestu nepouzivame,
# protoze jejich obdelniky zamerne lezi kolem souradnic [0,0].
check_epsg5514 <- function(x, popis, kontrola_polohy = FALSE) {
  if (!inherits(x, c("sf", "sfc")))
    stop("CRS ", popis, ": ocekavam objekt sf/sfc")
  sr <- sf::st_crs(x)
  if (is.na(sr) || !isTRUE(sr == sf::st_crs(TARGET_EPSG)))
    stop("CRS ", popis, ": ocekavam EPSG:5514 (S-JTSK / Krovak East North), ",
         "skutecna identifikace EPSG: ", if (is.na(sr)) "NEURCENA" else sr$epsg,
         ". Vstup se NEPREVADI automaticky.", call. = FALSE)
  if (isTRUE(kontrola_polohy)) {
    bbox <- sf::st_bbox(x)
    b <- as.numeric(bbox)
    if (length(b) != 4L || any(!is.finite(b)) ||
        bbox[["xmin"]] < -1100000 || bbox[["xmax"]] > -300000 ||
        bbox[["ymin"]] < -1400000 || bbox[["ymax"]] > -800000 ||
        mean(c(bbox[["xmin"]], bbox[["xmax"]])) <=
          mean(c(bbox[["ymin"]], bbox[["ymax"]])) + 80000)
      stop("CRS ", popis, ": rozsah souřadnic neodpovida ceskemu ",
           "S-JTSK / Krovak East North. Mozna zamenene osy nebo chybne ",
           "oznaceny CRS. BBOX: ", paste(signif(b, 8), collapse = ", "),
           ". ZASTAVUJI (bez transformace).", call. = FALSE)
  }
  invisible(TRUE)
}

# Kontrola WKID uvedeneho v JSON odpovedi serveru.
# 102067 a 5514 jsou alternativni kodova oznaceni stejneho EPSG:5514.
# Pokud server vrati jediny jiny kod, jde o chybu.
check_esri_sr <- function(sr, popis) {
  if (is.null(sr)) stop("REST ", popis, ": chybi spatialReference")
  kody <- c(sr$wkid, sr$latestWkid)
  if (!length(kody) || anyNA(suppressWarnings(as.integer(unlist(kody)))) ||
      !all(as.integer(unlist(kody)) %in% SAME_ESRI_WKIDS))
    stop("REST ", popis, ": neocekavany WKID: ",
         paste(unlist(kody), collapse = "/"),
         "; povoleno jen 5514 nebo ekvivalent 102067", call. = FALSE)
  invisible(TRUE)
}

# Jedine CESKE lokalni GIS soubory s EPSG:5514. Nespravny CRS je chyba.
read_vector <- function(path) {
  if (!file.exists(path)) stop("Soubor neexistuje: ", path)
  x <- sf::st_read(path, quiet = TRUE, stringsAsFactors = FALSE)
  check_epsg5514(x, paste0("soubor ", path), kontrola_polohy =
                   !synthetic_data && !self_test_geometrie)
  if (!all(grepl("POLYGON", as.character(sf::st_geometry_type(x)))))
    stop("Vrstva neni plne polygonova: ", path)
  x
}
# Odeslani dotazu na ArcGIS REST server (jeden HTTP pozadavek).
# 'layer' je cislo vrstvy; 'parameters' napriklad omezi vysledek na statuskod=1.
# Pri chybe serveru vypiseme chybu namisto ticheho prazdneho vysledku.
# Sitovy pozadavek muze obcas selhat. Opakujeme ho max. 3x,
# ale pokud ani potom nedostaneme korektni odpoved, VYPOCET SE ZASTAVI.
retry_request <- function(make_request, label) {
  last_error <- NULL
  for (attempt in 1:3) {
    answer <- tryCatch(make_request(), error = function(e) {
      last_error <<- conditionMessage(e)
      NULL
    })
    if (!is.null(answer)) return(answer)
    message("  Pokus ", attempt, "/3 selhal pro ", label, ": ", last_error)
    if (attempt < 3) Sys.sleep(2 * attempt)
  }
  stop("POVINNY ZDROJ NEDOSTUPNY, VYSLEDEK NEBUDE VYTVOREN: ", label,
       "; posledni chyba: ", last_error, call. = FALSE)
}
api_query <- function(layer, parameters, url = AOPK_URL) {
  if (offline) stop("Chybi lokalni vrstva, ale je zapnuto --offline=true: ", layer)
  retry_request(function() {
    req <- httr::GET(paste0(url, "/", layer, "/query"),
                     query = c(parameters, list(f = "json")), httr::timeout(180))
    httr::stop_for_status(req)
    x <- jsonlite::fromJSON(httr::content(req, "text", encoding = "UTF-8"))
    if (!is.null(x$error)) stop("ArcGIS REST: ", x$error$message)
    x
  }, paste0("ArcGIS REST ", layer))
}
# Jednorazove zkontrolujeme taky ZDROJOVE CRS vrstvy.
# Samotne outSR=5514 by nebylo dukazem: server umi prevest cizi vrstvy.
# Proto cteme sourceSpatialReference z metadat vrstvy a nespravny CRS
# zastavime jeste PRED dotazem na tisice polygonu.
api_layer_metadata <- function(layer, url = AOPK_URL) {
  if (offline) stop("Offline: nelze kontrolovat REST metadata ", layer)
  retry_request(function() {
    req <- httr::GET(paste0(url, "/", layer), query = list(f = "json"),
                     httr::timeout(90))
    httr::stop_for_status(req)
    m <- jsonlite::fromJSON(httr::content(req, "text", encoding = "UTF-8"),
                            simplifyVector = FALSE)
    if (!is.null(m$error)) stop("Metadata REST: ", m$error$message)
    if (!identical(m$geometryType, "esriGeometryPolygon"))
      stop("REST vrstva ", layer, ": zdroj neni polygonovy")
    original_sr <- m$sourceSpatialReference %||% m$spatialReference
    check_esri_sr(original_sr, paste0(url, "/", layer, " (zdroj)"))
    m
  }, paste0("metadata REST vrstvy ", layer))
}

# Precteni ArcGIS Esri JSON do sf pomoci GDAL ovladace ESRIJSON.
# GeoJSON zde NEPOUZIVAME: dle RFC 7946 je urcen pro WGS 84, coz vedlo
# ve starem skriptu k zbytecnemu prevodu 5514->4326->5514.
# GDAL umi polygonove rings vcetne der a multipart a zachova metricky CRS.
read_esrijson_5514 <- function(raw_json, popis) {
  if (!"ESRIJSON" %in% sf::st_drivers("vector")$name)
    stop("GDAL/sf nema ovladac ESRIJSON. Aktualizuj GDAL nebo knihovnu sf.")
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  writeBin(raw_json, tmp)
  dat <- tryCatch(sf::st_read(tmp, quiet = TRUE, drivers = "ESRIJSON",
                              stringsAsFactors = FALSE), error = function(e)
    stop("REST ", popis, ": ESRIJSON nelze precist: ",
         conditionMessage(e), call. = FALSE))
  check_epsg5514(dat, paste0("REST ", popis), kontrola_polohy = FALSE)
  dat
}

# Kontrola, ze API vratilo PRESNE ty objekty, o ktere jsme pozadali.
# OBJECTID je technicke ID zaznamu v REST sluzbe, NENI to kod USOP/RUIAN.
# Nektere sluzby (napr. CUZK) nazyvaji toto pole "objectid" malymi pismeny,
# jine "OBJECTID" velkymi. Drive jsme natvrdo hledali "OBJECTID" a uplne
# spravne nactenou davku CUZK chybne odmitli.
#
# Nazev ted NEHADAME: z metadat vybereme pole typu esriFieldTypeOID.
# Nasledne ho hledame ve skutecnych atributech bez ohledu na velikost pismen.
# KONTROLU OID NERUSIME: porovname uplnou mnozinu ocekavanych a vracenych ID.
# Pri chybe vypiseme skutecne dostupna pole a hodnoty, aby slo problem overit.
kontrola_oid_davky <- function(prvky, objednana_id, metadata, popis) {
  # metadata$fields je seznam popisu sloupcu v ArcGIS REST sluzbe.
  # Typ esriFieldTypeOID ma byt prave jeden: jde o interni identifikator prvku.
  pole <- metadata$fields %||% list()
  oid_pole <- Filter(function(p) identical(p$type %||% "", "esriFieldTypeOID"), pole)
  oid_nazvy <- vapply(oid_pole, function(p) as.character(p$name %||% NA_character_), character(1))
  if (length(oid_nazvy) != 1L || anyNA(oid_nazvy))
    stop(popis, ": v metadatech nebylo nalezeno presne jedno pole typu esriFieldTypeOID. ",
         "Nalezena OID pole: ", paste(oid_nazvy, collapse=", "), call. = FALSE)
  nazev_oid <- oid_nazvy[[1]]
  # U kazdeho vraceneho objektu dohledame konkretni nazev klice atributu.
  # 'objectid' i 'OBJECTID' jsou platne varianty tehoz pole.
  vracena_id <- vapply(seq_along(prvky), function(j) {
    atributy <- prvky[[j]]$attributes
    kandidati <- names(atributy)
    shody <- which(tolower(kandidati) == tolower(nazev_oid))
    if (length(shody) != 1L)
      stop(popis, ": objekt ", j, " neobsahuje jednoznacne OID pole '",
           nazev_oid, "'. Skutecne atributy: ", paste(kandidati, collapse=", "),
           call. = FALSE)
    hodnota <- atributy[[shody]]
    if (is.null(hodnota) || length(hodnota) != 1L) return(NA_integer_)
    suppressWarnings(as.integer(hodnota))
  }, integer(1))
  if (anyNA(vracena_id) || anyDuplicated(vracena_id) ||
      length(vracena_id) != length(objednana_id) ||
      !setequal(vracena_id, objednana_id))
    stop(popis, ": nesouhlas objektovych ID (pole '", nazev_oid, "'). ",
         "Objednano: [", paste(objednana_id, collapse=", "), "]; ",
         "vraceno: [", paste(vracena_id, collapse=", "), "]. ",
         "Vysledek NEBUDE vytvoren.", call. = FALSE)
  invisible(vracena_id)
}

# Nacteni CELE vrstvy ze serveru jako sf objektu (geometrie + atributy).
# Pouziva se dvoufazove stazeni, aby limit velikosti odpovedi neodrizl data.
rest_layer <- function(layer, where = "1=1", url = AOPK_URL, batch_size = 50L) {
  # Overime, ze i skutecna ZDROJOVA vrstva bezi v S-JTSK EPSG:5514.
  message("Nacitam REST vrstvu ", layer, ", filtr: ", where)
  metadata_vrstvy <- api_layer_metadata(layer, url)
  x <- api_query(layer, list(where = where, returnIdsOnly = "true",
                             returnGeometry = "false"), url = url)
  # Server nejprve vrati VSECHNA identifikacni cisla objektu (bez geometrie).
  # Tím víme, kolik polygonů máme opravdu očekávat.
  ids <- as.integer(x$objectIds %||% integer())
  # Pozadavek na uplnost: prazdny seznam a duplicitni ID jsou CHYBA.
  if (!length(ids) || anyNA(ids) || anyDuplicated(ids))
    stop("REST vrstva ", layer, ": prazdne, neplatne nebo duplicitni objektove ID")
  # Geometrie stahujeme po 50 zaznamech, abychom nenarazili na velikost odpovedi.
  # Geometrie stahujeme po 50 objektech. Velky MZCHU seznam ma tudiz
  # desitky davek, kdezto vojenske ujezdy se vejdou do jedne.
  # Pro slozite krajske hranice pouzijeme batch_size=1: jeden kraj
  # na dotaz, at server nemusi odesilat vsech 14 slozitych polygonu naraz.
  if (!is.numeric(batch_size) || length(batch_size) != 1L ||
      is.na(batch_size) || batch_size < 1L)
    stop("batch_size musi byt cele kladne cislo")
  batches <- split(ids, ceiling(seq_along(ids) / as.integer(batch_size)))
  pieces <- lapply(seq_along(batches), function(i) {
    if (i %% 10 == 1 || i == length(batches))
      message("  davka ", i, "/", length(batches), " (", length(ids), " objektu)")
    # Vyzadame skutecny ArcGIS JSON (f=json) v puvodnim EPSG:5514.
    # NENI TO GeoJSON. Esri JSON nese rings polygonu vcetne der a multipart.
    # outSR explicitne nastavime pro kontrolu. Zdrojove CRS jsme navic
    # overili oddelene v metadatech, aby server neskryval prevod vrstvy.
    piece <- retry_request(function() {
      req <- httr::GET(paste0(url, "/", layer, "/query"), query = list(
        objectIds = paste(batches[[i]], collapse = ","), outFields = "*",
        returnGeometry = "true", outSR = as.character(TARGET_EPSG),
        f = "json"), httr::timeout(180))
      httr::stop_for_status(req)
      body <- httr::content(req, as = "raw")
      obsah <- jsonlite::fromJSON(rawToChar(body), simplifyVector = FALSE)
      if (!is.null(obsah$error))
        stop("ArcGIS REST vrstva ", layer, ": ", obsah$error$message)
      if (!identical(obsah$geometryType, "esriGeometryPolygon"))
        stop("REST vrstva ", layer, ": neocekavany typ ", obsah$geometryType)
      check_esri_sr(obsah$spatialReference,
                    paste0("vrstva ", layer, " davka ", i))
      prvky <- obsah$features %||% list()
      if (length(prvky) != length(batches[[i]]))
        stop("NEUPLNA DAVKA: cekam ", length(batches[[i]]),
             " polygonu, mam ", length(prvky))
      if (any(vapply(prvky, function(f) is.null(f$geometry$rings), logical(1))))
        stop("REST vrstva ", layer, ": chybi geometrie v davce ", i)
      # Identifikatory kontrolujeme podle OID pole ze ZDROJOVYCH metadat.
      # Nehledame natvrdo OBJECTID: CUZK poskytuje atribut 'objectid'.
      kontrola_oid_davky(prvky, batches[[i]], metadata_vrstvy,
        paste0("REST vrstva ", layer, ", davka ", i, "/", length(batches)))
      dat <- read_esrijson_5514(body, paste0("vrstva ", layer, " davka ", i))
      if (nrow(dat) != length(batches[[i]]))
        stop("REST vrstva ", layer, ": GDAL vratil ", nrow(dat),
             " misto ", length(batches[[i]]), " polygonu")
      if (any(sf::st_is_empty(dat))) stop("Prazdna geometrie v davce")
      # Kontrola orientace os a polohy nad celejsim vzorkem dat.
      check_epsg5514(dat, paste0("vrstva ", layer, " davka ", i),
                     kontrola_polohy = !synthetic_data)
      dat
    }, paste0("REST vrstva ", layer, ", davka ", i, "/", length(batches)))
    piece
  })
  result <- if (length(pieces) == 1) pieces[[1]] else do.call(rbind, pieces)
  if (nrow(result) != length(ids))
    stop("REST vrstva ", layer, ": NEDOSTATECNY POCET polygonu! ")
  # ID jsou povinne zkontrolovana i ve vsech jednotlivych JSON davkach.
  # GDAL je muze v nekterych verzich schovat jako FID misto atributu.
  # Proto zde ponechame druhou kontrolu jen pokud je sloupec pritomen.
  oid <- column(names(result), c("OBJECTID", "objectid"), required = FALSE)
  if (!is.null(oid)) {
    actual <- as.integer(result[[oid]])
    if (anyNA(actual) || anyDuplicated(actual) || !setequal(actual, ids))
      stop("REST vrstva ", layer, ": seznam OBJECTID se neshoduje se serverem")
  }
  check_epsg5514(result, paste0("kompletni REST vrstva ", layer),
                 kontrola_polohy = !synthetic_data)
  result
}
# Cache uklada uspesne stazene podklady do mistniho GeoPackage.
# Pri druhem testu pak znovu nestahujeme tisice MZCHU. Pro nove aktualni
# podklady je --refresh=true. Datum vzniku souboru zapiseme do Metodiky.
# Pouze dokonale dokoncene stazeni se zapise do cache.
source_log <- list()
# Minimalni orientacni pocty prvku se maji projevit jako BEZPECNOSTNI ALARM.
# Nejsou to tvrde presne pocty: pri bezne zmene evidence se mohou zvysit.
# Pri skutecnem poklesu pod tyto hodnoty MUSI uzivatel data proverit.
MIN_COUNT <- c(data_mzchu=2300L, data_vzchu=25L, data_schu=45L,
               data_evl=950L, data_po=35L, data_op_mzchu=2000L, oop_rp=10L)
validate_source <- function(x, key) {
  if (is.null(x) || !inherits(x, "sf") || !nrow(x))
    stop("POVINNA VRSTVA ", key, " JE PRAZDNA: vysledek nevznikne")
  check_epsg5514(x, key, kontrola_polohy =
                   !synthetic_data && !self_test_geometrie)
  if (any(sf::st_is_empty(x))) stop("Prazdne polygony: ", key)
  if (!all(grepl("POLYGON", as.character(sf::st_geometry_type(x)))))
    stop("Nepolygonova geometrie: ", key)
  if (!synthetic_data && key %in% names(MIN_COUNT) &&
      nrow(x) < unname(MIN_COUNT[[key]]))
    stop("PODEZRELE NEUPLNA ", key, ": ", nrow(x),
         " prvku, bezpecnostni minimum je ", MIN_COUNT[[key]])
  invisible(x)
}
# Identifikátor obsahu zdrojové vrstvy pro bezpečné opakované použití cache.
# Průběžný OBJECTID seznam sám nestačí: geometrie se může změnit bez nového ID.
# Přijímáme pouze doložený čas editace služby nebo skutečné změnové pole.
# Pokud služba údaj nepublikuje, vracíme NULL a stáhneme kompletní vrstvu.
rest_otisk_zmen <- function(layer, where="1=1", url=AOPK_URL) {
  meta <- api_layer_metadata(layer,url)
  last <- meta$editingInfo$lastEditDate %||% meta$lastEditDate %||% NULL
  if (!is.null(last) && length(last)==1L && is.finite(suppressWarnings(as.numeric(last)))) {
    # Údaj musí skutečně popisovat změnu geometrické vrstvy; pouze čas
    # publikace webové stránky nebo přístupu není spolehlivým otiskem.
    return(paste("REST_LAST_EDIT",url,layer,where,as.character(last),sep="|"))
  }
  fields <- meta$fields %||% list()
  names_fields <- vapply(fields,function(f) as.character(f$name %||% ""),character(1))
  idx <- which(toupper(names_fields) == "ZMENAG")
  supports <- isTRUE(meta$advancedQueryCapabilities$supportsStatistics) ||
              isTRUE(meta$supportsStatistics)
  if (length(idx)!=1L || !supports) return(NULL)
  # Než získáme maximum, vynutíme úplnou množinu ID a nejprve zkontrolujeme,
  # že odpověď obsahuje unikátní IDs. Při chybě zastavit celý běh.
  ids_result <- api_query(layer,list(where=where,returnIdsOnly="true",returnGeometry="false"),url)
  ids <- as.integer(ids_result$objectIds %||% integer())
  if (!length(ids) || anyNA(ids) || anyDuplicated(ids))
    stop("Neuplny seznam ID pro overeni cache vrstvy ",layer)
  stats <- jsonlite::toJSON(list(list(statisticType="max",onStatisticField=names_fields[idx],
                             outStatisticFieldName="MAX_ZMENAG")),auto_unbox=TRUE)
  ans <- tryCatch(api_query(layer,list(where=where,outStatistics=as.character(stats),
             returnGeometry="false"),url),error=function(e) NULL)
  if (is.null(ans) || !length(ans$features)) return(NULL)
  current <- ans$features[[1]]$attributes$MAX_ZMENAG %||% NULL
  if (is.null(current) || !length(current) || is.na(current)) return(NULL)
  # Pokud nová úprava proběhne bez aktualizace zmenaG (porušení zdrojové
  # metadatové disciplíny), nelze ji technicky detekovat: dokumentujeme.
  ids_sorted <- paste(sort(ids),collapse=",")
  # Neužíváme externí balíček: md5 identifikátorů přes dočasný textový soubor.
  tf <- tempfile("ids_"); on.exit(unlink(tf),add=TRUE)
  writeLines(ids_sorted,tf,useBytes=TRUE)
  paste("ZMENAG",url,layer,where,length(ids),unname(tools::md5sum(tf)),
        as.character(current),sep="|")
}

# Vsechny online cache jsou nove versionovany. Stare soubory bez manifestu
# NELZE automaticky povazovat za kompletni, i kdyz jsou citelne.
cache_read <- function(path, key, layer=NULL, where="1=1", url=AOPK_URL) {
  manifest_file <- paste0(path, ".manifest.rds")
  if (!file.exists(path) || !file.exists(manifest_file)) return(NULL)
  manifest <- tryCatch(readRDS(manifest_file), error=function(e) NULL)
  # Casovy limit chrani pred nepozorovanym pouzivanim velmi starych dat.
  if (is.null(manifest) || is.null(manifest$unix_time) ||
      is.na(manifest$unix_time) ||
      (!verify_cache_online && (as.numeric(Sys.time()) - manifest$unix_time) > max_cache_age_days * 86400)) {
    message("Neni dostupna dostatecne cerstva OVERENA cache pro ", key)
    return(NULL)
  }
  if (!identical(manifest$key, key) ||
      !identical(unname(tools::md5sum(path)), manifest$md5)) return(NULL)
  if (verify_cache_online) {
    if (is.null(layer)) stop("Online overovani cache: neni urcena zdrojova vrstva ",key)
    otisk <- rest_otisk_zmen(layer,where,url)
    if (is.null(otisk) || is.null(manifest$source_fingerprint) ||
        !identical(otisk,manifest$source_fingerprint)) {
      message("CACHE: zdroj nemá průkazně shodný otisk změn; znovu stahuji ",key)
      return(NULL)
    }
  }
  x <- tryCatch(read_vector(path), error=function(e) NULL)
  if (is.null(x) || nrow(x) != manifest$n) return(NULL)
  validate_source(x, key)
  source_log[[key]] <<- paste0("OVERENA CACHE: ", path, "; puvodni stazeni ", manifest$date)
  x
}
# Jedine po uspesne validaci se zaznamena nova cache a jeji kontrolni soucet.
# Pri obnove se puvodni data nesmazou driv, nez jsou nova pripravena.
cache_store <- function(x, key, path, origin, layer=NULL, where="1=1", url=AOPK_URL) {
  if (!use_cache) return(invisible(NULL))
  validate_source(x, key)
  dir.create(dirname(path), showWarnings=FALSE, recursive=TRUE)
  tmp <- tempfile(pattern="verified_", tmpdir=dirname(path), fileext=".gpkg")
  on.exit(unlink(tmp), add=TRUE)
  sf::st_write(x, tmp, quiet=TRUE, delete_dsn=TRUE)
  # Otestujeme opetovne nacteni NOVÉHO GPKG, nikoliv jen objektu v pameti.
  check <- read_vector(tmp)
  if (nrow(check) != nrow(x)) stop("Zapis cache neobsahuje vsechny zaznamy: ", key)
  source_fingerprint <- if (verify_cache_online && !is.null(layer))
    rest_otisk_zmen(layer,where,url) else NULL
  meta <- list(key=key, n=nrow(x), source_fingerprint=source_fingerprint,
               unix_time=as.numeric(Sys.time()),
               date=format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
               md5=unname(tools::md5sum(tmp)), origin=origin)
  mtmp <- paste0(tmp, ".manifest.rds")
  on.exit(unlink(mtmp), add=TRUE)
  saveRDS(meta, mtmp)
  # Zalohujeme dosavadni funkcni dvojici pro pripad preruseni prepisu.
  old <- paste0(path, ".backup")
  oldm <- paste0(old, ".manifest.rds")
  if (file.exists(old)) unlink(old)
  if (file.exists(oldm)) unlink(oldm)
  if (file.exists(path)) file.rename(path, old)
  if (file.exists(paste0(path, ".manifest.rds")))
    file.rename(paste0(path, ".manifest.rds"), oldm)
  moved <- file.rename(tmp, path)
  movedm <- if (moved) file.rename(mtmp, paste0(path, ".manifest.rds")) else FALSE
  if (!moved || !movedm) {
    if (file.exists(path)) unlink(path)
    if (file.exists(paste0(path, ".manifest.rds"))) unlink(paste0(path, ".manifest.rds"))
    if (file.exists(old)) file.rename(old, path)
    if (file.exists(oldm)) file.rename(oldm, paste0(path, ".manifest.rds"))
    stop("Chyba atomickeho ulozeni cache ", key)
  }
  unlink(c(old, oldm))
  invisible(NULL)
}
load_layer <- function(local_key, layer, where="1=1", url=AOPK_URL) {
  local_path <- arg(local_key)
  if (!is.null(local_path)) {
    message("Mistni vrstva --", gsub("_", "-", local_key), ": ", local_path)
    x <- read_vector(local_path)
    validate_source(x, local_key)
    source_log[[local_key]] <<- paste0("MISTNI (zodpovida uzivatel): ", local_path)
    return(x)
  }
  cache_file <- file.path(cache_dir, sprintf("v055_native5514_aopk_%s_%s.gpkg", layer,
                              gsub("[^A-Za-z0-9]", "_", where)))
  if (use_cache && !refresh) {
    x <- cache_read(cache_file, local_key, layer=layer,where=where,url=url)
    if (!is.null(x)) return(x)
  }
  x <- rest_layer(layer, where, url)
  validate_source(x, local_key)
  origin <- paste0("ONLINE AOPK: ", url, "/", layer, "; filtr ", where)
  cache_store(x, local_key, cache_file, origin,layer=layer,where=where,url=url)
  source_log[[local_key]] <<- paste0(origin, "; stazeno ", format(Sys.time(), "%Y-%m-%d %H:%M"))
  x
}
# ---------------------------------------------------------------------------
# PRIMO Z CUZK: JEN CILENE POLYGONY RUIAN (NIKOLIV 240MB STATNI ZIP).
# ---------------------------------------------------------------------------
# Spolecna funkce rest_layer() provadi dva typy dotazu: seznam identifikatoru
# a potom samotne polygony. Kontroluje, zda nam server opravdu vratil vsechny.
# Pomocna cache se zapisuje az po uspechu vsech kontrol. Nebudeme se tise
# spolehat na castecny obsah, a to ani kdyz server zrovna nefunguje.
# POZOR: cache je dnes casove omezena (vychozi 7 dni), NEJDE zatim o
# inkrementalni aktualizaci podle atributu zmen. Ta prijde v dalsi verzi.
load_cuzk_ujezdy <- function() {
  key <- "data_ujezdy"                  # Nazev vstupu pouzity i jinde ve skriptu.
  local <- arg(key)                    # Volitelna mistni vrstva z --data-ujezdy.
  if (!is.null(local)) {
    x <- read_vector(local)
    validate_ujezdy(x)
    source_log[[key]] <<- paste("MISTNI:", local)
    return(x)
  }
  cache_path <- file.path(cache_dir, "v055_native5514_cuzk_vojenske_ujezdy.gpkg")
  if (use_cache && !refresh) {
    x <- cache_read(cache_path, key,layer=CUZK_UJEZDY_LAYER,where="statuskod = 1",url=CUZK_REST_URL)
    if (!is.null(x)) {
      validate_ujezdy(x)
      return(x)
    }
  }
  message("CUZK REST: vojenske ujezdy - filtr statuskod = 1 (ocekavam 4)")
  x <- rest_layer(CUZK_UJEZDY_LAYER, where = "statuskod = 1",
                  url = CUZK_REST_URL, batch_size = 4L)
  validate_ujezdy(x)                 # 4 konkretni nazvy a kody, geometrii nutno mit.
  origin <- paste0("CUZK RUIAN REST /", CUZK_UJEZDY_LAYER,
                   "; filtr statuskod = 1; ", CUZK_REST_URL)
  cache_store(x, key, cache_path, origin,layer=CUZK_UJEZDY_LAYER,where="statuskod = 1",url=CUZK_REST_URL)
  source_log[[key]] <<- paste0(origin, "; stazeno ",
                               format(Sys.time(), "%Y-%m-%d %H:%M"))
  x
}

load_cuzk_kraje <- function() {
  key <- "oop_kraje"                  # Jedine oficialni krajske hranice pro masku CR.
  local <- arg(key)                  # Volitelny GPKG/SHP --oop-kraje.
  if (!is.null(local)) {
    x <- read_vector(local)
    validate_kraje(x)
    source_log[[key]] <<- paste("MISTNI:", local)
    return(x)
  }
  cache_path <- file.path(cache_dir, "v055_native5514_cuzk_kraje.gpkg")
  if (use_cache && !refresh) {
    x <- cache_read(cache_path, key,layer=CUZK_KRAJE_LAYER,where="1=1",url=CUZK_REST_URL)
    if (!is.null(x)) {
      validate_kraje(x)
      return(x)
    }
  }
  message("CUZK REST: nacitam 14 kraju; zadny celostatni ZIP")
  # batch_size=1 znamena jeden kraj na jeden datovy dotaz: neni zpracovavan
  # ani prenasen zadny okres, obec ani katastralni uzemi mimo techto 14 kraju.
  x <- rest_layer(CUZK_KRAJE_LAYER, where = "1=1", url = CUZK_REST_URL,
                  batch_size = 1L)
  validate_kraje(x)                 # Pocet, kody, nazvy, geometrie.
  origin <- paste0("CUZK RUIAN REST /", CUZK_KRAJE_LAYER,
                   "; filtr 1=1; ", CUZK_REST_URL)
  cache_store(x, key, cache_path, origin,layer=CUZK_KRAJE_LAYER,where="1=1",url=CUZK_REST_URL)
  source_log[[key]] <<- paste0(origin, "; stazeno ",
                               format(Sys.time(), "%Y-%m-%d %H:%M"))
  x
}
# Bezpecnostni pojistky: znamy pocet, kody, nazvy, zadne prazdne plochy.
# Plati i pro MISTNI data, pokud uzivatel vyslovne neaktivoval fiktivni test.
validate_ujezdy <- function(x) {
  validate_source(x, "data_ujezdy")
  if (synthetic_data) return(invisible(TRUE))
  if (nrow(x) != 4L) stop("CUZK: musi byt presne 4 vojenske ujezdy, nalezeno ", nrow(x))
  kc <- column(names(x), c("KOD")); nc <- column(names(x), c("NAZEV"))
  observed <- setNames(norm(x[[nc]]), as.character(x[[kc]]))
  expected <- setNames(norm(names(VU_KODY)), unname(VU_KODY))
  if (!setequal(names(observed), names(expected)) ||
      !identical(unname(observed[names(expected)]), unname(expected)))
    stop("VOJENSKE UJEZDY: neshoduji se kody a nazvy (Boletice, Brezina, Hradiste, Libava)")
  invisible(TRUE)
}
validate_kraje <- function(x) {
  validate_source(x, "oop_kraje")
  if (synthetic_data) return(invisible(TRUE))
  if (nrow(x) != 14L) stop("CUZK: musi byt presne 14 kraju, nalezeno ", nrow(x))
  kc <- column(names(x), c("KOD")); nc <- column(names(x), c("NAZEV"))
  if (anyDuplicated(x[[kc]]) || anyNA(x[[kc]]) || anyNA(x[[nc]]))
    stop("CUZK: chybejici nebo duplicitni identifikatory kraju")
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# POMOCNA FUNKCE: z vysledku geometrickeho pruniku vezme POUZE plosne casti.
#
# Proc je potreba:
#   Dve uzemi se mohou dotykat POUZE hranici (LINESTRING) nebo rohem (POINT).
#   Oboji ma nulovou plochu a nepatri do tabulky plosnych prekryvu.
#   Normalni plosny prunik ale muze byt POLYGON nebo MULTIPOLYGON (vice casti).
#   Nekdy vznikne GEOMETRYCOLLECTION - smes polygonu s carami ci body.
#
# Pozor na caste chybne reseni: nevolame st_collection_extract("POLYGON")
# na KAZDY prunik. Podle dokumentace 'sf' je tato funkce urcena pro
# GEOMETRY / GEOMETRYCOLLECTION; na samostatnem MULTIPOLYGON ci LINESTRING
# muze vyhodit chybu 'singular geometry type'.
#
# Prijima sfc (seznam geometrii bez atributu). Vracime zase sfc.
#   - POLYGON / MULTIPOLYGON zachovame v plne plose.
#   - GEOMETRYCOLLECTION rozbalime a vybereme jen polygony.
#   - POINT a LINESTRING (vcetne MULTI variant) ignorujeme, maji 0 m2.
#   - Jiny neznamy typ je CHYBA, nikoli automaticka nula.
# ---------------------------------------------------------------------------
polygonove_casti <- function(g) {
  if (inherits(g, "sf")) g <- sf::st_geometry(g)
  if (!inherits(g, "sfc")) stop("polygonove_casti ocekava geometrii sf/sfc")
  if (!length(g)) return(g)
  typy <- as.character(sf::st_geometry_type(g, by_geometry = TRUE))
  polygon <- typy %in% c("POLYGON", "MULTIPOLYGON")
  kolekce <- typy == "GEOMETRYCOLLECTION"
  dotyk <- typy %in% c("POINT", "MULTIPOINT", "LINESTRING", "MULTILINESTRING")
  if (any(!(polygon | kolekce | dotyk)))
    stop("Nepodporovany typ geometrie v pruniku: ",
         paste(unique(typy[!(polygon | kolekce | dotyk)]), collapse = ", "))
  # Nejcastejsi pripad: plocha je uz platnym polygonem, nic neprevadime.
  if (all(polygon)) return(g[!sf::st_is_empty(g)])
  casti <- list()
  if (any(polygon)) casti[[length(casti) + 1L]] <- g[polygon]
  if (any(kolekce)) {
    # Na vstupu jsou ZDE VYHRADNE GEOMETRYCOLLECTION.
    # U nich smime bezpecne extrahovat polygonove soucasti.
    kol <- suppressWarnings(sf::st_collection_extract(g[kolekce], "POLYGON"))
    if (length(kol)) casti[[length(casti) + 1L]] <- kol
  }
  if (!length(casti)) return(sf::st_sfc(crs = sf::st_crs(g)))
  vysledek <- do.call(base::c, unname(casti))
  # Prazdne vysledky kolekci (napr. kolekce jen z car) nemaji plochu.
  if (length(vysledek)) vysledek <- vysledek[!sf::st_is_empty(vysledek)]
  if (length(vysledek) && any(!as.character(sf::st_geometry_type(vysledek)) %in%
                              c("POLYGON", "MULTIPOLYGON")))
    stop("Po extrakci zustala nepolygonova geometrie: NELZE pokracovat")
  vysledek
}

# VSTUPNI DATA jsou naopak povinne plosna. Na rozdil od PRUNIKU nesmime
# pri priprave vstupnich vrstev ztratit jediny polygon nebo jeho identitu.
# st_make_valid muze z neplatneho polygonu vyrobit GEOMETRYCOLLECTION;
# pro kazdy takovy prvek zachovame jeho polygonove casti SJEDNOCENE do
# JEDNE geometrie. Nepolygonova geometrie nebo prazdna plocha = STOP.
clean_geom <- function(x, oznaceni = "NEPOJMENOVANA_VRSTVA") {
  if (is.null(x) || !nrow(x)) return(NULL)

  # Kdyby kontrola CRS ci st_area selhaly kvuli JEDNOMU polygonu, zprava
  # musi alespon rikat ve ktere vrstve a v kterem kroku se tak stalo.
  krok <- function(nazev_kroku, vyraz) {
    tryCatch(force(vyraz), error = function(e)
      stop("GEOMETRIE: ", oznaceni, ", krok ", nazev_kroku, ": ",
           conditionMessage(e), call. = FALSE))
  }
  id_sloupec <- column(names(x), c("KOD", "NAZEV", "ID_ISOP", "OBJECTID"), FALSE)
  oznac_id <- function(i) {
    if (is.null(id_sloupec)) as.character(i) else
      paste0(i, " [", as.character(x[[id_sloupec]][i]), "]")
  }

  # 1) CRS pro plochy: musi JIZ BYT EPSG:5514.
  # st_transform() zde NIKDY nevolame; spatny system je chyba zdroje.
  krok("kontrola EPSG:5514", check_epsg5514(x, oznaceni,
           kontrola_polohy = !synthetic_data && !self_test_geometrie))

  # 2) V predchozich verzich se ST_MAKE_VALID poustel NA VSECHNY objekty.
  # To neni potreba a u slozitych multipart geometrii muze zbytecne
  # menit jejich reprezentaci. Zkontrolujeme kazdy; opravime JEN neplatne.
  platne <- krok("kontrola st_is_valid", sf::st_is_valid(x, NA_on_exception = TRUE))
  if (length(platne) != nrow(x) || anyNA(platne))
    stop("GEOMETRIE ", oznaceni,
         ": validita nekterych prvku neni zjistitelna; bez opravy podkladu nepokracuji")
  g <- sf::st_geometry(x)
  neplatne <- which(!platne)
  if (length(neplatne)) {
    message("  Geometrie ", oznaceni, ": ", length(neplatne),
            " neplatnych prvku; opravuji POUZE tyto prvky")
    tvary <- lapply(seq_along(g), function(i) g[[i]])
    # 'tvary' je obycejny seznam sfg; jeho prvky maji geometrii,
    # ale sam seznam NEMA tridu sfc ani vlastni CRS.
    for (i in neplatne) {
      id <- oznac_id(i)
      opravene <- tryCatch(
        suppressWarnings(sf::st_make_valid(g[i])),
        error = function(e) stop("GEOMETRIE ", oznaceni, " / ", id,
          ": st_make_valid selhalo: ", conditionMessage(e), call. = FALSE))
      poly <- tryCatch(polygonove_casti(opravene), error = function(e)
        stop("GEOMETRIE ", oznaceni, " / ", id,
          ": vyber polygonu selhal: ", conditionMessage(e), call. = FALSE))
      if (!length(poly)) stop("GEOMETRIE ", oznaceni, " / ", id,
                              ": oprava neobsahuje zadny polygon")
      jeden <- if (length(poly) == 1L) poly else tryCatch(
        suppressWarnings(sf::st_union(poly)), error = function(e)
          stop("GEOMETRIE ", oznaceni, " / ", id,
               ": sjednoceni opravenych casti selhalo: ",
               conditionMessage(e), call. = FALSE))
      if (length(jeden) != 1L || any(sf::st_is_empty(jeden)))
        stop("GEOMETRIE ", oznaceni, " / ", id,
             ": po oprave nevznikla jedna ne-prazdna geometrie")
      tvary[[i]] <- jeden[[1L]]
    }
    # do.call jednotlivymi prvky predava sfg1,sfg2,... do st_sfc().
    # NE st_sfc(tvary), coz predava vnorenej list misto souradnic.
    # c() zde spojuje OBYCEJNE seznamy, ne objekty tridy sfc.
    nove <- krok("sestaveni geometrii po oprave", do.call(
      sf::st_sfc, c(tvary, list(crs = sf::st_crs(x)))))
    sf::st_geometry(x) <- nove
  }

  # 3) Pocty, geometricke typy a plochy: na chybu se NESMI reagovat nulou.
  typy <- krok("typy polygonu", as.character(
    sf::st_geometry_type(x, by_geometry = TRUE)))
  if (any(!typy %in% c("POLYGON", "MULTIPOLYGON")))
    stop("GEOMETRIE ", oznaceni, ": nepolygonove prvky: ",
         paste(vapply(which(!typy %in% c("POLYGON", "MULTIPOLYGON")),
           oznac_id, character(1)), collapse = ", "))
  prazdne <- krok("prazdne geometrie", sf::st_is_empty(x))
  if (any(prazdne))
    stop("GEOMETRIE ", oznaceni, ": prazdne prvky: ",
         paste(vapply(which(prazdne), oznac_id, character(1)), collapse = ", "))
  konecna_validita <- krok("validita po oprave", sf::st_is_valid(x))
  if (any(!konecna_validita))
    stop("GEOMETRIE ", oznaceni, ": oprava nestacila u prvku: ",
         paste(vapply(which(!konecna_validita), oznac_id, character(1)), collapse = ", "))

  plochy <- tryCatch(as.numeric(sf::st_area(x)), error = function(e) {
    # Jen v pripade chyby projdeme polygony jednotlive. Toto neni
    # normalni zdlouhavy vypocet, ale diagnostika prvni vadne geometrie.
    for (i in seq_len(nrow(x))) {
      test <- tryCatch(as.numeric(sf::st_area(sf::st_geometry(x)[i])),
                       error = function(chyba) chyba)
      if (inherits(test, "error"))
        stop("GEOMETRIE ", oznaceni, " / ", oznac_id(i),
             ": st_area selhalo: ", conditionMessage(test), call. = FALSE)
    }
    stop("GEOMETRIE ", oznaceni, ": st_area cele vrstvy selhalo: ",
         conditionMessage(e), call. = FALSE)
  })
  if (any(!is.finite(plochy) | plochy <= 0))
    stop("GEOMETRIE ", oznaceni, ": nulova/neplatna plocha prvku: ",
         paste(vapply(which(!is.finite(plochy) | plochy <= 0),
           oznac_id, character(1)), collapse = ", "))
  x
}
# ---------------------------------------------------------------------------
# KONTROLA A OREZ PODLE KRAJU CUZK (PRED VESKERYMI PREKRYVY).
#
# Proc: EVL a PO AOPK mohou zasahovat kouskem za statni hranici.
# Hranice CR vznikne SJEDNOCENIM 14 polygonu kraju z CUZK, nikoli pouhym
# souctem jejich ploch. Jedinou geometrii potom orizneme vsechny ostatni
# vstupni vrstvy, vcetne podkladu pro vypocet pusobnosti OOP.
#
# Kontrola je vnitrni bezpecnostni pojistka, NENI NOVY KROK XLSX.
# Kazdy kraj musi mit spravnou geometrii. Kraje se nesmi plosne prekryvat,
# sjednocena CR nesmi mit vnitrni mezery ani vic oddelenych kusu.
# Bez nezavisle referencni hranice nelze z TETO kontroly odvodit, ze
# zahranicni hranice je polohove dokonala. Pro orez ji bereme za autoritativni
# vrstvu CUZK podle zvolene metodiky.
# ---------------------------------------------------------------------------
kontrola_a_maska_kraju <- function(kraje) {
  validate_kraje(kraje)                    # musi byt 14 kraju, kody a nazvy
  kraje <- clean_geom(kraje)              # S-JTSK, korektni polygonove tvary
  if (any(!sf::st_is_valid(kraje)))
    stop("CUZK KRAJE: nektery polygon neni platny; neprovadim orez")
  maska <- suppressWarnings(sf::st_union(sf::st_geometry(kraje)))
  if (length(maska) != 1L || any(sf::st_is_empty(maska)) ||
      any(!sf::st_is_valid(maska)))
    stop("CUZK KRAJE: sjednocena hranice CR neni jeden platny objekt")
  celkem_kraju <- sum(as.numeric(sf::st_area(kraje)))
  celkem_cr <- as.numeric(sf::st_area(maska))
  prekryv_kraju <- celkem_kraju - celkem_cr
  # Kontrola vnitrnich prekryvu: soucet jednotlivych ploch by jinak
  # prevysoval plochu jejich unie. Tolerujeme pouze 1 m2 numerickeho sumu.
  if (!is.finite(prekryv_kraju) || prekryv_kraju > 1)
    stop("CUZK KRAJE: polygony kraju se prekrývaji o ",
         round(prekryv_kraju, 3), " m2. Vypocet zastaven")
  if (!synthetic_data && (celkem_cr < 7.7e10 || celkem_cr > 8.1e10))
    stop("CUZK KRAJE: podezrela rozloha CR: ", round(celkem_cr/1e6), " km2")
  # CR ma tvorit jedno souvisle polygonove uzemi bez der uvnitr.
  # Vnejsi hranice nebo geopoliticke souvislosti se zde neodhaduji.
  polygony <- suppressWarnings(sf::st_cast(maska, "POLYGON", warn = FALSE))
  if (!synthetic_data && length(polygony) != 1L)
    stop("CUZK KRAJE: sjednocene kraje maji ", length(polygony),
         " oddelenych casti. Mozna mezera ci chybejici hranice")
  prstence <- sf::st_coordinates(maska)
  if (!synthetic_data && "L1" %in% colnames(prstence) &&
      any(prstence[, "L1"] > 1L))
    stop("CUZK KRAJE: ve sjednocene hranici jsou vnitrni diry. STOP")
  message("CUZK: overeno 14 kraju, sjednocena plocha ",
          format(round(celkem_cr / 1e6, 1), big.mark = " "), " km2; ",
          "vazne vnitrni prekryvy/diry nenalezeny")
  maska
}

# Statistiky orezu ukladame pouze do metodiky; nevytvarime novy list
# ani samostatnou vyrobni fazi. Puvodni stazena data v cache neprepisujeme.
orezy_cr <- list()
orez_podle_cr <- function(x, oznaceni, maska) {
  if (is.null(x) || !nrow(x)) return(x)
  message("  Orez CR: zacinam ", oznaceni, " (", nrow(x), " polygonu)")
  # Jasne pojmenovani kazde faze, abychom pri selhani nehadali,
  # zda chyba byla ve zdrojovem polygonu, pruniku nebo zapisu geometrie.
  etapa <- "kontrola vstupnich polygonu"
  tryCatch({
    x <- clean_geom(x, oznaceni)
    crs <- sf::st_crs(x)
    if (is.na(crs)) stop("Vstup nema urceny CRS")

    etapa <- "priprava masky CR"
    if (inherits(maska, "sf")) maska <- sf::st_geometry(maska)
    if (!inherits(maska, "sfc") || length(maska) != 1L || is.na(sf::st_crs(maska)))
      stop("Maska musi byt jedina geometrie s CRS")
    check_epsg5514(maska, paste0(oznaceni, " / orezova maska"))
    if (!isTRUE(sf::st_crs(maska) == crs) || any(!sf::st_is_valid(maska)))
      stop("Maska nema shodne CRS nebo neni platna")

    etapa <- "plochy pred orezem"
    puvodni_geometrie <- sf::st_geometry(x)
    plochy_pred <- as.numeric(sf::st_area(x))

    etapa <- "vyber prvku pro orez"
    uvnitr <- lengths(sf::st_covered_by(puvodni_geometrie, maska)) > 0L
    if (length(uvnitr) != nrow(x) || anyNA(uvnitr))
      stop("Neni mozno jednoznacne urcit, ktere polygony lezi v CR")
    upravit <- which(!uvnitr)

    # KLICOVA ZMENA v0.5.4: nahradni geometrie sbirame do obycejneho
    # seznamu sfg, NIKOLIV upravou existujiciho sloupce tridy sfc.
    # Teprve po dokonceni vsech pruniku vznikne novy platny sloupec sfc
    # jednim volanim st_sfc(sfg_1, sfg_2, ..., crs=5514).
    tvary <- lapply(seq_along(puvodni_geometrie),
                    function(i) puvodni_geometrie[[i]])
    stopifnot(is.list(tvary), !inherits(tvary, "sfc"),
              all(vapply(tvary, inherits, logical(1), "sfg")))
    id_sloupec <- column(names(x), c("KOD", "NAZEV", "ID_ISOP", "OBJECTID"), FALSE)
    for (i in upravit) {
      id <- if (is.null(id_sloupec)) as.character(i) else as.character(x[[id_sloupec]][i])
      etapa <- paste0("prunik ", oznaceni, " / radek ", i, " / ", id)
      prunik <- suppressWarnings(sf::st_intersection(puvodni_geometrie[i], maska))
      # st_intersection obvykle vraci platny polygon. Bezduvodne volani
      # st_make_valid by mohlo zbytecne zmenit typ multipart geometrie.
      if (length(prunik)) {
        platne <- sf::st_is_valid(prunik, NA_on_exception = TRUE)
        if (anyNA(platne)) stop("Nelze zjistit platnost geometrie pruniku")
        if (any(!platne))
          prunik <- suppressWarnings(sf::st_make_valid(prunik))
      }
      prunik <- polygonove_casti(prunik)
      if (!length(prunik)) stop("Prvek by orezem cely zmizel; vysledek nevydam")
      if (!isTRUE(sf::st_crs(prunik) == crs))
        stop("Geometrie po pruniku ztratila CRS")
      jeden <- if (length(prunik) == 1L) prunik else
        suppressWarnings(sf::st_union(prunik))
      if (length(jeden) != 1L || any(sf::st_is_empty(jeden)))
        stop("Orez nevytvoril jednu neprázdnou geometrii")
      # Z dvojite zavorky dostaneme polygon sfg, ne seznam sfc.
      tvary[[i]] <- jeden[[1L]]
    }

    if (length(upravit)) {
      etapa <- "sestaveni geometrii po orezu"
      if (!all(vapply(tvary, inherits, logical(1), "sfg")))
        stop("Interni chyba: nektery prvek noveho seznamu neni sfg")
      # VÝZNAMNY DETAIL R: do.call rozbali jednotlivé polygony.
      # st_sfc(tvary, crs=...) je SPATNE: tvary je vnorenej seznam!
      nova_sfc <- do.call(sf::st_sfc, c(tvary, list(crs = crs)))
      if (length(nova_sfc) != nrow(x) || !isTRUE(sf::st_crs(nova_sfc) == crs))
        stop("Po sestaveni se zmenil pocet prvku nebo CRS")
      sf::st_geometry(x) <- nova_sfc
    }

    etapa <- "kontrola vyslednych ploch"
    plochy_po <- as.numeric(sf::st_area(x))
    typy <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
    if (length(plochy_pred) != length(plochy_po) ||
        any(!is.finite(plochy_po) | plochy_po <= 0) ||
        any(!typy %in% c("POLYGON", "MULTIPOLYGON")) ||
        any(sf::st_is_empty(x)) || any(!sf::st_is_valid(x)) ||
        any(plochy_po > plochy_pred + pmax(1, plochy_pred * 1e-9)))
      stop("Po orezu vznikl neplatny tvar, nulova plocha nebo zmeneny pocet radku")
    odriznuto <- pmax(0, plochy_pred - plochy_po)
    orezy_cr[[oznaceni]] <<- list(
      celkem = nrow(x), upravenych = sum(odriznuto > 1),
      odriznuto_m2 = sum(odriznuto))
    message("  Orez CR: ", oznaceni, ": provereno ", length(upravit),
            " hranicnich prvku; >1 m2 odriznuto u ", sum(odriznuto > 1),
            "; celkem ", round(sum(odriznuto)), " m2")
    x
  }, error = function(e) {
    stop("OREZ CR: vrstva ", oznaceni, ", krok '", etapa, "': ",
         conditionMessage(e), call. = FALSE)
  })
}
# ==========================================================================
# INTERNI DIAGNOSTIKA GEOMETRICKYCH NESOULADU (nikdy do verejneho XLSX)
# ==========================================================================
# Pracujeme s dvema RUZNYMI sadami geometrii:
# A) NEORIZNUTE originaly v cache -> odriznute presahy do zahranici.
# B) OREZANE CHKO/NPR/NPP/OP + orezane RP -> chybejici casti RP.
# Kazdy nalez zustane samostatnym polygonem (i u multipart objektu).
# V atributu 'operace' je explicitne uvedeno, od ceho se co odecita.
# Krome tabulky vznikne GeoPackage pro Zoom To Selection v ArcGIS Pro/QGIS.
# Prilis maly fragment pod prahem min_m2 se nezapisuje, nema vliv
# na provozni plochy ani na testy kompletnosti zdrojovych vrstev.

# Bezpecne rozdelit polygonovy vystup na jednotlivy POLYGON.
# Kazdy fragment si ponecha CRS (EPSG:5514).
fragmenty_polygony <- function(geometrie) {
  g <- polygonove_casti(geometrie)
  if (!length(g)) return(g)
  suppressWarnings(sf::st_cast(g, "POLYGON", warn = FALSE))
}

# Jeden diagnosticky radek na jednu cast vzniklou operaci A minus B.
# Vstup 'geom' je sfc a 'puvodni' je plocha pred orezem (pro procenta).
zaznam_frag <- function(geom, typ, kategorie, kod, nazev, vrstva_a,
                        vrstva_b, operace, puvodni, detail = "") {
  geom <- fragmenty_polygony(geom)
  if (!length(geom)) return(NULL)
  a <- as.numeric(sf::st_area(geom))
  ok <- which(is.finite(a) & a >= diagnostic_min_area)
  if (!length(ok)) return(NULL)
  sf::st_sf(
    typ_chyby = rep(typ, length(ok)),
    kategorie = rep(kategorie, length(ok)),
    kod = rep(as.character(kod), length(ok)),
    nazev = rep(as.character(nazev), length(ok)),
    vrstva_a = rep(vrstva_a, length(ok)),
    vrstva_b = rep(vrstva_b, length(ok)),
    operace = rep(operace, length(ok)),
    detail = rep(detail, length(ok)),
    plocha_m2 = a[ok],
    podil_pct = if (is.finite(puvodni) && puvodni > 0) 100 * a[ok] / puvodni else NA_real_,
    geometry = geom[ok]
  )
}

# Porovnat KAZDY original se sjednocenou hranici CR. Vetsinu polygonu
# lze preskocit diky rychlemu prostorovemu testu 'st_covered_by'.
# Presny zbytek ale vzdy pocitame 'st_difference', nikoli odhadem.
presahy_mimo_cr <- function(vrstvy, cr_maska) {
  vysledky <- list()
  for (nazev_vrstvy in names(vrstvy)) {
    v <- vrstvy[[nazev_vrstvy]]
    if (is.null(v) || !nrow(v)) next
    # Od tohoto okamziku jsou vsechny vstupy v EPSG:5514.
    v <- clean_geom(v, paste0("DIAGNOSTIKA_", nazev_vrstvy))
    check_epsg5514(cr_maska, "diagnosticka maska CR")
    if (!isTRUE(sf::st_crs(cr_maska) == sf::st_crs(v)))
      stop("CRS diagnostiky: maska CR a vstupni vrstva nejsou ve stejnem EPSG:5514")
    cr <- cr_maska
    kc <- column(names(v), c("KOD", "ID_ISOP", "OBJECTID"), FALSE)
    nc <- column(names(v), c("NAZEV", "NAZEV_RP", "NAME"), FALSE)
    uvnitr <- lengths(sf::st_covered_by(sf::st_geometry(v), cr)) > 0L
    hranicni <- which(!uvnitr)
    message("Diagnostika hranice CR ", nazev_vrstvy, ": ", length(hranicni), " kandidatu")
    for (i in hranicni) {
      original <- sf::st_geometry(v)[i]
      zbytek <- suppressWarnings(sf::st_difference(original, cr))
      res <- zaznam_frag(zbytek, "PRESAH_MIMO_CR", nazev_vrstvy,
        if (is.null(kc)) i else v[[kc]][i],
        if (is.null(nc)) paste(nazev_vrstvy, i) else v[[nc]][i],
        nazev_vrstvy, "CUZK_KRAJE_UNIE", paste0(nazev_vrstvy, " MINUS unie krajů ČÚZK"),
        as.numeric(sf::st_area(original)))
      if (!is.null(res)) vysledky[[length(vysledky) + 1L]] <- res
    }
  }
  if (!length(vysledky)) return(NULL)
  do.call(rbind, vysledky)
}

# Vecna pusobnost AOPK, BEZ pojmenovani RP. Pri geo-discrepanci
# CHKO vs RP se musi vycislit cela mezera, nikoliv pouze jeji nahodny
# prunik s desetikusovym testovacim vyberem.
maska_pusobnosti_aopk <- function(mzchu, vzchu, op_mzchu, ujezdy) {
  if (is.null(mzchu) || is.null(vzchu) || is.null(op_mzchu))
    stop("DIAGNOSTIKA RP: chybi povinne podklady MZCHU / VZCHU / OP MZCHU")
  kc <- column(names(mzchu), c("KAT", "KATEGORIE"))
  nc <- column(names(vzchu), c("KAT", "KATEGORIE"))
  oc <- column(names(op_mzchu), c("KAT_ZCHU", "KAT_ZCHU_KOD"), FALSE)
  a <- mzchu[toupper(trimws(mzchu[[kc]])) %in% c("NPR", "NPP"), , drop=FALSE]
  b <- vzchu[toupper(trimws(vzchu[[nc]])) == "CHKO", , drop=FALSE]
  if (!is.null(oc)) {
    # Aktualni zdroj: kategorie CHU, kteremu OP patri.
    op_npr_npp <- op_mzchu[toupper(trimws(op_mzchu[[oc]])) %in% c("NPR", "NPP"), , drop=FALSE]
  } else {
    # Stare lokalni SHP a synteticke testy toto pole nemusi mit.
    # Vazbu OP dovolime VYLUCNE pres jednoznacny KOD NPR/NPP.
    k_op <- column(names(op_mzchu), c("KOD", "KOD_USOP"), FALSE)
    k_mz <- column(names(a), c("KOD", "KOD_USOP"), FALSE)
    if (is.null(k_op) || is.null(k_mz)) stop("DIAGNOSTIKA RP: KAT_ZCHU ani kodova vazba OP")
    op_npr_npp <- op_mzchu[as.character(op_mzchu[[k_op]]) %in% as.character(a[[k_mz]]), , drop=FALSE]
  }
  if (!nrow(a) || !nrow(b))
    stop("DIAGNOSTIKA RP: chybi NPR/NPP nebo CHKO")
  # Pozor: pouze na ochrannou masku AOPK, pro NP/specialni CHKO
  # plati dalsi kompetencni priorita, kterou resi provozni OOP model.
  geom <- base::c(sf::st_geometry(a), sf::st_geometry(b))
  # U historickych/syntetickych dat muze byt OP NPR/NPP prazdne.
  # Nazev 'op_npr_npp' je zamerne vymluvny: drive zde byla promenna 'c',
  # ktera prekryvala stejnojmennou zakladni funkci R pro spojovani objektu.
  if (nrow(op_npr_npp)) geom <- base::c(geom, sf::st_geometry(op_npr_npp))
  maska <- suppressWarnings(sf::st_union(geom))
  # AOPK zde nevykonava prioritu pred vojenskym ujezdem ani spravou NP.
  # Proto tyto plochy z diagnosticke masky ODECTEME. Jinak by chybejici
  # RP v NP/CHKO Sumava ci Labske piskovce vznikaly jako FALSE POSITIVE.
  kategorie_vzchu <- toupper(trimws(as.character(vzchu[[nc]])))
  nazvy_vzchu <- column(names(vzchu), c("NAZEV", "NAME"))
  spec <- kategorie_vzchu == "CHKO" & grepl("SUMAV|LABSKEPISKOVCE", norm(vzchu[[nazvy_vzchu]]))
  bez_aopk <- vzchu[kategorie_vzchu == "NP" | spec, , drop=FALSE]
  vyjimky <- list()
  if (nrow(bez_aopk)) vyjimky[[length(vyjimky)+1L]] <- sf::st_geometry(bez_aopk)
  if (!is.null(ujezdy) && nrow(ujezdy))
    vyjimky[[length(vyjimky)+1L]] <- sf::st_geometry(ujezdy)
  if (length(vyjimky)) {
    # do.call potrebuje FUNKCI, ne geoprvkovy objekt. Pouzivame explicitni
    # base::c, abychom ji nemohli omylem prekryt lokalni promennou.
    vylouceno <- suppressWarnings(sf::st_union(do.call(base::c, vyjimky)))
    maska <- suppressWarnings(sf::st_difference(maska, vylouceno))
  }
  maska
}

# Rozdil mezi uzemim vecne pusobnosti AOPK a sjednocenymi obvody RP.
mezery_regionalnich_pracovist <- function(mzchu, vzchu, op_mzchu, ujezdy, rp) {
  povinnost <- maska_pusobnosti_aopk(mzchu, vzchu, op_mzchu, ujezdy)
  rp_geometrie <- sf::st_union(sf::st_geometry(clean_geom(rp,"DIAGNOSTIKA_RP")))
  rozdil <- suppressWarnings(sf::st_difference(povinnost, rp_geometrie))
  # Pro dohledani zdroje zobrazime pouze krajni casti, nikdy jim
  # neprirazujeme 'nejblizsi RP' jako vypoctenou pravni pusobnost.
  if (!length(rozdil)) return(NULL)
  zdroje <- rbind(
    standard(mzchu, "MZCHU", "MZCHU"),
    standard(vzchu, "CHKO", "VZCHU", names_for_category="CHKO"))
  castecne <- fragmenty_polygony(rozdil)
  if (!length(castecne)) return(NULL)
  res <- list()
  for (j in seq_along(castecne)) {
    ktere <- sf::st_intersects(castecne[j], sf::st_geometry(zdroje))[[1L]]
    detail <- if (length(ktere)) paste(sprintf("%s %s (%s)",
      zdroje$kategorie[ktere], zdroje$nazev[ktere], zdroje$kod[ktere]),
      collapse="; ") else "NPR/NPP/jejich OP nebo CHKO bez shody ve vypisu"
    z <- zaznam_frag(castecne[j], "MEZERA_RP", "AOPK", "", "AOPK – RP hranice",
      "unie CHKO+NPR+NPP+OP NPR/NPP", "unie obvodů RP AOPK",
      "maska působnosti AOPK MINUS unie RP", as.numeric(sf::st_area(povinnost)), detail)
    if (!is.null(z)) res[[length(res)+1L]] <- z
  }
  if (!length(res)) return(NULL)
  do.call(rbind, res)
}

# Druhy typ chyby RP: skutecne plosne prekryvy DVOU ruznych RP.
# I kdyz provozni algoritmus vylouci dvoji zapocteni prioritou prirazeni,
# chyba hranice RP se musi objevit v diagnostice jako opravitelny polygon.
prekryvy_mezi_rp <- function(rp) {
  rp <- clean_geom(rp, "DIAGNOSTIKA_RP")
  nc <- column(names(rp), c("NAZEV_RP", "NAZEV", "NAME"))
  kd <- column(names(rp), c("KOD", "ID_ISOP", "OBJECTID"), FALSE)
  ident <- if (is.null(kd)) seq_len(nrow(rp)) else as.character(rp[[kd]])
  res <- list()
  neighbours <- sf::st_intersects(rp, rp)
  for (i in seq_len(nrow(rp))) {
    # kazdy par pouze JEDNOU (j>i), bez porovnani polygonu se sebou.
    for (j in neighbours[[i]][neighbours[[i]] > i]) {
      g <- suppressWarnings(sf::st_intersection(
        sf::st_geometry(rp)[i], sf::st_geometry(rp)[j]))
      z <- zaznam_frag(g, "PREKRYV_RP", "RP", ident[i], rp[[nc]][i],
        paste0("RP ", rp[[nc]][i]), paste0("RP ", rp[[nc]][j]),
        "RP_A PRUNIK RP_B", as.numeric(sf::st_area(rp[i, ])),
        paste0("Druhe RP: ", rp[[nc]][j], "; kod ", ident[j]))
      if (!is.null(z)) res[[length(res)+1L]] <- z
    }
  }
  if (!length(res)) return(NULL)
  do.call(rbind, res)
}


# =============================================================================
# INTERNI KATALOG TECHNICKE NEPLATNOSTI GEOMETRII (GEOS / sf)
# =============================================================================
# DULEZITE PRO GEOINFORMATIKA:
# - Funkce st_is_valid(x, reason=TRUE) testuje FORMALNI platnost polygonu
#   podle topologickych pravidel GEOS / OGC Simple Features v rovinne 5514.
# - Neoveruje pravni vyhlaseni CHU, spravnost hranice ani shodu s katastrem.
# - Text duvodu prebirame DOSLOVNE od GEOS; ceske popisy jsou vysvetlivky.
# - st_make_valid je pouze navrh TECHNICKE opravy, nikoli rozhodnuti o tom,
#   jaka hranice ma platit. Zvlaste samoprotinajici se kruznice/prstence
#   mohou mit vice rozumnych interpretaci vymezene plochy.
# - Original a navrzena provozni geometrie se proto ukladaji ZVLAST do GPKG,
#   ktery umoznuje Zoom To Selection. Stazena cache zustava nedotcena.
# - Plochu NEPLATNE geometrie nelze vzdy jednoznacne interpretovat; proto
#   porovnani jejich ploch NEPOUZIVAME jako dukaz spravnosti opravy.
# - Zaznamenavame verzi sf, GEOS, GDAL, pouzity operator i casto presnou
#   souradnici chyby (pokud ji GEOS v textu duvodu skutecne poskytl).
# - ZOZNAM v diagnostice vznikne pro CELE vstupni vrstvy, ne jen testovaci
#   vzorek deseti CHU. Soubor se nikdy nezverejnuje na verejnem GitHubu.

vysvetleni_geos_duvodu <- function(duvod) {
  d <- tolower(as.character(duvod))
  if (grepl("ring self-intersection|ring self intersection", d))
    return(c("RING_SELF_INTERSECTION",
      "Hraniční prstenec se dotýká nebo protíná sám sebe. V modelu polygonu není jeho vnitřek jednoznačně reprezentován; dvě plochy dotýkající se ve vrcholu mohou patřit do jednoho MULTIPOLYGON.",
      "V mapě ověřit bod kontaktu; samotné vložení vertexu nemusí stačit. Rozlišit technický rozpad na části od možné změny vymezení."))
  if (grepl("self-intersection|self intersection", d))
    return(c("SELF_INTERSECTION",
      "Hranice polygonu se sama kříží (nejde jen o běžné sousedství více samostatných polygonů). GEOS proto nemůže použít běžná pravidla plochy a vnitřku polygonu.",
      "Porovnat originál s navrženou opravou a s vyhlašovací dokumentací; rozhodnout, které plochy byly zamýšleny."))
  if (grepl("hole lies outside shell|hole outside shell", d))
    return(c("HOLE_OUTSIDE_SHELL",
      "Prstenec označený jako díra leží mimo svůj vnější obvod. To odporuje datovému modelu POLYGON.",
      "Ověřit pořadí a hierarchii prstenců a právní vymezení chráněné plochy."))
  if (grepl("holes are nested|nested holes", d))
    return(c("NESTED_HOLES",
      "Díry polygonu jsou vnořené do sebe způsobem, který daný model považuje za neplatný.",
      "Prověřit, zda má jít o další ostrov chráněné plochy nebo jinak sestavený multipolygon."))
  if (grepl("nested shells|shells are nested", d))
    return(c("NESTED_SHELLS",
      "Jeden vnější prstenec polygonu je uvnitř jiného, aniž je platně popsána topologie částí.",
      "Zkontrolovat vnější/vnitřní prstence a správnou reprezentaci jednotlivých částí."))
  if (grepl("disconnected interior", d))
    return(c("DISCONNECTED_INTERIOR",
      "Vnitřek polygonu není podle topologických pravidel souvislý (např. v důsledku konfigurace děr).",
      "Prověřit kontakt prstenců a případné rozdělení do více polygonů."))
  if (grepl("too few points|too few distinct points", d))
    return(c("TOO_FEW_POINTS",
      "Prstenec nemá dostatek různých souřadnic k vymezení uzavřené plošné hranice.",
      "Zkontrolovat zdegenerovaný segment; oprava může znamenat zánik geometrické části."))
  if (grepl("duplicate rings", d))
    return(c("DUPLICATE_RINGS",
      "Polygon obsahuje duplicitní hraniční prstence, jejichž role v topologii je rozporná.",
      "Zkontrolovat duplicitní kresbu a případné překrytí částí."))
  if (grepl("invalid coordinate|non-finite", d))
    return(c("INVALID_COORDINATE",
      "Geometrie obsahuje nepřípustnou či nečíselnou souřadnici.",
      "Zkontrolovat konkrétní vrchol a zdroj dat; nevymýšlet chybějící souřadnice."))
  c("JINY_DUVOD_GE0S",
    "GEOS vrátil důvod neplatnosti, který není pokryt touto vysvětlivkou. Rozhodující je doslovný text důvodu.",
    "Prohlédnout vstupní geometrii, zdokumentovat interpretaci geoinformatikem a případně doplnit pravidlo.")
}

# GEOS zpravidla uvádí místo vady v hranatých závorkách na konci důvodu,
# např. 'Self-intersection[-718456 -1043556]'. Pokud ho neuvede, nevymýšlíme
# náhradní bod. Souřadnice jsou už v metrech EPSG:5514.
misto_geos_vady <- function(duvod) {
  match <- regmatches(duvod, regexpr("\\[[^]]+\\]", duvod))
  if (!length(match) || !nzchar(match)) return(NULL)
  ciste <- gsub("[", " ", match, fixed=TRUE)
  ciste <- gsub("]", " ", ciste, fixed=TRUE)
  ciste <- gsub(",", " ", ciste, fixed=TRUE)
  polozky <- strsplit(trimws(ciste), "[[:space:]]+")[[1]]
  xy <- suppressWarnings(as.numeric(polozky))
  if (length(xy) < 2L || any(!is.finite(xy[1:2]))) return(NULL)
  xy[1:2]
}

# Primární geometrie bez oprav (raw_diag) musí být k dispozici ještě před
# ořezem hranicí krajů. Funkci NIKDY nepoužívat na již opravenou pracovní
# kopii, jinak by důvody neplatnosti zmizely.
prover_neplatne_geometrie <- function(vrstvy, slozka = NULL, zapis = TRUE) {
  rows <- list(); puvodni <- list(); navrzene <- list(); body <- list(); bod_rows <- list()
  zkontrolovano <- 0L
  for (nazev_vrstvy in names(vrstvy)) {
    vstup <- vrstvy[[nazev_vrstvy]]
    if (is.null(vstup) || !nrow(vstup)) next
    check_epsg5514(vstup, paste0("kontrola neplatnosti ", nazev_vrstvy),
                   kontrola_polohy = FALSE)
    zkontrolovano <- zkontrolovano + nrow(vstup)
    valid <- sf::st_is_valid(vstup, NA_on_exception = TRUE)
    if (anyNA(valid)) stop("NELZE diagnostikovat validitu všech prvků: ", nazev_vrstvy)
    neplatne <- which(!valid)
    if (!length(neplatne)) next
    reasons <- sf::st_is_valid(vstup[neplatne, , drop=FALSE],
                                reason=TRUE, NA_on_exception=TRUE)
    if (anyNA(reasons)) stop("GEOS nevrátil důvod neplatnosti: ", nazev_vrstvy)
    kod_sl <- column(names(vstup), c("KOD", "KOD_USOP", "ID_ISOP", "OBJECTID"), FALSE)
    nazev_sl <- column(names(vstup), c("NAZEV", "NAZEV_RP", "NAME"), FALSE)
    for (jj in seq_along(neplatne)) {
      i <- neplatne[jj]
      puvodni_geometrie <- sf::st_geometry(vstup)[i]
      doslovny_duvod <- as.character(reasons[jj])
      vysv <- vysvetleni_geos_duvodu(doslovny_duvod)
      kod <- if (is.null(kod_sl)) as.character(i) else as.character(vstup[[kod_sl]][i])
      jmeno <- if (is.null(nazev_sl)) "" else as.character(vstup[[nazev_sl]][i])
      if (is.na(kod)) kod <- ""
      if (is.na(jmeno)) jmeno <- ""
      id <- sprintf("GEOM_%05d", length(rows)+1L)
      # Stejné st_make_valid() jako ve funkci clean_geom(); samotný kandidát
      # může být GEOMETRYCOLLECTION. Následně čistě pro geometrický výpočet
      # ponecháváme polygonové části, nikoli liniové či bodové zbytky.
      kandidat <- tryCatch(suppressWarnings(sf::st_make_valid(puvodni_geometrie)),
                          error=function(e) stop("st_make_valid selhalo u ", nazev_vrstvy,
                            " / ", kod, ": ", conditionMessage(e)))
      typ_make_valid <- paste(unique(as.character(sf::st_geometry_type(kandidat))), collapse=", ")
      polygon <- polygonove_casti(kandidat)
      if (!length(polygon)) stop("Po st_make_valid nejsou žádné plošné části: ", nazev_vrstvy, " / ", kod)
      opravene <- if (length(polygon) == 1L) polygon else
        suppressWarnings(sf::st_union(polygon))
      if (length(opravene) != 1L || any(!sf::st_is_valid(opravene)))
        stop("Technická oprava je neplatná: ", nazev_vrstvy, " / ", kod)
      # 'Před opravou' je orientační st_area neplatné geometrie; nemusí
      # představovat jednoznačně definovaný plošný rozsah území!
      plocha_pred <- tryCatch(as.numeric(sf::st_area(puvodni_geometrie)),
                             error=function(e) NA_real_)
      plocha_po <- as.numeric(sf::st_area(opravene))
      typ_pred <- as.character(sf::st_geometry_type(puvodni_geometrie))[1]
      typ_po <- as.character(sf::st_geometry_type(opravene))[1]
      pozice <- misto_geos_vady(doslovny_duvod)
      rows[[length(rows)+1L]] <- data.frame(
        id_nalezu=id, vrstva=nazev_vrstvy, radek_zdroje=i, kod=kod, nazev=jmeno,
        funkce_detekce="sf::st_is_valid(x, reason=TRUE, NA_on_exception=TRUE)",
        topologicky_model="GEOS / OGC Simple Features; rovinný výpočet EPSG:5514",
        geos_duvod_doslovne=doslovny_duvod, typ_neplatnosti=vysv[1],
        vyznam=vysv[2], postup_pro_geoinformatika=vysv[3],
        stav="NEPLATNE_DLE_GEOS_NIKOLI_PROKAZANA_CHYBA_PRAVNI_HRANICE",
        funkce_navrhu="sf::st_make_valid() + polygonove_casti() + pripadne st_union()",
        geometrie_pred=typ_pred, geometrie_make_valid=typ_make_valid,
        geometrie_po=typ_po, plocha_pred_m2_orientacne=plocha_pred,
        plocha_po_m2=plocha_po, rozdil_ploch_m2_orientacne=plocha_po-plocha_pred,
        vliv_na_pravni_hranici="NEURCENO; posoudit ve vyhlasovaci dokumentaci",
        xy_chyby_dle_geos=if (is.null(pozice)) "NEUVEDENO" else paste(pozice, collapse="; "),
        stringsAsFactors=FALSE)
      puvodni[[length(puvodni)+1L]] <- puvodni_geometrie[[1L]]
      navrzene[[length(navrzene)+1L]] <- opravene[[1L]]
      if (!is.null(pozice)) {
        bod_rows[[length(bod_rows)+1L]] <- data.frame(
          id_nalezu=id, vrstva=nazev_vrstvy, kod=kod,
          geos_duvod_doslovne=doslovny_duvod, stringsAsFactors=FALSE)
        body[[length(body)+1L]] <- sf::st_point(pozice)
      }
    }
  }
  tab <- if (length(rows)) dplyr::bind_rows(rows) else data.frame(
    id_nalezu=character(), vrstva=character(), kod=character(),
    geos_duvod_doslovne=character(), typ_neplatnosti=character())
  message("GEOS DIAGNOSTIKA: ", nrow(tab), " technicky neplatných prvků z ",
          zkontrolovano, " kontrolovaných; záznamy nejsou důkazem právní chyby")
  if (!zapis) return(list(tabulka=tab, puvodni=puvodni, navrzene=navrzene))
  if (is.null(slozka) || !nzchar(slozka)) stop("Chybí složka interní diagnostiky")
  dir.create(slozka, recursive=TRUE, showWarnings=FALSE)
  verz <- sf::sf_extSoftVersion()
  metodika <- data.frame(
    polozka=c("Detekce", "Rozhodovací pravidlo", "Význam výsledku", "Technický návrh",
      "Původní geometrie", "Po opravě", "Rozdíl ploch", "Místa vad", "CRS",
      "R sf", "GEOS", "GDAL", "Právní interpretace"),
    hodnota=c("sf::st_is_valid(x, NA_on_exception=TRUE); sf::st_is_valid(x, reason=TRUE)",
      "Každý prvek, pro nějž GEOS vrátí FALSE; důvod ponechán doslovně",
      "Nesplnění topologických pravidel geometrického modelu, ne důkaz nesprávně vyhlášené hranice CHÚ",
      "st_make_valid + výběr polygonových částí; výsledek je návrh provozní geometrie, nikoliv změna právní hranice",
      "Vrstva neplatne_originaly v GPKG, identický ID_NALEZU jako v Excelu",
      "Vrstva technicke_navrhy v GPKG; viz rozdíly atributů geometrie_make_valid/geometrie_po",
      "Plocha před opravou je u neplatné geometrie jen orientační, nikoli pravdivá referenční plocha; o právním rozdílu nerozhoduje",
      "Vrstva mista_geos jen tam, kde GEOS přímo vrací konkrétní souřadnici; není-li v důvodu, nezakresluje se odhadem",
      "Vždy EPSG:5514, bez transformace", as.character(utils::packageVersion("sf")),
      as.character(verz[["GEOS"]]), as.character(verz[["GDAL"]]),
      "Samostatně prověřit původní vyhlašovací podklad; zejména samodotyk v jediném vrcholu může mít korektní multipolygonovou reprezentaci"),
    stringsAsFactors=FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Nalezy")
  openxlsx::writeData(wb, "Nalezy", popisne_hlavicky(tab))
  openxlsx::freezePane(wb, "Nalezy", firstRow=TRUE)
  openxlsx::addWorksheet(wb, "Metodika")
  openxlsx::writeData(wb, "Metodika", popisne_hlavicky(metodika))
  # Nejdříve zápis do dočasného souboru, aby neúplný běh nepřepsal výsledek.
  tmp <- tempfile("neplatne_", fileext=".xlsx")
  openxlsx::saveWorkbook(wb, tmp, overwrite=TRUE)
  vysledek <- file.path(slozka, "neplatne_geometrie.xlsx")
  diag_publish(tmp, vysledek)
  if (nrow(tab)) {
    geometrie <- function(g) do.call(sf::st_sfc, base::c(g, list(crs=5514)))
    pred <- sf::st_sf(tab, geometry=geometrie(puvodni))
    po <- sf::st_sf(tab, geometry=geometrie(navrzene))
    gpkg_tmp <- tempfile("neplatne_", fileext=".gpkg")
    sf::st_write(pred, gpkg_tmp, layer="neplatne_originaly", quiet=TRUE)
    sf::st_write(po, gpkg_tmp, layer="technicke_navrhy", append=FALSE,
                 delete_dsn=FALSE, quiet=TRUE)
    if (length(body)) {
      bod <- sf::st_sf(dplyr::bind_rows(bod_rows), geometry=geometrie(body))
      sf::st_write(bod, gpkg_tmp, layer="mista_geos", append=FALSE,
                   delete_dsn=FALSE, quiet=TRUE)
    }
    target <- file.path(slozka, "neplatne_geometrie.gpkg")
    diag_publish(gpkg_tmp, target)
  } else {
    # Kdyby při novém běhu nebyla nalezena žádná neplatnost, starý GPKG
    # nesmí dál vypadat jako aktuální výsledek.
    target <- file.path(slozka, "neplatne_geometrie.gpkg")
    if (file.exists(target)) unlink(target)
  }
  invisible(tab)
}

# Zapsat soukroma data jen do zadane mistni slozky. GitHub Actions
# pro verejnou cast pouziva --mode=public, takze sem nikdy nevstoupi.
uloz_diagnostiku <- function(presahy, mezery, prekryvy_rp, slozka) {
  dir.create(slozka, showWarnings = FALSE, recursive = TRUE)
  dsn <- file.path(slozka, "nesoulady_uzemi.gpkg")
  vystupy <- list(presahy_mimo_cr = presahy, mezery_rp = mezery, prekryvy_rp = prekryvy_rp)
  n <- sum(vapply(vystupy, function(x) if (is.null(x)) 0L else nrow(x), integer(1)))
  # Atomicky zapis: nekolik vrstev nejdrive do DOCASNEHO GPKG.
  # Stary report se meni AZ po bezchybnem zapisu vsech vrstev.
  docasny_gpkg <- tempfile(pattern="diagnostika_", fileext=".gpkg")
  on.exit(unlink(docasny_gpkg), add=TRUE)
  if (n) {
    prvni <- TRUE
    for (vrstva in names(vystupy)) {
      x <- vystupy[[vrstva]]
      if (is.null(x) || !nrow(x)) next
      sf::st_write(x, docasny_gpkg, layer=vrstva, quiet=TRUE,
                   append=FALSE, delete_dsn=prvni)
      prvni <- FALSE
    }
  }
  tabulky <- lapply(names(vystupy), function(k) {
    x <- vystupy[[k]]
    if (is.null(x) || !nrow(x)) return(NULL)
    tab <- sf::st_drop_geometry(x)
    tab$vrstva_gpkg <- k
    tab
  })
  celkem <- dplyr::bind_rows(tabulky)
  # Prazdna diagnostika je take platny vysledek; XLSX musi mit zahlavi.
  if (!ncol(celkem)) celkem <- data.frame(
    typ_chyby=character(), kategorie=character(), kod=character(),
    nazev=character(), vrstva_a=character(), vrstva_b=character(),
    operace=character(), detail=character(), plocha_m2=numeric(),
    podil_pct=numeric(), vrstva_gpkg=character())
  # XLSX prehled nese stejny identifikator a typ chyby jako GPKG.
  soubor <- file.path(slozka, "katalog_nesouladu.xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Nesoulady")
  openxlsx::writeData(wb, "Nesoulady", popisne_hlavicky(celkem))
  openxlsx::addWorksheet(wb, "Metodika")
  openxlsx::writeData(wb, "Metodika", data.frame(
    polozka=c("Zdroj statni hranice", "Presahy", "Mezery RP", "PUOS", "Poznamka"),
    hodnota=c("Unie krajů RÚIAN/ČÚZK", "PŮVODNÍ vrstva MINUS hranice ČR",
      "(CHKO + NPR + NPP + jejich OP) MINUS RP AOPK; RP A PRŮNIK RP B", "Nezohledněno",
      "GeoPackage: vybrat chybu v atributové tabulce a použít Zoom To Selection")))
  docasny_xlsx <- tempfile(pattern="diagnostika_", fileext=".xlsx")
  on.exit(unlink(docasny_xlsx), add=TRUE)
  openxlsx::saveWorkbook(wb, docasny_xlsx, overwrite=TRUE)
  # Pri uspechu se soubory postupne nahradi; zadny nedokonceny zapis
  # nebude oznacen jako vysledny. GPKG stary zustane pri selhani R.
  soubor_aktualni <- diag_publish(docasny_xlsx, soubor)
  dsn_aktualni <- if (n) diag_publish(docasny_gpkg, dsn) else NULL
  message("INTERNI DIAGNOSTIKA: ", n, " fragmentu; ", if (n) dsn_aktualni else "bez geometrickych nalezu",
    "; ", soubor_aktualni)
  invisible(list(gpkg=dsn_aktualni, xlsx=soubor_aktualni, pocet=n))
}

# RYCHLY AUTOTEST GEOMETRII, BEZ STAHOVANI DAT, pred hlavni fazi 1/5.
# Testujeme (1) skutecny polygonovy prunik, (2) hranicni dotyk,
# (3) MULTIPOLYGON, (4) smisenou GEOMETRYCOLLECTION.
if (self_test_geometrie) {
  # Kazda cast se vyzkousi samostatne. Pokud nektera selze, zprava napise
  # PRESNE KTERY TEST (v0.4.6 hlasila jen obecnou chybu bez kontextu).
  over_test <- function(nazev, vyraz) {
    message("AUTOTEST: ", nazev)
    tryCatch(force(vyraz), error = function(e)
      stop("AUTOTEST '" , nazev, "' SELHAL: ", conditionMessage(e),
           call. = FALSE))
  }
  obdelnik <- function(x1, y1, x2, y2) {
    sf::st_polygon(list(matrix(c(x1,y1, x2,y1, x2,y2, x1,y2, x1,y1),
                               ncol = 2, byrow = TRUE)))
  }
  a <- sf::st_sfc(obdelnik(0,0,10,10), crs = 5514)
  b <- sf::st_sfc(obdelnik(5,0,15,10), crs = 5514)
  over_test("1/10: skutecny plosny prunik", {
    prekryv <- polygonove_casti(sf::st_intersection(a,b))
    stopifnot(length(prekryv) == 1L,
              abs(sum(as.numeric(sf::st_area(prekryv))) - 50) < 1e-7)
  })
  over_test("2/10: dotyk pouze hranici", {
    dotyk <- polygonove_casti(sf::st_intersection(a,
                 sf::st_sfc(obdelnik(10,0,20,10), crs = 5514)))
    stopifnot(length(dotyk) == 0L)
  })
  over_test("3/10: jeden objekt MULTIPOLYGON", {
    vice_casti <- sf::st_sfc(sf::st_multipolygon(list(
      unclass(obdelnik(0,0,10,10)), unclass(obdelnik(20,0,30,10)))), crs = 5514)
    mnoho <- polygonove_casti(vice_casti)
    stopifnot(length(mnoho) == 1L,
              abs(sum(as.numeric(sf::st_area(mnoho))) - 200) < 1e-7)
  })
  over_test("4/10: polygon uvnitr GEOMETRYCOLLECTION", {
    smes <- sf::st_sfc(sf::st_geometrycollection(list(
      obdelnik(0,0,10,10), sf::st_linestring(matrix(c(10,0,20,0),
                                                    ncol=2, byrow=TRUE)))), crs = 5514)
    jen_plocha <- polygonove_casti(smes)
    stopifnot(length(jen_plocha) >= 1L,
              abs(sum(as.numeric(sf::st_area(jen_plocha))) - 100) < 1e-7)
  })
  over_test("5/10: orez pres hranici CR", {
    mistni_cr <- sf::st_sfc(obdelnik(0,0,10,10), crs = 5514)
    vstupni <- sf::st_sf(KOD = c("TEST_A", "TEST_B"), geometry = sf::st_sfc(
      obdelnik(5,5,15,15), obdelnik(0,0,2,2), crs = 5514))
    vyrezane <- orez_podle_cr(vstupni, "AUTOTEST_CR", mistni_cr)
    stopifnot(nrow(vyrezane) == 2L,
              identical(as.character(vyrezane$KOD), c("TEST_A", "TEST_B")),
              all(abs(as.numeric(sf::st_area(vyrezane)) - c(25,4)) < 1e-7))
  })
  over_test("6/10: hromadny orez multipart a neorezanych polygonu", {
    mistni_cr <- sf::st_sfc(obdelnik(0,0,10,10), crs = 5514)
    # Reprodukuje situaci, kdy u velke vrstvy orežeme jen nektere prvky.
    # Na rozdil od puvodniho maleho autotestu obsahuje i MULTIPOLYGON.
    tvary <- lapply(seq_len(61L), function(i) {
      if (i == 31L) {
        sf::st_multipolygon(list(
          unclass(obdelnik(9,1,12,3)), unclass(obdelnik(1,1,2,2))))
      } else {
        xx <- 1 + (i %% 7) * 0.3
        obdelnik(xx, 1, xx + 0.1, 2)
      }
    })
    pokus <- sf::st_sf(KOD = paste0("SCHU_TEST_", seq_len(61L)),
      geometry = do.call(sf::st_sfc, c(tvary, list(crs = 5514))))
    vysledek <- orez_podle_cr(pokus, "AUTOTEST_SCHU", mistni_cr)
    stopifnot(nrow(vysledek) == 61L,
              identical(vysledek$KOD, pokus$KOD),
              all(sf::st_is_valid(vysledek)),
              all(as.numeric(sf::st_area(vysledek)) > 0),
              all(as.numeric(sf::st_area(vysledek)) <=
                  as.numeric(sf::st_area(pokus)) + 1e-7))
  })
  # Tento test cilene reprodukuje selhani v0.5.3: po orezani bylo mozne
  # sestavit masku AOPK, ale pri ODCTENI spravy NP a vojenskeho ujezdu
  # program spadl na do.call(c, vyjimky) kvuli promenne pojmenovane 'c'.
  # Nyni musi vypocet projit i tehdy, kdyz jsou OBE vyjimky neprázdné.
  over_test("7/10: maska pusobnosti AOPK a vylouceni NP i voj. ujezdu", {
    test_mzchu <- sf::st_sf(
      KOD = c("NPR_TEST", "NPP_TEST"), KAT = c("NPR", "NPP"),
      NAZEV = c("NPR Test", "NPP Test"),
      geometry = sf::st_sfc(obdelnik(1,1,2,2), obdelnik(3,1,4,2), crs=5514))
    test_vzchu <- sf::st_sf(
      KOD = c("CHKO_TEST", "NP_TEST"), KAT = c("CHKO", "NP"),
      NAZEV = c("CHKO Test", "NP Test"),
      geometry = sf::st_sfc(obdelnik(0,0,10,10), obdelnik(6,0,8,10), crs=5514))
    test_op <- sf::st_sf(
      KOD = "OP_TEST", KAT_ZCHU = "NPR",
      geometry = sf::st_sfc(obdelnik(10,0,12,2), crs=5514))
    test_vu <- sf::st_sf(
      KOD = "VU_TEST", geometry = sf::st_sfc(obdelnik(0,0,1,10), crs=5514))
    test_maska <- maska_pusobnosti_aopk(test_mzchu, test_vzchu, test_op, test_vu)
    # Z CHKO 100 m2 + OP 4 m2 odecteme NP 20 m2 a ujezd 10 m2.
    # NPR a NPP jsou uvnitr CHKO; nezvetsuji celkovou plochu.
    stopifnot(inherits(test_maska, "sfc"),
              abs(sum(as.numeric(sf::st_area(test_maska))) - 74) < 1e-7)
  })
  over_test("8/10: nativni Esri JSON v EPSG:5514 a odmítnuti spatneho CRS", {
    # Fiktivni obdelnik v ceskych S-JTSK souradnicich: 10 x 10 m.
    # Testujeme stejny GDAL/ESRIJSON parser jako pri skutecnem stahovani.
    mock <- paste0('{"geometryType":"esriGeometryPolygon",',
      '"spatialReference":{"wkid":102067,"latestWkid":5514},',
      '"objectIdFieldName":"OBJECTID",',
      '"fields":[{"name":"OBJECTID","type":"esriFieldTypeOID"}],',
      '"features":[{"attributes":{"OBJECTID":17},',
      '"geometry":{"rings":[[[-700000,-1050000],[-700000,-1049990],',
      '[-699990,-1049990],[-699990,-1050000],[-700000,-1050000]]]}}]}')
    check_esri_sr(list(wkid = 102067L, latestWkid = 5514L), "autotest")
    polygon <- read_esrijson_5514(charToRaw(mock), "autotest EsriJSON")
    stopifnot(nrow(polygon) == 1L,
              abs(as.numeric(sf::st_area(polygon)) - 100) < 0.001)
    check_epsg5514(polygon, "autotest EsriJSON", kontrola_polohy=TRUE)
    # Simulace chyby: EPSG 4326 se MUSI odmítnout.
    spatne <- sf::st_sf(geometry = sf::st_sfc(
      obdelnik(10,10,11,11), crs = 4326))
    odmitnuto <- inherits(tryCatch({
      check_epsg5514(spatne, "autotest WGS84"); NULL
    }, error = function(e) e), "error")
    stopifnot(odmitnuto)
  })
  # Testujeme primo chybu, ktera se objevila na CUZK /MapServer/12.
  # Ve metadatech je OID pole 'objectid', nikoli 'OBJECTID'. Kody obci
  # (545422 a 592935) jsou jiny atribut a nesmeji se s OID zamenit.
  over_test("9/10: REST OID - mala/velka pismena a uplnost davky", {
    meta <- list(fields = list(
      list(name="objectid", type="esriFieldTypeOID"),
      list(name="kod", type="esriFieldTypeInteger")))
    features <- list(
      list(attributes=list(objectid=101L, kod=545422L)),
      list(attributes=list(objectid=102L, kod=592935L)))
    # Uplna davka musi projit.
    kontrola_oid_davky(features, c(101L,102L), meta, "AUTOTEST OID")
    # Pri vynechanem ci zamenenem ID musi kontrola zamerne skoncit chybou.
    neuspech <- inherits(tryCatch({
      kontrola_oid_davky(features, c(101L,999L), meta, "AUTOTEST OID"); NULL
    }, error=function(e) e), "error")
    stopifnot(neuspech)
  })
  over_test("10/10: presna diagnostika neplatnosti GEOS a navrh opravy", {
    # Zamerne samoprotinajici se prstenec (nikoli tvrzeni o pravni chybe).
    osmacka <- sf::st_polygon(list(matrix(c(
      0,0, 2,2, 0,2, 2,0, 0,0), ncol=2, byrow=TRUE)))
    x_bad <- sf::st_sf(KOD="AUTOTEST_OSM", NAZEV="Test samoprotinani",
      geometry=sf::st_sfc(osmacka, crs=5514))
    out <- prover_neplatne_geometrie(list(AUTOTEST=x_bad), zapis=FALSE)
    stopifnot(nrow(out$tabulka)==1L,
      !is.na(out$tabulka$geos_duvod_doslovne[1]),
      length(out$puvodni)==1L, length(out$navrzene)==1L)
  })
  message("AUTOTEST GEOMETRII PROSEL: 10 testu vcetne GEOS diagnostiky")
  quit(save = "no", status = 0L)
}

# =============================================================================
# NEZAVISLE DOPLNENI OOP Z DR USOP (NEMA VLIV NA GEOMETRICKY OOP)
# =============================================================================
# Stary HTML parser jednotlivych karet (126 neuspesnych ziskani OOP) se
# NEPOUZIVA. Misto nej importujeme jeden hromadny tabulkovy export na
# evidenci; k tomu slouzi separatni zdokumentovany modul v lib/.
# Bez publikovaneho exportniho API neni bezpecne odhadovat dynamicke PHP POST.
if (self_test_drusop) {
  file_arg <- grep("^--file=",commandArgs(trailingOnly=FALSE),value=TRUE)
  root <- if (length(file_arg)) dirname(normalizePath(sub("^--file=","",file_arg[1]),
               winslash="/",mustWork=TRUE)) else getwd()
  source(file.path(root,"tests","overeni_exportu_v058.R"),local=FALSE,
         encoding="UTF-8")
  quit(save="no",status=0L)
}

# STANDARDIZACE: ruzne zdroje maji ruzne nazvy sloupcu.
# Interni tabulka ma 'klic, kod, id_isop, kategorie, podkategorie, nazev'.
# Pole podkategorie je pouze pro zpetnou kompatibilitu metod; nevystupuje v XLSX.
# Klic kombinuje kategorii + kod, aby stejny kod ruznych evidenci nebyl
# povazovan za stejny objekt. Vice casti JEDNOHO objektu sloucime (union).
standard <- function(x, category, source_name, names_for_category = NULL) {
  x <- clean_geom(x)
  if (is.null(x)) return(NULL)
  kc <- column(names(x), c("KAT", "KATEGORIE"), required = FALSE)
  if (!is.null(names_for_category) && is.null(kc))
    stop("Zdroj ", source_name, " musi mit sloupec KAT (abych odlisil NP, CHKO ci OP)")
  if (!is.null(names_for_category)) {
    sel <- toupper(trimws(as.character(x[[kc]]))) %in% names_for_category
    x <- x[which(sel), , drop = FALSE]
  }
  if (!nrow(x)) return(NULL)
  # Nulove nebo chybne plochy neni dovoleno vyradit bez upozorneni.
  if (any(!is.finite(as.numeric(sf::st_area(x))) |
          as.numeric(sf::st_area(x)) <= 0))
    stop("Standardizace zjistila nulovou plochu: ", category)
  code_col <- column(names(x), c("KOD", "KOD_USOP", "SITECODE", "Kod", "ID_ISOP"), FALSE)
  # Verejna data AOPK obsahuji primo odkaz na kartu objektu v DR USOP.
  # Uchovame ho pro samostatny, NEGEOGRAFICKY dotaz na evidovany OOP.
  usop_col <- column(names(x), c("URL_USOP", "URLUSOP"), FALSE)
  usop_url <- if (is.null(usop_col)) rep("", nrow(x)) else trimws(as.character(x[[usop_col]]))
  usop_url[is.na(usop_url)] <- ""
  isop_col <- column(names(x), c("ID_ISOP", "IDISOP"), FALSE)
  name_col <- column(names(x), c("NAZEV", "NAZEV_RP", "Nazev", "NAME"), FALSE)
  object_col <- column(names(x), c("OBJECTID", "FID", "objectid"), FALSE)
  code <- if (is.null(code_col)) rep(NA_character_, nrow(x)) else trimws(as.character(x[[code_col]]))
  invalid <- is.na(code) | !nzchar(code)
  if (any(invalid)) {
    code[invalid] <- if (!is.null(object_col)) {
      paste0("OBJ_", x[[object_col]][invalid])
    } else {
      paste0("RAD_", which(invalid))
    }
  }
  isop <- if (is.null(isop_col)) rep(NA_character_, nrow(x)) else as.character(x[[isop_col]])
  subcat <- if (is.null(kc)) rep("", nrow(x)) else as.character(x[[kc]])
  # NPR/NPP/PR/PP jsou ve vystupu kazda samostatnou kategorii.
  if (category %in% c("NPR", "NPP", "PR", "PP") && any(!subcat %in% c("NPR", "NPP", "PR", "PP")))
    stop("V MZCHU zdroji je necekana kategorie KAT: ", paste(unique(subcat), collapse = ", "))
  lab <- if (is.null(name_col)) paste(category, code) else as.character(x[[name_col]])
  lab[is.na(lab) | !nzchar(lab)] <- paste(category, code[is.na(lab) | !nzchar(lab)])
  # V nove metodice je kategorie uz primo NPR/NPP/PR/PP; zadny dalsi
  # sloupec podkategorie do XLSX nevstupuje (v pameti jej ponechame kvuli
  # kompatibilite s pomocnymi diagnostickymi funkcemi).
  y <- sf::st_sf(kategorie = category, kod = code, id_isop = isop,
    podkategorie = subcat, nazev = lab, zdroj = source_name,
    url_usop = usop_url, geometry = sf::st_geometry(x))
  # group_by + summarise sjednoti pripadne vicero GIS casti jedne lokality.
  y <- y |> dplyr::group_by(kategorie, kod) |>
    dplyr::summarise(nazev = dplyr::first(nazev), id_isop = dplyr::first(id_isop),
                     podkategorie = dplyr::first(podkategorie),
                     zdroj = dplyr::first(zdroj),
                     url_usop = if (any(nzchar(url_usop))) dplyr::first(url_usop[nzchar(url_usop)]) else "",
                     .groups = "drop")
  y$klic <- paste(y$kategorie, y$kod, sep = ":")
  y |> dplyr::select(klic, kod, id_isop, kategorie, podkategorie, nazev, zdroj, url_usop)
}

# FAZE 1: Nacteni uplnych referencnich vrstev. Jiz zde je nutne stahnout
# VSECHNY objekty: jinak bychom u testovaciho ciloveho objektu mohli prehlednout
# prunik s nevybranym polygonem. Vrstvy se stahuji jen jednou na jeden beh.
message("1/5: Nacitam UPLNE referencni vrstvy")
mzchu_raw <- if (any(c("NPR", "NPP", "PR", "PP") %in% categories) || compute_oop) load_layer("data_mzchu", LAYER_IDS[["MZCHU"]]) else NULL
vzchu_raw <- if (any(c("NP", "CHKO", "OP_NP") %in% categories) || compute_oop || include_op_vzchu)
  load_layer("data_vzchu", LAYER_IDS[["VZCHU"]]) else NULL
schu_raw <- if ("SCHU" %in% categories) load_layer("data_schu", LAYER_IDS[["SCHU"]]) else NULL
evl_raw <- if ("EVL" %in% categories) load_layer("data_evl", LAYER_IDS[["EVL"]]) else NULL
po_raw <- if ("PO" %in% categories) load_layer("data_po", LAYER_IDS[["PO"]]) else NULL
# OP MZCHU pouzijeme i pro OOP (OP NPR a NPP patri do pusobnosti AOPK).
op_mzchu_raw <- if (any(c("OP_NPR", "OP_NPP", "OP_PR", "OP_PP") %in% categories) || compute_oop)
  load_layer("data_op_mzchu", LAYER_IDS[["OP_MZCHU"]]) else NULL
# Vojenske ujezdy: 4 polygony z oficialniho CUZK REST /12.
# Pokud neni nactena uplna sada ctyr ujezdu, skript NEPOKRACUJE.
ujezdy_raw <- if ("VOJ_UJEZD" %in% categories || compute_oop)
  load_cuzk_ujezdy() else NULL

# ZAPAMATOVAT PUVODNI geometrie pro interni diagnostiku.
# Jedna se o kopie objektu v pameti; cache na disku se NEMENI.
# Diagnostika se nesmi spoustet nad uz oriznutymi vrstvami,
# protoze by presahy do zahranici uz nebyly k nalezeni.
raw_diag <- if (mode != "public") list(
  MZCHU=mzchu_raw, VZCHU=vzchu_raw, SCHU=schu_raw,
  EVL=evl_raw, PO=po_raw, OP_MZCHU=op_mzchu_raw,
  VOJ_UJEZD=ujezdy_raw) else NULL
# Pro interní porovnani RP potrebujeme stejnou OVERENOU zdrojovou vrstvu
# jako pro OOP. Pri --mode=both se stahne jen JEDNOU.
rp_src_original <- if (mode != "public" || compute_oop)
  load_layer("oop_rp", LAYER_IDS[["RP"]]) else NULL
# Puvodni hranice RP mohou mit presah mimo CR stejne jako kterakoliv jina vrstva.
if (mode != "public") raw_diag$RP <- rp_src_original

# ZDE se kontroluje a pouzije hranice CR. Pred vyberem testovacich
# cilu, pred jakymkoli prunikem a pred prirazenim OOP. I kdyz je
# --oop=false, hranice CR pro samotne prekryvy stale potrebujeme.
kraje_src <- load_cuzk_kraje()
maska_cr <- kontrola_a_maska_kraju(kraje_src)
# Rozbor TECHNICKE neplatnosti se musi udelat NAD ORIGINALY pred jakoukoli
# opravou ci orezem. Uklada oddeleny XLSX + GPKG, nema vliv na OOP.
if (mode != "public") {
  prover_neplatne_geometrie(
    base::c(raw_diag, list(KRAJE=kraje_src)), slozka=diagnostic_dir)
}
message("Orezavam podkladove vrstvy hranici CR dle CUZK")
mzchu_raw <- orez_podle_cr(mzchu_raw, "MZCHU", maska_cr)
vzchu_raw <- orez_podle_cr(vzchu_raw, "VZCHU", maska_cr)
schu_raw <- orez_podle_cr(schu_raw, "SCHU", maska_cr)
evl_raw <- orez_podle_cr(evl_raw, "EVL", maska_cr)
po_raw <- orez_podle_cr(po_raw, "PO", maska_cr)
op_mzchu_raw <- orez_podle_cr(op_mzchu_raw, "OP_MZCHU", maska_cr)
ujezdy_raw <- orez_podle_cr(ujezdy_raw, "VOJ_UJEZD", maska_cr)

# INTERNE: priprava diagnozy V CELEM ROZSAHU, nezavisle na 10 testech.
# Puvodni geometrii chyby vidime v GPKG. Nevyrabime ani neopravujeme OOP.
# Ostatni vrstvy pro provozni vypocet zustavaji oriznute hranici kraju.
if (mode != "public") {
  message("DIAGNOSTIKA: analyzuji originaly vuci hranici CR a RP")
  rp_diag <- orez_podle_cr(rp_src_original, "DIAG_RP", maska_cr)
  diag_presahy <- presahy_mimo_cr(raw_diag, maska_cr)
  diag_mezery <- mezery_regionalnich_pracovist(
    mzchu_raw, vzchu_raw, op_mzchu_raw, ujezdy_raw, rp_diag)
  diag_prekryvy_rp <- prekryvy_mezi_rp(rp_diag)
  uloz_diagnostiku(diag_presahy, diag_mezery, diag_prekryvy_rp, diagnostic_dir)
}

# Diagnosticky rezim skonci az PO kontrole vzajemnych prekryvu vsech uzemi.

# HLAVNI KATEGORIE: zadne skryte spojovani NPR/NPP/PR/PP do MZCHU.
# OP MZCHU deli atribut KAT_ZCHU (kategorie CHU, k nemuz OP nalezi).
# Pokud chybi atribut nebo je hodnota jina, vysledek by mohl byt
# VECNE CHYBNY: proto skonci jasnou chybou, nikdy neodhaduje typ OP.
items <- list()
for (cat in categories) {
  if (cat %in% c("NPR", "NPP", "PR", "PP")) {
    src <- mzchu_raw
    filter_kat <- cat
  } else if (cat %in% c("NP", "CHKO")) {
    src <- vzchu_raw
    filter_kat <- cat
  } else if (cat %in% c("OP_NPR", "OP_NPP", "OP_PR", "OP_PP")) {
    src <- op_mzchu_raw
    if (is.null(src)) stop("Povinna vrstva ochrannych pasem MZCHU chybi")
    op_type <- column(names(src), c("KAT_ZCHU", "KAT_ZCHU_KOD"), FALSE)
    if (is.null(op_type)) stop("OP MZCHU nemaji pole KAT_ZCHU; nelze bezpecne rozdelit OP podle kategorie")
    belongs <- toupper(trimws(as.character(src[[op_type]])))
    if (any(is.na(belongs) | !belongs %in% c("NPR", "NPP", "PR", "PP"))) {
      stop("Neznama kategorie KAT_ZCHU u OP MZCHU: ", paste(unique(belongs[is.na(belongs) | !belongs %in% c("NPR", "NPP", "PR", "PP")]), collapse=", "))
    }
    src <- src[belongs == sub("^OP_", "", cat), , drop=FALSE]
    filter_kat <- NULL
  } else if (cat == "OP_NP") {
    src <- vzchu_raw
    filter_kat <- "OP"
  } else {
    src <- switch(cat, SCHU=schu_raw, EVL=evl_raw, PO=po_raw, VOJ_UJEZD=ujezdy_raw)
    filter_kat <- NULL
  }
  std <- standard(src, cat, cat, names_for_category=filter_kat)
  # Skutecne prazdna kategorie OP muze nastat; zapiseme ji do souhrnu jako 0.
  if (is.null(std) || !nrow(std)) {
    if (startsWith(cat, "OP_")) { message("Poznamka: ", cat, " nema evidovane polygony"); next }
    stop("Povinna kategorie neobsahuje zadna uzemi: ", cat)
  }
  items[[cat]] <- std
}
if (!length(items)) stop("Nebyla nactena zadna analyzovatelna kategorie")
# Pozor: prazdna OP kategorie ma v souhrnu rovnez byt, i kdyz nema prvky.
reference_cats <- categories
reference <- do.call(rbind, items) |> dplyr::arrange(kategorie, kod)
if (anyDuplicated(reference$klic)) stop("Nejednoznacny klic kategorie:KOD")
# Topologicke kontroly se provadeji na UPLNEM reference, nikdy na testovacim base.
if (mode != "public") {
  exe060 <- grep("^--file=",commandArgs(trailingOnly=FALSE),value=TRUE)
  koren060 <- if (length(exe060)) dirname(normalizePath(sub("^--file=","",exe060[1L]),mustWork=TRUE)) else getwd()
  source(file.path(koren060,"lib","topologie_diagnostika.R"),local=FALSE,encoding="UTF-8")
  topologie060 <- vypocti_topologii(reference, diagnostic_dir, diagnostic_min_area)
}
if (mode == "diagnostic") {
  # I bez geopocitane pusobnosti OOP sestavime jednotny rozcestnik diagnostiky.
  vytvor_diagnosticky_sesit(diagnostic_dir, topologie060, NULL,
    drusop_export_date, drusop_file, FALSE)
  message("DIAGNOSTICKY REZIM DOKONCEN: provozni XLSX ani web nevytvarim.")
  quit(save="no", status=0L)
}


# FAZE 2: vyber CILU; v plnem rezimu vsechny HLAVNI kategorie, v testu
# pseudonahodne po 10 na kazdou z nich. Reference vyse zustava beze zmeny.
message("2/5: Pripravuji cile (test=", test_mode, ")")
if (test_mode) {
  chosen <- list()
  for (i in seq_along(items)) {
    x <- items[[i]] |> dplyr::arrange(kod)
    set.seed(seed + i - 1L)
    chosen[[i]] <- x[sample.int(nrow(x), min(sample_n, nrow(x))), , drop = FALSE]
  }
  base <- do.call(rbind, chosen) |> dplyr::arrange(kategorie, kod)
} else {
  base <- do.call(rbind, items) |> dplyr::arrange(kategorie, kod)
}
message("Cilovych uzemi: ", nrow(base), "; VSECH referencnich uzemi: ", nrow(reference))

# Na vsechny referencni polygony postacuje jeden prostorovy index. Pro kazdy
# cil najdeme referencni uzemi zasahujici do jeho obaloveho polygonu/geometrie.
# Vlastni polygon se NESMI vykazovat jako prekryv sam se sebou.
# FAZE 3/5: PREKRYVY CHRANENYCH UZEMI.
# U kazdeho ciloveho objektu vypocitame presny polygonovy prunik
# se vsemi referencnimi objekty, ktere do nej zasahuji.
message("3/5: Pocitam skutecne geometricke pruniky")
# st_intersects je rychly prostorovy vyber kandidatu podle geometrie.
# Vrati pro kazdy cil seznam indexu moznych pruniku s referencemi.
# Nenulovy prekryv PLOCHY az nasledne potvrdi st_intersection.
refs_index <- sf::st_intersects(base, reference)
base_area <- setNames(as.numeric(sf::st_area(base)), base$klic)

# Jednotlive pruniky uchovavame take jako geometrie, abychom u kazde kategorie
# spocitali plochu UNIE (nikoliv prosty soucet, ktery muze byt >100 %).
details <- list(); sums <- list(); detail_i <- 0L; sums_i <- 0L
for (i in seq_len(nrow(base))) {
  if (i %% 100 == 1 || i == nrow(base)) message("  zpracovano ", i, "/", nrow(base))
  candidates <- refs_index[[i]]
  candidates <- candidates[reference$klic[candidates] != base$klic[i]]
  intersections <- list()
  if (length(candidates)) for (j in candidates) {
    # st_intersection vytvori novy polygon = skutecne spolecna plocha.
    # Nasledne st_area zmeri jeho velikost v m2.
    # suppressWarnings potlacuje obecna technicka varovani sf, nikoli chyby.
    # Identifikatory obou uzemi v hlasce zjednodusi nalezeni pripadne
    # problematicke geometrie v GIS. Nikdy nevracime 0 pri SKUTECNE chybe.
    cut <- tryCatch({
      prunik <- suppressWarnings(sf::st_intersection(
        sf::st_geometry(base[i, ]), sf::st_geometry(reference[j, ])))
      if (length(prunik)) prunik <- suppressWarnings(sf::st_make_valid(prunik))
      polygonove_casti(prunik)
    }, error = function(e) {
      stop("NELZE SPOCITAT PLOCHU PRUNIKU ", base$klic[i], " (", base$nazev[i],
           ") x ", reference$klic[j], " (", reference$nazev[j], "): ",
           conditionMessage(e), call. = FALSE)
    })
    # Dotyk POUZE v bode nebo linii: neni to plocha, do XLSX nepatri.
    if (!length(cut)) next
    m2 <- sum(as.numeric(sf::st_area(cut)))
    if (!is.finite(m2) || m2 < min_area || m2 <= 0) next
    detail_i <- detail_i + 1L
    # Jeden radek v listu Jednotlive_prekryvy = jeden konkretni par uzemi.
    # Procento pocitame vzdy z plochy CILOVEHO uzemi (A -> B).
    details[[detail_i]] <- data.frame(
      klic = base$klic[i], kod = base$kod[i], id_isop = base$id_isop[i],
      kategorie = base$kategorie[i], podkategorie = base$podkategorie[i], nazev = base$nazev[i],
      prekryv_klic = reference$klic[j], prekryv_kod = reference$kod[j],
      prekryv_id_isop = reference$id_isop[j], prekryv_kategorie = reference$kategorie[j],
      prekryv_podkategorie = reference$podkategorie[j], prekryv_nazev = reference$nazev[j],
      prekryv_m2 = m2, prekryv_km2 = m2 / 1e6,
      prekryv_pct = 100 * m2 / base_area[[base$klic[i]]],
      stringsAsFactors = FALSE)
    intersections[[as.character(j)]] <- cut
  }
  # Souhrn po kategoriich: pro kazdy typ i nulovy prekryv.
  # Souhrn za kategorii nema byt prosty soucet vsech zasahu!
  # Dva prekryvajici se polygony PO by jinak mohly vykazat treba 120 %.
  # Proto spojujeme skutecne pruniky pomoci st_union.
  # Pro kategorii bez pruniku vytvarime radek s nulou.
  for (cat in reference_cats) {
    match_idx <- which(vapply(names(intersections), function(idx)
      reference$kategorie[as.integer(idx)] == cat, logical(1)))
    group <- intersections[match_idx]
    presnost <- "STANDARDNI_GEOMETRICKY_VYPOCET"
    if (length(group)) {
      geoms <- do.call(base::c, unname(group))
      union <- suppressWarnings(sf::st_union(geoms))
      coverage <- sum(as.numeric(sf::st_area(union)))
      if (!is.finite(coverage)) stop("Neplatna plocha unie: ", base$klic[i], ", ", cat)
      # Skutecne vypoctenou plochu NESMIME tiše upravit pri vaznem nesouladu.
      # Pripustime jen jednotkove numericke zaokrouhleni (nejvyse 1e-9 plochy).
      area_cil <- base_area[[base$klic[i]]]
      if (coverage > area_cil + max(0.01, area_cil * 1e-9))
        stop("Plocha sjednoceneho prekryvu presahuje cil: ", base$klic[i], ", ", cat)
      # Pokud plochy vypadaji temer stejne, porovname skutecnou geometrii.
      # NESMIME povazovat cislo 99,999... za 100 jen podle prahu plochy.
      # Rozdil prazdnych GEOMETRII = numericka odchylka vypoctu plochy;
      # existujici rozdilovy polygon = geometricky zbytek, byt maly.
      if (abs(area_cil - coverage) <= max(1e-6, area_cil*1e-12)) {
        zbytek <- tryCatch(polygonove_casti(suppressWarnings(sf::st_difference(
          sf::st_geometry(base[i, ]), union))),
          error=function(e) stop("KONTROLA PRESNOSTI ",base$klic[i],
                                  " x ",cat,": ",conditionMessage(e)))
        if (!length(zbytek) || all(sf::st_is_empty(zbytek))) {
          coverage <- area_cil
          presnost <- "POKRYTI_GEOMETRICKY_UPLNE_ROZDIL_PLOCH_NUMERICKY"
        } else {
          presnost <- "GEOMETRICKY_ZBYTEK_I_PRI_TEMER_100_PCT"
        }
      }
      coverage <- min(area_cil, coverage)
    } else coverage <- 0
    if (coverage < min_area) coverage <- 0
    sums_i <- sums_i + 1L
    sums[[sums_i]] <- data.frame(
      klic = base$klic[i], kod = base$kod[i], kategorie = base$kategorie[i],
      podkategorie = base$podkategorie[i], nazev = base$nazev[i],
      prekryv_kategorie = cat, plocha_m2 = coverage, plocha_km2 = coverage / 1e6,
      podil_pct = 100 * coverage / base_area[[base$klic[i]]],
      pocet_uzemi = length(group), presnost_vypoctu = presnost,
      stringsAsFactors = FALSE)
  }
}

# Po vypoctu NEZAPOMINAME na prazdne tabulky: zapisi se alespon zahlavi.
# Souhrn KAZDEHO cile s KAZDOU referencni kategorii musi mit jeden radek,
# i kdyz je jejich prekryv presne 0 m2. To je soucasne kontrola uplnosti.
empty_detail <- data.frame(klic = character(), kod = character(), id_isop = character(),
  kategorie = character(), podkategorie = character(), nazev = character(),
  prekryv_klic = character(), prekryv_kod = character(), prekryv_id_isop = character(),
  prekryv_kategorie = character(), prekryv_podkategorie = character(),
  prekryv_nazev = character(), prekryv_m2 = numeric(),
  prekryv_km2 = numeric(), prekryv_pct = numeric())
detail <- if (length(details)) dplyr::bind_rows(details) else empty_detail
summary <- dplyr::bind_rows(sums)
if (nrow(summary) != nrow(base) * length(reference_cats))
  stop("V souhrnu kategorii chybi radky – nepokracujte s chybnym vystupem")

# Nezavisla vnitrni numericka kontrola: geometricka unie kategorie musi
# lezet nejvyse na plose cile, nesmi byt vetsi nez prosty soucet pruniku
# a nesmi byt mensi nez nejvetsi jednotlive zasazene uzemi.
if (nrow(summary)) {
  for (r in seq_len(nrow(summary))) {
    z <- summary[r,]
    d <- detail[detail$klic==z$klic & detail$prekryv_kategorie==z$prekryv_kategorie,,drop=FALSE]
    if (nrow(d) != z$pocet_uzemi) stop("NESEDI POCET PRUNIKU: ",z$klic,", ",z$prekryv_kategorie)
    area <- base_area[[z$klic]]
    if (z$plocha_m2 > area+max(0.01,area*1e-9)) stop("PRUNIK VETSI NEZ CIL: ",z$klic)
    if (nrow(d) && (z$plocha_m2 > sum(d$prekryv_m2)+max(0.01,area*1e-9) ||
                    z$plocha_m2+max(0.01,area*1e-9) < max(d$prekryv_m2)))
      stop("ROZPOR UNIE A INDIVIDUALNICH PRUNIKU: ",z$klic,", ",z$prekryv_kategorie)
  }
}
# VYSTUPNI ZAOKROUHLOVANI v0.6.5: 4 platne cislice, ale nikdy
# nezaokrouhlovat na desitky/stovky (nejhrubeji na cela cisla).
# Priklady: 1111111.111 -> 1111111; 1.111111 -> 1.111;
# 0.000011111111 -> 0.00001111; 11.111111 -> 11.11.
# ZASADNI: pouze vystupni hodnoty; vypocet geometrie zustava v double.
# Nulove hodnoty a cela cisla neskryvaji desetinna mista.
format_4platne <- function(v) {
  if (!is.finite(v)) return(NA_character_)
  if (v == 0) return("0")
  desetinna <- max(0L, as.integer(3 - floor(log10(abs(v)))))
  # formatC("f") nepouzije vedecky zapis ani pro male hodnoty.
  # Pro soucasne vstupy se pocet mist vejde do standardni numericke presnosti.
  y <- formatC(v, format="f", digits=desetinna, decimal.mark=".")
  if (desetinna > 0L) y <- sub("\\.?0+$", "", y)
  y
}
format_ha <- function(m2) format_4platne(as.numeric(m2)/10000)
format_pct <- function(x) format_4platne(as.numeric(x))
# Excel ma tvrdy limit 32767 znaku na bunku. Nic nekratime:
# seznam delime na cele zaznamy do navazujicich sloupcu *_2, *_3.
rozdel_seznam <- function(values, max_chars=30000L) {
  groups <- character(); cur <- ""
  for (val in values) {
    if (nchar(val) > max_chars) stop("Jednotlivy zaznam presahuje limit bunky Excelu")
    attempt <- if (nzchar(cur)) paste(cur,val,sep="; ") else val
    if (nchar(attempt) > max_chars) {
      groups <- c(groups,cur); cur <- val
    } else cur <- attempt
  }
  if (nzchar(cur) || !length(groups)) groups <- c(groups,cur)
  groups
}
# Sestavit sloupce s nekracenym seznamem, automaticky zvetsit pocet sloupcu.
pridej_seznam <- function(tbl, name, mapping) {
  chunks <- lapply(tbl$klic, function(key) rozdel_seznam(mapping[[key]] %||% character()))
  width <- max(vapply(chunks,length,integer(1)))
  for (k in seq_len(width)) {
    nm <- if (k==1) name else paste0(name,"_",k)
    tbl[[nm]] <- vapply(chunks, function(x) if(length(x)>=k) x[k] else "", character(1))
  }
  tbl
}
# Jedna radka za kazde vybrane uzemi, s kategoriemi V PRESNEM PORADI.
wide <- sf::st_drop_geometry(base) |>
  dplyr::select(klic, kategorie, nazev, kod, id_isop, url_usop) |>
  dplyr::mutate(plocha_ha = as.numeric(gsub(" ", "", vapply(unname(base_area[klic]), format_ha, character(1)), fixed=TRUE)))
# Kompletní soupis vsech individualnich pruniku, vcetne OP.
all_map <- list()
for (i in seq_len(nrow(base))) {
  key <- base$klic[i]
  d <- detail[detail$klic == key, , drop=FALSE]
  all_map[[key]] <- if (nrow(d)) sprintf("%s %s (%s ha)", d$prekryv_kategorie,
      d$prekryv_nazev, vapply(d$prekryv_m2,format_ha,character(1))) else character()
}
wide$pocet_prekryvu <- as.integer(tabulate(match(detail$klic, wide$klic), nbins=nrow(wide)))
wide <- pridej_seznam(wide,"vsechny_prekryvy",all_map)
# Kazda kategorie ma souvisle tri udaje: pocet, nazvy a plochy,
# SJEDNOCENA plocha v ha (a ctvrtou hodnotu procento).
for (cat in reference_cats) {
  dc <- detail[detail$prekryv_kategorie == cat, , drop=FALSE]
  cat_counts <- table(factor(dc$klic, levels=wide$klic))
  wide[[paste0(cat,"_pocet")]] <- as.integer(cat_counts)
  map_cat <- lapply(wide$klic,function(key) {
    d <- dc[dc$klic==key,,drop=FALSE]
    if (nrow(d)) sprintf("%s (%s ha)",d$prekryv_nazev,
                      vapply(d$prekryv_m2,format_ha,character(1))) else character()
  })
  names(map_cat) <- wide$klic
  wide <- pridej_seznam(wide,paste0(cat,"_nazvy_a_plochy"),map_cat)
  sc <- summary[summary$prekryv_kategorie==cat,,drop=FALSE]
  mm <- match(wide$klic,sc$klic)
  if (anyNA(mm)) stop("V souhrnu chybi kategorie: ", cat)
  wide[[paste0(cat,"_prekryv_ha")]] <- as.numeric(gsub(" ", "", vapply(sc$plocha_m2[mm],format_ha,character(1)), fixed=TRUE))
  wide[[paste0(cat,"_prekryv_pct")]] <- as.numeric(vapply(sc$podil_pct[mm],format_pct,character(1)))
  if (any(sc$pocet_uzemi[mm] != as.integer(cat_counts)))
    stop("ROZPOR poctu mezi detaily a souhrnem v kategorii: ", cat)
}
# Pro dalsi zpracovani hodnoty ponechavame v detailu numericke; prehled
# pouziva pozadovane zaokrouhlene texty, aby neztratil blizkost 100 %.

# 4/5: Ke kazdemu uzemi zvlast priradime uzemni pusobnost OOP.
# OOP NESLOUZI jako dalsi typ chraneneho uzemi v matici prekryvu.
# PUOS mimo vojenske ujezdy nezohlednujeme – jde o metodicke omezeni.
# FAZE 4/5: PUSOBNOST ORGANU OCHRANY PRIRODY.
# Toto je JINA analyza nez prekryvy CHU. K jednomu polygonu priradi
# plochu pro kazdy skutecne prislusny urad (soucet typicky 100 %).
# Poradi je dulezite: vojensky ujezd > sprava NP > RP AOPK > kraj.
message("4/5: Pocitam pusobnost OOP (zapnuto=", compute_oop, ")")
empty_oop <- data.frame(klic = character(), kategorie = character(), podkategorie = character(), kod = character(),
  nazev = character(), oop_typ = character(), oop_id = character(), oop_nazev = character(),
  plocha_m2 = numeric(), plocha_km2 = numeric(), podil_pct = numeric())
oopp <- empty_oop
oopc <- data.frame(klic = character(), kod = character(), kategorie = character(),
  podkategorie = character(), nazev = character(),
  plocha_m2 = numeric(), soucet_oop_m2 = numeric(), rozdil_m2 = numeric(),
  neurceno_m2 = numeric(), soucet_pct = numeric(), stav = character())

# Samostatny audit drobnych, jednoznacne potvrzenych oprav RP.
# I pri --oop=false zustane tabulka s hlavickou.
oop_korekce <- list()
if (compute_oop) {
  rp_src <- rp_src_original
  rp_src <- orez_podle_cr(rp_src, "OOP_RP", maska_cr)
  # Kraje jsou uz nactene, overene a spojene do masky CR ve FAZI 1.
  # NEMA SMYSL je stahovat nebo sestavovat podruhe.
  # Pro OOP byly jiz stazeny uplne MZCHU, VZCHU a vojenske ujezdy.
  # V pripade vlastniho souboru --oop-mzchu/--oop-vzchu lze pouzit alternativu.
  mzchu_oop <- if (!is.null(arg("oop_mzchu"))) read_vector(arg("oop_mzchu")) else mzchu_raw
  vzchu_oop <- if (!is.null(arg("oop_vzchu"))) read_vector(arg("oop_vzchu")) else vzchu_raw
  ujezdy_oop <- if (!is.null(arg("oop_ujezdy"))) read_vector(arg("oop_ujezdy")) else ujezdy_raw
  # Dodatecne lokalni vrstvy pro OOP take MUSI dodrzet hranici CR.
  # Bezne zdroje mzchu_raw/vzchu_raw/ujezdy_raw uz orezem prosly;
  # druhy orez jim neuskodi a umozni pouzit --oop-* bez chyby.
  mzchu_oop <- orez_podle_cr(mzchu_oop, "OOP_MZCHU", maska_cr)
  vzchu_oop <- orez_podle_cr(vzchu_oop, "OOP_VZCHU", maska_cr)
  ujezdy_oop <- orez_podle_cr(ujezdy_oop, "OOP_UJEZDY", maska_cr)
  validate_ujezdy(ujezdy_oop)
  choose_kat <- function(x, wanted) {
    if (is.null(x) || !nrow(x)) return(NULL)
    kc <- column(names(x), c("KAT", "KATEGORIE"))
    x[toupper(trimws(as.character(x[[kc]]))) %in% wanted, , drop = FALSE]
  }
  mzchu_naa <- clean_geom(choose_kat(mzchu_oop, c("NPR", "NPP")), "OOP_NPR_NPP")
  # § 78 ZOPK: AOPK pusobi take v ochrannych pasmech NPR a NPP.
  # Ve vrstve AOPK /3 existuje navic pole KAT_ZCHU = kategorie
  # CHRANENEHO UZEMI, ke kteremu OP patri. To ma PREDNOST pred KAT.
  # Pokud tuto hodnotu nezname, NESMIME OP PR/PP chybne priradit AOPK.
  op_naa <- NULL
  if (!is.null(op_mzchu_raw) && nrow(op_mzchu_raw)) {
    kc_op <- column(names(op_mzchu_raw), c("KAT_ZCHU", "KAT", "KATEGORIE"), FALSE)
    filtered <- NULL
    if (!is.null(kc_op)) {
      filtered <- op_mzchu_raw[which(
        toupper(trimws(as.character(op_mzchu_raw[[kc_op]]))) %in% c("NPR", "NPP")), , drop = FALSE]
    }
    if (!is.null(filtered) && nrow(filtered)) op_naa <- clean_geom(filtered,"OOP_OP_NPR_NPP")
    # U stareho lokalniho souboru bez pouzitelne KAT_ZCHU zkusime
    # vazbu pres KOD. Kod OP musi byt totozny s kodem NPR/NPP.
    if (is.null(op_naa) && !is.null(mzchu_naa)) {
      code_op <- column(names(op_mzchu_raw), c("KOD", "KOD_USOP"), FALSE)
      code_mz <- column(names(mzchu_naa), c("KOD", "KOD_USOP"), FALSE)
      if (!is.null(code_op) && !is.null(code_mz)) {
        op_naa <- clean_geom(op_mzchu_raw[which(as.character(op_mzchu_raw[[code_op]]) %in%
                                                     as.character(mzchu_naa[[code_mz]])), , drop = FALSE])
      }
    }
    if (is.null(op_naa) && !synthetic_data)
      stop("NELZE IDENTIFIKOVAT OP NPR/NPP: bez vyreseni NEPROVADIM OOP!")
  }
  np_raw <- clean_geom(choose_kat(vzchu_oop, "NP"),"OOP_NP")
  chko_raw <- clean_geom(choose_kat(vzchu_oop, "CHKO"),"OOP_CHKO")

  # Z ruznych GIS vrstev sestavime jednotny seznam uradu:
  # typ, identifikator, lidsky citelny nazev a polygon pusobnosti.
  # rename_fun slouzi jen k tvorbe vystupniho textu, nikoli hranic.
  oop_layer <- function(x, typ, name_candidates, rename_fun) {
    x <- clean_geom(x,paste0("OOP_",typ))
    if (is.null(x)) return(NULL)
    nm <- column(names(x), name_candidates)
    val <- as.character(x[[nm]])
    val[is.na(val) | !nzchar(val)] <- "NEURCENO"
    oid <- column(names(x), c("KOD", "ID_ISOP", "NAZEV_RP", "OBJECTID", "Kod"), FALSE)
    ids <- if (is.null(oid)) val else as.character(x[[oid]])
    ids[is.na(ids) | !nzchar(ids)] <- val[is.na(ids) | !nzchar(ids)]
    y <- sf::st_sf(oop_typ = typ, oop_id = ids,
      oop_nazev = vapply(val, rename_fun, character(1)), geometry = sf::st_geometry(x))
    y |> dplyr::group_by(oop_typ, oop_id, oop_nazev) |>
      dplyr::summarise(.groups = "drop") |>
      dplyr::select(oop_typ, oop_id, oop_nazev)
  }
  ujezdy <- oop_layer(ujezdy_oop, "UJEZDNI_URAD", c("NAZEV", "Nazev", "NAME"),
    function(x) paste("Újezdní úřad", x))
  kraje <- oop_layer(kraje_src, "KRAJSKY_URAD", c("NAZEV", "Nazev", "NAME"),
    function(x) if (norm(x) %in% c("PRAHA", "HLAVNIMESTOPRAHA"))
      "Magistrát hlavního města Prahy" else paste("KÚ –", x))
  rp <- oop_layer(rp_src, "AOPK_RP", c("NAZEV_RP", "NAZEV", "NAME"),
    function(x) paste("AOPK ČR –", x))

  # Narodni parky a CHKO Sumava / Labske piskovce maji zvlastni spravu.
  # Nazvy sprav NP museji byt srozumitelne. Z normalizovaneho nazvu
  # NP odvodime, ktera sprava jej ma na starosti.
  np_name <- function(x) {
    z <- norm(x)
    if (grepl("KRKONOS", z)) return("Správa Krkonošského národního parku")
    if (grepl("SUMAV", z)) return("Správa Národního parku Šumava")
    if (grepl("PODYJ", z)) return("Správa Národního parku Podyjí")
    if (grepl("CESKESVYCAR", z)) return("Správa Národního parku České Švýcarsko")
    if (synthetic_data) return(paste("Správa NP –", x))
    stop("Nepoznam spravu NP pro nazvove oznaceni: ", x)
  }
  spravy <- oop_layer(np_raw, "SPRAVA_NP", c("NAZEV", "NAME"), np_name)
  # OP narodniho parku mohou byt ve VZCHU pod KAT=OP. Pokud lze jejich KOD
  # jednoznacne sparovat s KOD NP, priradime je sprave konkretniho NP.
  # Nesparovana OP NEHADAME a nespolehame na nazvovou podobnost.
  np_op <- clean_geom(choose_kat(vzchu_oop, "OP"),"OOP_OP_NP")
  if (!is.null(np_op) && !is.null(np_raw) && nrow(np_op)) {
    nk <- column(names(np_raw), c("KOD", "KOD_USOP"), FALSE)
    ok <- column(names(np_op), c("KOD", "KOD_USOP"), FALSE)
    nn <- column(names(np_raw), c("NAZEV", "NAME"), FALSE)
    if (!is.null(nk) && !is.null(ok) && !is.null(nn)) {
      np_codes <- as.character(np_raw[[nk]])
      op_codes <- as.character(np_op[[ok]])
      links <- match(op_codes, np_codes)
      # Pokud nektere evidovane OP VZCHU nelze priřadit k NP, nedokazeme
      # bezpecne urcit, zda se jedna o OP NP ci jine uzemi. Nevytvaret OOP.
      if (anyNA(links) && !synthetic_data)
        stop("OP VZCHU bez jednoznacne vazby na NP: chybi podklad pro bezpecne OOP")
      for (h in which(!is.na(links))) {
        x <- np_name(as.character(np_raw[[nn]][links[h]]))
        y <- sf::st_sf(oop_typ = "SPRAVA_NP", oop_id = x, oop_nazev = x,
                       geometry = sf::st_geometry(np_op[h, ]))
        spravy <- if (is.null(spravy)) y else rbind(spravy, y)
      }
    }
  }
  if (!is.null(chko_raw)) {
    nc <- column(names(chko_raw), c("NAZEV", "NAME"))
    chko_names <- norm(chko_raw[[nc]])
    special <- chko_raw[grepl("SUMAV|LABSKEPISKOVCE", chko_names), , drop = FALSE]
    if (nrow(special)) {
      sname <- ifelse(grepl("LABSKEPISKOVCE", norm(special[[nc]])),
        "Správa Národního parku České Švýcarsko", "Správa Národního parku Šumava")
      y <- sf::st_sf(oop_typ = "SPRAVA_NP", oop_id = sname,
                     oop_nazev = sname, geometry = sf::st_geometry(special))
      spravy <- if (is.null(spravy)) y else rbind(spravy, y)
    }
  }
  if (!is.null(spravy)) {
    spravy <- spravy |> dplyr::group_by(oop_typ, oop_nazev) |>
      dplyr::summarise(.groups = "drop") |>
      dplyr::mutate(oop_id = oop_nazev) |>
      dplyr::select(oop_typ, oop_id, oop_nazev)
  }

  # AOPK spravuje plochu NPR/NPP a CHKO, ale konkretni RP urcime az
  # geometrickym prunikem s obvody regionalnich pracovist.
  # AOPK maska = sjednocena plocha NPR, NPP a CHKO.
  # Jeji rozdeleni na konkretni RP delame az geometrickym prunikem
  # s polygonovymi obvody RP (nezavadi se odhadem podle nazvu MZCHU).
  geom_parts <- Filter(Negate(is.null), list(mzchu_naa, op_naa, chko_raw))
  empty_mask <- sf::st_sfc(crs = 5514)
  if (length(geom_parts)) {
    masks <- do.call(base::c, lapply(geom_parts, sf::st_geometry))
    aopk_mask <- suppressWarnings(sf::st_union(masks))
  } else aopk_mask <- empty_mask
  rp_cut <- NULL; rp_neurceno <- NULL
  leftover <- aopk_mask
  if (length(aopk_mask) && !is.null(rp)) {
    # Vne dostupnych obvodu RP zustane pri AOPK povinnost jako 'RP neurceno'.
    rp_cut <- suppressWarnings(sf::st_intersection(rp,
      sf::st_sf(zona = 1L, geometry = aopk_mask)))
    if (nrow(rp_cut)) {
      rp_cut <- rp_cut |> dplyr::select(oop_typ, oop_id, oop_nazev)
      assigned <- sf::st_union(sf::st_geometry(rp_cut))
      leftover <- suppressWarnings(sf::st_difference(aopk_mask, assigned))
    }
  }
  # I velmi drobny zbytek musi byt blokovaci maskou, jinak by se
  # pri nasledujici krajské fazi omylem zapocital KÚ jako skutecny OOP.
  if (length(leftover) && sum(as.numeric(sf::st_area(leftover))) > 1e-8) {
    rp_neurceno <- sf::st_sf(oop_typ = "AOPK_RP_NEURCENO",
      oop_id = "AOPK_RP_NEURCENO", oop_nazev = "AOPK ČR – RP neurčeno",
      geometry = sf::st_make_valid(leftover))
  }

  # Poradi uradu je rozhodujici: jedna plocha muze pripadnout jen jednomu OOP.
  # Ujezdni urad -> sprava NP -> AOPK -> krajsky urad -> neurceno.
  # PRIORITA URADU: kazdy polygon uradu muze prispet jen z dosud
  # neprirazené zbývající plochy. Po kazdem pruniku se prirazena cast
  # odebere funkcí st_difference. Tím predchazime dvojitemu zapocteni.
  stages <- Filter(function(x) !is.null(x) && nrow(x),
                   list(ujezdy, spravy, rp_cut, rp_neurceno, kraje))
  if (!length(stages)) stop("Chybeji podklady pro vypocet OOP")
  records <- list(); checks <- list()
  # Diagnostika nepripustnych KU zasahu (neni OOP a neni ani nulovy radek).
  # Tyto fragmenty NEMA smysl prirazovat podle plochy sousednimu uradu.
  vyloucene_ku <- list()
  bez_ku_dle_kategorie <- c("CHKO","NPR","NPP","OP_NPR","OP_NPP","NP","OP_NP")
  for (i in seq_len(nrow(base))) {
    if (i %% 100 == 1 || i == nrow(base)) message("  OOP ", i, "/", nrow(base))
    area <- base_area[[base$klic[i]]]
    rest <- sf::st_geometry(base[i, ])
    rows <- list()
    rp_vynechano <- 0  # interně auditovaná mezera RP, ne OOP
    for (stage in stages) {
      if (!length(rest) || all(sf::st_is_empty(rest))) break
      hits <- unique(unlist(sf::st_intersects(rest, stage), use.names = FALSE))
      if (!length(hits)) next
      for (j in hits) {
        # I pri OOP muze vzniknout pouhy dotyk hranici. Ten ma 0 m2
        # a NESMI vytvorit falesne prirazeni plochy uradu.
        cut <- tryCatch({
          prunik <- suppressWarnings(sf::st_intersection(
            rest, sf::st_geometry(stage[j, ])))
          if (length(prunik)) prunik <- suppressWarnings(sf::st_make_valid(prunik))
          polygonove_casti(prunik)
        }, error = function(e) {
          stop("CHYBA GEOMETRIE OOP u ", base$klic[i], " / ",
               stage$oop_nazev[j], ": ", conditionMessage(e), call. = FALSE)
        })
        if (!length(cut)) next
        # OOP ZASADNI PRAVIDLO: KRAJSKY URAD NESMI dostat plochu CHKO,
        # NPR/NPP ani jejich OP. Nejde o prahovou hodnotu pro male plochy.
        # Urcujici je PRAVNI maska AOPK, nikoliv maly numericky vysledek.
        # Zbyle slivery zustanou v diagnostice, ale nikdy jako dalsi KU.
        if (stage$oop_typ[j] == "KRAJSKY_URAD" && length(aopk_mask)) {
          cut <- polygonove_casti(suppressWarnings(sf::st_difference(cut, aopk_mask)))
          if (!length(cut)) next
        }
        ap <- sum(as.numeric(sf::st_area(cut)))
        if (!is.finite(ap) || ap <= 0) next
        # Vecna pravidla maji prednost pred geometrickym sliverem.
        # V CHKO/NPR/NPP a jejich OP podle ZOPK nema byt krajsky urad.
        # To plati i pri vypoctene nenulove miniaturni plose a nezavisi
        # to na libovolnem zaokrouhlovacim prahu.
        if (stage$oop_typ[j] == "KRAJSKY_URAD" &&
            base$kategorie[i] %in% bez_ku_dle_kategorie) {
          if (mode != "public") {
            kvalita <- if (ap <= 1e-8) "PODEZRENI_NA_NUMERICKY_ARTEFAKT" else
                         "GEOMETRICKY_FRAGMENT_K_MAPOVE_KONTROLE"
            vyloucene_ku[[length(vyloucene_ku)+1L]] <- sf::st_sf(
              klic=base$klic[i], nazev=base$nazev[i],
              kategorie=base$kategorie[i], kandidat_urad=stage$oop_nazev[j],
              plocha_m2=ap, interpretace=kvalita,
              poznamka="KU vyloucen pravni kategorii, ne velikosti plochy; klasifikace mikrozbytku je jen podezreni",
              geometry=sf::st_union(cut))
          }
          next
        }
        # RP_NEURCENO JE VYLUČOVACÍ MASKA, NIKOLI DALŠÍ ORGÁN.
        # Bez tohoto rozlišení by drobnou mezeru nespravne dostal KÚ.
        # Jeji plocha NEBUDE ve verejnych OOP radcich ani v OOP souhrnu.
        if (stage$oop_typ[j] == "AOPK_RP_NEURCENO") {
          rp_vynechano <- rp_vynechano + ap
        } else {
          rows[[length(rows) + 1L]] <- data.frame(
            klic = base$klic[i], kategorie = base$kategorie[i],
            podkategorie = base$podkategorie[i], kod = base$kod[i], nazev = base$nazev[i],
            oop_typ = stage$oop_typ[j], oop_id = stage$oop_id[j], oop_nazev = stage$oop_nazev[j],
            plocha_m2 = ap)
        }
        rest <- suppressWarnings(sf::st_make_valid(sf::st_difference(rest, sf::st_geometry(stage[j, ]))))
        if (!length(rest) || all(sf::st_is_empty(rest))) break
      }
    }
    # ZADNE DOPLNOVANI NEJBLIŽŠÍM RP.
    # Uvnitř masky AOPK mohou být drobné topologické mezery vrstvy RP.
    # Jejich plocha se v samostatne etape rp_neurceno odebrala z 'rest',
    # NENI pripsana zadnemu RP ani naslednemu krajskemu uradu.
    # Pro provereni je PRESNY POLYGON v soukrome diagnostice.
    # Plosny zbytek mimo VSECHNY kraje ani AOPK NENI dovoleno
    # zamaskovat disclaimerem: selhani kompetencniho podkladu = STOP.
    unresolved <- if (length(rest)) sum(as.numeric(sf::st_area(rest))) else 0
    if (!is.finite(unresolved) || unresolved > max(min_area, area * 1e-8)) {
      stop("OOP NEMOZNO PUBLIKOVAT: mimo kraje/známe pusobnosti zustalo ",
           format(unresolved, digits=12), " m2 u ", base$klic[i],
           "; povoleny je jen zbytek mezi maskou AOPK a RP")
    }
    # Drobnou mezeru RP smime ignorovat pouze v nastavenych mezich.
    # Neni-li drobna, nejde o provozni zjednoduseni => STOP.
    if (!is.finite(rp_vynechano) ||
        rp_vynechano > max_rp_gap_m2 ||
        100 * rp_vynechano / area > max_rp_gap_pct) {
      stop("VÝZNAMNÁ MEZERA RP u ", base$klic[i], ": ",
           round(rp_vynechano,3), " m2 / ",
           signif(100*rp_vynechano/area, 6),
           " %. Nezverejnuji neoverene rozdeleni OOP; viz interni diagnostika.")
    }
    allocated <- if (length(rows)) sum(vapply(rows, function(x) x$plocha_m2[1], numeric(1))) else 0
    # Součet známých OOP může být O KOUSEK NIŽŠÍ než 100 %.
    # Žádné procento uměle nenormalizujeme a nevyrábíme fiktivní OOP.
    if (abs(area - allocated - rp_vynechano - unresolved) > max(1, area * 1e-7))
      stop("NESOULAD PLOCH pri OOP: ", base$klic[i],
           "; soucet RP mezery + OOP neodpovida celku")
    records[[i]] <- if (length(rows)) dplyr::bind_rows(rows) else NULL
    checks[[i]] <- data.frame(klic = base$klic[i], kod = base$kod[i],
      kategorie = base$kategorie[i], podkategorie = base$podkategorie[i],
      nazev = base$nazev[i], plocha_m2 = area,
      soucet_oop_m2 = allocated,
      rozdil_m2 = area - allocated,
      neurceno_m2 = rp_vynechano + unresolved,
      soucet_pct = 100 * allocated / area,
      stav = "OK")
  }
  assigned <- dplyr::bind_rows(records)
  if (nrow(assigned)) {
    oopp <- assigned |> dplyr::group_by(klic, kategorie, podkategorie, kod, nazev, oop_typ, oop_id, oop_nazev) |>
      dplyr::summarise(plocha_m2 = sum(plocha_m2), .groups = "drop") |>
      dplyr::mutate(plocha_km2 = plocha_m2 / 1e6,
                    podil_pct = 100 * plocha_m2 / unname(base_area[klic])) |>
      dplyr::arrange(kategorie, kod, dplyr::desc(plocha_m2))
    # v0.6.3: nevýznamný geometrický zbytek zůstává v DETAILU, ale
    # nepředstavuje další plnohodnotný úřad v souhrnu jednoho území.
    # Obě podmínky platí současně; žádná plocha se nepřiřazuje jinému OOP.
    oopp$mikrofragment_oop <- (oopp$plocha_m2 < 1 & oopp$podil_pct < 0.001)
    oopp$uvaden_v_souhrnu <- !oopp$mikrofragment_oop
    oopp_souhrn <- oopp[oopp$uvaden_v_souhrnu, , drop=FALSE]
    # Neztratit území, u kterého by se omylem odfiltrovaly všechny úřady.
    if (!setequal(unique(oopp$klic), unique(oopp_souhrn$klic)))
      stop("OOP souhrn: některé území má pouze mikrofragmenty")
    oopwide <- oopp_souhrn |> dplyr::group_by(klic) |>
      dplyr::summarise(OOP_pocet = dplyr::n(),
        OOP_souhrn = paste(sprintf("%s: %s %%", oop_nazev, vapply(podil_pct, format_pct, character(1))), collapse = "; "),
        .groups = "drop")
    wide <- dplyr::left_join(wide, oopwide, by = "klic")
  }
  oopc <- dplyr::bind_rows(checks)
  if (nrow(oopc) != nrow(base)) stop("Chybi nektera kontrola OOP")
  if (nrow(oopp) == 0) stop("OOP byly zapnuty, ale nevznikl zadny vysledek")
  # Do OOP_podle_uradu se smi dostat pouze SKUTECNY urad.
  # V OOP_kontrola zachovame pouze stav kontroly, bez fiktivniho OOP
  # s podilem vynechane plochy. Neprirazene polygony jsou INTERNI report.
  if (any(oopp$oop_typ == "KRAJSKY_URAD" &
          oopp$kategorie %in% bez_ku_dle_kategorie))
    stop("VECNA CHYBA OOP: krajske urady u uzemi v prioritni pusobnosti AOPK/NP")
  if (any(oopp$oop_typ %in% c("NEURCENO", "AOPK_RP_NEURCENO")))
    stop("CHYBA: do verejneho OOP pronikl neexistujici urad")
  if (any(oopc$stav != "OK")) stop("CHYBA: interni kontrola OOP neprosla")
  oopc <- oopc[, c("klic", "kod", "kategorie", "podkategorie", "nazev", "stav")]
  if (mode != "public") {
    if (!dir.exists(diagnostic_dir)) dir.create(diagnostic_dir,recursive=TRUE)
    dest <- file.path(diagnostic_dir, "nepripustne_OOP_kraje.gpkg")
    if (length(vyloucene_ku)) {
      private <- do.call(rbind, vyloucene_ku)
      docasny_ku <- tempfile("KU_", fileext=".gpkg")
      sf::st_write(private,docasny_ku,layer="KU_vyloucene_kategorie",
                   delete_dsn=TRUE,quiet=TRUE)
      diag_publish(docasny_ku,dest)
      message("OOP DIAGNOSTIKA: ", nrow(private),
              " vecne nepripustnych KU zasahu (v GPkg; neni duvod je prirazovat).")
    } else if (file.exists(dest)) unlink(dest)  # stary soubor nesmi pretrvat jako aktualni
  }
} else {
  wide$OOP_souhrn <- "NEPOCITANO (--oop=false)"
}

# Predchozi automaticke 'OOP_korekce' byly odstraneny.
# Zadne odhadnute prirazeni RP neni dovoleno. Prislusnost uradu
# a presna geometrie chyby zustavaji ve dvou oddelenych vetvich.

# Kody a URL budou ve verejnem Souhrnu_po_uzemich AZ NA KONCI.
# Tabulka OOP_DRUSOP je dostupna i kdyz dotazy vypneme (jen prazdny sloupec).
# To umozni v budoucnu snadno porovnavat s geografickym OOP v jednom Excelu.
wide$OOP_DRUSOP <- ""
wide$DRUSOP_stav <- if (query_drusop) "NEZPRACOVANO" else "NEPOZADOVANO"
wide$DRUSOP_overeno <- ""
wide$DRUSOP_zdroj <- ""
wide$DRUSOP_kategorie <- ""
wide$DRUSOP_nazev <- ""
wide$OOP_shoda <- if (!compute_oop) "GEO_NEVYPOCTENO" else "DRUSOP_NEDOSTUPNY"
wide$OOP_pouze_DRUSOP <- ""
wide$OOP_pouze_geo <- ""
wide$OOP_geo_mikrofragmenty <- ""
wide$OOP_geo_pocet_vsech <- NA_integer_
wide$OOP_geo_pocet_v_souhrnu <- NA_integer_
wide$OOP_vysvetleni_rozdilu <- ""
if (query_drusop) {
  # Nacteme jen tabulkovy export; NIKDY neprepisujeme geografickou pusobnost.
  exe <- grep("^--file=",commandArgs(trailingOnly=FALSE),value=TRUE)
  koren <- if (length(exe)) dirname(normalizePath(sub("^--file=","",exe[1L]),
                           winslash="/",mustWork=TRUE)) else getwd()
  source(file.path(koren,"lib","drusop_export.R"),local=FALSE,encoding="UTF-8")
  # Novy primarni rezim: jeden tabulatorem oddeleny drusop_oop.txt (CP1250).
  # Kdyz soubor v WD chybi, zustava stary rezim se slozkou exportu evidenci.
  if (nzchar(drusop_file)) {
    if (!file.exists(drusop_file)) stop("DR USOP: chybi soubor --drusop-file=",drusop_file)
    exports <- import_drusop_jednotny(drusop_file)
    jednotny_export <- TRUE
  } else {
    exports <- import_drusop_exporty(drusop_export_dir)
    jednotny_export <- FALSE
  }
  # Kontrola, ze export souhlasi se vsemi *aktualnimi* GIS kody.
  # JEDNOTNY export muze zahrnovat i stare zaznamy. Rozdil celkovych poctu
  # proto neni chyba. Chybejici kod naopak zaznamename; u tohoto doplnkoveho
  # zdroje se tim NESMI prepsat nebo vynechat geograficky vysledek.
  exp_kat <- list(MZCHU=c("NPR","NPP","PR","PP"),
                  VZCHU=c("NP","CHKO"), EVL="EVL", PO="PO", SCHU="SCHU")
  for (ty in names(exports)) {
    expected <- unique(as.character(reference$kod[reference$kategorie %in% exp_kat[[ty]]]))
    present <- as.character(exports[[ty]]$kod)
    missing <- setdiff(expected,present)
    if (length(missing)) {
      text <- paste0("DR USOP: ",ty,": chybi ",length(missing),
          " kodu z ",length(expected)," GIS objektu; prvni: ",
          paste(head(missing,10L),collapse=", "))
      if (!jednotny_export) stop(text,". Exportujte VSE, ne jen aktualni stranku.")
      message("UPOZORNENI: ",text," (neovlivni GIS vypocet)")
    }
  }
  for (i in seq_len(nrow(wide))) {
    x <- najdi_oop_v_exportu(exports, as.character(wide$kategorie[i]),
                             as.character(wide$kod[i]),as.character(wide$nazev[i]))
    wide$OOP_DRUSOP[i] <- x$oop
    wide$DRUSOP_stav[i] <- x$stav
    wide$DRUSOP_zdroj[i] <- x$zdroj
    wide$DRUSOP_kategorie[i] <- x$kategorie_export
    wide$DRUSOP_nazev[i] <- x$nazev_export
    wide$DRUSOP_overeno[i] <- paste0("IMPORTOVANO ",format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
    if (compute_oop && !nzchar(x$oop)) wide$OOP_shoda[i] <- x$stav
  }
  message("DR USOP: ", sum(nzchar(wide$OOP_DRUSOP)),
          " OOP z ",nrow(wide)," testovanych objektu; ",
          "bez samostatneho zaznamu ",sum(wide$DRUSOP_stav=="BEZ_SAMOSTATNEHO_ZAZNAMU"))
}
# Srovnani je NEZAVISLE na geografickem modelu a nic v nem nemeni.
# Rozlisujeme presne porovnane nazvy, alternativni oficialni pojmenovani
# (RP/KU/NP) a vice ruznych OOP. Nesoulad jen oznacujeme K PROVERENI.
if (compute_oop && query_drusop && nrow(oopp)) {
  for (i in seq_len(nrow(wide))) {
    if (!nzchar(wide$OOP_DRUSOP[i])) next
    matches <- oopp[oopp$klic == wide$klic[i] &
         !(oopp$oop_typ %in% c("NEURCENO", "AOPK_RP_NEURCENO")), ,drop=FALSE]
    # Porovnávat evidenci se SOUHRNNĚ vykazovanými úřady.
    # Podrobné geometrické přiřazení včetně mikrofragmentů je zachováno.
    celkove <- porovnej_oop_drusop_geo(wide$OOP_DRUSOP[i],matches$oop_nazev)
    podstatne <- matches[!matches$mikrofragment_oop, , drop=FALSE]
    cmp <- porovnej_oop_drusop_geo(wide$OOP_DRUSOP[i],podstatne$oop_nazev)
    mikro <- matches[matches$mikrofragment_oop, , drop=FALSE]
    wide$OOP_geo_mikrofragmenty[i] <- if(nrow(mikro))
      paste(sprintf("%s (%.6f m²; %.9f %%)", mikro$oop_nazev,
        mikro$plocha_m2, mikro$podil_pct),collapse="; ") else ""
    wide$OOP_geo_pocet_vsech[i] <- nrow(matches)
    wide$OOP_geo_pocet_v_souhrnu[i] <- nrow(podstatne)
    wide$OOP_shoda[i] <- cmp$stav
    wide$OOP_pouze_DRUSOP[i] <- cmp$pouze_drusop
    wide$OOP_pouze_geo[i] <- cmp$pouze_geo
    if (identical(cmp$stav,"SHODA") && !identical(celkove$stav,"SHODA")) {
      wide$OOP_shoda[i] <- "MIKROFRAGMENT"
      wide$OOP_vysvetleni_rozdilu[i] <- "Úplná geometrie obsahuje další OOP jen na ploše <1 m² a současně <0,001 % území; uveden pouze v detailním geometrickém rozpisu."
    } else if (identical(cmp$stav,"ROZDIL_K_PROVERENI") &&
               !nzchar(cmp$pouze_drusop) && nzchar(cmp$pouze_geo)) {
      wide$OOP_shoda[i] <- "DILCI_PUSOBNOST"
      wide$OOP_vysvetleni_rozdilu[i] <- paste0(
        "Evidovaný úřad je také geometricky přítomen; navíc se v jiné části území uplatňuje: ",
        cmp$pouze_geo, ". Konkrétní právní důvod a vrstvu ověřit v GIS; nejde o prokázanou chybu evidence.")
    } else if (identical(cmp$stav,"ROZDIL_K_PROVERENI")) {
      wide$OOP_vysvetleni_rozdilu[i] <- "Rozdíl evidence DR ÚSOP oproti plošně relevantním geometrickým OOP; vyžaduje ruční prověření včetně možného PUOS."
    } else if (identical(cmp$stav,"SHODA")) {
      wide$OOP_vysvetleni_rozdilu[i] <- "Shoda evidence se seznamem významných geometrických OOP."
    }
  }
  message("DR USOP vs. GEO: ",paste(names(table(wide$OOP_shoda)),
          as.integer(table(wide$OOP_shoda)),sep="=",collapse="; "))
}

# 5/5: Dokumentace ve vystupnim XLSX + ulozeni souboru.
# FAZE 5/5: ZAPIS XLSX.
# Ke kazde tabulce pridame filtry, zamrazeni prvniho radku a sirky sloupcu.
# Metodika obsahuje zdroje, pravidla a disclaimer k PUOS.
message("5/5: Ukladam XLSX")
# Jeden souhrn orezu pouze do metodiky (nikoli dalsi XLSX kontrolni list).
orez_popis <- if (!length(orezy_cr)) "Orez se neprovedl" else paste(
  vapply(names(orezy_cr), function(k) {
    z <- orezy_cr[[k]]
    sprintf("%s: %d z %d uzemi, odriznuto %.3f km2",
            k, z$upravenych, z$celkem, z$odriznuto_m2/1e6)
  }, character(1)), collapse = "; ")
counts <- data.frame(kategorie = reference_cats,
  funkce = ifelse(reference_cats %in% secondary_cats, "vedlejsi reference (OP)", "hlavni kategorie"),
  vsechna_uzemi = vapply(reference_cats, function(cat) sum(reference$kategorie == cat), integer(1)),
  vypoctena_uzemi = vapply(reference_cats, function(cat) sum(base$kategorie == cat), integer(1)))
# Zaznamenavame rovnez puvod kazde vrstvy – ONLINE / lokalni soubor / cache.
source_info <- if (length(source_log)) {
  data.frame(vrstva = names(source_log),
             zdroj_a_stazeni = unlist(source_log, use.names = FALSE))
} else {
  data.frame(vrstva = character(), zdroj_a_stazeni = character())
}
metadata <- data.frame(polozka = c(
    "Verze", "Datum a cas vypoctu", "Rezim", "Fiktivni testovaci data", "Velikost testovaciho vzorku", "Seed",
    "Cilova uzemi", "Referencni uzemi", "Vystupni kategorie", "Dalsi reference",
    "Minimalni plocha pruniku m2", "Metoda plochy", "Vyuziti jednotlivych kategorii MZCHU",
    "OP MZCHU", "OOP zapnuto", "OOP – priorita", "OOP – pravni omezeni",
    "PUOS – ZASADNI METODICKY DISCLAIMER",
    "OREZ HRANICI CR – ZASADNI METODICKY DISCLAIMER", "Orez – souhrn", "Zdroj geodat AOPK",
    "Zdroj vojenskych ujezdu a kraju CUZK", "CACHE – vyznam", "Maximalni stari cache ve dnech", "Presnost vyhodnoceni",
    "Ochranna pasma NP a MZCHU", "Nezkracene seznamy v Excelu", "Budouci feature", "Dotyky hranic a smesne geometrie",
    "Interni diagnostika"),
  hodnota = c(
    "0.6.3", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    if (test_mode) "TEST: max. N cilu z hlavni kategorie proti UPLNYM referencim" else "PLNY: vsechna hlavni uzemi proti UPLNYM referencim",
    if (synthetic_data) "ANO – FIKTIVNI DATA, NEPOUZIVAT jako skutecne podklady" else "NE",
    if (test_mode) as.character(sample_n) else "nepouziva se",
    if (test_mode) as.character(seed) else "nepouziva se",
    as.character(nrow(base)), as.character(nrow(reference)), paste(categories, collapse = ", "),
    paste(secondary_cats, collapse = ", "), as.character(min_area),
    "Vsechny zdrojove vrstvy musi BYT v EPSG:5514 (Esri starsi WKID 102067 je ekvivalent). REST geometrie se stahuji primo v tomto systemu jako Esri JSON, bez WGS84 a bez st_transform. Pred vypoctem se oriznou sjednocenymi kraji CUZK. Pro kategorii se bere unie pruniku; mezi kategoriemi se procenta nesectou.",
    "NPR, NPP, PR a PP jsou jednotlive samostatne kategorie, stejne jako jejich ochranna pasma.",
    "OP_NPR, OP_NPP, OP_PR, OP_PP a OP_NP jsou samostatne kategorie i cilove objekty.",
    if (compute_oop) "ANO" else "NE – OOP listy jsou prazdne zamerne",
    "Ujezdni urad > sprava NP (vc. CHKO Sumava a Labske piskovce) > RP AOPK v CHKO/NPR/NPP/OP NPR/NPP > krajsky urad; PUOS ignorovano.",
    "Model urcuje teritorium typicke pusobnosti OOP, ne vsechny konkretni vyjimky podle ZOPK. Zohledneni ochrannych pasem NP zavisi na sparovani KOD.",
    "PUOS MIMO VOJENSKE UJEZDY ZATIM NENI ZOHLEDNENO. Pozemky tvorici soucast objektu dulezitych pro obranu statu mohou mit jinou pusobnost OOP; NEPOUZIVAT pro zavazne spravni rozhodovani bez kontroly.",
    "VSECHNY sledovane polygony mimo vrstvu kraju byly PRED vypoctem plosnych prekryvu a OOP oriznuty sjednocenou hranici 14 kraju dle RUIAN/CUZK. Vysledne plochy a procenta se vztahuji vyhradne k casti na uzemi CR. Puvodni evidovana plocha se muze lisit. Sjednocena hranice kraju je zde uznana za referencni; bezvislou presnost statni hranice vyhodnoceni neprokazuje.",
    orez_popis,
    AOPK_URL, paste0(CUZK_REST_URL, "/", CUZK_KRAJE_LAYER, " + ",
                      CUZK_REST_URL, "/", CUZK_UJEZDY_LAYER, " (statuskod=1)"),
    "Cache má kontrolní součet a počet prvků. Při --verify-cache-online=true se před použitím porovnává důvěryhodné datum editace zdroje nebo maximum zmenaG + seznam identifikátorů; není-li dostupný průkazný údaj, vrstva se stáhne znovu. Nemění se jednotlivé prvky inkrementálně. Pro nucené obnovení --refresh=true.",
    as.character(max_cache_age_days),
    "Zadne nulove/jen hranicni dotyky; skutecna plocha >= --min-area-m2. Povinne vrstvy musi byt uplne; male rozdily hranic RP se vynechaji z OOP, ale vetsi nesoulady zastavi beh.",
    "OP_NP jsou z VZCHU (KAT=OP); OP_NPR, OP_NPP, OP_PR, OP_PP se cleni podle KAT_ZCHU. CHKO OP nemaji.",
    "Seznam se nikdy nezkracuje: pri limitu Excelu 32767 znaku pokracuje do sousednich sloupcu _2, _3 atd.",
    "Libovolna uzivatelem dodana vrstva bude teprve dalsi funkce; v0.5.5 ji nema.",
    "Pouhe dotyky hranici nebo bodem nejsou plosne prekryvy. POLYGON a MULTIPOLYGON se zachovaji; z GEOMETRYCOLLECTION se vyberou polygonove casti; neznama geometrie zastavi vypocet.",
    "Diagnostika technickych vad, topologie a porovnani s rucne aktualizovanym exportem DRUSOP je v samostatnem soukromem vystupu. Verejne OOP jsou vypocteny pouze geograficky. Mikrofragment OOP <1 m² a současně <0,001 % plochy území zůstává v podrobném OOP_podle_uradu, nikoliv však v OOP_souhrn."))

metadata <- rbind(metadata, data.frame(
 polozka="NUMERICKA VERSUS GEOMETRICKA ODCHYLKA",
 hodnota=paste0("Nesmi se ignorovat maly fragment jen podle plochy. U prekryvu ",
 "blizkych 100 % se kontroluje i geometricky rozdil cile a unie pruniku. ",
 "Pokud je prazdny, jde o numericky rozdil vypoctu plochy; kdyz existuje ",
 "rozdilovy polygon, jde o skutecnou geometrii vyzadujici pripadne provereni. ",
 "Stav je ulozen v Souhrn_po_kategoriich/presnost_vypoctu. ",
 "Nepovolene KU uvnitr CHKO/NPR/NPP/OP NPR/NPP/NP/OP NP se vylucuji ",
 "z vecnych duvodu, nikoli podle velikosti; pripadne fragmenty jsou ",
 "v soukrome diagnostice nepripustne_OOP_kraje.gpkg."),
 stringsAsFactors=FALSE))
# Verejny disclaimer: bez samostatnych 'RP neurceno' radku.
metadata <- rbind(metadata, data.frame(
  polozka = "GEOMETRICKE NESOULADY RP – DISKLAIMER",
  hodnota = paste0(
    "U uzemi AOPK se hranice CHKO/NPR/NPP/jejich OP a obvodu RP nemusi ",
    "presne kryt. Neprirazene drobne fragmenty se nezapocitavaji ZADNEMU OOP, ",
    "nepridavaji se jako samostatna kategorie OOP a neprirazuji se odhadem. ",
    "Procenta uvadenych OOP se umele nenormalizuji na 100 %. ",
    "Za vyznamny nesoulad se povazuje > ", max_rp_gap_m2, " m2 nebo > ",
    max_rp_gap_pct, " % vstupniho uzemi a zastavi publikaci. ",
    "Pro presnou identifikaci pouzit INTERNI GeoPackage s rozdilovymi polygony. ",
    "Tyto mikro-nesoulady jsou vlastnosti pracovnich vrstev, nikoli dukazem ",
    "skutecne existence uzemi bez pravni pusobnosti OOP."),
  stringsAsFactors=FALSE))
# Geometricky model a mozna technicka oprava jsou metodicka omezeni i pro
# provozni vypocet. Pravne zavazny tvar hranice se automaticky NEurcuje.
metadata <- rbind(metadata, data.frame(
  polozka = "GEOMETRIE – TECHNICKA VALIDITA DLE GEOS",
  hodnota = paste0(
    "Neplatne polygonove geometrie podle sf::st_is_valid() se v pracovni kopii ",
    "opravuji sf::st_make_valid() a vyberem polygonovych casti. ",
    "To neni pravni rozhodnuti o spravnosti vyhlasene hranice. ",
    "V interni diagnostice jsou originaly, technicke navrhy a doslovne duvody ",
    "vracene GEOS. Vyklad puvodni neplatne plochy nemusi byt jednoznacny."),
  stringsAsFactors=FALSE))
# openxlsx zapisuje vice listu do jedineho souboru .xlsx.
# Kazdy list zachovava stejna identifikacni pole (kod a kategorie).
book <- openxlsx::createWorkbook()
# Rozlisitelne, ale netrjstive pastelove barvy pro kategoriove bloky.
# Kazda kategorie ma stejnou barvu ve vsech 4 svych sloupcich.
barvy_kategorii <- c(
  NPR="D4E9D5", NPP="F4DFC7", PR="D9E4F5", PP="E8D8EE",
  EVL="D0E8E5", PO="F3D8DD", CHKO="E7E1C5", NP="D3DFED",
  OP_NPR="E0EBC8", OP_NPP="F6E6CD", OP_PR="D5E8EE", OP_PP="EAD9DE",
  OP_NP="D8DFD0", SCHU="E9DFCA", VOJ_UJEZD="D7E0E9")
write_sheet <- function(sheet, data) {
  openxlsx::addWorksheet(book,sheet)
  if ("kod" %in% names(data) && sheet != "Zdroje_dat")
    data <- data[,c("kod",setdiff(names(data),"kod")),drop=FALSE]
  puvodni_nazvy <- names(data)
  data <- popisne_hlavicky(data)
  openxlsx::writeData(book,sheet,data,withFilter=nrow(data)>0)
  nc <- ncol(data); nr <- nrow(data)
  if (!nc) return(invisible(NULL))
  # Ukotveni prvniho radku a soucasne prvnich dvou sloupcu – bunka C2.
  openxlsx::freezePane(book,sheet,firstActiveRow=2L,firstActiveCol=3L)
  openxlsx::setColWidths(book,sheet,cols=seq_len(nc),widths=17)
  # Velikosti podle dat: evidenční kód ÚSOP první a těsně úzký.
  for (i in seq_len(nc)) {
    nm <- puvodni_nazvy[i]
    w <- if (nm == "kod") 10 else if (nm == "kategorie") 14 else if (nm == "nazev") 31
      else if (nm %in% c("id_isop", "klic")) 17
      else if (grepl("(^pocet_prekryvu$|_pocet$|^OOP_pocet$)",nm)) 11
      else if (grepl("(_prekryv_ha$|_prekryv_pct$|^plocha_ha$|^plocha_m2$|^podil_pct$)",nm)) 13
      else 24
    openxlsx::setColWidths(book,sheet,cols=i,widths=w)
  }
  openxlsx::setRowHeights(book,sheet,rows=seq_len(nr+1L),heights=25)
  openxlsx::setRowHeights(book,sheet,rows=1,heights=64)
  # Zajistime, ze text neprizpusobi vysku radku a dlouhy text je oznacen
  # zalomenim. Pri otevreni v Excelu lze vysku radku zvetsit rucne.
  openxlsx::addStyle(book,sheet,
    style=openxlsx::createStyle(wrapText=TRUE, valign="center"),
    rows=seq_len(nr+1L),cols=seq_len(nc),gridExpand=TRUE,stack=TRUE)
  # Barevne bloky pouze v hlavnim souhrnu. Barva pokryje pocet,
  # nekracene seznamy (vcetne _2, _3), plochu i procenta.
  if (sheet=="Souhrn_po_uzemich") {
    for (ct in names(barvy_kategorii)) {
      x <- which(puvodni_nazvy==paste0(ct,"_pocet"))
      y <- which(puvodni_nazvy==paste0(ct,"_prekryv_pct"))
      if (length(x)==1L && length(y)==1L && y>=x) {
        openxlsx::addStyle(book,sheet,
          style=openxlsx::createStyle(fgFill=paste0("#",barvy_kategorii[[ct]])),
          rows=seq_len(nr+1L),cols=x:y,gridExpand=TRUE,stack=TRUE)
      }
    }
  }
  header <- openxlsx::createStyle(textDecoration="bold",valign="center",
                                   border="Bottom",borderColour="#8D9CA7")
  openxlsx::addStyle(book,sheet,style=header,rows=1,cols=seq_len(nc),
                     gridExpand=TRUE,stack=TRUE)
  id_cols <- which(puvodni_nazvy %in% c("kod","nazev"))
  if (nr && length(id_cols)) openxlsx::addStyle(book,sheet,
    style=openxlsx::createStyle(textDecoration="bold"),
    rows=seq.int(2L,nr+1L),cols=id_cols,
    gridExpand=TRUE,stack=TRUE)
  long <- which(grepl("^vsechny_prekryvy|_nazvy_a_plochy|^OOP_souhrn$|^OOP_DRUSOP$|^OOP_pouze_|^DRUSOP_nazev$|^hodnota$|^zdroj_a_stazeni$|^prekryv_nazev$",puvodni_nazvy))
  if (length(long)) openxlsx::setColWidths(book,sheet,cols=long,widths=49)
  # JEN JEDEN odkaz na kartu DR USOP. Neni duplicitni DRUSOP_url.
  for (name in intersect(puvodni_nazvy,"url_usop")) {
    ci <- match(name,puvodni_nazvy); links <- as.character(data[[name]])
    for (r in which(!is.na(links)&grepl("^https?://",links))) {
      openxlsx::writeFormula(book,sheet,
        x=paste0('HYPERLINK("',gsub('"','""',links[r],fixed=TRUE),'","Otevřít DR ÚSOP")'),
        startCol=ci,startRow=r+1L)
    }
  }
}
# Souhrny a detail exportujeme bez stareho sloupce podkategorie,
# protoze kategorie uz samy rozlisuji NPR / NPP / PR / PP a jednotliva OP.
for (nm in c("detail","summary","oopp","oopc")) {
  if (exists(nm) && is.data.frame(get(nm)) && "podkategorie" %in% names(get(nm))) {
    assign(nm, get(nm)[, setdiff(names(get(nm)),"podkategorie"),drop=FALSE])
  }
}
# Základní identifikace je na začátku, kód ÚSOP úplně první.
wide <- wide[,c(intersect(c("kod","kategorie","nazev"),names(wide)),
                 setdiff(names(wide),c("kod","kategorie","nazev"))),drop=FALSE]
# Podrobny, filtrovany prehled zaznamu o doplnkovem zdroji DR USOP.
# Tato evidence se NIKDY nepouzije misto geometrickeho prirazeni OOP.
# DRUSOP a rozdily OOP patri VYHRADNE do interni diagnostiky.
privatni_sloupce <- c("OOP_DRUSOP", "OOP_shoda", "OOP_pouze_DRUSOP",
  "OOP_pouze_geo", "OOP_geo_mikrofragmenty", "OOP_geo_pocet_vsech", "OOP_geo_pocet_v_souhrnu", "OOP_vysvetleni_rozdilu", "DRUSOP_stav", "DRUSOP_kategorie", "DRUSOP_nazev",
  "DRUSOP_overeno", "DRUSOP_zdroj", "DRUSOP_url")
wide_verejne <- wide[,setdiff(names(wide), privatni_sloupce),drop=FALSE]
if (any(grepl("^(DRUSOP_|OOP_shoda$|OOP_pouze_|OOP_DRUSOP$)",names(wide_verejne))))
  stop("CHYBA BEZPECNOSTI: interní sloupec pronikl do veřejného souhrnu")
write_sheet("Souhrn_po_uzemich", wide_verejne)
write_sheet("Jednotlive_prekryvy", detail)
write_sheet("Souhrn_po_kategoriich", summary)
write_sheet("OOP_podle_uradu", oopp)
write_sheet("Pocet_uzemi", counts)
write_sheet("Metodika", metadata)
write_sheet("Zdroje_dat", source_info)
if (mode == "both") {
  kontrola060 <- sf::st_drop_geometry(wide) |>
    dplyr::select(klic, kategorie, kod, nazev, OOP_DRUSOP,
                  OOP_shoda, OOP_vysvetleni_rozdilu, OOP_pouze_DRUSOP, OOP_pouze_geo,
                  OOP_geo_mikrofragmenty, OOP_geo_pocet_vsech, OOP_geo_pocet_v_souhrnu,
                  DRUSOP_stav, DRUSOP_kategorie, DRUSOP_nazev,
                  DRUSOP_overeno, DRUSOP_zdroj, url_usop)
  vytvor_diagnosticky_sesit(diagnostic_dir, topologie060, kontrola060,
     drusop_export_date, drusop_file, query_drusop, oopc)
}
# VYSLEDNY XLSX NESMI BYT PREPSANY NEUSPESNYM BEHEM.
# Nejdrive pripravime cely sesit do docasneho souboru ve STEJNE slozce.
# Pokud se zapis nepodari, puvodni vysledek zustava nedotcen.
out_dir <- dirname(outfile)
if (!dir.exists(out_dir)) stop("Neexistuje vystupni slozka: ", out_dir)
tmp_xlsx <- tempfile(pattern="prekryvy_kompletni_", tmpdir=out_dir, fileext=".xlsx")
openxlsx::saveWorkbook(book, tmp_xlsx, overwrite=TRUE)
if (!file.exists(tmp_xlsx) || file.info(tmp_xlsx)$size < 1000L)
  stop("Neuplny docasny XLSX: vystup se neprepise")
# Puvodni XLSX se nejdrive odlozi do zalohy, aby slo vratit.
backup_xlsx <- paste0(outfile, ".previous")
if (file.exists(backup_xlsx)) unlink(backup_xlsx)
if (file.exists(outfile) && !file.rename(outfile, backup_xlsx))
  stop("Nelze zalohovat predchozi XLSX (otevreny v Excelu?): ", outfile)
if (!file.rename(tmp_xlsx, outfile)) {
  if (file.exists(backup_xlsx)) file.rename(backup_xlsx, outfile)
  stop("Nepodarilo se dokoncit zapis XLSX; predchozi verze byla vracena")
}
if (file.exists(backup_xlsx)) unlink(backup_xlsx)
# PUBLIC WEB v0.6.5: samostatný HTML soubor, funkční i lokálně přes file://.
# Veřejná data jsou přímo součástí HTML; do stránky nevstupuje diagnostika DR ÚSOP.
if (nzchar(site_dir)) {
  dir.create(site_dir, recursive=TRUE, showWarnings=FALSE)
  file.copy(outfile, file.path(site_dir, "prekryvy_aktualni.xlsx"), overwrite=TRUE)
  # Ponechání JSON umožňuje další navazující nástroje, i když HTML ho nevyžaduje.
  jsonlite::write_json(as.data.frame(wide_verejne), file.path(site_dir, "prehled.json"),
    dataframe="rows", na="null", auto_unbox=TRUE, digits=NA)
  jsonlite::write_json(list(verze="0.6.5", datum_vypoctu=format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    pocet_uzemi=nrow(wide_verejne), test=test_mode,
    poznamka="Ořez unii krajů ČÚZK; PUOS nezohledněno; drobné mezery RP nikomu nepřiřazeny."),
    file.path(site_dir, "manifest.json"), auto_unbox=TRUE, pretty=TRUE)
  # Pro čitelný web sjednotíme pokračovací sloupce dlouhých seznamů.
  spoj_seznam <- function(tbl, prefix) {
    vybrane <- grep(paste0("^",prefix,"(_[0-9]+)?$"), names(tbl), value=TRUE)
    if (!length(vybrane)) return(rep("",nrow(tbl)))
    vapply(seq_len(nrow(tbl)), function(i) {
      casti <- trimws(as.character(unlist(tbl[i,vybrane,drop=FALSE], use.names=FALSE)))
      paste(casti[!is.na(casti)&nzchar(casti)],collapse="; ")
    },character(1))
  }
  web_seznam_vse <- spoj_seznam(wide_verejne,"vsechny_prekryvy")
  web_seznam_kat <- setNames(lapply(reference_cats,function(ct)
    spoj_seznam(wide_verejne,paste0(ct,"_nazvy_a_plochy"))),reference_cats)
  web_get <- function(nm,default=0) {
    if (nm %in% names(wide_verejne)) wide_verejne[[nm]] else rep(default,nrow(wide_verejne))
  }
  web_records <- lapply(seq_len(nrow(wide_verejne)),function(i) {
    skupiny <- lapply(reference_cats,function(ct) list(
      typ=ct, pocet=as.integer(web_get(paste0(ct,"_pocet"))[i]),
      ha=as.numeric(web_get(paste0(ct,"_prekryv_ha"))[i]),
      pct=as.numeric(web_get(paste0(ct,"_prekryv_pct"))[i]),
      seznam=web_seznam_kat[[ct]][i]))
    list(kod=as.character(web_get("kod", "")[i]),
         kategorie=as.character(web_get("kategorie", "")[i]),
         nazev=as.character(web_get("nazev", "")[i]),
         plocha=as.numeric(web_get("plocha_ha")[i]),
         pocet=as.integer(web_get("pocet_prekryvu")[i]),
         prekryvy=web_seznam_vse[i],
         oop=as.character(web_get("OOP_souhrn", "")[i]),
         skupiny=skupiny)
  })
  template_file <- file.path("web", "index_template.html")
  if (!file.exists(template_file)) stop("Chybí šablona webu: ",template_file)
  html <- paste(readLines(template_file, warn=FALSE, encoding="UTF-8"),collapse="\n")
  web_json <- as.character(jsonlite::toJSON(web_records,auto_unbox=TRUE,na="null",digits=NA))
  # JSON se zapisuje jako obsah inertního <script type=application/json>.
  if (grepl("</script",web_json,fixed=TRUE))
    stop("Ve veřejných datech je nepovolený uzavírací HTML tag")
  html_casti <- strsplit(html,"__DATA_JSON__",fixed=TRUE)[[1]]
  if (length(html_casti)!=2L) stop("V HTML šabloně chybí právě jeden datový zástupný znak")
  html <- paste0(html_casti[1],web_json,html_casti[2])
  writeLines(html,file.path(site_dir,"index.html"),useBytes=TRUE)
  message("PUBLIC WEB: plný samostatný HTML připraven (včetně uživatelského XLSX exportu): ",
          normalizePath(site_dir,mustWork=FALSE))
}
message("Hotovo: ", normalizePath(outfile, mustWork = FALSE))
