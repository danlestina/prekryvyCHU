# Interni topologicka diagnostika v0.6.1; nikdy nezapisovat do site/.
# Jednotlive evidovane objekty jsou jiz sjednocene podle klice v reference.
# Pouze plosny prunik ruznych objektu, vcetne jinych kategorii v ramci MZCHU/VZCHU.

vypocti_topologii <- function(reference, slozka, minimalni_plocha_m2=0.01) {
  dir.create(slozka, recursive=TRUE, showWarnings=FALSE)
  skupiny <- list(
    Prekryvy_MZCHU=c("NPR","NPP","PR","PP"),
    Prekryvy_VZCHU=c("NP","CHKO"),
    Prekryvy_EVL="EVL")
  prazdna <- function() data.frame(
    klic_a=character(), kategorie_a=character(), kod_a=character(), nazev_a=character(),
    klic_b=character(), kategorie_b=character(), kod_b=character(), nazev_b=character(),
    plocha_pruniku_m2=numeric(), podil_na_a_pct=numeric(), podil_na_b_pct=numeric(),
    mozny_artefakt=logical(), stringsAsFactors=FALSE)
  tabulky <- list()
  geomet <- list()
  for (nm in names(skupiny)) {
    x <- reference[reference$kategorie %in% skupiny[[nm]], , drop=FALSE]
    tab <- prazdna(); geometrie <- list()
    if (nrow(x)>1L) {
      cand <- sf::st_intersects(x, sparse=TRUE)
      plochy <- as.numeric(sf::st_area(x))
      rows <- list()
      for (i in seq_len(nrow(x))) {
        js <- cand[[i]]
        js <- js[js>i & x$klic[js] != x$klic[i]]
        for (j in js) {
          inter <- suppressWarnings(sf::st_intersection(sf::st_geometry(x)[i],
                                                         sf::st_geometry(x)[j]))
          if (!length(inter) || all(sf::st_is_empty(inter))) next
          # Prunik muze obsahovat jen linii nebo bod; zadna plosna chyba.
          a <- sum(as.numeric(sf::st_area(inter)))
          if (!is.finite(a) || a<=0 || a<minimalni_plocha_m2) next
          # Geometrii sjednotit, aby jeden par byl jeden identifikovatelny zaznam.
          poly <- suppressWarnings(sf::st_collection_extract(inter, "POLYGON"))
          poly <- poly[!sf::st_is_empty(poly)]
          if (!length(poly)) next
          shape <- suppressWarnings(sf::st_union(poly))
          rows[[length(rows)+1L]] <- data.frame(
            klic_a=as.character(x$klic[i]), kategorie_a=as.character(x$kategorie[i]),
            kod_a=as.character(x$kod[i]), nazev_a=as.character(x$nazev[i]),
            klic_b=as.character(x$klic[j]), kategorie_b=as.character(x$kategorie[j]),
            kod_b=as.character(x$kod[j]), nazev_b=as.character(x$nazev[j]),
            plocha_pruniku_m2=a,
            podil_na_a_pct=if (plochy[i]>0) a/plochy[i]*100 else NA_real_,
            podil_na_b_pct=if (plochy[j]>0) a/plochy[j]*100 else NA_real_,
            mozny_artefakt=a<1,
            stringsAsFactors=FALSE)
          geometrie[[length(geometrie)+1L]] <- shape[[1L]]
        }
      }
      if (length(rows)) tab <- dplyr::bind_rows(rows)
    }
    tabulky[[nm]] <- tab
    if (length(geometrie)) {
      geomet[[nm]] <- sf::st_sf(tab, geometry=do.call(sf::st_sfc,
                                       base::c(geometrie,list(crs=5514))))
    }
    message("TOPOLOGIE: ",nm,": ",nrow(tab)," plosnych dvojic")
  }
  dest <- file.path(slozka,"prekryvy_nezadouci.gpkg")
  temp <- tempfile("topologie_",fileext=".gpkg")
  on.exit(unlink(temp),add=TRUE)
  if (length(geomet)) {
    first <- TRUE
    for (nm in names(geomet)) {
      sf::st_write(geomet[[nm]],temp,layer=nm,quiet=TRUE,delete_dsn=first)
      first <- FALSE
    }
    actual <- diag_publish(temp, dest)
    attr(tabulky,"gpkg_soubor") <- actual
  } else if (file.exists(dest)) unlink(dest)
  tabulky
}

# Konsoliduje jiz vytvorene jednotlive diagnostiky do jedineho prehledu.
# Zdrojove XLSX a GPKG ponechava jako podrobne/pracovni soubory.
vytvor_diagnosticky_sesit <- function(slozka, topologie, drusop=NULL,
       datum_exportu="NEZJISTENO", soubor_exportu="", provedeno_drusop=FALSE, oopc=NULL) {
  dir.create(slozka,recursive=TRUE,showWarnings=FALSE)
  wb <- openxlsx::createWorkbook()
  pridat <- function(nm, df) {
    openxlsx::addWorksheet(wb,nm)
    df <- as.data.frame(df)
    df <- popisne_hlavicky(df)
    openxlsx::writeData(wb,nm,df,withFilter=nrow(df)>0)
    openxlsx::freezePane(wb,nm,firstRow=TRUE)
    if (ncol(df)) openxlsx::setColWidths(wb,nm,cols=seq_len(ncol(df)),widths=32)
    openxlsx::setRowHeights(wb,nm,rows=1,heights=56)
    if (ncol(df)) openxlsx::addStyle(wb,nm,
       openxlsx::createStyle(textDecoration="bold",wrapText=TRUE,fgFill="#E7EDF2"),
       rows=1,cols=seq_len(ncol(df)),gridExpand=TRUE,stack=TRUE)
  }
  info <- data.frame(polozka=c("Verze", "Datum vypoctu", "Export DRUSOP aktualizovan automaticky?",
      "Datum poslední změny souboru DR ÚSOP (není doložené datum pořízení exportu)", "Soubor exportu DRUSOP",
      "Čas poslední změny souboru DR ÚSOP (může být změněn kopírováním)", "Kontrola DRUSOP provedena?",
      "Nutny postup spravce", "Vyklad topologie", "Minimalni plocha topologickeho pruniku",
      "Aktualni GPKG topologickych prekryvu"),
    hodnota=c("0.6.3",format(Sys.time(),"%Y-%m-%d %H:%M:%S %Z"),"NE – RUCNI EXPORT",
      if (provedeno_drusop) datum_exportu else "NEPROVEDENO",
      if (provedeno_drusop) soubor_exportu else "NEPOUZITO",
      if (provedeno_drusop && nzchar(soubor_exportu) && file.exists(soubor_exportu))
        format(file.info(soubor_exportu)$mtime,"%Y-%m-%d %H:%M:%S %Z") else "NEZJISTENO",
      if (provedeno_drusop) "ANO" else "NE",
      "Export DR ÚSOP se neaktualizuje automaticky. Uvedené datum pochází z vlastnosti souboru – poslední změna; datum může být změněno kopírováním a nedokazuje stáří samotných údajů. Před interpretací rozdílů export ručně obnovte.",
      "Vzajemny plosny prekryv je kandidat ke kontrole; sam o sobe nedokazuje pravni vadu. Geometrie po opravach validity a orezu na CR.",
      "Nastaveni --diagnostic-min-area-m2; vychozi 0.01 m2",
      if (is.null(attr(topologie,"gpkg_soubor"))) "BEZ NALEZU" else attr(topologie,"gpkg_soubor")),stringsAsFactors=FALSE)
  pridat("Informace",info)
  for (nm in names(topologie)) pridat(nm,topologie[[nm]])
  if (!is.null(oopc)) pridat("OOP_kontrola",oopc)
  if (!is.null(drusop)) pridat("DRUSOP_kontrola",drusop)
  ostatni <- list(
    Geometricke_nesoulady=list(file="katalog_nesouladu.xlsx",sheet="Nesoulady"),
    Neplatne_geometrie=list(file="neplatne_geometrie.xlsx",sheet="Nalezy"))
  for (nm in names(ostatni)) {
    z <- ostatni[[nm]]
    f <- file.path(slozka,z$file)
    if (!file.exists(diag_resolve(f))) stop("Chybi predchozi diagnosticky soubor: ",diag_resolve(f))
    tab <- openxlsx::read.xlsx(diag_resolve(f),sheet=z$sheet,check.names=FALSE)
    # Samostatné XLSX mohou mít popisné hlavičky [strojovy_klic]
    # nebo historicke kratke nazvy. Identifikator vezmeme z koncove
    # zavorky; pokud chybi, ponechame puvodni text beze zmeny.
    hlavicky <- names(tab)
    ma_klic <- grepl("\\[[A-Za-z0-9_]+\\]$", hlavicky)
    hlavicky[ma_klic] <- sub("^.*\\[([A-Za-z0-9_]+)\\]$", "\\1", hlavicky[ma_klic])
    names(tab) <- hlavicky
    if (nm == "Geometricke_nesoulady") {
      pozadovane <- c("kategorie", "kod", "nazev", "plocha_m2", "typ_chyby")
      chybi <- setdiff(pozadovane, names(tab))
      if (length(chybi)) stop(
        "NELZE SESTAVIT Nesoulady_po_uzemich: v ", z$file,
        " chybi sloupce: ", paste(chybi, collapse=", "),
        ". Nactene sloupce: ", paste(names(tab), collapse=" | "),
        call.=FALSE)
      if (nrow(tab) && (anyNA(tab$kategorie) || anyNA(tab$kod) ||
          anyNA(tab$typ_chyby)))
        stop("NELZE SESTAVIT Nesoulady_po_uzemich: chybi identifikatory fragmentu.",call.=FALSE)
      # Souhrn vytvarime i kdyz nebyly nalezeny zadne nesoulady.
      if (nrow(tab)) {
        plochy <- suppressWarnings(as.numeric(tab$plocha_m2))
        if (any(!is.finite(plochy)))
          stop("NELZE SESTAVIT Nesoulady_po_uzemich: neplatne plochy fragmentu.",call.=FALSE)
        tab$plocha_m2 <- plochy
        sumar <- tab |>
          dplyr::group_by(kategorie,kod,nazev,typ_chyby) |>
          dplyr::summarise(pocet_fragmentu=dplyr::n(),
                           celkova_plocha_fragmentu_m2=sum(plocha_m2),
                           .groups="drop") |>
          dplyr::arrange(dplyr::desc(celkova_plocha_fragmentu_m2))
      } else {
        sumar <- data.frame(kategorie=character(),kod=character(),
          nazev=character(),typ_chyby=character(),pocet_fragmentu=integer(),
          celkova_plocha_fragmentu_m2=numeric())
      }
      pridat("Nesoulady_po_uzemich",sumar)
      message("DIAGNOSTIKA: souhrn geometrickych nesouladu po uzemich: ",nrow(sumar)," radku")
    }
    pridat(nm,tab)
  }
  # Stručný slovník významů diagnostických stavů a prahových hodnot.
  pridat("Vysvetlivky_stavu",data.frame(
    stav=c("SHODA","MIKROFRAGMENT","DILCI_PUSOBNOST","ROZDIL_K_PROVERENI",
           "BEZ_SAMOSTATNEHO_ZAZNAMU","OOP_PRAZDNY_V_EXPORTU"),
    vyznam=c(
      "Evidence DR ÚSOP souhlasí se seznamem geometricky významných OOP.",
      "Odlišný OOP se objevil pouze na ploše menší než 1 m² a zároveň menší než 0,001 % celého území; geometricky se neztrácí.",
      "OOP z DR ÚSOP je geometricky přítomen a další OOP se uplatňuje na části území. Je nutné ověřit konkrétní důvod/podklad.",
      "Významný rozdíl nelze vysvětlit pouhým drobným fragmentem či další dílčí působností; vyžaduje kontrolu včetně PUOS.",
      "Pro daný typ území chybí samostatný záznam v použitém exportu DR ÚSOP.",
      "Objekt v exportu nalezen, ale údaj o OOP je prázdný."),stringsAsFactors=FALSE))
  tmp <- tempfile("diag060_",fileext=".xlsx")
  on.exit(unlink(tmp),add=TRUE)
  openxlsx::saveWorkbook(wb,tmp,overwrite=TRUE)
  dest <- file.path(slozka,"diagnostika_aktualni.xlsx")
  # V pripade zamku Nextcloudu zustane nova diagnostika jako dalsi XLSX.
  aktualni <- diag_publish(tmp,dest)
  message("SOUHRNNA INTERNI DIAGNOSTIKA: ",aktualni)
  invisible(aktualni)
}
