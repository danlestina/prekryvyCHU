#!/usr/bin/env Rscript
# Test nacitani exportu DR USOP BEZ internetu. Fiktivni testovaci data.
source("lib/drusop_export.R", encoding="UTF-8")
x <- tempfile(); dir.create(x)
writeLines(c("Kód\tKód Natura\tNázev\tOrgány ochrany přírody",
             "2895\tCZ0520519\tAdršpašsko-teplické skály\tAOPK ČR - RP Východní Čechy",
             "2509\tCZ0213086\tAglaja\tKrajský úřad Středočeského kraje"),
           file.path(x,"EVL.tsv"),useBytes=TRUE)
tab <- import_drusop_exporty(x)
stopifnot(nrow(tab$EVL)==2L)
a <- najdi_oop_v_exportu(tab,"EVL","2895")
stopifnot(identical(a$stav,"OK_EXPORT"),grepl("Východní",a$oop))
stopifnot(identical(najdi_oop_v_exportu(tab,"EVL","9999")$stav,
                    "KOD_NENALEZEN_V_EXPORTU"))
cat("IMPORT DR USOP TEST PROSEL (FIKTIVNI TABULKA)\n")
