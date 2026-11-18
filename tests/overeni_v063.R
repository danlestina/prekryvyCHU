#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(openxlsx))
a <- commandArgs(trailingOnly=TRUE)
if (length(a)<2L) stop("Použití: Rscript tests/overeni_v063.R veřejný.xlsx diagnostika/diagnostika_aktualni.xlsx")
public <- openxlsx::getSheetNames(a[1]); private <- openxlsx::getSheetNames(a[2])
ocekavane_verejne <- c("Souhrn_po_uzemich","OOP_podle_uradu","Metodika")
ocekavane_interni <- c("Informace","DRUSOP_kontrola","OOP_kontrola",
  "Prekryvy_MZCHU","Prekryvy_VZCHU","Prekryvy_EVL",
  "Geometricke_nesoulady","Neplatne_geometrie",
  "Nesoulady_po_uzemich","Vysvetlivky_stavu")
chybi_verejne <- setdiff(ocekavane_verejne, public)
chybi_interni <- setdiff(ocekavane_interni, private)
if (length(chybi_verejne)) stop("Chybi verejne listy: ",paste(chybi_verejne,collapse=", "),call.=FALSE)
if (length(chybi_interni)) stop("Chybi interni listy: ",paste(chybi_interni,collapse=", "),call.=FALSE)
if (any(c("DRUSOP_kontrola","OOP_kontrola") %in% public))
  stop("Interni list nalezen ve verejnem XLSX",call.=FALSE)

read <- function(f,s) openxlsx::read.xlsx(f,s,check.names=FALSE)
contains <- function(df,key) any(endsWith(names(df),paste0("[",key,"]")))
wide <- read(a[1],"Souhrn_po_uzemich")
oopp <- read(a[1],"OOP_podle_uradu")
int <- read(a[2],"DRUSOP_kontrola")
stopifnot(contains(wide,"OOP_souhrn"),contains(oopp,"mikrofragment_oop"),
          contains(oopp,"uvaden_v_souhrnu"),contains(int,"OOP_vysvetleni_rozdilu"),
          contains(int,"OOP_geo_mikrofragmenty"),
          !any(grepl("\\[(OOP_DRUSOP|OOP_shoda|OOP_pouze_geo|DRUSOP_stav)\\]",names(wide))))
info <- read(a[2],"Informace")
stopifnot(any(grepl("poslední změny souboru",unlist(info),ignore.case=TRUE)))
cat("KONTROLA V0.6.3 PROŠLA\n")
