#!/usr/bin/env Rscript
# =============================================================================
# omopdependencies.R
# OMOP / OHDSI package provisioning for the cohortbuilder Shiny application
# =============================================================================
#
# PURPOSE
#   One-time (re-runnable) provisioning of the OMOP / OHDSI R ecosystem that
#   cohortbuilder uses for its standards path: the CDMConnector adapter, the
#   characterisation and diagnostics packages, the visOmopResults rendering
#   layer, and the local testing stack.
#
#   This is a SETUP script, run by hand once per workspace (or whenever the
#   stack changes). It is NOT part of the app runtime. The app never calls
#   install.packages; it guards every optional package with requireNamespace
#   and degrades gracefully when one is absent. This script is what makes those
#   packages present in the first place.
#
# CONVENTION (important)
#   This file is the single source of truth for the OHDSI stack cohortbuilder
#   depends on. Whenever a new feature needs a new package, ADD IT HERE in the
#   same edit. Do not let the app and this manifest drift.
#
# USAGE
#   Rscript omopdependencies.R              # install anything missing
#   FORCE=1 Rscript omopdependencies.R      # reinstall everything (upgrade)
#
#   To use a workspace mirror (for example a Posit Package Manager URL) instead
#   of public CRAN, either set options(repos = ...) before sourcing, or export
#   CRAN_MIRROR to point at it:
#       CRAN_MIRROR=https://my.workspace/cran Rscript omopdependencies.R
#
# BEHAVIOUR
#   - Installs only packages that are missing, so re-runs are cheap (FORCE=1
#     overrides and reinstalls).
#   - CRAN first. If a package is not reachable on CRAN, falls back to GitHub
#     (darwin-eu for the DARWIN EU tidy stack, OHDSI for PhenotypeR and Eunomia).
#   - One package failing does not stop the rest; a PASS / FAIL summary with
#     installed versions is printed at the end.
# =============================================================================
 
force_reinstall <- nzchar(Sys.getenv("FORCE", "")) &&
  !identical(tolower(Sys.getenv("FORCE")), "0") &&
  !identical(tolower(Sys.getenv("FORCE")), "false")
 
# ---- Repository resolution --------------------------------------------------
# Honour an already-configured mirror; otherwise CRAN_MIRROR; otherwise cloud.
repos <- getOption("repos")
if (is.null(repos) || length(repos) == 0 || any(repos %in% c("@CRAN@", "", NA))) {
  repos <- c(CRAN = Sys.getenv("CRAN_MIRROR", "https://cloud.r-project.org"))
}
options(repos = repos)
ncpus <- tryCatch(max(1L, parallel::detectCores() - 1L), error = function(e) 1L)
 
message("omopdependencies.R")
message("  repos : ", paste(repos, collapse = ", "))
message("  Ncpus : ", ncpus)
message("  force : ", force_reinstall)
message("")
 
# ---- Package manifest -------------------------------------------------------
# Grouped by role in cohortbuilder. Order places foundational packages first so
# that, even on a partial failure, the lower layers are already in place.
packages <- c(
  # -- Core infrastructure: cdm_reference + summarised_result classes ---------
  "DBI",                  # database interface used directly by the app
  "dbplyr",               # lazy SQL translation under the tidy stack
  "omopgenerics",         # standard cdm_reference and summarised_result classes
  "CDMConnector",         # build a cdm_reference from a DBI connection (get_cdm)
  "PatientProfiles",      # add demographics and cohort intersections to a cdm
  "CohortConstructor",    # build and modify cohorts within the tidy stack
 
  # -- Database driver --------------------------------------------------------
  "RPostgres",            # second DBI driver the OHDSI stack uses for DRE Postgres
 
  # -- Concept sets and phenotype diagnostics ---------------------------------
  "CodelistGenerator",    # concept-set building, orphan and unmapped code detection
  "PhenotypeR",           # phenotype diagnostics: database, codelist, cohort, population
 
  # -- Characterisation and analysis -----------------------------------------
  "CohortCharacteristics",# cohort demographics and characterisation
  "OmopSketch",           # database and cohort profiling / snapshots
  "IncidencePrevalence",  # incidence and prevalence (cumulative incidence)
  "CohortSurvival",       # survival and Kaplan-Meier estimation
  "DrugUtilisation",      # drug utilisation and treatment pathways
  "CohortSymmetry",       # sequence symmetry analysis
  "MeasurementDiagnostics",# measurement-value diagnostics (PhenotypeR companion)
 
  # -- Reporting and visualisation over summarised_result ---------------------
  "visOmopResults",       # tables and ggplot2 plots over summarised_result
  "gt",                   # HTML table backend for visOmopResults
  "flextable",            # Word / PDF table backend for visOmopResults
 
  # -- Local testing and example data ----------------------------------------
  "omock",                # mock OMOP CDM data for the automated test suite
  "duckdb",               # in-process database for local tests and Eunomia data
  "Eunomia"               # example OMOP datasets (GiBleed, Synpuf) for dev / tests
)
 
# Packages published on CRAN only; no GitHub fallback is attempted for these.
cran_only <- c("DBI", "dbplyr", "RPostgres", "gt", "flextable", "duckdb")
 
# Explicit GitHub org/repo for packages NOT under the darwin-eu organisation.
# Everything else falls back to darwin-eu/<package> if CRAN is unreachable.
# These paths are only used when CRAN fails; adjust if an org ever moves.
github_override <- c(
  PhenotypeR = "OHDSI/PhenotypeR",
  Eunomia    = "OHDSI/Eunomia"
)
 
github_source_for <- function(pkg) {
  if (pkg %in% cran_only) return(NA_character_)
  if (pkg %in% names(github_override)) return(unname(github_override[[pkg]]))
  paste0("darwin-eu/", pkg)
}
 
# ---- Bootstrap remotes (needed for any GitHub fallback) ---------------------
if (!requireNamespace("remotes", quietly = TRUE)) {
  message("[bootstrap] installing 'remotes' ...")
  tryCatch(
    install.packages("remotes", repos = repos, Ncpus = ncpus, quiet = FALSE),
    error = function(e) message("[bootstrap] remotes install failed: ",
                                conditionMessage(e))
  )
}
 
# ---- Installer --------------------------------------------------------------
install_one <- function(pkg) {
  if (!force_reinstall && requireNamespace(pkg, quietly = TRUE)) return("present")
 
  # CRAN first
  cran_ok <- tryCatch({
    install.packages(pkg, repos = repos, Ncpus = ncpus, quiet = FALSE)
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) {
    message("  CRAN install error for ", pkg, ": ", conditionMessage(e)); FALSE
  })
  if (isTRUE(cran_ok)) return("cran")
 
  # GitHub fallback
  gh <- github_source_for(pkg)
  if (!is.na(gh) && requireNamespace("remotes", quietly = TRUE)) {
    message("  CRAN unavailable for ", pkg, "; trying GitHub: ", gh)
    gh_ok <- tryCatch({
      remotes::install_github(gh, upgrade = "never", quiet = FALSE)
      requireNamespace(pkg, quietly = TRUE)
    }, error = function(e) {
      message("  GitHub install error for ", pkg, ": ", conditionMessage(e)); FALSE
    })
    if (isTRUE(gh_ok)) return("github")
  }
  "FAILED"
}
 
results <- character(length(packages))
names(results) <- packages
for (pkg in packages) {
  message("== ", pkg, " ==")
  results[pkg] <- install_one(pkg)
}
 
# ---- Summary ----------------------------------------------------------------
version_of <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE))
    as.character(utils::packageVersion(pkg)) else "-"
}
 
message("\n=============================================================")
message("PROVISIONING SUMMARY")
message("=============================================================")
status_label <- c(present = "already present", cran = "installed (CRAN)",
                  github = "installed (GitHub)", FAILED = "FAILED")
for (pkg in packages) {
  st <- results[[pkg]]
  message(sprintf("  %-24s %-20s %s",
                  pkg, status_label[[st]], version_of(pkg)))
}
 
failed <- names(results)[results == "FAILED"]
message("-------------------------------------------------------------")
if (length(failed) == 0) {
  message("All ", length(packages), " packages are present.")
} else {
  message(length(failed), " package(s) FAILED: ", paste(failed, collapse = ", "))
  message("Re-run after resolving the cause (mirror reachability, system ",
          "libraries, or an org path in github_override).")
}
message("=============================================================")
 
invisible(results)
