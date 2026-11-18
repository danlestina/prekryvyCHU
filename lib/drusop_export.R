# IMPORT HROMADNYCH EXPORTU DR USOP (v0.5.8)
# ==============================================================
# Tato cast NESTAHUJE stranky jednotlivych objektu; cte TABULKOVY EXPORT
# z verejneho prehledu (Export -> vse -> KOD + ORGANY OCHRANY PRIRODY).
# R nemusi znat dynamicke PHP formulare. Export ulozte do slozky, napr.
#   drusop_exporty/evl.xls, po.xls, mzchu.xls, vzchu.xls, schu.xls
# Formát "Excel (Tabbed)" je text oddeleny tabulatory, i kdyz ma priponu .xls.
# Lze pouzit take .tsv/.txt/.csv/.xlsx, pripadne tabulku HTML v .xls.
# Vsechny data jsou externi doplnek: nikdy neprepisuji geograficky OOP.

export_norm <- function(x) {
  y <- iconv(enc2utf8(as.character(x)), from="UTF-8", to="ASCII//TRANSLIT", sub="")
  toupper(gsub("[^A-Za-z0-9]", "", y))
}

# U Excel (Tabbed) rozpozname tabulatory bez ohledu na priponu souboru.
# Texty z registru mohou byt v kodovani Windows-1250, UTF-8 nebo s BOM.
import_text_table <- function(path) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  if (length(raw) >= 2L && identical(as.integer(raw[1:2]), c(80L,75L)))
    stop("DR USOP: ", basename(path), " je ZIP/XLSX. Ulozte se spravnou ",
         "priponou .xlsx, aby se nacetl excelovou knihovnou.")
  if (length(raw) >= 2L && identical(as.integer(raw[1:2]), c(255L,254L))) {
    con16 <- file(path, open="r", encoding="UTF-16LE")
    txt <- paste(readLines(con16, warn=FALSE), collapse="\n")
    close(con16)
  } else {
    txt <- rawToChar(raw)
    if (!validUTF8(txt)) txt <- iconv(txt, from="CP1250", to="UTF-8", sub="")
  }
  if (is.na(txt)) stop("DR USOP: nelze prevest text na UTF-8: ",basename(path))
  txt <- sub("^\ufeff", "", txt)
  if (!nzchar(trimws(txt))) stop("DR USOP: prazdny export: ", path)
  if (grepl("<table\\b", txt, ignore.case=TRUE)) {
    if (!requireNamespace("xml2", quietly=TRUE)) stop("DR USOP HTML export vyzaduje xml2")
    root <- xml2::read_html(txt)
    tables <- xml2::xml_find_all(root, ".//table")
    if (!length(tables)) stop("DR USOP: HTML neobsahuje tabulku: ", path)
    # Jednoduchy HTML export – bereme nejvetsi tabulku, nikoli formular.
    rows <- lapply(tables, function(tb) xml2::xml_find_all(tb,".//tr"))
    tb <- tables[[which.max(lengths(rows))]]
    rr <- xml2::xml_find_all(tb,".//tr")
    vals <- lapply(rr,function(tr) trimws(xml2::xml_text(xml2::xml_find_all(tr,"./th|./td"))))
    vals <- Filter(length, vals)
    w <- max(lengths(vals)); vals <- lapply(vals, `length<-`, w)
    mat <- do.call(rbind, vals)
    if (nrow(mat) < 2L) stop("DR USOP: HTML export nema zadna data")
    df <- as.data.frame(mat[-1,,drop=FALSE], stringsAsFactors=FALSE)
    names(df) <- as.character(mat[1,]); return(df)
  }
  # Tabulator ma prednost (Excel Tabbed); CSV rozpozname podle hlavicky.
  first <- strsplit(txt, "\\r?\\n")[[1]][1]
  sep <- if (grepl("\\t", first)) "\t" else if (grepl(";", first, fixed=TRUE)) ";" else ","
  con <- textConnection(txt)
  on.exit(close(con), add=TRUE)
  utils::read.table(con, header=TRUE, sep=sep, quote='"', comment.char="",
                    check.names=FALSE, stringsAsFactors=FALSE, fill=TRUE,
                    na.strings=character(), fileEncoding="UTF-8")
}

import_jeden_export <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "xlsx") {
    d <- openxlsx::read.xlsx(path, detectDates=FALSE, colNames=TRUE)
  } else if (ext == "xls" && requireNamespace("readxl", quietly=TRUE)) {
    # Rozlisime opravdu binarni XLS od textoveho souboru s priponou .xls.
    head <- readBin(path,"raw",n=8L)
    if (length(head)==8L && identical(as.integer(head),c(208L,207L,17L,224L,161L,177L,26L,225L))) {
      d <- as.data.frame(readxl::read_excel(path), stringsAsFactors=FALSE)
    } else d <- import_text_table(path)
  } else d <- import_text_table(path)
  if (!nrow(d)) stop("DR USOP: export nema radky: ", path)
  nn <- export_norm(names(d))
  k <- which(nn %in% c("KOD","KODUSOP","EVIDENCNICISLO","CIS","CISLOUSOP"))
  o <- which(nn %in% c("ORGANOCHRANYPRIRODY","ORGANYOCHRANYPRIRODY",
                       "PRISLUSNYORGANOCHRANYPRIRODY","PRISLUSNEORGANYOCHRANYPRIRODY"))
  if (length(k)!=1L || length(o)!=1L) {
    stop("DR USOP: export ",basename(path)," musi mit jednoznacne sloupce Kód a Orgán(y) ochrany přírody. ",
         "Nalezeno: ",paste(names(d),collapse=" | "))
  }
  kat <- which(nn %in% c("KATEGORIE","KAT"))
  na <- which(nn %in% c("NAZEV","JMENO","NAZEVUZEMI"))
  d <- data.frame(kod=trimws(as.character(d[[k]])),
                  oop=trimws(as.character(d[[o]])),
                  kategorie=if(length(kat)) trimws(as.character(d[[kat[1L]]])) else "",
                  nazev=if(length(na)) trimws(as.character(d[[na[1L]]])) else "",
                  stringsAsFactors=FALSE)
  d <- d[!is.na(d$kod) & nzchar(d$kod),,drop=FALSE]
  if (!nrow(d)) stop("DR USOP: export nema zadne platne kody: ",path)
  if (anyDuplicated(d$kod)) {
    dup <- unique(d$kod[duplicated(d$kod)])
    stop("DR USOP: opakovany kod v jednom exportu ",basename(path),": ",paste(head(dup,10L),collapse=", "))
  }
  d
}

# Jmena souboru identifikuji evidenci, v niz je kod unikatni.
# Pro hlavni kategorie pouzijeme kod; pokud je ve vice vstupnich exportech,
# MUSI odpovidat prislusne evidenci. Neodvozujeme OOP jen podle nazvu.
import_drusop_exporty <- function(slozka) {
  if (!dir.exists(slozka)) stop("Slozka exportu DR USOP neexistuje: ",slozka)
  files <- list.files(slozka, pattern="\\.(xls|xlsx|csv|tsv|txt|html?)$",
                      full.names=TRUE, ignore.case=TRUE)
  if (!length(files)) stop("Slozka ",slozka," neobsahuje soubory exportu DR USOP")
  out <- list()
  for (f in files) {
    nm <- export_norm(tools::file_path_sans_ext(basename(f)))
    typ <- if (grepl("MZCHU|ZCHRU|MALOPLOS",nm)) "MZCHU" else
      if (grepl("VZCHU|VELKOPLOS",nm)) "VZCHU" else
      if (grepl("^EVL|EVL",nm)) "EVL" else
      if (grepl("^PO|PTACI",nm)) "PO" else
      if (grepl("SCHU|SMLUVN",nm)) "SCHU" else NA_character_
    if (is.na(typ)) stop("DR USOP: ze jmena souboru nelze poznat evidenci: ",basename(f),
                        ". Pouzijte EVL, PO, MZCHU, VZCHU, SCHU.")
    if (!is.null(out[[typ]])) stop("DR USOP: vice exportu pro evidenci ",typ,
                                  ". Uchovejte jedinou uplnou tabulku.")
    x <- import_jeden_export(f)
    x$typ <- typ
    x$zdroj <- basename(f)  # verejny XLSX nesmi obsahovat cestu na uzivateluv pocitac
    out[[typ]] <- x
    message("DR USOP export ",typ,": ",nrow(x)," kodu; ",basename(f))
  }
  out
}

najdi_oop_v_exportu <- function(exporty, kategorie, kod) {
  ty <- if (kategorie %in% c("NPR","NPP","PR","PP")) "MZCHU" else
    if (kategorie %in% c("CHKO","NP")) "VZCHU" else
    if (kategorie %in% c("EVL","PO","SCHU")) kategorie else ""
  if (!nzchar(ty)) return(list(oop="",stav="NENI_SAMOSTATNE_V_REGISTRU",zdroj=""))
  dat <- exporty[[ty]]
  if (is.null(dat)) return(list(oop="",stav="EXPORT_CHYBI",zdroj=""))
  sel <- which(dat$kod == as.character(kod))
  if (!length(sel)) return(list(oop="",stav="KOD_NENALEZEN_V_EXPORTU",zdroj=dat$zdroj[1L]))
  if (length(sel)!=1L) stop("DR USOP: nejednoznacny kod ",kod," v ",ty)
  o <- dat$oop[sel]
  if (is.na(o) || !nzchar(o)) return(list(oop="",stav="OOP_PRAZDNY_V_EXPORTU",zdroj=dat$zdroj[sel]))
  list(oop=o,stav="OK_EXPORT",zdroj=dat$zdroj[sel])
}


# ============================================================================
# JEDINY CELOSTATNI EXPORT DR USOP (v0.5.9)
# ============================================================================
# Pri vyberu "vsechny objekty" DR USOP lze ziskat jeden textovy export,
# ktery obsahuje nejen EVL, ale i PO, MZCHU, VZCHU, SCHU a pamatne stromy.
# Uzivatel ho uklada jako drusop_oop.txt do pracovni slozky (working directory).
# Skutecny soubor ma kodovani Windows-1250, tabulatory a posledni radek
#   COUNT:  10564
# Tento radek NENI chranene uzemi; overime ho a odstraníme.
# DULEZITE: DR USOP muze obsahovat i historicke/archivni zaznamy; proto
# nevyzadujeme presnou rovnost celkovych poctu s AKTUALNIMI GIS vrstvami.
# Srovnavame jednotlivy KOD + KATEGORII, nikoli pouze nazvy ani pocty.

# Preklad z nazvu kategorii exportu DR USOP na nase hlavni GIS kategorie.
# Jde o KATEGORIE OBJEKTU, nikoliv o organy ochrany prirody.
drusop_map_kategorii <- c(
  "Národní přírodní rezervace"="NPR", "Národní přírodní památka"="NPP",
  "Přírodní rezervace"="PR", "Přírodní památka"="PP",
  "Evropsky významná lokalita"="EVL", "Ptačí oblast"="PO",
  "Chráněná krajinná oblast"="CHKO", "Národní park"="NP",
  "Smluvně chráněné území"="SCHU"
)

drusop_evidence_kategorie <- function(kategorie) {
  if (kategorie %in% c("NPR","NPP","PR","PP")) return("MZCHU")
  if (kategorie %in% c("NP","CHKO")) return("VZCHU")
  if (kategorie %in% c("EVL","PO","SCHU")) return(kategorie)
  ""  # OP a VU nemaji stejny druh samostatneho zaznamu v tomto exportu
}

import_drusop_jednotny <- function(path) {
  if (!file.exists(path)) stop("DR USOP: nelze najit soubor ", path,
      ". Ulozte drusop_oop.txt do pracovni slozky a overte getwd().")
  tab <- import_jeden_export(path)   # cast kodovani, TSV, nazvu sloupcu
  if (!any(nzchar(tab$kategorie)) || !any(nzchar(tab$nazev)))
    stop("DR USOP: sjednoceny export musi mit Kód, Kategorie, Název a Orgán ochrany přírody")
  footer <- which(grepl("^COUNT:$", tab$kod, ignore.case=TRUE))
  if (length(footer) > 1L) stop("DR USOP: vice kontrolnich radku COUNT:")
  if (length(footer)) {
    deklarovano <- suppressWarnings(as.integer(tab$kategorie[footer]))
    skutecne <- nrow(tab) - length(footer)
    if (!is.finite(deklarovano) || deklarovano != skutecne)
      stop("DR USOP: NESOUHLASI pocet zaznamu COUNT: ",deklarovano,
           " vs. ",skutecne,". Export muze byt neúplný.")
    tab <- tab[-footer,,drop=FALSE]
  } else {
    # Jinou verzi exportu bez paticky podporujeme, ale nelze ji prohlasit
    # za potvrzene uplnou pouze na zaklade poctu radku.
    warning("DR USOP: export nema kontrolni radek COUNT:. Nezavisla kontrola uplnosti nebyla mozna.")
  }
  if (any(!grepl("^[0-9]+$", tab$kod)))
    stop("DR USOP: nejaky objekt nema ciselny Kód ÚSOP; prvni: ",
         paste(head(tab$kod[!grepl("^[0-9]+$", tab$kod)],5),collapse=", "))
  # Jedinecny kod je kontrolni pojistka proti zdvojenym strankam exportu.
  if (anyDuplicated(tab$kod))
    stop("DR USOP: duplicitni kod ", tab$kod[anyDuplicated(tab$kod)],
         "; import nejspis obsahuje opakovana data")
  key <- export_norm(names(drusop_map_kategorii))
  values <- unname(drusop_map_kategorii)
  tab$gis_kategorie <- values[match(export_norm(tab$kategorie), key)]
  tab$typ <- vapply(tab$gis_kategorie, function(cat) {
    if (is.na(cat)) return(NA_character_)
    drusop_evidence_kategorie(cat)
  }, character(1))
  tab$zdroj <- basename(path)  # verejny XLSX nema obsahovat lokalni cestu
  out <- split(tab[!is.na(tab$typ),,drop=FALSE],tab$typ[!is.na(tab$typ)])
  stopifnot(all(c("MZCHU","VZCHU","EVL","PO","SCHU") %in% names(out)))
  message("DR USOP: importovano ",nrow(tab)," zaznamu z ",basename(path),
          "; pro sledovana polygonova uzemi ",sum(!is.na(tab$typ)),
          "; dalsich evidenci ",sum(is.na(tab$typ)))
  for (ty in names(out)) {
    kinds <- paste(sort(unique(out[[ty]]$gis_kategorie)),collapse=",")
    message("  ",ty,": ",nrow(out[[ty]])," zaznamu (",kinds,")")
  }
  attr(out,"sjednoceny_export") <- TRUE
  attr(out,"pocet_vsech_zaznamu") <- nrow(tab)
  attr(out,"kontrola_count") <- length(footer)==1L
  out
}

# Bezpecna dvojice kategorií: kod 2895 EVL nelze zaměnit za 2895 PR.
# Chybny nebo historicky zaznam je vzdy explicitni stav, nikoliv odhad OOP.
najdi_oop_v_exportu <- function(exporty, kategorie, kod, nazev="") {
  ty <- drusop_evidence_kategorie(kategorie)
  prazdny <- function(stav, zdroj="", kategorie_export="", nazev_export="")
    list(oop="",stav=stav,zdroj=zdroj,kategorie_export=kategorie_export,
         nazev_export=nazev_export)
  if (!nzchar(ty)) return(prazdny("BEZ_SAMOSTATNEHO_ZAZNAMU"))
  dat <- exporty[[ty]]
  if (is.null(dat)) return(prazdny("EXPORT_EVIDENCE_CHYBI"))
  sel <- which(dat$kod == as.character(kod))
  if (!length(sel)) return(prazdny("KOD_NENALEZEN_V_EXPORTU",dat$zdroj[1L]))
  if (length(sel)>1L) stop("DR USOP: nejednoznacny kod ",kod," v ",ty)
  rec <- dat[sel,,drop=FALSE]
  if ("gis_kategorie" %in% names(rec) && !is.na(rec$gis_kategorie[1L]) &&
      !identical(as.character(rec$gis_kategorie[1L]),as.character(kategorie)))
    return(prazdny("NESOULAD_KATEGORIE",rec$zdroj[1L],
                   rec$kategorie[1L],rec$nazev[1L]))
  oop <- trimws(as.character(rec$oop[1L]))
  if (is.na(oop) || !nzchar(oop))
    return(prazdny("OOP_PRAZDNY_V_EXPORTU",rec$zdroj[1L],
                   rec$kategorie[1L],rec$nazev[1L]))
  # Odchylne jmeno neovlivní přiřazení OOP, ale musi byt viditelne.
  stejne_jmeno <- !nzchar(nazev) || identical(export_norm(nazev),export_norm(rec$nazev[1L]))
  list(oop=oop,stav=if (stejne_jmeno) "OK_EXPORT" else "OK_NAZEV_SE_LISI",
       zdroj=rec$zdroj[1L],kategorie_export=rec$kategorie[1L],nazev_export=rec$nazev[1L])
}

# Standardizace pojmenovani OOP z dvou administrativnich evidenci.
# Umoznuje porovnat napr. "Krajský úřad Jihočeského kraje" s
# "KÚ – Jihočeský kraj", aniz by se bezduvodne hlasila neshoda.
# Neznámé zkratky neprekladame odhadem; zustavaji k manualnimu provereni.
drusop_klic_uradu <- function(s) {
  a <- export_norm(s)
  if (!nzchar(a)) return("")
  if (grepl("^(AOPKCR)?RP",a)) return(paste0("RP:",sub("^(AOPKCR)?RP", "",a)))
  if (grepl("^KU|^KRAJSKYURAD|^MAGISTRATHLAVNIHOMESTAPRAHY",a)) {
    kraje <- c("JIHOCES","JIHOMORAVSK","MORAVSKOSLEZ",
      "KARLOVARSK","KRALOVEHRADECK","PARDUBICK","STREDOCESK",
      "USTECK","PLZENSK","OLOMOUCK","ZLINSK","LIBERECK",
      "VYSOCIN","PRAH")
    hit <- kraje[vapply(kraje,function(z) grepl(z,a,fixed=TRUE),logical(1))]
    if (length(hit)==1L) return(paste0("KU:",hit))
  }
  if (grepl("^SPRAVA",a)) {
    if (grepl("KRNAP|KRKONOS",a)) return("NP:KRKONOSE")
    if (grepl("SUMAV",a)) return("NP:SUMAVA")
    if (grepl("CESKESVYCAR",a)) return("NP:CESKESVYCARSKO")
    if (grepl("PODYJ",a)) return("NP:PODYJI")
  }
  if (grepl("^UJEZDNIURAD",a)) return(paste0("VU:",sub("^UJEZDNIURAD","",a)))
  if (a=="MINISTERSTVOOBRANY") return("MINISTERSTVO:OBRANY")
  paste0("NAZEV:",a)
}

# Tato kontrola porovnava SEZNAMY uradu, nikoli jen prvni urad z exportu.
# Pripadny rozdil je podnet k manualnimu provereni, ne automaticka chyba GIS.
porovnej_oop_drusop_geo <- function(evidovane, geograficke) {
  zdroj <- if(nzchar(evidovane)) trimws(strsplit(evidovane,",",fixed=TRUE)[[1]]) else character()
  zdroj <- unique(zdroj[nzchar(zdroj)])
  geo <- unique(as.character(geograficke))
  geo <- geo[!is.na(geo) & nzchar(geo)]
  ek <- vapply(zdroj,drusop_klic_uradu,character(1))
  gk <- vapply(geo,drusop_klic_uradu,character(1))
  je <- !ek %in% gk
  jg <- !gk %in% ek
  list(stav=if (!length(zdroj)) "DRUSOP_BEZ_OOP" else if(!length(geo)) "GEO_BEZ_OOP" else
          if (!any(je) && !any(jg)) "SHODA" else "ROZDIL_K_PROVERENI",
       pouze_drusop=paste(zdroj[je],collapse="; "),
       pouze_geo=paste(geo[jg],collapse="; "))
}
