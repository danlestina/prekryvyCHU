#!/usr/bin/env Rscript
# TEST JEDINEHO EXPORTU DR USOP. Nevyzaduje GIS, internet ani ArcGIS.
# Spusteni: Rscript tests/overeni_jednotneho_DRUSOP.R drusop_oop.txt
args <- commandArgs(trailingOnly=TRUE)
f <- if(length(args)) args[1L] else "drusop_oop.txt"
source("lib/drusop_export.R",encoding="UTF-8")
x <- import_drusop_jednotny(f)
stopifnot(isTRUE(attr(x,"kontrola_count")))
stopifnot(attr(x,"pocet_vsech_zaznamu") >= 1000L)
stopifnot(all(c("EVL","PO","MZCHU","VZCHU","SCHU") %in% names(x)))
# Konkretni znama data z poskytnuteho exportu (pokud se export vyrazne
# aktualizuje, odpovidajici testovaci hodnoty je treba overit).
a <- najdi_oop_v_exportu(x,"EVL","2895","Adršpašsko-teplické skály")
stopifnot(identical(a$stav,"OK_EXPORT"),grepl("Východní Čechy",a$oop))
b <- najdi_oop_v_exportu(x,"CHKO","62","Broumovsko")
stopifnot(identical(b$stav,"OK_EXPORT"),grepl("Východní Čechy",b$oop))
c <- najdi_oop_v_exportu(x,"OP_NPP","2895")
stopifnot(identical(c$stav,"BEZ_SAMOSTATNEHO_ZAZNAMU"))
stopifnot(identical(porovnej_oop_drusop_geo("Krajský úřad Jihočeského kraje",
  "KÚ – Jihočeský kraj")$stav,"SHODA"))
stopifnot(identical(porovnej_oop_drusop_geo("Správa NP Šumava",
  "Správa Národního parku Šumava")$stav,"SHODA"))
cat("TEST DR USOP PROSEL: ",attr(x,"pocet_vsech_zaznamu"),
    " zaznamu, porovnani kodu/kategorii i aliasu uradu.\n",sep="")
