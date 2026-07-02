# Marcador — wRC+ y SIERA de FanGraphs en Netlify

Dashboard estático que muestra los líderes de **wRC+** (bateo) y **SIERA** (pitcheo)
de FanGraphs.com, actualizado automáticamente todos los días.

## Cómo funciona (por qué no corre R dentro de Netlify)

`baseballr` es un paquete de **R**, pero las Functions de Netlify solo soportan
Node.js y Go — no hay runtime de R disponible ahí. Por eso el proyecto separa
las dos cosas:

1. **GitHub Actions** corre `scripts/fetch_stats.R` con un cron diario. Ese
   script usa `baseballr::fg_batter_leaders()` y `baseballr::fg_pitcher_leaders()`
   para bajar los datos de FanGraphs y los guarda como JSON en `site/data/`.
2. El Action hace **commit + push** de esos JSON al repo.
3. **Netlify** está conectado al repo con *continuous deployment*: cada push
   (incluido el del bot de Actions) dispara un nuevo deploy automáticamente.
4. `site/index.html` es un dashboard estático (sin build) que simplemente hace
   `fetch()` de esos JSON y renderiza las tablas.

```
GitHub Actions (R + baseballr) → commit JSON → push → Netlify redeploya
```

Nada de scraping ocurre en el navegador del usuario ni en Netlify: solo se
sirven archivos estáticos.

## Estructura

```
fangraphs-dashboard/
├── .github/workflows/update-stats.yml   # cron que corre el script de R
├── scripts/fetch_stats.R                 # baja wRC+ y SIERA con baseballr
├── site/
│   ├── index.html                        # dashboard (con selector de período)
│   └── data/
│       ├── batters_season.json           # wRC+, temporada completa
│       ├── batters_7d.json               # wRC+, últimos 7 días
│       ├── batters_14d.json              # wRC+, últimos 14 días
│       ├── pitchers_season.json          # SIERA, temporada completa
│       ├── pitchers_7d.json              # SIERA, últimos 7 días
│       ├── pitchers_14d.json             # SIERA, últimos 14 días
│       └── meta.json                     # fecha de corrida + rangos de fecha
└── netlify.toml
```

## Sobre los splits

- **Últimos 7 / 14 días**: soportado de forma nativa. `fg_batter_leaders()` y
  `fg_pitcher_leaders()` aceptan `startdate`/`enddate`, así que el script
  simplemente pide `Sys.Date() - 6` / `Sys.Date() - 13` hasta hoy.
- **vs RHP / vs LHP y Home / Away**: **no** están disponibles a través de
  `baseballr`. El parámetro `hand` de esas funciones filtra por el lado desde
  el que *batea* el jugador (L/R/B), no por la mano del lanzador rival — es
  un error común. Esos splits viven en una herramienta separada de FanGraphs
  (el *Splits Leaderboards*, en `fangraphs.com/leaders/splits-leaderboards`),
  que corre sobre otra API que ninguna función de `baseballr` envuelve
  actualmente.

## Puesta en marcha

1. **Creá un repo en GitHub** y subí esta carpeta completa.

2. **Conectá el repo a Netlify**:
   - "Add new site" → "Import an existing project" → elegí el repo.
   - Build command: dejalo vacío.
   - Publish directory: `site`
   - (Netlify va a leer `netlify.toml`, así que estos dos campos ya quedan
     configurados solos.)
   - Deploy.

3. **Activá GitHub Actions**: no hace falta ninguna config extra — el
   workflow ya tiene permiso de escritura (`contents: write`) para hacer
   push usando el `GITHUB_TOKEN` automático del repo. Si tu organización
   tiene bloqueados los permisos de escritura por defecto para Actions,
   habilitalos en *Settings → Actions → General → Workflow permissions →
   Read and write permissions*.

4. **Primera carga de datos**: no hace falta esperar al cron. Andá a la
   pestaña *Actions* del repo → "Actualizar stats de FanGraphs" → *Run
   workflow*. Eso corre el script, hace commit de los JSON, y dispara el
   primer deploy real en Netlify.

## Ajustes que probablemente quieras hacer

- **Umbrales mínimos** (`MIN_PA`, `MIN_IP` en `fetch_stats.R`): controlan
  cuántos jugadores aparecen. Con valores bajos aparecen más jugadores pero
  con muestras chicas (SIERA/wRC+ menos estables). Subilos si querés algo
  más parecido a las tablas de "calificados" de FanGraphs.
- **Horario del cron** (`.github/workflows/update-stats.yml`): está en
  `0 9 * * *` (09:00 UTC). FanGraphs recalcula sus leaderboards después de
  que cierran los partidos del día anterior, así que un horario de mañana
  (hora de EE.UU.) suele ser seguro.
- **Diseño**: todo el CSS está en `site/index.html` como variables (`--paper`,
  `--ink`, `--grass`, `--clay`, `--amber`) por si querés adaptarlo a otra
  paleta.

## Probarlo en local

Como el dashboard hace `fetch()` de archivos locales, abrirlo con
`file://` directamente falla por CORS. Serví la carpeta con cualquier
servidor estático:

```bash
npx serve site
# o
python3 -m http.server --directory site 8080
```

## Nota sobre el origen de los datos

`baseballr` scrapea las leaderboards **públicas** de FanGraphs.com (no
contenido de pago). El propio paquete muestra un mensaje pidiendo considerar
apoyar a FanGraphs con una suscripción — vale la pena tenerlo en cuenta,
sobre todo si el cron corre con mucha frecuencia. Con una corrida diaria no
deberías tener problemas de rate-limiting.

## Alternativa sin R

Si en algún momento preferís no depender de R, el paquete de Python
[`pybaseball`](https://github.com/jldbc/pybaseball) expone las mismas
leaderboards de FanGraphs (`batting_stats()` / `pitching_stats()`, con
columnas `wRC+` y `SIERA`) contra el mismo origen de datos. El resto de la
arquitectura (GitHub Actions → commit JSON → Netlify redeploya) queda igual,
solo cambiarías `scripts/fetch_stats.R` por un script de Python y el paso de
"Set up R" del workflow por `actions/setup-python`.
