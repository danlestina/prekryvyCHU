#!/usr/bin/env Rscript
# ============================================================================
# DR USOP VERSUS VYPOCTENI OOP - BEZ NOVÉHO GIS VYPOCTU (v0.5.9)
# ============================================================================
# Tento pomocny skript otevre JIZ HOTOVY soubor test_v058.xlsx nebo novější.
# Porovna OOP z geografickeho vypoctu s jedinym hromadnym drusop_oop.txt.
# Samotny XLSX nemeni, vystupuje jako NOVY prehledovy Excel.
#
# SPUSTENI V GIT BASH / RSTUDIO TERMINALU:
# Rscript kontrola_drusop_z_xlsx.R --in=test_v058.xlsx --drusop-file=drusop_oop.txt --out=kontrola_drusop_v058.xlsx
#
# Potreba: jen balicek openxlsx (je i v hlavnim R skriptu); bez sf, bez webu.
# Pouzivejte z korene repozitare, kde jsou lib/ a drusop_oop.txt.
# ============================================================================
suppressPackageStartupMessages(library(openxlsx))
args <- commandArgs(trailingOnly=TRUE)
o <- list()
for (a in args) {
  if (!grepl("^--[^=]+=",a)) stop("Parametr musi byt --nazev=hodnota: ",a)
  p <- regexpr("=",a,fixed=TRUE)[1L]
  o[[substring(a,3L,p-1L)]] <- substring(a,p+1L)
}
xlsx <- if (!is.null(o$`in`)) o$`in` else "test_v058.xlsx"
txt <- if (!is.null(o$`drusop-file`)) o$`drusop-file` else "drusop_oop.txt"
outfile <- if (!is.null(o$out)) o$out else "kontrola_drusop.xlsx"
if (!file.exists(xlsx)) stop("Nenalezen hotovy XLSX: ",xlsx)
if (!file.exists(txt)) stop("Nenalezen export DR USOP: ",txt)
exe <- grep("^--file=",commandArgs(trailingOnly=FALSE),value=TRUE)
root <- if(length(exe)) dirname(normalizePath(sub("^--file=","",exe[1L]),winslash="/",mustWork=TRUE)) else getwd()
source(file.path(root,"lib","drusop_export.R"),encoding="UTF-8")
exp <- import_drusop_jednotny(txt)
base <- openxlsx::read.xlsx(xlsx,sheet="Souhrn_po_uzemich",detectDates=FALSE)
oop <- openxlsx::read.xlsx(xlsx,sheet="OOP_podle_uradu",detectDates=FALSE)
if (!all(c("klic","kategorie","kod","nazev") %in% names(base)))
  stop("V XLSX chybi identifikatory 'klic', 'kategorie', 'kod', 'nazev'")
if (!all(c("klic","oop_nazev") %in% names(oop)))
  stop("V listu OOP_podle_uradu chybi 'klic' nebo 'oop_nazev'")
# Jeden radek pro kazde testovane uzemi. OP a VU nemaji samostatny
# zaznam odpovidajici kategorii v tomto exportu -> nehodnotit jako chybu.
rows <- lapply(seq_len(nrow(base)),function(i){
  b <- base[i,,drop=FALSE]
  kod <- as.character(b$kod[1L]); cat <- as.character(b$kategorie[1L]);
  ref <- najdi_oop_v_exportu(exp,cat,kod,as.character(b$nazev[1L]))
  names_geo <- as.character(oop$oop_nazev[as.character(oop$klic)==as.character(b$klic[1L])])
  names_geo <- names_geo[!is.na(names_geo) & nzchar(names_geo)]
  cmp <- if (nzchar(ref$oop)) porovnej_oop_drusop_geo(ref$oop,names_geo) else
    list(stav=ref$stav,pouze_drusop="",pouze_geo="")
  data.frame(kategorie=cat,kod=kod,nazev=as.character(b$nazev[1L]),
    oop_drusop=ref$oop,
    oop_geo=paste(names_geo,collapse="; "),
    stav_importu=ref$stav,
    stav_porovnani=cmp$stav,
    pouze_v_drusop=cmp$pouze_drusop,
    pouze_v_geo=cmp$pouze_geo,
    kategorie_drusop=ref$kategorie_export,
    nazev_drusop=ref$nazev_export,
    stringsAsFactors=FALSE)
})
dat <- do.call(rbind,rows)
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb,"OOP_porovnani",gridLines=FALSE)
openxlsx::writeData(wb,"OOP_porovnani",dat,withFilter=TRUE)
openxlsx::freezePane(wb,"OOP_porovnani",firstActiveRow=2,firstActiveCol=3)
openxlsx::setRowHeights(wb,"OOP_porovnani",rows=seq_len(nrow(dat)+1L),heights=25)
openxlsx::setColWidths(wb,"OOP_porovnani",cols=seq_len(ncol(dat)),widths=22)
openxlsx::setColWidths(wb,"OOP_porovnani",cols=c(3,4,5,8,9,11),widths=c(35,49,49,43,43,36))
hstyle <- openxlsx::createStyle(fgFill="#D1E2EA",textDecoration="bold",valign="center",border="Bottom")
openxlsx::addStyle(wb,"OOP_porovnani",hstyle,rows=1,cols=seq_len(ncol(dat)),gridExpand=TRUE)
openxlsx::addStyle(wb,"OOP_porovnani",openxlsx::createStyle(textDecoration="bold"),
                   rows=2:(nrow(dat)+1L),cols=1:2,gridExpand=TRUE)
openxlsx::addStyle(wb,"OOP_porovnani",openxlsx::createStyle(wrapText=TRUE,valign="top"),
                   rows=2:(nrow(dat)+1L),cols=seq_len(ncol(dat)),gridExpand=TRUE,stack=TRUE)
openxlsx::addWorksheet(wb,"Metodika",gridLines=FALSE)
met <- data.frame(polozka=c("Zdroj XLSX","Zdroj DR USOP","Celkem zaznamu TXT","Identifikace",
                            "Význam stavu SHODA","Význam stavu ROZDIL_K_PROVERENI",
                            "Bez samostatneho zaznamu","OOP v GIS"),
 hodnota=c(basename(xlsx),basename(txt),as.character(attr(exp,"pocet_vsech_zaznamu")),
 "Kód ÚSOP a kategorie (ne pouze název)",
 "Stejná sada správních orgánů po normalizaci hlavních variant názvů",
 "Rozdílná sada evidovaných a vypočtených orgánů; nemusí znamenat právní chybu",
 "OP MZCHÚ/NP a vojenské újezdy v exportu nemají samostatný záznam odpovídající tomuto typu",
 "Pouze přečteno z již existujícího XLSX, bez změny geografického výpočtu"),stringsAsFactors=FALSE)
openxlsx::writeData(wb,"Metodika",met)
openxlsx::setColWidths(wb,"Metodika",1:2,c(31,96))
openxlsx::freezePane(wb,"Metodika",firstActiveRow=2)
tmp <- tempfile(pattern="drusop_",tmpdir=dirname(outfile),fileext=".xlsx")
openxlsx::saveWorkbook(wb,tmp,overwrite=TRUE)
if (!file.copy(tmp,outfile,overwrite=TRUE)) stop("Nepodarilo se ulozit vysledek: ",outfile)
unlink(tmp)
message("DR USOP porovnani DOKONCENO: ",outfile,"; ",nrow(dat)," uzemi")
message(paste(names(table(dat$stav_porovnani)),as.integer(table(dat$stav_porovnani)),sep="=",collapse="; "))
