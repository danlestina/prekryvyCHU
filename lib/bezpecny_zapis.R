# v0.6.2 – local staging, safe replacement/fallback for Windows / Nextcloud.
# Temporary XLSX/GPKG is generated in tempdir(), not in the synchronized folder.
.diag_paths <- new.env(parent=emptyenv())
diag_resolve <- function(path) {
  k <- normalizePath(path, winslash="/", mustWork=FALSE)
  if (exists(k, envir=.diag_paths, inherits=FALSE)) get(k, envir=.diag_paths) else path
}

diag_mkdir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive=TRUE, showWarnings=FALSE)
  if (!dir.exists(path)) stop("Nelze vytvorit diagnostickou slozku: ", path)
  invisible(path)
}

diag_publish <- function(temp, target) {
  if (!file.exists(temp) || is.na(file.info(temp)$size) || file.info(temp)$size <= 0)
    stop("Docasny diagnosticky soubor chybi nebo je prazdny: ", temp)
  diag_mkdir(dirname(target))
  ext <- tools::file_ext(target)
  suffix <- if (nzchar(ext)) paste0(".",ext) else ""
  stem <- if (nzchar(ext)) substr(basename(target),1,nchar(basename(target))-nchar(suffix)) else basename(target)
  # Copy to a unique complete candidate at destination, before touching existing files.
  # This is necessary when tempdir() and Nextcloud reside on separate volumes.
  candidate <- tempfile(pattern=paste0(stem,"_pripraveno_"),tmpdir=dirname(target),fileext=suffix)
  for (attempt in seq_len(3L)) {
    if (isTRUE(file.copy(temp,candidate,overwrite=FALSE)) &&
        file.exists(candidate) && file.info(candidate)$size==file.info(temp)$size) break
    if (file.exists(candidate)) unlink(candidate)
    if (attempt<3L) Sys.sleep(attempt)
  }
  if (!file.exists(candidate) || is.na(file.info(candidate)$size) ||
      file.info(candidate)$size!=file.info(temp)$size)
    stop("Nelze prevest diagnosticky soubor do slozky Nextcloud: ",target)
  backup <- paste0(target,".previous")
  published <- FALSE
  for (attempt in seq_len(3L)) {
    if (!file.exists(target)) {
      published <- isTRUE(file.rename(candidate,target))
    } else if (!file.exists(backup) && isTRUE(file.rename(target,backup))) {
      published <- isTRUE(file.rename(candidate,target))
      if (published) unlink(backup)
      else if (!isTRUE(file.rename(backup,target)))
        warning("ZALOHA: Puvodni soubor je v ",backup,"; nepodarilo se vratit na ",target,call.=FALSE)
    }
    if (published) break
    if (attempt<3L) Sys.sleep(attempt)
  }
  actual <- if (published) target else candidate
  if (!published) warning("NEXTCLOUD / ZAMEK: Novy diagnosticky soubor byl ulozen jako ", actual,
    "; cilovy soubor ",target," nepovazujte za aktualni.",call.=FALSE)
  assign(normalizePath(target,winslash="/",mustWork=FALSE),actual,envir=.diag_paths)
  unlink(temp)
  actual
}
