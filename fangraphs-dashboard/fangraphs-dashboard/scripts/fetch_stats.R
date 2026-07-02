#!/usr/bin/env Rscript
# scripts/fetch_stats.R
#
# Descarga los líderes de wRC+ (bateo) y SIERA (pitcheo) desde FanGraphs.com
# usando el paquete baseballr, y los guarda como JSON dentro de site/data
# para que el sitio estático (publicado en Netlify) los pueda leer.
#
# Este script está pensado para correr en GitHub Actions (ver
# .github/workflows/update-stats.yml), no dentro de Netlify: Netlify no
# tiene un runtime de R disponible para sus Functions.

pkgs <- c("baseballr", "dplyr", "jsonlite")
to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install) > 0) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
}

suppressPackageStartupMessages({
  library(baseballr)
  library(dplyr)
  library(jsonlite)
})

# --- Configuración ---------------------------------------------------------
SEASON  <- as.integer(format(Sys.Date(), "%Y"))
OUT_DIR <- "site/data"
TODAY   <- Sys.Date()

# Umbrales mínimos por ventana. En una ventana de 7 días nadie llega a 50 PA,
# así que cada período tiene su propio mínimo razonable (ajustable).
MIN_PA  <- list(season = 50, d7 = 10, d14 = 20)
MIN_IP  <- list(season = 20, d7 = 3,  d14 = 6)

WINDOWS <- list(
  d7  = list(start = TODAY - 6,  end = TODAY),
  d14 = list(start = TODAY - 13, end = TODAY)
)

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# --- Helpers -------------------------------------------------------------
fetch_batting <- function(qual, startdate = "", enddate = "") {
  fg_batter_leaders(
    startseason = SEASON,
    endseason   = SEASON,
    qual        = as.character(qual),
    pos         = "np",   # excluye lanzadores de la tabla de bateo
    startdate   = startdate,
    enddate     = enddate
  ) |>
    transmute(
      season   = Season,
      player   = PlayerName,
      team     = team_name,
      pa       = PA,
      wrc_plus = wRC_plus,
      woba     = wOBA,
      war      = WAR
    ) |>
    filter(!is.na(wrc_plus)) |>
    arrange(desc(wrc_plus))
}

fetch_pitching <- function(qual, startdate = "", enddate = "") {
  fg_pitcher_leaders(
    startseason = SEASON,
    endseason   = SEASON,
    qual        = as.character(qual),
    startdate   = startdate,
    enddate     = enddate
  ) |>
    transmute(
      season = Season,
      player = PlayerName,
      team   = team_name,
      ip     = IP,
      siera  = SIERA,
      era    = ERA,
      fip    = FIP,
      war    = WAR
    ) |>
    filter(!is.na(siera)) |>
    arrange(siera)   # SIERA más bajo = mejor
}

# --- Temporada completa ----------------------------------------------------
message("Descargando líderes de temporada completa (", SEASON, ")...")
batters_season  <- fetch_batting(MIN_PA$season)
pitchers_season <- fetch_pitching(MIN_IP$season)

# --- Últimos 7 días --------------------------------------------------------
message("Descargando líderes de últimos 7 días (", WINDOWS$d7$start, " a ", WINDOWS$d7$end, ")...")
batters_7d  <- fetch_batting(MIN_PA$d7,  as.character(WINDOWS$d7$start),  as.character(WINDOWS$d7$end))
pitchers_7d <- fetch_pitching(MIN_IP$d7, as.character(WINDOWS$d7$start),  as.character(WINDOWS$d7$end))

# --- Últimos 14 días ---------------------------------------------------
message("Descargando líderes de últimos 14 días (", WINDOWS$d14$start, " a ", WINDOWS$d14$end, ")...")
batters_14d  <- fetch_batting(MIN_PA$d14,  as.character(WINDOWS$d14$start), as.character(WINDOWS$d14$end))
pitchers_14d <- fetch_pitching(MIN_IP$d14, as.character(WINDOWS$d14$start), as.character(WINDOWS$d14$end))

# --- Escribir JSON -----------------------------------------------------
write_json(batters_season,  file.path(OUT_DIR, "batters_season.json"),  auto_unbox = TRUE, na = "null", digits = 3)
write_json(pitchers_season, file.path(OUT_DIR, "pitchers_season.json"), auto_unbox = TRUE, na = "null", digits = 3)
write_json(batters_7d,      file.path(OUT_DIR, "batters_7d.json"),      auto_unbox = TRUE, na = "null", digits = 3)
write_json(pitchers_7d,     file.path(OUT_DIR, "pitchers_7d.json"),     auto_unbox = TRUE, na = "null", digits = 3)
write_json(batters_14d,     file.path(OUT_DIR, "batters_14d.json"),     auto_unbox = TRUE, na = "null", digits = 3)
write_json(pitchers_14d,    file.path(OUT_DIR, "pitchers_14d.json"),    auto_unbox = TRUE, na = "null", digits = 3)

meta <- list(
  season     = SEASON,
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  windows    = list(
    d7  = list(start = as.character(WINDOWS$d7$start),  end = as.character(WINDOWS$d7$end)),
    d14 = list(start = as.character(WINDOWS$d14$start), end = as.character(WINDOWS$d14$end))
  ),
  counts = list(
    season = list(batters = nrow(batters_season), pitchers = nrow(pitchers_season)),
    d7     = list(batters = nrow(batters_7d),      pitchers = nrow(pitchers_7d)),
    d14    = list(batters = nrow(batters_14d),     pitchers = nrow(pitchers_14d))
  )
)
write_json(meta, file.path(OUT_DIR, "meta.json"), auto_unbox = TRUE)

message(
  "Listo. Temporada: ", nrow(batters_season), "/", nrow(pitchers_season),
  " | 7d: ", nrow(batters_7d), "/", nrow(pitchers_7d),
  " | 14d: ", nrow(batters_14d), "/", nrow(pitchers_14d)
)
