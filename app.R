# ============================================================================
# HiCarta  -  interactive Hi-C contact map viewer
#
# Slippy-map contact viewer that scales to high resolution / large genomes.
# Instead of loading a whole chromosome, it serves 256-px tiles on demand:
# Leaflet's GridLayer requests only the visible tiles (+ a buffer) and evicts
# distant ones automatically, and each tile is rendered from strawr at the
# resolution matching the current zoom (level-of-detail). All tiles share one
# global Value scale (vmin/vmax) so they line up seamlessly. 1-D tracks
# (bigWig / BED / gene GFF3 / Border Strength) sync to the map's x-range.
#
# Run:  double-click run_windows.bat (or run_mac.command), or
#       Rscript -e "shiny::runApp('.', launch.browser=TRUE, port=7788)"
# ============================================================================

suppressWarnings(suppressMessages({
  library(shiny); library(leaflet); library(htmlwidgets); library(base64enc)
}))

# shinyFiles powers the native file-picker dialog for the local .hic path. It is
# optional: if it is not installed the app still runs and the path can be typed.
HAS_SHINYFILES <- requireNamespace("shinyFiles", quietly = TRUE)

source("R/i18n.R",        local = TRUE)
source("R/readers.R",     local = TRUE)
source("R/juicer_menu.R", local = TRUE)
source("R/draw.R",        local = TRUE)
source("R/tiles.R",       local = TRUE)
source("R/tracks.R",      local = TRUE)
source("R/genes.R",       local = TRUE)
source("R/borderstrength.R", local = TRUE)
source("R/export.R",       local = TRUE)

APP_VERSION <- "4.0 (2026-07)"

# ---- config.txt (key = value) in the app folder: startup defaults -----------
read_config <- function(path) {
  cfg <- list()
  if (file.exists(path)) for (ln in readLines(path, warn = FALSE)) {
    ln <- trimws(ln); if (ln == "" || startsWith(ln, "#")) next
    kv <- strsplit(ln, "=", fixed = TRUE)[[1]]
    if (length(kv) >= 2) cfg[[trimws(kv[1])]] <- trimws(paste(kv[-1], collapse = "="))
  }
  cfg
}
CFG <- read_config(file.path(getwd(), "config.txt"))
cfg_or <- function(k, d) if (!is.null(CFG[[k]]) && nzchar(CFG[[k]])) CFG[[k]] else d

# Rewrite config.txt from the in-app dialog. Known keys get friendly comments;
# any other keys already in the file are preserved so nothing is lost.
write_config <- function(path, values) {
  known <- c("language", "menu_url", "track_list_url")
  cur   <- read_config(path)
  extra <- cur[setdiff(names(cur), known)]
  v <- function(k) { x <- values[[k]]; if (is.null(x)) "" else trimws(as.character(x)) }
  lines <- c(
    "# HiCarta configuration.  key = value  (lines starting with # are ignored)",
    "# Edit via the in-app config dialog (or by hand), then restart the app.",
    "",
    "# Interface language: en = English (default), ja = Japanese.",
    sprintf("language = %s", v("language")),
    "",
    "# Default Juicer sample menu (Hi-C .hic list) shown in the Data panel.",
    sprintf("menu_url = %s", v("menu_url")),
    "",
    "# Default track list shown in the Tracks panel. May be a single IGV XML,",
    "# or an index file listing several IGV XML URLs (one per line).",
    sprintf("track_list_url = %s", v("track_list_url")))
  if (length(extra))
    lines <- c(lines, "", "# Other settings",
               vapply(names(extra),
                      function(k) sprintf("%s = %s", k, extra[[k]]), character(1)))
  writeLines(lines, path)
}

DEFAULT_MENU_URL  <- cfg_or("menu_url",       "")   # set in config.txt (see config.example.txt)
DEFAULT_TRACKLIST <- cfg_or("track_list_url", "")   # set in config.txt (see config.example.txt)
# Interface language: default English; config.txt "language = ja" switches to
# Japanese (or any language defined in R/i18n.R). Chosen once at startup.
set_language(cfg_or("language", "en"))
TRK_COLORS  <- c("darkblue", "steelblue", "firebrick", "red", "darkgreen",
                 "seagreen", "purple", "magenta", "orange", "goldenrod", "black", "grey40")
COLOR_SWATCHES <- tags$div(id = "trk_swatches", style = "margin-bottom:6px;",
  lapply(TRK_COLORS, function(cc)
    tags$span(title = cc,
      style = paste0("display:inline-block;width:22px;height:22px;margin:2px;cursor:pointer;",
                     "border:2px solid #fff;vertical-align:middle;background:", cc, ";"),
      onclick = sprintf(paste0("Shiny.setInputValue('trk_color','%s',{priority:'event'});",
        "var s=document.querySelectorAll('#trk_swatches span');",
        "for(var i=0;i<s.length;i++){s[i].style.borderColor='#fff';}this.style.borderColor='#333';"), cc))))

MAP_JS <- "
function(el, x) {
  var map = this;
  window._hidmap = map;
  window._tileURL = null;
  window._tileLayer = null;
  window._scale = 1;   // bp per map-unit (set in initTiles)

  // map-unit (latlng) <-> genomic bp. genomic y = -lat (origin top-left).
  function toBpX(lng){ return lng * window._scale; }
  function toBpY(lat){ return -lat * window._scale; }
  function toLng(bp){ return bp / window._scale; }
  function toLat(bp){ return -bp / window._scale; }

  function report() {
    var b = map.getBounds();
    Shiny.setInputValue('map_view', {
      west: toBpX(b.getWest()), east: toBpX(b.getEast()),
      north: toBpY(b.getNorth()), south: toBpY(b.getSouth()),
      zoom: map.getZoom()
    }, {priority: 'event'});
  }

  // ---- rulers (top = x, right = y); genomic y = -lat, origin top-left ----
  var topR = L.DomUtil.create('div', 'hid-ruler', map.getContainer());
  topR.style.cssText = 'position:absolute;top:0;left:0;right:0;height:24px;background:rgba(255,255,255,0.85);border-bottom:1px solid #ccc;z-index:650;pointer-events:none;font:11px sans-serif;';
  var rightR = L.DomUtil.create('div', 'hid-ruler', map.getContainer());
  rightR.style.cssText = 'position:absolute;top:0;right:0;bottom:0;width:66px;background:rgba(255,255,255,0.85);border-left:1px solid #ccc;z-index:650;pointer-events:none;font:11px sans-serif;';
  function fmtbp(v){ v=Math.round(v); if(Math.abs(v)>=1e6)return (v/1e6).toFixed(2)+' Mb'; if(Math.abs(v)>=1e3)return (v/1e3).toFixed(0)+' kb'; return String(v); }
  function niceStep(r,n){ var raw=r/n, mag=Math.pow(10,Math.floor(Math.log10(raw))), q=raw/mag, s=(q<1.5)?1:(q<3)?2:(q<7)?5:10; return s*mag; }
  function addEl(p,css,t){ var d=document.createElement('div'); d.style.cssText=css; if(t!=null)d.textContent=t; p.appendChild(d); return d; }
  function drawRulers(){
    if(!map._loaded) return;
    var b=map.getBounds(), size=map.getSize();
    topR.innerHTML=''; rightR.innerHTML='';
    var gxMin=toBpX(b.getWest()), gxMax=toBpX(b.getEast());
    var gyTop=toBpY(b.getNorth()), gyBot=toBpY(b.getSouth());
    var xr=gxMax-gxMin, yr=gyBot-gyTop; if(xr<=0||yr<=0) return; var SUB=5;
    var xs=niceStep(xr,7), xsub=xs/SUB;
    for(var gx=Math.ceil(gxMin/xsub)*xsub; gx<=gxMax; gx+=xsub){
      var p=map.latLngToContainerPoint(L.latLng(b.getNorth(), toLng(gx)));
      if(p.x<0||p.x>size.x-66) continue;
      var maj=Math.abs(gx/xs-Math.round(gx/xs))<1e-6;
      addEl(topR,'position:absolute;left:'+p.x+'px;top:'+(maj?15:19)+'px;width:1px;height:'+(maj?9:5)+'px;background:'+(maj?'#333':'#999')+';');
      if(maj) addEl(topR,'position:absolute;left:'+p.x+'px;top:1px;transform:translateX(-50%);color:#222;white-space:nowrap;',fmtbp(gx));
    }
    var ys=niceStep(yr,7), ysub=ys/SUB;
    for(var gy=Math.ceil(gyTop/ysub)*ysub; gy<=gyBot; gy+=ysub){
      var q=map.latLngToContainerPoint(L.latLng(toLat(gy), b.getEast()));
      if(q.y<24||q.y>size.y) continue;
      var mj=Math.abs(gy/ys-Math.round(gy/ys))<1e-6;
      addEl(rightR,'position:absolute;left:0;top:'+q.y+'px;width:'+(mj?9:5)+'px;height:1px;background:'+(mj?'#333':'#999')+';');
      if(mj) addEl(rightR,'position:absolute;left:12px;top:'+q.y+'px;transform:translateY(-50%);color:#222;white-space:nowrap;',fmtbp(gy));
    }
  }
  map.on('move zoom moveend zoomend resize viewreset', drawRulers);
  map.on('moveend', report);

  // size the map to fill the window on first load (like Auto adjust, 0 tracks)
  function autoSize(){
    var c = map.getContainer();
    var top = c.getBoundingClientRect().top;
    var h = Math.max(200, Math.floor(window.innerHeight - top - 16));
    c.style.height = h + 'px';
    map.invalidateSize(); drawRulers();
    Shiny.setInputValue('auto_map_height', h, {priority: 'event'});
  }
  setTimeout(autoSize, 80);

  // ---- crosshair + hover ----
  // vertical line lives in the wrapper so it spans the map AND the tracks below
  var wrap = document.getElementById('mapwrap');
  var vLine = document.createElement('div');
  vLine.style.cssText='position:absolute;top:0;bottom:0;width:1px;background:rgba(0,0,0,0.55);z-index:640;pointer-events:none;display:none;';
  (wrap || map.getContainer()).appendChild(vLine);
  var hLine=L.DomUtil.create('div','hid-cross',map.getContainer());
  hLine.style.cssText='position:absolute;left:0;right:0;height:1px;background:rgba(0,0,0,0.55);z-index:640;pointer-events:none;display:none;';
  var lastH=0;
  map.on('mousemove',function(e){
    var cp=e.containerPoint;
    vLine.style.left=cp.x+'px'; vLine.style.display='block';
    hLine.style.top=cp.y+'px'; hLine.style.display='block';
    var now=Date.now(); if(now-lastH>60){ lastH=now;
      Shiny.setInputValue('hover',{x:toBpX(e.latlng.lng),y:toBpY(e.latlng.lat)},{priority:'event'}); }
  });
  map.on('mouseout',function(){ vLine.style.display='none'; hLine.style.display='none';
    Shiny.setInputValue('hover',null,{priority:'event'}); });

  // ---- middle-drag rubber-band zoom ----
  var container=map.getContainer(), bStart=null, bDiv=null;
  function rel(e){ var r=container.getBoundingClientRect(); return {x:e.clientX-r.left,y:e.clientY-r.top}; }
  container.addEventListener('mousedown',function(e){ if(e.button!==1)return; e.preventDefault();
    bStart=rel(e); map.dragging.disable();
    bDiv=document.createElement('div'); bDiv.style.cssText='position:absolute;border:2px dashed #d33;background:rgba(220,50,50,0.10);z-index:660;pointer-events:none;'; container.appendChild(bDiv); });
  window.addEventListener('mousemove',function(e){ if(!bStart||!bDiv)return; var p=rel(e);
    bDiv.style.left=Math.min(bStart.x,p.x)+'px'; bDiv.style.top=Math.min(bStart.y,p.y)+'px';
    bDiv.style.width=Math.abs(p.x-bStart.x)+'px'; bDiv.style.height=Math.abs(p.y-bStart.y)+'px'; });
  window.addEventListener('mouseup',function(e){ if(!bStart)return; var p=rel(e),a=bStart; bStart=null;
    if(bDiv){container.removeChild(bDiv); bDiv=null;} map.dragging.enable();
    if(Math.abs(p.x-a.x)<5||Math.abs(p.y-a.y)<5)return;
    var l1=map.containerPointToLatLng([a.x,a.y]), l2=map.containerPointToLatLng([p.x,p.y]);
    map.fitBounds([[l1.lat,l1.lng],[l2.lat,l2.lng]]); });

  // ---- tile layer ----
  var TileLayer = L.GridLayer.extend({
    createTile: function(coords, done){
      var img = document.createElement('img');
      img.style.imageRendering='pixelated';
      var url = window._tileURL;
      if(!url){ done(null,img); return img; }
      var sep = url.indexOf('?')>=0 ? '&' : '?';
      img.onload  = function(){ done(null,img); };
      img.onerror = function(){ done(null,img); };
      img.src = url + sep + 'z=' + coords.z + '&x=' + coords.x + '&y=' + coords.y + '&v=' + window._tileVer;
      return img;
    }
  });

  Shiny.addCustomMessageHandler('initTiles', function(msg){
    window._tileURL = msg.url;
    window._scale   = msg.scale;
    window._tileVer = msg.ver;   // cache-buster: forces fresh tiles per Open
    map.setMinZoom(0); map.setMaxZoom(msg.mapMaxZoom);
    if(window._tileLayer){ map.removeLayer(window._tileLayer); window._tileLayer=null; }
    var U = msg.U;   // map-unit extent of the chromosome
    window._tileLayer = new TileLayer({
      tileSize: 256, noWrap: true,
      bounds: L.latLngBounds([[-U,0],[0,U]]),
      minZoom: 0, maxZoom: msg.mapMaxZoom,          // allow over-zoom (upscaled)
      minNativeZoom: 0, maxNativeZoom: msg.maxZoom, // finest real tiles
      keepBuffer: 0                                 // only render visible tiles first (single-threaded R)
    });
    window._tileLayer.addTo(map);
    map.setMaxBounds(L.latLngBounds([[-U*1.05,-0.05*U],[0.05*U,U*1.05]]));
    map.fitBounds([[toLat(msg.fy1), toLng(msg.fx0)],[toLat(msg.fy0), toLng(msg.fx1)]]);
    report(); drawRulers();
  });
  Shiny.addCustomMessageHandler('redrawTiles', function(msg){
    if(msg.ver != null) window._tileVer = msg.ver;   // fresh URLs so tiles actually refresh
    if(window._tileLayer){ window._tileLayer.redraw(); }
  });
  Shiny.addCustomMessageHandler('gotoRegion', function(msg){
    window._scale = msg.scale;
    map.fitBounds([[toLat(msg.fx1), toLng(msg.fx0)],[toLat(msg.fx0), toLng(msg.fx1)]]);
  });
  Shiny.addCustomMessageHandler('panView', function(msg){
    if(!map._loaded) return;
    var s = map.getSize();                       // pan by a fraction of the view
    map.panBy([msg.fx * s.x, msg.fy * s.y], {animate: true});
  });
  Shiny.addCustomMessageHandler('viewWhole', function(msg){
    map.fitBounds([[toLat(msg.chrlen), toLng(0)],[toLat(0), toLng(msg.chrlen)]]);
  });
  Shiny.addCustomMessageHandler('gotoView', function(msg){
    // jump to a saved 2-D region (x = genomic X, y = genomic Y)
    map.fitBounds([[toLat(msg.y1), toLng(msg.x0)],[toLat(msg.y0), toLng(msg.x1)]]);
  });
  Shiny.addCustomMessageHandler('setMapHeight', function(msg){
    var c = map.getContainer();
    c.style.height = msg.h + 'px';
    map.invalidateSize();          // resize without rebuilding the map
    report(); drawRulers();
  });
  Shiny.addCustomMessageHandler('fitMap', function(msg){
    var c = map.getContainer();
    var top = c.getBoundingClientRect().top;
    var h = Math.max(200, Math.floor(window.innerHeight - top - msg.tracksTotal - 16));
    c.style.height = h + 'px';
    map.invalidateSize();
    report(); drawRulers();
    Shiny.setInputValue('auto_map_height', h, {priority: 'event'});
  });
  Shiny.addCustomMessageHandler('autoAdjust', function(msg){
    var c = map.getContainer();
    var top = c.getBoundingClientRect().top;             // viewport-top -> map-top
    var tracks = msg.ntracks * (msg.perTrack + 6);        // stacked tracks below
    var h = Math.max(200, Math.floor(window.innerHeight - top - tracks - 16));
    c.style.height = h + 'px';
    map.invalidateSize();
    report(); drawRulers();
    Shiny.setInputValue('auto_map_height', h, {priority: 'event'});
  });
  Shiny.addCustomMessageHandler('closeLoader', function(msg){
    Shiny.setInputValue('loader_open', false, {priority: 'event'});
    var b = document.getElementById('open_loader_btn');
    if (b) b.classList.remove('active');
  });
}
"

# UI is a per-request function so it re-reads config.txt on every page load.
# That lets "Apply / reload" take effect with a simple session$reload() — no OS
# process restart needed: the language and the default URL fields are rebuilt
# from the freshly-saved config each time the page (re)loads.
ui <- function(request) {
  cfg <- read_config(file.path(getwd(), "config.txt"))
  set_language(if (!is.null(cfg[["language"]]) && nzchar(cfg[["language"]]))
                 cfg[["language"]] else "en")
  DEFAULT_MENU_URL  <- if (!is.null(cfg[["menu_url"]]))       cfg[["menu_url"]]       else ""
  DEFAULT_TRACKLIST <- if (!is.null(cfg[["track_list_url"]])) cfg[["track_list_url"]] else ""
  fluidPage(
  tags$head(tags$style(HTML(
    ".leaflet-container{background:#fff}", ".nav-pills>li>a{padding:6px 14px}",
    "#topnav{margin-bottom:8px; display:flex; align-items:center; gap:12px}",
    # dark backdrop + centered white box for the data-loading overlay ("modal")
    ".loader-overlay{position:fixed; inset:0; background:rgba(0,0,0,0.45);",
    "  z-index:1050; display:flex; align-items:flex-start; justify-content:center}",
    ".loader-box{background:#fff; margin-top:56px; width:700px; max-width:92vw;",
    "  max-height:86vh; overflow:auto; border-radius:8px; padding:16px 22px 22px;",
    "  box-shadow:0 10px 40px rgba(0,0,0,0.35)}",
    ".loader-head{display:flex; justify-content:space-between; align-items:center;",
    "  margin:-4px 0 10px}",
    ".loader-head .ttl{font-size:18px; font-weight:600}",
    ".loader-x{border:none; background:none; font-size:20px; line-height:1;",
    "  cursor:pointer; color:#777; padding:2px 8px}",
    ".loader-x:hover{color:#222}",
    # data button: styled like an (unselected) nav pill — white until active
    ".loader-btn{background:#fff; color:#337ab7; border:1px solid transparent;",
    "  border-radius:4px; padding:6px 14px; font-weight:400}",
    ".loader-btn:hover{background:#eee; color:#337ab7}",
    ".loader-btn.active{background:#337ab7; color:#fff}",
    ".pan-pad .btn{width:44px; padding:4px 0; font-size:14px}",
    ".pan-pad .btn.home{color:#337ab7}"))),
  titlePanel("HiCarta"),
  div(id = "topnav",
    # single entry point for all data loading (opens the overlay below)
    tags$button(id = "open_loader_btn", type = "button", class = "btn loader-btn",
      onclick = paste0("Shiny.setInputValue('loader_open', true, {priority:'event'});",
                       "this.classList.add('active');"),
      HTML("&#128194; "), tr("nav_data")),
    tabsetPanel(id = "nav", type = "pills", selected = "Region",
      tabPanel(tr("nav_region"),  value = "Region"),
      tabPanel(tr("nav_display"), value = "Display"),
      tabPanel(tr("nav_print"),   value = "Print"),
      tabPanel(tr("nav_setting"), value = "Setting"),
      tabPanel(tr("nav_about"),   value = "About"))),

  # ---- data-loading overlay ("modal"): Hi-C + track loading in two tabs. ----
  # It is always in the DOM (so menu/sample selections survive close/reopen) and
  # only shown when input.loader_open is true.
  conditionalPanel("input.loader_open == true",
    div(class = "loader-overlay",
      div(class = "loader-box",
        div(class = "loader-head",
          tags$span(class = "ttl", tr("data_loader_title")),
          tags$button(type = "button", class = "loader-x", title = tr("data_loader_close"),
            onclick = paste0("Shiny.setInputValue('loader_open', false, {priority:'event'});",
                             "var b=document.getElementById('open_loader_btn');",
                             "if(b) b.classList.remove('active');"),
            HTML("&#10005;"))),
        tabsetPanel(id = "loader_tab", type = "tabs",
          tabPanel(tr("data_loader_hic"),
            div(style = "padding-top:12px;",
              fileInput("menu_file", tr("data_menu_file"), accept = ".txt"),
              textInput("menu_url", tr("data_menu_url"), value = DEFAULT_MENU_URL),
              actionButton("load_menu", tr("data_load_menu"), class = "btn-sm"),
              hr(),
              selectInput("sample_sel", tr("data_sample"), NULL),
              selectInput("dataset_sel", tr("data_dataset"), NULL),
              selectInput("normalization", tr("data_norm"), c("NONE"), "NONE"),
              hr(),
              tags$b(tr("data_local_hic")),
              textInput("hic_local", tr("data_hic_path"), ""),
              if (HAS_SHINYFILES)
                shinyFiles::shinyFilesButton("hic_file_btn", tr("data_hic_browse"),
                                             tr("data_hic_browse_title"),
                                             multiple = FALSE, class = "btn-sm"),
              hr(),
              actionButton("open", tr("data_open"), class = "btn-primary btn-block"),
              verbatimTextOutput("status"))),
          tabPanel(tr("nav_tracks"),
            div(style = "padding-top:12px;",
              textInput("trk_xml", tr("trk_xml_url"), value = DEFAULT_TRACKLIST),
              actionButton("trk_xml_load", tr("trk_load"), class = "btn-sm"),
              selectInput("trk_xmlfile", tr("trk_xmlfile"), NULL),
              selectInput("trk_xml_cat", tr("trk_category"), NULL),
              selectInput("trk_xml_sel", tr("trk_from_xml"), NULL),
              hr(),
              textInput("trk_path", tr("trk_or_path"), ""),
              if (HAS_SHINYFILES)
                shinyFiles::shinyFilesButton("trk_file_btn", tr("trk_browse"),
                                             tr("trk_browse_title"),
                                             multiple = FALSE, class = "btn-sm"),
              selectInput("trk_type", tr("trk_type"),
                          setNames(c("bigWig", "BED", "gene", "BorderStrength"),
                                   c("bigWig", "BED", tr("trk_type_gene"), tr("trk_type_bs")))),
              textInput("trk_name", tr("trk_label"), ""),
              tags$label(tr("trk_color")), COLOR_SWATCHES,
              numericInput("trk_height", tr("trk_height"), 90, min = 30, step = 10),
              actionButton("trk_add", tr("trk_add"), class = "btn-sm btn-primary"),
              actionButton("trk_clear", tr("trk_clear"), class = "btn-sm"),
              verbatimTextOutput("trk_status"),
              hr(), uiOutput("trk_list"))),
          # -- save / restore the whole display state as a JSON session file --
          tabPanel(tr("session_tab"),
            div(style = "padding-top:12px;",
              tags$p(tags$small(tr("session_help"))),
              downloadButton("session_save", tr("session_save"), class = "btn-sm btn-primary"),
              hr(),
              fileInput("session_file", tr("session_load"), accept = ".json"))))))),

  sidebarLayout(
    sidebarPanel(width = 3,
      conditionalPanel("input.nav == 'Region'",
        selectInput("chr", tr("region_chr"), c("I", "II", "III"), "II"),
        fluidRow(column(6, numericInput("start", tr("region_ystart"), 1)),
                 column(6, numericInput("end", tr("region_yend"), 1000000))),
        actionButton("goto", tr("region_goto"), class = "btn-sm btn-primary"),
        hr(),
        tags$label(tr("region_nav")),
        # how far each button moves, as a fraction of the visible view
        radioButtons("pan_step", tr("region_step"),
                     choices = setNames(c("0.25", "0.5", "1"), c("¼", "½", "1")),
                     selected = "0.5", inline = TRUE),
        # 8-direction pad incl. diagonals (Hi-C's diagonal runs ↖–↘); the
        # center resets to the whole chromosome. Up/Down move along the Y axis.
        div(class = "pan-pad", style = "max-width:150px; margin:2px 0 8px;",
          div(style = "display:flex; gap:4px; justify-content:center; margin-bottom:4px;",
            actionButton("pan_ul", HTML("&#8598;"), class = "btn-sm", title = tr("region_pan_ul")),
            actionButton("pan_up", HTML("&#9650;"), class = "btn-sm", title = tr("region_pan_up")),
            actionButton("pan_ur", HTML("&#8599;"), class = "btn-sm", title = tr("region_pan_ur"))),
          div(style = "display:flex; gap:4px; justify-content:center; margin-bottom:4px;",
            actionButton("pan_left",   HTML("&#9664;"), class = "btn-sm", title = tr("region_pan_left")),
            actionButton("view_whole", HTML("&#8962;"), class = "btn-sm home", title = tr("region_whole")),
            actionButton("pan_right",  HTML("&#9654;"), class = "btn-sm", title = tr("region_pan_right"))),
          div(style = "display:flex; gap:4px; justify-content:center;",
            actionButton("pan_dl", HTML("&#8601;"), class = "btn-sm", title = tr("region_pan_dl")),
            actionButton("pan_down", HTML("&#9660;"), class = "btn-sm", title = tr("region_pan_down")),
            actionButton("pan_dr", HTML("&#8600;"), class = "btn-sm", title = tr("region_pan_dr")))),
        hr(),
        # bookmarks: star the current view, jump back to it later
        tags$label(tr("bm_title")),
        textInput("bm_name", NULL, placeholder = tr("bm_name_ph")),
        actionButton("bm_add", HTML(paste0("&#9733; ", tr("bm_add"))),
                     class = "btn-sm btn-primary"),
        uiOutput("bookmark_list")),
      conditionalPanel("input.nav == 'Display'",
        tabsetPanel(id = "disp_tab", type = "tabs",
          # -- contact-map display: palette, value scale, map height --
          tabPanel(tr("disp_tab_map"),
            div(style = "padding-top:12px;",
              selectInput("color", tr("disp_palette"), c("matlab", "gentle", "red", "blue")),
              uiOutput("scale_controls"),
              hr(),
              fluidRow(
                column(6, numericInput("map_height", tr("set_map_height"), 720, min = 200, step = 20)),
                column(6, div(style = "margin-top:25px;",
                              actionButton("fit_map", tr("set_fit"), class = "btn-sm")))),
              actionButton("apply_map", tr("set_apply"), class = "btn-sm btn-primary"))),
          # -- track display: resolution + per-track name/color/height/max/agg --
          tabPanel(tr("nav_tracks"),
            div(style = "padding-top:12px;",
              sliderInput("trk_bins", tr("set_trk_res"),
                          min = 100, max = 1000, value = 1000, step = 100),
              uiOutput("track_settings"),
              hr(),
              actionButton("apply_tracks", tr("set_apply"), class = "btn-sm btn-primary"),
              tags$span(" "),
              actionButton("auto_adjust", tr("set_auto"), class = "btn-sm"))))),
      conditionalPanel("input.nav == 'Print'",
        h4(tr("print_title")),
        p(tags$small(tr("print_desc"))),
        actionButton("exp_open", tr("print_open_preview"), class = "btn-primary btn-block"),
        hr(),
        helpText(tr("print_help"))),
      conditionalPanel("input.nav == 'Setting'",
        helpText(tr("set_app_desc")),
        actionButton("cfg_open", tr("cfg_open"), class = "btn-sm btn-block")),
      conditionalPanel("input.nav == 'About'",
        h4("HiCarta"),
        p(tags$small(tr("about_former"))),
        p(sprintf(tr("about_version"), APP_VERSION)),
        p(tr("about_author"), tags$a(href = "mailto:rafysta@gmail.com", "rafysta@gmail.com"), ")"),
        p(tr("about_desc")),
        tags$ul(
          tags$li(tr("about_feat1")),
          tags$li(tr("about_feat2")),
          tags$li(tr("about_feat3")),
          tags$li(tr("about_feat4"))),
        tags$hr(),
        p(tags$small(tr("about_built"))))
    ),
    mainPanel(width = 9,
      # fixed-height info area so the map does not shift when hover text appears
      div(style = "height: 42px; line-height: 1.35; overflow: hidden;",
        strong(textOutput("coord", inline = TRUE)), br(),
        textOutput("hover", inline = TRUE)),
      # map + tracks share one positioned wrapper so a single vertical cursor
      # line can span both. Tracks share the map's x-range; the right 66px gutter
      # mirrors the map's y-ruler so a track's width matches the contact map's.
      div(id = "mapwrap", style = "position: relative;",
        leafletOutput("map", height = "720px"),
        div(style = "position: relative;",
          uiOutput("tracks_ui"),
          div(style = paste0("position:absolute; top:0; right:0; bottom:0; width:66px;",
                             "background:rgba(255,255,255,0.85); border-left:1px solid #ccc;",
                             "pointer-events:none;")))))
  )
  )
}

server <- function(input, output, session) {
  rv <- reactiveValues(menu = NULL, msg = tr("msg_start"),
                       ov = NULL, ov_res = NULL, chr = NULL, chrlen = NULL,
                       tileURL = NULL, tracks = list(), trk_seq = 0, trk_bins = 1000,
                       trk_msg = "", sample_name = NULL, restore_vmax = NULL,
                       bookmarks = list(), bm_seq = 0L,
                       exp_key = NULL, exp_data = NULL, exp_msg = "")
  st <- new.env()   # tile-render state shared with the tile HTTP handler

  # ---- local file pickers (shinyFiles) ----
  # Browses the machine running the app (= the user's own computer for the
  # desktop build). The chosen file's full path fills the matching text box:
  #   .hic  -> Data panel path;   bigWig/BED/GFF3 -> Tracks panel path.
  if (HAS_SHINYFILES) {
    sf_roots <- c(Home = normalizePath("~", winslash = "/", mustWork = FALSE),
                  shinyFiles::getVolumes()())

    shinyFiles::shinyFileChoose(input, "hic_file_btn", roots = sf_roots,
                                filetypes = c("hic"))
    observeEvent(input$hic_file_btn, {
      fp <- tryCatch(shinyFiles::parseFilePaths(sf_roots, input$hic_file_btn),
                     error = function(e) NULL)
      if (!is.null(fp) && nrow(fp) > 0)
        updateTextInput(session, "hic_local", value = as.character(fp$datapath[1]))
    })

    # Tracks: accept bigWig, BED and gene-model extensions (both letter cases).
    trk_ext <- c("bw", "bigwig", "bigWig", "bedgraph", "bedGraph",
                 "bed", "narrowPeak", "narrowpeak", "broadPeak", "broadpeak",
                 "gff", "gff3", "gtf")
    shinyFiles::shinyFileChoose(input, "trk_file_btn", roots = sf_roots,
                                filetypes = trk_ext)
    observeEvent(input$trk_file_btn, {
      fp <- tryCatch(shinyFiles::parseFilePaths(sf_roots, input$trk_file_btn),
                     error = function(e) NULL)
      if (!is.null(fp) && nrow(fp) > 0) {
        path <- as.character(fp$datapath[1])
        updateTextInput(session, "trk_path", value = path)
        # Pre-select the track type from the extension as a convenience.
        ext <- tolower(tools::file_ext(path))
        ty  <- if (ext %in% c("bed", "narrowpeak", "broadpeak")) "BED"
               else if (ext %in% c("gff", "gff3", "gtf")) "gene"
               else "bigWig"   # bw / bigwig / bedgraph = signal
        updateSelectInput(session, "trk_type", selected = ty)
      }
    })
  }

  # ---- menu ----
  observeEvent(input$load_menu, {
    src <- if (!is.null(input$menu_file)) input$menu_file$datapath
           else if (nzchar(input$menu_url)) input$menu_url else NULL
    if (is.null(src)) { rv$msg <- tr("msg_choose_menu"); return() }
    tryCatch({
      lines <- if (grepl("^https?://", src)) readLines(url(src), warn = FALSE) else readLines(src, warn = FALSE)
      m <- parse_juicer_menu(lines); rv$menu <- m
      samp <- unique(m[, c("sample_id", "sample_label")])
      updateSelectInput(session, "sample_sel", choices = setNames(samp$sample_id, samp$sample_label))
      rv$msg <- sprintf(tr("msg_loaded_samp"), nrow(samp))
    }, error = function(e) rv$msg <- sprintf(tr("msg_menu_err"), conditionMessage(e)))
  })
  observeEvent(input$sample_sel, {
    req(rv$menu)
    sub <- rv$menu[rv$menu$sample_id == input$sample_sel, ]
    updateSelectInput(session, "dataset_sel", choices = setNames(sub$url, sub$dataset_label))
  })

  # NOTE: do NOT read .hic metadata over the network here — it blocks the single
  # R thread and made later clicks (Open) unresponsive. Just offer the common
  # normalizations; the true set is read from the LOCAL file on Open.
  observeEvent(input$dataset_sel, {
    path <- input$dataset_sel
    if (is.null(path) || !nzchar(path)) return()
    updateSelectInput(session, "normalization",
                      choices = c("NONE", "KR", "VC", "VC_SQRT"), selected = "NONE")
  }, ignoreInit = TRUE)

  # value-scale controls (global vmin/vmax), seeded from an overview read
  output$scale_controls <- renderUI({
    if (is.null(rv$dmin)) return(helpText(tr("disp_open_first")))
    dmin <- rv$dmin; dmax <- rv$dmax; p99 <- rv$p99
    logmin <- rv$logmin; logmax <- rv$logmax
    steplin <- signif((dmax - dmin) / 200, 2); if (!is.finite(steplin) || steplin <= 0) steplin <- 1
    steplog <- (logmax - logmin) / 200; if (!is.finite(steplog) || steplog <= 0) steplog <- 0.01
    # seed the scale from a restored session value if present, else auto (p99)
    v0 <- if (!is.null(rv$restore_vmax) && is.finite(rv$restore_vmax) && rv$restore_vmax > 0)
            rv$restore_vmax else p99
    lvmax <- if (v0 > 0) log10(v0) else logmin
    tagList(
      tags$label(tr("disp_maxval")),
      sliderInput("vmax", tr("disp_linear"), dmin, dmax, v0, step = steplin),
      sliderInput("vmax_log", tr("disp_log"), logmin, logmax, lvmax, step = steplog),
      numericInput("vmax_num", tr("disp_value"), signif(v0, 4), step = steplin),
      helpText(sprintf(tr("disp_min_fixed"), signif(dmax, 4)))
    )
  })

  # Both sliders feed the numeric box ONE-WAY (linear slider -> numeric,
  # log slider -> numeric). The numeric is never pushed back to the sliders,
  # which avoids the slider<->numeric feedback loop (stepped log values kept
  # bouncing the value). The numeric box is the source of truth for redraw.
  link_sliders <- function(num, lin, lg) {
    observeEvent(input[[lin]], {
      v <- input[[lin]]; if (is.null(v) || is.na(v)) return()
      if (is.null(input[[num]]) || !isTRUE(all.equal(v, input[[num]])))
        updateNumericInput(session, num, value = v)
    }, ignoreInit = TRUE)
    observeEvent(input[[lg]], {
      lv <- input[[lg]]; if (is.null(lv) || is.na(lv)) return()
      updateNumericInput(session, num, value = signif(10^lv, 6))
    }, ignoreInit = TRUE)
  }
  link_sliders("vmax_num", "vmax", "vmax_log")

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(crs = leafletCRS("L.CRS.Simple"),
                                     minZoom = 0, maxZoom = 20)) |>
      setView(0, 0, 0) |>
      onRender(MAP_JS)
  })

  register_tiles <- function() {
    if (!is.null(rv$tileURL)) return(rv$tileURL)
    rv$tileURL <- session$registerDataObj("tiles", st, function(data, req) {
      q <- shiny::parseQueryString(req$QUERY_STRING)
      z <- as.integer(q$z); x <- as.integer(q$x); y <- as.integer(q$y)
      bytes <- tryCatch(
        render_tile(data, z, x, y),
        error = function(e) { message(sprintf("[tile ERROR] z=%s x=%s y=%s : %s", z, x, y, conditionMessage(e))); blank_tile(data) })
      shiny:::httpResponse(200L, "image/png", bytes)
    })
    message("[tiles] registered at URL: ", rv$tileURL)
    rv$tileURL
  }

  # the .hic source: a local file path takes priority, else the menu dataset URL
  current_src <- function() {
    if (!is.null(input$hic_local) && nzchar(input$hic_local)) input$hic_local
    else if (!is.null(input$dataset_sel) && nzchar(input$dataset_sel)) input$dataset_sel
    else NULL
  }

  # Open a .hic and render it. All parameters default to the current inputs, but
  # can be passed explicitly (used by session restore, which must not depend on
  # asynchronous input updates). vmax = NULL means auto-scale (99th percentile).
  do_open <- function(src = current_src(), chr = input$chr,
                      start = input$start, end = input$end,
                      ystart = start, yend = end,
                      norm = input$normalization, color = input$color,
                      vmax = NULL) {
    if (is.null(src)) { rv$msg <- tr("msg_pick_src"); return() }
    tryCatch({
      # remote URLs are downloaded once and read locally; local paths pass through
      withProgress(message = tr("prog_cache_hic"), value = 0.3, {
        path <- tryCatch(hic_local(src),
                         error = function(e) { message("[cache] download failed: ", conditionMessage(e)); src })
      })
      if (!identical(path, src)) message("[cache] using local file: ", path)
      res_all <- sort(strawr::readHicBpResolutions(path))
      chrlen  <- .hic_chrom_length(path, chr)
      # confirm the true normalization list from the local file, keep selection
      norms_local <- tryCatch(strawr::readHicNormTypes(path), error = function(e) NULL)
      if (!is.null(norms_local) && length(norms_local) > 0) {
        sel <- if (!is.null(norm) && norm %in% norms_local) norm else "NONE"
        updateSelectInput(session, "normalization", choices = norms_local, selected = sel)
        norm <- sel
      }
      # overview at a moderate resolution (~400 bins across the chromosome),
      # not the very coarsest — gives a meaningful default scale & hover score.
      ovres <- choose_res(chrlen / 400, res_all)
      withProgress(message = tr("prog_overview"), value = 0.5, {
        rv$ov     <- read_hic_map(path, chr = chr, start = 1, end = NA,
                                  resolution = ovres, normalization = norm)
        rv$ov_res <- ovres
      })
      rv$chr <- chr; rv$chrlen <- chrlen
      rv$open_key <- paste(src, chr)
      # human-readable name of the sample now on screen: local file -> basename;
      # menu dataset -> "sample label / dataset label" looked up in the menu.
      rv$sample_name <- {
        if (!is.null(input$hic_local) && nzchar(input$hic_local)) {
          basename(input$hic_local)
        } else {
          lbl <- NULL
          if (!is.null(rv$menu) && !is.null(input$dataset_sel)) {
            row <- rv$menu[rv$menu$url == input$dataset_sel, ]
            if (nrow(row) > 0)
              lbl <- paste(row$sample_label[1], row$dataset_label[1], sep = " / ")
          }
          if (is.null(lbl)) basename(src) else lbl
        }
      }
      vals <- as.numeric(rv$ov); vals <- vals[is.finite(vals)]
      p99  <- sort(vals)[max(1, round(length(vals) * 0.99))]
      rv$restore_vmax <- vmax     # seeds the value-scale UI (NULL = auto p99)
      rv$dmin <- min(vals); rv$dmax <- max(vals)
      pos <- vals[vals > 0]; rv$dfloor <- if (length(pos)) min(pos) else 1
      rv$p99 <- p99
      rv$logmin <- log10(rv$dfloor); rv$logmax <- log10(max(rv$dmax, rv$dfloor * 10))

      # deep-zoom coordinate system (non-negative zoom, standard slippy tiling)
      baseRes <- min(res_all)
      Nfine   <- ceiling(chrlen / baseRes)                 # finest bins
      maxZoom <- max(1, ceiling(log2(Nfine / TILE_PX)))     # zoom levels 0..maxZoom
      SCALE   <- baseRes * 2^maxZoom                        # bp per map-unit
      Umap    <- chrlen / SCALE                             # chromosome extent in map-units
      rv$scale <- SCALE
      rv$res_all <- res_all; rv$baseRes <- baseRes; rv$maxZoom <- maxZoom

      # fill tile-render state (read by the HTTP handler)
      st$type <- "hic"; st$db <- NULL
      st$path <- path; st$chr <- chr; st$chrlen <- chrlen
      st$res <- res_all; st$norm <- norm
      st$color <- color
      st$baseRes <- baseRes; st$maxZoom <- maxZoom; st$ovres <- ovres
      st$vmin <- 0
      st$vmax <- if (!is.null(vmax) && is.finite(vmax) && vmax > 0) vmax else p99
      st$blank <- NULL

      url <- register_tiles()
      mapMaxZoom <- maxZoom + 6      # allow zooming in past the finest tiles (upscaled)
      ver <- as.numeric(Sys.time())  # cache-buster so re-Open replaces old tiles
      message(sprintf("[open] chr=%s chrlen=%d baseRes=%d maxZoom=%d mapMaxZoom=%d SCALE=%g U=%g",
                      chr, chrlen, baseRes, maxZoom, mapMaxZoom, SCALE, Umap))
      fx0 <- max(1, start);  fx1 <- min(chrlen, end)
      fy0 <- max(1, ystart); fy1 <- min(chrlen, yend)
      session$sendCustomMessage("initTiles", list(
        url = url, scale = SCALE, U = Umap, maxZoom = maxZoom, mapMaxZoom = mapMaxZoom,
        ver = ver, chrlen = chrlen, fx0 = fx0, fy0 = fy0, fx1 = fx1, fy1 = fy1))
      rv$msg <- sprintf(tr("msg_ready"),
                        chr, format(chrlen, big.mark = ","),
                        paste(res_all, collapse = "/"))
      session$sendCustomMessage("closeLoader", list())   # reveal the map
    }, error = function(e) rv$msg <- sprintf(tr("msg_open_err"), conditionMessage(e)))
  }
  observeEvent(input$open, do_open())

  # ---- session save / restore : the whole display state <-> a JSON file ----
  # Captures the data source, current region, display scale and every track so
  # the same view can be reproduced later.
  snapshot_session <- function() {
    v <- input$map_view
    region <- if (!is.null(v))
                list(start = round(max(1, v$west)), end = round(v$east),
                     ystart = round(max(1, v$north)), yend = round(v$south))
              else list(start = input$start, end = input$end)
    tracks <- lapply(unname(rv$tracks), function(t) list(
      path = t$path, type = t$type, name = t$name, color = t$color,
      height = t$height, ymax = if (is.null(t$ymax)) 0 else t$ymax,
      agg = if (is.null(t$agg)) "mean" else t$agg))
    bookmarks <- lapply(unname(rv$bookmarks), function(b) list(
      name = b$name, chr = b$chr, x0 = b$x0, x1 = b$x1, y0 = b$y0, y1 = b$y1))
    list(app = "HiCarta", format = 1L,
         hic = list(src = current_src(), chr = rv$chr, normalization = input$normalization),
         region = region,
         display = list(color = input$color, vmax = input$vmax_num,
                        map_height = input$map_height, trk_bins = rv$trk_bins),
         tracks = tracks, bookmarks = bookmarks)
  }

  output$session_save <- downloadHandler(
    filename = function() sprintf("HiCarta_session_%s.json", format(Sys.time(), "%Y%m%d_%H%M%S")),
    content  = function(file) {
      writeLines(jsonlite::toJSON(snapshot_session(), auto_unbox = TRUE, pretty = TRUE,
                                  null = "null", na = "null"), file)
    }
  )

  observeEvent(input$session_file, {
    f <- input$session_file
    if (is.null(f) || is.null(f$datapath)) return()
    sess <- tryCatch(jsonlite::fromJSON(f$datapath, simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(sess) || !identical(sess$app, "HiCarta")) {
      rv$trk_msg <- tr("msg_session_bad"); rv$msg <- tr("msg_session_bad"); return()
    }
    hic <- sess$hic %||% list(); reg <- sess$region %||% list(); d <- sess$display %||% list()
    if (is.null(hic$src) || !nzchar(hic$src)) { rv$msg <- tr("msg_session_bad"); return() }

    # rebuild tracks
    tl <- list(); n <- 0L
    for (t in (sess$tracks %||% list())) {
      n <- n + 1L
      tl[[as.character(n)]] <- list(id = n, name = t$name %||% basename(t$path %||% "track"),
        path = t$path, type = t$type %||% "bigWig", color = t$color %||% "darkblue",
        height = t$height %||% 90, ymax = t$ymax %||% 0, agg = t$agg %||% "mean")
    }
    rv$trk_seq <- n; rv$tracks <- tl

    # rebuild bookmarks
    bl <- list(); bn <- 0L
    for (b in (sess$bookmarks %||% list())) {
      bn <- bn + 1L
      bl[[as.character(bn)]] <- list(id = bn, name = b$name %||% sprintf("bm%d", bn),
        chr = b$chr, x0 = b$x0, x1 = b$x1, y0 = b$y0, y1 = b$y1)
    }
    rv$bm_seq <- bn; rv$bookmarks <- bl

    # reflect state in the widgets (for later manual editing)
    updateTextInput(session, "hic_local", value = hic$src)
    if (!is.null(hic$chr))
      updateSelectInput(session, "chr", choices = unique(c(hic$chr, "I", "II", "III")),
                        selected = hic$chr)
    if (!is.null(reg$start)) updateNumericInput(session, "start", value = reg$start)
    if (!is.null(reg$end))   updateNumericInput(session, "end",   value = reg$end)
    if (!is.null(d$color))   updateSelectInput(session, "color", selected = d$color)
    if (!is.null(d$trk_bins)) {
      rv$trk_bins <- d$trk_bins; updateSliderInput(session, "trk_bins", value = d$trk_bins)
    }
    if (!is.null(d$map_height)) updateNumericInput(session, "map_height", value = d$map_height)

    # open with explicit values so we don't depend on async input updates
    do_open(src = hic$src, chr = hic$chr %||% input$chr,
            start = reg$start %||% 1, end = reg$end %||% 1e12,
            ystart = reg$ystart %||% reg$start %||% 1,
            yend = reg$yend %||% reg$end %||% 1e12,
            norm = hic$normalization %||% "NONE",
            color = d$color %||% input$color, vmax = d$vmax)
    if (!is.null(d$map_height))
      session$sendCustomMessage("setMapHeight", list(h = d$map_height))
    rv$trk_msg <- tr("msg_session_loaded")
  })

  # per-track display controls (Display panel -> Tracks tab): name, colour,
  # height, max value and (bigWig) aggregation. Committed by "Apply".
  output$track_settings <- renderUI({
    if (length(rv$tracks) == 0) return(helpText(tr("set_no_trk_size")))
    do.call(tagList, lapply(rv$tracks, function(t) tagList(
      tags$hr(),
      tags$b(sprintf("%s  [%s]", t$name, t$type)),
      textInput(paste0("trk_nm_", t$id), tr("trk_label"), t$name),
      fluidRow(
        column(6, selectInput(paste0("trk_col_", t$id), tr("trk_color"),
                              choices = TRK_COLORS,
                              selected = if (is.null(t$color)) "darkblue" else t$color)),
        column(6, numericInput(paste0("trk_h_", t$id), tr("set_height"), t$height, min = 30, step = 10))),
      fluidRow(
        column(6, numericInput(paste0("trk_max_", t$id), tr("set_max_auto"),
                               if (is.null(t$ymax)) 0 else t$ymax, min = 0)),
        column(6, if (identical(t$type, "bigWig"))
          selectInput(paste0("trk_agg_", t$id), tr("set_agg"),
                      choices = setNames(c("mean", "max"),
                                         c(tr("set_agg_mean"), tr("set_agg_max"))),
                      selected = if (is.null(t$agg)) "mean" else t$agg))))))
  })

  # Display > Map tab: apply the contact-map height.
  observeEvent(input$apply_map, {
    h <- input$map_height
    if (is.null(h) || is.na(h) || h < 100) h <- 720
    session$sendCustomMessage("setMapHeight", list(h = h))
  })

  # Display > Tracks tab: apply track resolution + per-track name/colour/height/
  # max/aggregation.
  observeEvent(input$apply_tracks, {
    rv$trk_bins <- if (is.null(input$trk_bins) || is.na(input$trk_bins)) 1000 else input$trk_bins
    if (length(rv$tracks) > 0) {
      tl <- rv$tracks
      for (t in tl) {
        k <- as.character(t$id)
        nv <- input[[paste0("trk_nm_", t$id)]]
        if (!is.null(nv) && nzchar(nv)) tl[[k]]$name <- nv
        cv <- input[[paste0("trk_col_", t$id)]]
        if (!is.null(cv) && nzchar(cv)) tl[[k]]$color <- cv
        hv <- input[[paste0("trk_h_", t$id)]]
        if (!is.null(hv) && !is.na(hv) && hv >= 20) tl[[k]]$height <- hv
        mv <- input[[paste0("trk_max_", t$id)]]
        if (!is.null(mv) && !is.na(mv)) tl[[k]]$ymax <- mv
        av <- input[[paste0("trk_agg_", t$id)]]
        if (!is.null(av) && av %in% c("mean", "max")) tl[[k]]$agg <- av
      }
      rv$tracks <- tl
    }
  })

  # Fit to window: contact map = window height minus all tracks (heights unchanged)
  observeEvent(input$fit_map, {
    tot <- if (length(rv$tracks) > 0)
             sum(vapply(rv$tracks, function(t) as.numeric(t$height) + 6, numeric(1))) else 0
    session$sendCustomMessage("fitMap", list(tracksTotal = tot))
  })

  # Auto adjust: each track ~70px, contact map fills the rest of the window
  observeEvent(input$auto_adjust, {
    if (length(rv$tracks) > 0) {
      tl <- rv$tracks
      for (k in names(tl)) tl[[k]]$height <- 70
      rv$tracks <- tl
    }
    session$sendCustomMessage("autoAdjust", list(ntracks = length(rv$tracks), perTrack = 70))
  })
  observeEvent(input$auto_map_height, {
    if (!is.null(input$auto_map_height))
      updateNumericInput(session, "map_height", value = input$auto_map_height)
  })

  # ---------------- config.txt dialog (view / edit / restart) ----------------
  cfg_path <- file.path(getwd(), "config.txt")

  # Build the modal from the CURRENT on-disk config each time it opens.
  observeEvent(input$cfg_open, {
    cur     <- read_config(cfg_path)
    cur_get <- function(k, d = "") if (!is.null(cur[[k]])) cur[[k]] else d
    raw     <- if (file.exists(cfg_path))
                 paste(readLines(cfg_path, warn = FALSE), collapse = "\n") else ""
    lang    <- tolower(cur_get("language", "en"))
    langs   <- names(LANG_STRINGS)
    labels  <- ifelse(langs == "en", "English",
               ifelse(langs == "ja", "日本語 / Japanese", langs))
    showModal(modalDialog(
      title     = tr("cfg_title"),
      easyClose = TRUE,
      p(tags$small(tr("cfg_intro"))),
      selectInput("cfg_language", tr("cfg_language"),
                  choices  = setNames(langs, labels),
                  selected = if (lang %in% langs) lang else "en"),
      textInput("cfg_menu_url",  tr("cfg_menu_url"),  value = cur_get("menu_url")),
      textInput("cfg_tracklist", tr("cfg_tracklist"), value = cur_get("track_list_url")),
      tags$label(tr("cfg_raw")),
      tags$pre(style = "max-height:180px;overflow:auto;background:#f7f7f7;padding:8px;", raw),
      footer = tagList(
        actionButton("cfg_apply",    tr("cfg_apply"),    class = "btn-primary"),
        actionButton("cfg_openfile", tr("cfg_openfile")),
        modalButton(tr("cfg_close")))))
  })

  # Open config.txt in the user's default editor (local app, so this is fine).
  observeEvent(input$cfg_openfile, {
    tryCatch({
      if (.Platform$OS.type == "windows")
        shell.exec(normalizePath(cfg_path, winslash = "\\", mustWork = FALSE))
      else
        system(paste(if (Sys.info()[["sysname"]] == "Darwin") "open" else "xdg-open",
                     shQuote(cfg_path)), wait = FALSE)
    }, error = function(e)
      showNotification(sprintf(tr("cfg_openfile_err"), conditionMessage(e)),
                       type = "error", duration = NULL))
  })

  save_cfg_now <- function() write_config(cfg_path, list(
    language       = input$cfg_language,
    menu_url       = input$cfg_menu_url,
    track_list_url = input$cfg_tracklist))

  # Apply & save: write config.txt, then reload the page. Because the UI is a
  # per-request function that re-reads config.txt and re-sets the language on
  # each load, session$reload() makes the new language and default URLs take
  # effect immediately — no OS process restart, no port juggling.
  observeEvent(input$cfg_apply, {
    res <- tryCatch({ save_cfg_now(); TRUE }, error = function(e) conditionMessage(e))
    if (isTRUE(res)) {
      showNotification(tr("cfg_saved"), type = "message", duration = 2)
      removeModal()
      session$reload()
    } else {
      showNotification(res, type = "error", duration = NULL)
    }
  })

  # Go to region: if the dataset/chromosome changed, re-open (rebuilds the tile
  # coordinate system for that chromosome); otherwise just pan/zoom the current
  # map to Start–End without reloading.
  observeEvent(input$goto, {
    src <- current_src()
    if (is.null(src)) { rv$msg <- tr("msg_pick_src"); return() }
    if (is.null(rv$open_key) || !identical(rv$open_key, paste(src, input$chr))) {
      do_open()   # different chromosome or dataset -> full open (fits to region)
    } else {
      session$sendCustomMessage("gotoRegion", list(
        scale = rv$scale, fx0 = max(1, input$start), fx1 = min(rv$chrlen, input$end)))
    }
  })

  # 8-direction pan (dx,dy in {-1,0,1}) scaled by the chosen step fraction, plus
  # a center reset to the whole chromosome. All no-ops until a map is loaded.
  pan <- function(dx, dy) {
    if (is.null(rv$chr)) return()
    step <- suppressWarnings(as.numeric(input$pan_step))
    if (is.na(step) || step <= 0) step <- 0.5
    session$sendCustomMessage("panView", list(fx = dx * step, fy = dy * step))
  }
  observeEvent(input$pan_left,  pan(-1, 0))
  observeEvent(input$pan_right, pan( 1, 0))
  observeEvent(input$pan_up,    pan(0, -1))
  observeEvent(input$pan_down,  pan(0,  1))
  observeEvent(input$pan_ul,    pan(-1, -1))
  observeEvent(input$pan_ur,    pan( 1, -1))
  observeEvent(input$pan_dl,    pan(-1,  1))
  observeEvent(input$pan_dr,    pan( 1,  1))
  observeEvent(input$view_whole, {
    if (is.null(rv$chrlen)) return()
    session$sendCustomMessage("viewWhole", list(chrlen = rv$chrlen))
  })

  # ---- bookmarks : star the current view, jump back to it later ----
  observeEvent(input$bm_add, {
    if (is.null(rv$chr)) { rv$msg <- tr("msg_need_hic_first"); return() }
    v <- input$map_view; if (is.null(v)) return()
    x0 <- round(max(1, v$west)); x1 <- round(v$east)
    y0 <- round(max(1, v$north)); y1 <- round(v$south)
    rv$bm_seq <- rv$bm_seq + 1L; id <- rv$bm_seq
    nm <- if (!is.null(input$bm_name) && nzchar(input$bm_name)) input$bm_name
          else sprintf("%s:%s-%s", rv$chr, format(x0, big.mark = ","), format(x1, big.mark = ","))
    rv$bookmarks[[as.character(id)]] <-
      list(id = id, name = nm, chr = rv$chr, x0 = x0, x1 = x1, y0 = y0, y1 = y1)
    updateTextInput(session, "bm_name", value = "")
  })

  # click a bookmark: same chromosome -> smooth pan; different -> re-open there
  observeEvent(input$bm_goto, {
    b <- rv$bookmarks[[as.character(input$bm_goto)]]
    if (is.null(b)) return()
    if (!is.null(rv$chr) && identical(b$chr, rv$chr))
      session$sendCustomMessage("gotoView", list(x0 = b$x0, x1 = b$x1, y0 = b$y0, y1 = b$y1))
    else
      do_open(chr = b$chr, start = b$x0, end = b$x1, ystart = b$y0, yend = b$y1)
  })
  observeEvent(input$bm_del, { rv$bookmarks[[as.character(input$bm_del)]] <- NULL })

  output$bookmark_list <- renderUI({
    if (length(rv$bookmarks) == 0) return(helpText(tr("bm_none")))
    do.call(tagList, lapply(rv$bookmarks, function(b)
      div(style = "display:flex; align-items:center; gap:4px; margin-bottom:3px;",
        tags$button(type = "button", class = "btn btn-sm btn-default",
          style = paste0("flex:1; text-align:left; overflow:hidden;",
                         "text-overflow:ellipsis; white-space:nowrap;"),
          title = b$name,
          onclick = sprintf("Shiny.setInputValue('bm_goto','%s',{priority:'event'});", b$id),
          b$name),
        tags$button(type = "button", class = "btn btn-sm", title = tr("bm_delete"),
          onclick = sprintf("Shiny.setInputValue('bm_del','%s',{priority:'event'});", b$id),
          HTML("&#10005;")))))
  })

  # display changes -> update state and redraw tiles (no re-open needed)
  observeEvent(list(input$color, input$vmax_num), {
    if (is.null(rv$chrlen)) return()
    st$color <- input$color
    st$vmin <- 0                       # Min fixed at 0
    if (!is.null(input$vmax_num) && !is.na(input$vmax_num)) st$vmax <- input$vmax_num
    session$sendCustomMessage("redrawTiles", list(ver = as.numeric(Sys.time())))
  }, ignoreInit = TRUE)

  # view coordinate readout
  output$coord <- renderText({
    v <- input$map_view; if (is.null(v) || is.null(rv$chr)) return("")
    f <- function(z) format(round(max(1, z)), big.mark = ",", scientific = FALSE)
    resLab <- ""
    if (!is.null(v$zoom) && !is.null(rv$baseRes)) {
      nz  <- max(0, min(round(v$zoom), rv$maxZoom))
      bpp <- rv$baseRes * 2^(rv$maxZoom - nz)
      res <- rv$res_all[which.min(abs(log2(rv$res_all) - log2(bpp)))]
      resLab <- sprintf(tr("coord_res"),
                        if (res >= 1000) paste0(res / 1000, " kb") else paste0(res, " bp"))
    }
    nameLab <- if (!is.null(rv$sample_name) && nzchar(rv$sample_name))
                 paste0(sprintf(tr("coord_sample"), rv$sample_name), "   ") else ""
    paste0(nameLab,
           sprintf(tr("coord_view"), rv$chr, f(v$west), f(v$east),
                   rv$chr, f(v$north), f(v$south), resLab))
  })

  # hover readout (score sampled from the coarse overview; distance is exact)
  output$hover <- renderText({
    h <- input$hover
    if (is.null(h) || is.null(rv$ov) || is.null(rv$chrlen)) return("")
    if (h$x < 1 || h$y < 1 || h$x > rv$chrlen || h$y > rv$chrlen) return(tr("hover_outside"))
    r <- rv$ov_res; nr <- nrow(rv$ov); nc <- ncol(rv$ov)
    ix <- min(nc, floor((h$x - 1) / r) + 1); iy <- min(nr, floor((h$y - 1) / r) + 1)
    score <- rv$ov[iy, ix]
    f <- function(z) format(round(z), big.mark = ",", scientific = FALSE)
    sc <- if (is.na(score)) "NA" else formatC(score, format = "g", digits = 4)
    sprintf(tr("hover_line"),
            rv$chr, f(h$x), rv$chr, f(h$y), sc, f(abs(h$x - h$y)))
  })

  # ---------------- 1-D tracks (bigWig / BED), synced to the map x-range ------
  output$trk_status <- renderText(rv$trk_msg)

  observeEvent(input$trk_add, {
    # tracks are drawn on the Hi-C map's coordinate system, so a map must be
    # loaded first — otherwise the sync/auto-fit runs against an unset view.
    if (is.null(rv$chr)) { rv$trk_msg <- tr("msg_need_hic_first"); return() }
    if (is.null(input$trk_path) || !nzchar(input$trk_path)) {
      rv$trk_msg <- tr("msg_enter_track"); return() }
    withProgress(message = tr("prog_cache_trk"), value = 0.4, {
      lp <- tryCatch(cache_local(input$trk_path),
                     error = function(e) { message("[track] cache failed: ", conditionMessage(e)); input$trk_path })
    })
    rv$trk_seq <- rv$trk_seq + 1L
    id <- rv$trk_seq
    nm <- if (nzchar(input$trk_name)) input$trk_name else tools::file_path_sans_ext(basename(input$trk_path))
    col <- if (is.null(input$trk_color) || !nzchar(input$trk_color)) "darkblue" else input$trk_color
    rv$tracks[[as.character(id)]] <- list(id = id, name = nm, path = lp,
      type = input$trk_type, color = col, height = input$trk_height, ymax = 0,
      agg = "mean")
    if (identical(input$trk_type, "gene"))
      withProgress(message = tr("prog_parse_gff3"), value = 0.5,
                   { tryCatch(read_genes(lp), error = function(e) rv$trk_msg <- sprintf(tr("msg_gff3_err"), conditionMessage(e))) })
    if (identical(input$trk_type, "BorderStrength"))
      withProgress(message = tr("prog_read_bs"), value = 0.5,
                   { tryCatch(read_bs(lp), error = function(e) rv$trk_msg <- sprintf(tr("msg_bs_err"), conditionMessage(e))) })
    rv$trk_msg <- sprintf(tr("msg_added_track"), nm, input$trk_type)
    # Auto Fit to window: resize the contact map so it + all tracks fit the window
    tot <- sum(vapply(rv$tracks, function(t) as.numeric(t$height) + 6, numeric(1)))
    session$sendCustomMessage("fitMap", list(tracksTotal = tot))
  })
  observeEvent(input$trk_clear, { rv$tracks <- list(); rv$trk_msg <- tr("msg_cleared_trk") })

  # parse one IGV XML URL -> populate the Category dropdown
  load_one_xml <- function(url) {
    df <- parse_igv_xml(url); df$idx <- seq_len(nrow(df)); rv$xml_tracks <- df
    cats <- unique(df$category)
    updateSelectInput(session, "trk_xml_cat", choices = cats, selected = cats[1])
    rv$trk_msg <- sprintf(tr("msg_loaded_xml"), basename(url), nrow(df), length(cats))
  }

  # "Load" accepts EITHER a single IGV XML, OR an index file listing XML URLs
  observeEvent(input$trk_xml_load, {
    src <- input$trk_xml
    if (is.null(src) || !nzchar(src)) { rv$trk_msg <- tr("msg_enter_xml"); return() }
    withProgress(message = tr("prog_loading"), value = 0.5, {
      tryCatch({
        con <- if (grepl("^https?://", src)) url(src) else src
        txt <- paste(readLines(con, warn = FALSE), collapse = "\n")
        if (grepl("<Resource", txt)) {                       # a single IGV XML
          urls <- src
        } else {                                             # an index of XML URLs
          urls <- trimws(strsplit(txt, "\n")[[1]])
          urls <- urls[grepl("^https?://", urls) | grepl("\\.xml$", urls)]
        }
        if (length(urls) == 0) { rv$trk_msg <- tr("msg_no_xml"); return() }
        updateSelectInput(session, "trk_xmlfile",
                          choices = setNames(urls, basename(urls)), selected = urls[1])
        rv$trk_msg <- sprintf(tr("msg_loaded_list"), length(urls))
      }, error = function(e) rv$trk_msg <- sprintf(tr("msg_load_err"), conditionMessage(e)))
    })
  })
  observeEvent(input$trk_xmlfile, {
    u <- input$trk_xmlfile
    if (is.null(u) || !nzchar(u)) return()
    withProgress(message = tr("prog_loading_xml"), value = 0.5, {
      tryCatch(load_one_xml(u), error = function(e) rv$trk_msg <- sprintf(tr("msg_xml_err"), conditionMessage(e)))
    })
  }, ignoreInit = TRUE)
  observeEvent(input$trk_xml_cat, {
    df <- rv$xml_tracks; cat <- input$trk_xml_cat
    if (is.null(df) || is.null(cat) || !nzchar(cat)) return()
    d <- df[df$category == cat, ]
    updateSelectInput(session, "trk_xml_sel",
                      choices = setNames(c("", as.character(d$idx)), c(tr("sel_choose"), d$name)))
  }, ignoreInit = TRUE)

  observeEvent(input$trk_xml_sel, {
    df <- rv$xml_tracks; sel <- input$trk_xml_sel
    if (is.null(df) || is.null(sel) || !nzchar(sel)) return()
    i <- suppressWarnings(as.integer(sel))
    if (is.na(i) || i < 1 || i > nrow(df)) return()
    updateTextInput(session, "trk_path", value = df$path[i])
    updateSelectInput(session, "trk_type", selected = df$type[i])
    updateTextInput(session, "trk_name", value = df$name[i])
  }, ignoreInit = TRUE)

  output$trk_list <- renderUI({
    if (length(rv$tracks) == 0) return(helpText(tr("trk_none_added")))
    tags$ul(lapply(rv$tracks, function(t)
      tags$li(sprintf("%s  [%s, %dpx]", t$name, t$type, as.integer(t$height)))))
  })

  output$tracks_ui <- renderUI({
    if (length(rv$tracks) == 0) return(NULL)
    do.call(tagList, lapply(rv$tracks, function(t)
      plotOutput(paste0("trk_plot_", t$id), height = paste0(as.integer(t$height), "px"))))
  })

  # (re)register a synced renderPlot for each track whenever the set changes
  observeEvent(rv$tracks, {
    for (t in rv$tracks) local({
      tt <- t
      output[[paste0("trk_plot_", tt$id)]] <- renderPlot({
        v <- input$map_view; req(v, rv$chr)
        if (identical(tt$type, "gene"))
          plot_gene_track(read_genes(tt$path), rv$chr, v$west, v$east,
                          chrlen = rv$chrlen, name = tt$name, color = tt$color)
        else if (identical(tt$type, "BorderStrength"))
          plot_bs_track(read_bs(tt$path), rv$chr, v$west, v$east,
                        chrlen = rv$chrlen, name = tt$name)
        else
          plot_track(tt, rv$chr, v$west, v$east, chrlen = rv$chrlen, nbins = rv$trk_bins)
      })
    })
  }, ignoreInit = TRUE)

  output$status <- renderText(rv$msg)

  # ---------------- image / print export (Print pill -> modal) ----------------
  # Open the print-preview modal, pre-filled from the current view.
  observeEvent(input$exp_open, {
    if (is.null(st$path)) {
      showNotification(tr("print_need_map"), type = "warning")
      return()
    }
    v <- input$map_view
    cur_chr   <- if (!is.null(rv$chr)) rv$chr else input$chr
    cur_start <- if (!is.null(v)) max(1, round(v$west)) else max(1, input$start)
    cur_end   <- if (!is.null(v)) round(v$east)
                 else if (!is.null(rv$chrlen)) min(rv$chrlen, input$end) else input$end
    if (!is.finite(cur_end) || cur_end <= cur_start)
      cur_end <- if (!is.null(rv$chrlen)) rv$chrlen else cur_start + 1e6
    chr_choices <- tryCatch({
      info <- strawr::readHicChroms(st$path)
      cc <- info$name[!tolower(info$name) %in% c("all", "assembly")]
      if (length(cc)) cc else c("I", "II", "III")
    }, error = function(e) c("I", "II", "III"))
    if (!cur_chr %in% chr_choices) chr_choices <- unique(c(cur_chr, chr_choices))
    def_name <- sprintf("HiCarta_%s_%d-%d", cur_chr, round(cur_start), round(cur_end))

    showModal(modalDialog(
      title = tr("print_preview"), size = "l", easyClose = FALSE,
      fluidRow(
        column(7,
          tags$div(style = "border:1px solid #ddd; padding:4px; background:#fff;",
            uiOutput("exp_preview_ui"))),
        column(5,
          radioButtons("exp_dest", tr("print_dest"),
                       setNames(c("printer", "file"),
                                c(tr("print_dest_printer"), tr("print_dest_file"))),
                       selected = "file", inline = TRUE),
          conditionalPanel("input.exp_dest == 'file'",
            tags$label(tr("print_out_folder"), style = "margin-bottom:4px;"),
            tags$style(HTML(paste0(
              "#exp_folder_row{display:flex; gap:6px; align-items:center;",
              " margin-bottom:10px; width:100%; box-sizing:border-box;}",
              "#exp_folder_row .form-group{margin-bottom:0;}",
              "#exp_folder_row .exp-folder-input{flex:1 1 auto; min-width:0;}",
              "#exp_folder_row .exp-folder-input .form-control{height:34px; width:100%;}",
              "#exp_folder_row .btn{flex:0 0 auto; height:34px; padding:6px 10px;",
              " white-space:nowrap;}"))),
            div(id = "exp_folder_row",
              div(class = "exp-folder-input", textInput("exp_folder", NULL, value = getwd())),
              actionButton("exp_browse", tr("print_browse"))),
            textInput("exp_name", tr("print_filename"), value = def_name),
            radioButtons("exp_fmt", tr("print_format"),
                         setNames(c("pdf", "png"), c("PDF", tr("print_fmt_png"))),
                         selected = "pdf", inline = TRUE)),
          tags$hr(style = "margin:8px 0;"),
          selectInput("exp_paper", tr("print_paper"),
                      setNames(c("a4p", "a4l", "sq", "custom"),
                               c(tr("print_paper_a4p"), tr("print_paper_a4l"),
                                 tr("print_paper_sq"), tr("print_paper_custom"))),
                      selected = "a4p"),
          fluidRow(
            column(6, numericInput("exp_w", tr("print_width"), 210, min = 10, step = 5)),
            column(6, numericInput("exp_h", tr("print_height"), 297, min = 10, step = 5))),
          tags$hr(style = "margin:8px 0;"),
          tags$b(tr("print_region")), tags$small(tr("print_region_note")),
          selectInput("exp_chr", tr("print_chr"), chr_choices, selected = cur_chr),
          fluidRow(
            column(6, numericInput("exp_start", tr("print_start"), round(cur_start), min = 1)),
            column(6, numericInput("exp_end", tr("print_end"), round(cur_end), min = 1))),
          tags$hr(style = "margin:8px 0;"),
          checkboxInput("exp_ticks", tr("print_ticks"), TRUE),
          checkboxInput("exp_legend", tr("print_legend"), TRUE),
          checkboxInput("exp_nomargin", tr("print_nomargin"), FALSE),
          if (length(rv$tracks) > 0)
            checkboxInput("exp_tracks", tr("print_export_trk"), TRUE),
          tags$hr(style = "margin:8px 0;"),
          verbatimTextOutput("exp_status"))),
      footer = tagList(
        actionButton("exp_run", tr("print_run"), class = "btn-primary"),
        modalButton(tr("print_close")))
    ))
    rv$exp_msg <- ""
  })

  # paper preset -> width/height (mm)
  observeEvent(input$exp_paper, {
    wh <- switch(input$exp_paper,
                 a4p = c(210, 297), a4l = c(297, 210), sq = c(210, 210), NULL)
    if (!is.null(wh)) {
      updateNumericInput(session, "exp_w", value = wh[1])
      updateNumericInput(session, "exp_h", value = wh[2])
    }
  }, ignoreInit = TRUE)

  # "参照…" -> native folder chooser -> fill the 出力フォルダ field
  observeEvent(input$exp_browse, {
    start_dir <- if (!is.null(input$exp_folder) && nzchar(input$exp_folder))
                   input$exp_folder else getwd()
    d <- tryCatch(choose_folder_dialog(start_dir), error = function(e) NULL)
    if (!is.null(d) && nzchar(d)) updateTextInput(session, "exp_folder", value = d)
  })

  # region matrix for export: re-read only when chr/start/end change (key-guarded)
  export_mat <- reactive({
    req(input$exp_chr, input$exp_start, input$exp_end)
    if (is.null(st$path)) return(NULL)
    s <- max(1, as.numeric(input$exp_start)); e <- as.numeric(input$exp_end)
    if (!is.finite(s) || !is.finite(e) || e <= s) return(NULL)
    key <- paste(st$path, input$exp_chr, s, e, st$norm)
    if (!identical(rv$exp_key, key)) {
      rv$exp_data <- tryCatch(
        read_export_matrix(st, input$exp_chr, s, e),
        error = function(err) { rv$exp_msg <- sprintf(tr("print_read_err"), conditionMessage(err)); NULL })
      rv$exp_key <- key
    }
    rv$exp_data
  })

  # scaled colour bounds so the export matches the on-screen tiles (which scale
  # the global vmin/vmax by (res/ovres)^2 for the tile's resolution).
  exp_bounds <- function(res) {
    f    <- (res / (st$ovres %||% res))^2
    vmax <- ((if (!is.null(st$vmax)) st$vmax else 1)) * f
    vmin <- ((if (!is.null(st$vmin)) st$vmin else 0)) * f
    list(vmin = vmin, vmax = vmax)
  }

  # Build stackable track closures for the export, drawn over the same x-range
  # [s,e] as the map. Returns list() when tracks are off or none are added.
  build_export_tracks <- function(s, e) {
    if (!isTRUE(input$exp_tracks) || length(rv$tracks) == 0) return(list())
    chr <- input$exp_chr; chrlen <- rv$chrlen; nbins <- rv$trk_bins
    lapply(unname(rv$tracks), function(t) {
      force(t)
      list(height = as.numeric(t$height),
           draw = function(mar) {
             if (identical(t$type, "gene"))
               plot_gene_track(read_genes(t$path), chr, s, e,
                               chrlen = chrlen, name = t$name, color = t$color,
                               mar = mar, frame = FALSE)
             else if (identical(t$type, "BorderStrength"))
               plot_bs_track(read_bs(t$path), chr, s, e,
                             chrlen = chrlen, name = t$name, mar = mar,
                             frame = FALSE, yscale = "axis")
             else
               plot_track(t, chr, s, e, chrlen = chrlen, nbins = nbins,
                          mar = mar, frame = FALSE, yscale = "axis")
           })
    })
  }

  output$exp_preview_ui <- renderUI({
    w <- input$exp_w %||% 210; h <- input$exp_h %||% 297
    ph <- max(220, min(560, round(500 * as.numeric(h) / as.numeric(w))))
    plotOutput("exp_preview", height = paste0(ph, "px"))
  })

  output$exp_preview <- renderPlot({
    d <- export_mat(); req(d)
    b <- exp_bounds(d$res)
    s <- max(1, as.numeric(input$exp_start)); e <- as.numeric(input$exp_end)
    draw_export_map(d$m, input$exp_chr, input$exp_start, input$exp_end,
                    color = st$color %||% input$color, vmin = b$vmin, vmax = b$vmax,
                    ticks = isTRUE(input$exp_ticks), legend = isTRUE(input$exp_legend),
                    no_margin = isTRUE(input$exp_nomargin),
                    tracks = build_export_tracks(s, e),
                    map_weight = input$map_height %||% 720)
  })

  output$exp_status <- renderText(rv$exp_msg)

  observeEvent(input$exp_run, {
    d <- export_mat()
    if (is.null(d)) { rv$exp_msg <- tr("print_check_region"); return() }
    b <- exp_bounds(d$res)
    s <- max(1, as.numeric(input$exp_start)); e <- as.numeric(input$exp_end)
    exp_tracks <- build_export_tracks(s, e)
    mapw <- input$map_height %||% 720
    draw_fn <- function()
      draw_export_map(d$m, input$exp_chr, input$exp_start, input$exp_end,
                      color = st$color %||% input$color, vmin = b$vmin, vmax = b$vmax,
                      ticks = isTRUE(input$exp_ticks), legend = isTRUE(input$exp_legend),
                      no_margin = isTRUE(input$exp_nomargin),
                      tracks = exp_tracks, map_weight = mapw)
    W <- input$exp_w %||% 210; H <- input$exp_h %||% 297

    if (identical(input$exp_dest, "printer")) {
      tryCatch({
        tmp <- tempfile(fileext = ".pdf")
        write_export_file(tmp, "pdf", W, H, draw_fn = draw_fn)
        rv$exp_msg <- print_file(tmp)
      }, error = function(e) rv$exp_msg <- sprintf(tr("print_print_err"), conditionMessage(e)))
    } else {
      folder <- input$exp_folder; if (is.null(folder) || !nzchar(folder)) folder <- getwd()
      if (!dir.exists(folder))
        tryCatch(dir.create(folder, recursive = TRUE, showWarnings = FALSE),
                 error = function(e) NULL)
      fmt  <- input$exp_fmt %||% "pdf"
      ext  <- if (identical(fmt, "pdf")) ".pdf" else ".png"
      name <- input$exp_name; if (is.null(name) || !nzchar(name)) name <- "HiCarta_export"
      if (!grepl(paste0("\\", ext, "$"), tolower(name)))
        name <- paste0(tools::file_path_sans_ext(name), ext)
      file <- file.path(folder, name)
      tryCatch({
        write_export_file(file, fmt, W, H, draw_fn = draw_fn)
        rv$exp_msg <- sprintf(tr("print_saved"), file)
      }, error = function(e) rv$exp_msg <- sprintf(tr("print_save_err"), conditionMessage(e)))
    }
  })
}

shinyApp(ui, server)
