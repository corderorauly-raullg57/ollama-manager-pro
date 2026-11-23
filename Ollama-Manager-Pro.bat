<# :
@echo off
setlocal
title Ollama Manager Pro
set "SELF=%~f0"
set "BATDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Sta -Command "iex ((Get-Content -LiteralPath $env:SELF -Encoding UTF8) -join [char]10)"
echo.
pause
exit /b
#>

# =====================================================================
#  OLLAMA MANAGER PRO  v3.2
#  - NUEVO 3.2: cola persistente (reanuda sola al abrir), pausa/reanudar, ver/ordenar cola,
#    búsqueda en internet (ollama.com + Hugging Face) cuando un modelo no está, límite de
#    velocidad, proxy, notificaciones de Windows, aviso de nueva versión de Ollama, instancia única
#  - NUEVO 3.1: pestaña Imagen (generar y editar, stable-diffusion.cpp + Vulkan),
#    aviso Vulkan para Radeon RX 5000/6000, kit de programación (VS Code / Continue)
#  - Descarga reanudable (cortes de luz / internet) con verificacion SHA-256
#  - Catalogo amplio con uso y fortaleza de cada modelo (+ explorador ollama.com)
#  - Compatibilidad calculada segun el hardware (detectado o introducido a mano)
#  - Repositorio offline: exportar / importar modelos (USB, disco externo)
#  - Verificacion de integridad, busqueda de actualizaciones, reparacion
#  - Log diario + historial (CSV) de todas las operaciones
#  - Ajustes de optimizacion de Ollama, chat de prueba con imagenes y benchmark
# =====================================================================

try { Add-Type -AssemblyName System.Windows.Forms } catch {}
try { Add-Type -AssemblyName System.Drawing } catch {}
try { Add-Type -AssemblyName Microsoft.VisualBasic } catch {}
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$ErrorActionPreference = 'Stop'
$AppName = 'Ollama Manager Pro'
$createdNew = $false
try { $Script:AppMutex = New-Object System.Threading.Mutex($true,'Local\OllamaManagerPro_Instancia',[ref]$createdNew) } catch { $createdNew = $true }
if (-not $createdNew) { [void][System.Windows.Forms.MessageBox]::Show('Ollama Manager Pro ya está abierto. Usa la ventana existente (puede estar minimizada en la barra de tareas).',$AppName,'OK','Information'); return }
$AppVer  = '3.2'

# ---------------- Colores y fuentes ----------------
$Col = @{
  Bg     = [System.Drawing.Color]::FromArgb(15,17,23)
  Panel  = [System.Drawing.Color]::FromArgb(22,25,35)
  Card   = [System.Drawing.Color]::FromArgb(30,34,50)
  CardH  = [System.Drawing.Color]::FromArgb(38,43,66)
  Border = [System.Drawing.Color]::FromArgb(48,54,76)
  Txt    = [System.Drawing.Color]::FromArgb(232,234,242)
  Sub    = [System.Drawing.Color]::FromArgb(150,158,180)
  Acc    = [System.Drawing.Color]::FromArgb(124,92,255)
  AccH   = [System.Drawing.Color]::FromArgb(142,116,255)
  Cyan   = [System.Drawing.Color]::FromArgb(34,211,238)
  Green  = [System.Drawing.Color]::FromArgb(52,211,153)
  Amber  = [System.Drawing.Color]::FromArgb(251,191,36)
  Red    = [System.Drawing.Color]::FromArgb(248,113,113)
  Orange = [System.Drawing.Color]::FromArgb(251,146,60)
  Purple = [System.Drawing.Color]::FromArgb(192,132,252)
  White  = [System.Drawing.Color]::White
}
function Fnt([string]$name,[double]$size,[string]$style){
  if ($style) { return (New-Object System.Drawing.Font($name,$size,[System.Drawing.FontStyle]::$style)) }
  return (New-Object System.Drawing.Font($name,$size))
}
$FNorm = Fnt 'Segoe UI' 9.5
$FBold = Fnt 'Segoe UI' 9.5 'Bold'
$FSm   = Fnt 'Segoe UI' 8.5
$FSmB  = Fnt 'Segoe UI' 8.5 'Bold'
$FH2   = Fnt 'Segoe UI' 11 'Bold'
$FTitle= Fnt 'Segoe UI' 16 'Bold'
$FMono = Fnt 'Consolas' 9

try {
Add-Type -ReferencedAssemblies @('System.Drawing','System.Windows.Forms') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
public class RoundedPanel : Panel {
  public int Radius = 12;
  public Color BorderColor = Color.FromArgb(48,54,76);
  public RoundedPanel(){ SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer,true); ResizeRedraw=true; }
  private GraphicsPath RR(Rectangle r,int rad){
    GraphicsPath p=new GraphicsPath(); int d=rad*2;
    p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90);
    p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90);
    p.CloseFigure(); return p;
  }
  protected override void OnPaint(PaintEventArgs e){
    e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
    Rectangle r=new Rectangle(0,0,Math.Max(1,Width-1),Math.Max(1,Height-1));
    using(GraphicsPath p=RR(r,Radius)){
      using(SolidBrush b=new SolidBrush(BackColor)) e.Graphics.FillPath(b,p);
      using(Pen pn=new Pen(BorderColor,1f)) e.Graphics.DrawPath(pn,p);
    }
  }
}
'@
} catch {}
function New-RP([int]$radius,[System.Drawing.Color]$border){
  try { $p = New-Object RoundedPanel; $p.Radius = $radius; $p.BorderColor = $border; return $p }
  catch { $p = New-Object System.Windows.Forms.Panel; $p.BackColor = $Col.Card; return $p }
}

# =====================================================================
#  CODIGO COMPARTIDO (interfaz + trabajadores en segundo plano)
# =====================================================================
$SharedCode = {
function Human([double]$b){ if ($b -ge 1GB){return ('{0:N2} GB' -f ($b/1GB))} if ($b -ge 1MB){return ('{0:N1} MB' -f ($b/1MB))} if ($b -ge 1KB){return ('{0:N0} KB' -f ($b/1KB))} return ('{0:N0} B' -f $b) }
function SpeedFmt([double]$s){ if ($s -le 0){return '--'} if ($s -ge 1MB){return ('{0:N1} MB/s' -f ($s/1MB))} return ('{0:N0} KB/s' -f ($s/1KB)) }
function EtaSec([double]$s){
  if ($s -le 0 -or [double]::IsInfinity($s) -or [double]::IsNaN($s)) { return '--' }
  if ($s -gt 359999) { return '>99 h' }
  $t = [TimeSpan]::FromSeconds([int]$s)
  if ($t.TotalHours -ge 1) { return ('{0}h {1:D2}m' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
  return ('{0}:{1:D2}' -f $t.Minutes, $t.Seconds)
}
function Fmt-Dur([double]$s){
  if ($s -lt 60) { return ('{0:N0} s' -f $s) }
  $t = [TimeSpan]::FromSeconds([int]$s)
  if ($t.TotalHours -ge 1) { return ('{0}h {1:D2}m' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
  return ('{0}m {1:D2}s' -f $t.Minutes, $t.Seconds)
}
function SizeOf([string]$p){ if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return [int64](Get-Item -LiteralPath $p -Force).Length } return [int64]0 }
function Split-ModelId([string]$id){
  $id = $id.Trim(); $tag = 'latest'; $path = $id
  $ls = $id.LastIndexOf('/'); $co = $id.LastIndexOf(':')
  if ($co -gt $ls) { $path = $id.Substring(0,$co); $tag = $id.Substring($co+1) }
  $parts = $path.Split('/')
  $hst = 'registry.ollama.ai'; $ns = 'library'; $nm = $path
  if ($parts.Count -eq 2) { $ns = $parts[0]; $nm = $parts[1] }
  elseif ($parts.Count -ge 3) { $hst = $parts[0]; $ns = $parts[1]; $nm = ($parts[2..($parts.Count-1)] -join '/') }
  return @{ host=$hst; ns=$ns; name=$nm; tag=$tag }
}
function Join-ModelId([string]$hst,[string]$ns,[string]$nm,[string]$tag){
  if ($hst -eq 'registry.ollama.ai') { if ($ns -eq 'library') { return ('{0}:{1}' -f $nm,$tag) } return ('{0}/{1}:{2}' -f $ns,$nm,$tag) }
  return ('{0}/{1}/{2}:{3}' -f $hst,$ns,$nm,$tag)
}
function Get-RegUrl($p,[string]$defaultReg){ if ($p.host -eq 'registry.ollama.ai') { return $defaultReg } return ('https://' + $p.host) }
function Get-LocalManifestPath([string]$modelsRoot,$p){ return (Join-Path $modelsRoot ('manifests\{0}\{1}\{2}\{3}' -f $p.host,$p.ns,$p.name,$p.tag)) }
function Get-ManifestBlobs($mj){
  $seen = @{}
  if ($mj.config -and $mj.config.digest) { $seen[[string]$mj.config.digest] = $true; @{ digest=[string]$mj.config.digest; size=[int64]$mj.config.size } }
  foreach ($l in @($mj.layers)) { if ($l -and $l.digest -and -not $seen.ContainsKey([string]$l.digest)) { $seen[[string]$l.digest] = $true; @{ digest=[string]$l.digest; size=[int64]$l.size } } }
}
function Get-RegistryManifest([string]$curl,[string]$defaultReg,[string]$id,[string]$outFile){
  $p = Split-ModelId $id; $reg = Get-RegUrl $p $defaultReg
  $acc = 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
  $tmp = $outFile + '.tmp'
  $url = '{0}/v2/{1}/{2}/manifests/{3}' -f $reg,$p.ns,$p.name,$p.tag
  $code = [string](& $curl @CurlX -s -L --connect-timeout 20 --max-time 120 -H $acc -o $tmp -w '%{http_code}' $url)
  if ($code -ne '200') { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; return $code }
  $mj = [IO.File]::ReadAllText($tmp) | ConvertFrom-Json
  if ($mj.manifests) {
    $pick = $null
    foreach ($m in @($mj.manifests)) {
      $os = ''; if ($m.platform) { $os = [string]$m.platform.os }
      if ($os -eq 'darwin' -or ([string]$m.mediaType) -match 'mlx') { continue }
      $pick = $m; break
    }
    if (-not $pick) { $pick = @($mj.manifests)[0] }
    $url2 = '{0}/v2/{1}/{2}/manifests/{3}' -f $reg,$p.ns,$p.name,$pick.digest
    $code = [string](& $curl @CurlX -s -L --connect-timeout 20 --max-time 120 -H $acc -o $tmp -w '%{http_code}' $url2)
    if ($code -ne '200') { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; return $code }
  }
  Move-Item -LiteralPath $tmp -Destination $outFile -Force
  return '200'
}
function Get-ManifestMap([string]$modelsRoot){
  $map = @{}; $root = Join-Path $modelsRoot 'manifests'
  if (-not (Test-Path -LiteralPath $root)) { return $map }
  foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    try {
      $rel = $f.FullName.Substring($root.Length).TrimStart('\'); $pp = $rel.Split('\')
      if ($pp.Count -ne 4) { continue }
      if ($pp[3] -match '\.(tmp|part)$') { continue }
      $id = Join-ModelId $pp[0] $pp[1] $pp[2] $pp[3]
      $mj = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
      $bl = @(Get-ManifestBlobs $mj); [int64]$sz = 0; $dg = @()
      foreach ($b in $bl) { $sz += $b.size; $dg += $b.digest }
      $map[$id] = @{ bytes=$sz; date=$f.LastWriteTime; path=$f.FullName; digests=$dg; key=((@($dg) | Sort-Object) -join ',') }
    } catch {}
  }
  return $map
}
}
. $SharedCode
$SharedText = $SharedCode.ToString()

# =====================================================================
#  RUTAS, CONFIGURACION, LOG E HISTORIAL
# =====================================================================
$Here = if ($env:BATDIR) { $env:BATDIR.TrimEnd('\') } else { (Get-Location).Path }
$DataDir = Join-Path $Here 'OllamaManager-datos'
try {
  if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
  $probe = Join-Path $DataDir '.w'; [IO.File]::WriteAllText($probe,'1'); Remove-Item -LiteralPath $probe -Force
} catch { $DataDir = Join-Path $env:LOCALAPPDATA 'OllamaManagerPro'; New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
$LogDir      = Join-Path $DataDir 'logs'
$InstDir     = Join-Path $DataDir 'instalador'
$HistFile    = Join-Path $DataDir 'historial.csv'
$CfgFile     = Join-Path $DataDir 'config.json'
$UserCatFile = Join-Path $DataDir 'catalogo-usuario.json'
$SizeFile    = Join-Path $DataDir 'tamanos-verificados.json'
$Base        = Join-Path $Here 'descargas-ollama'
if ($DataDir -like ($env:LOCALAPPDATA + '*')) { $Base = Join-Path $DataDir 'descargas' }
foreach ($d in @($LogDir,$InstDir,$Base)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }

$Script:Cfg = @{ ModelsDir=''; Registry=''; WaitSec=15; RepoExport=''; RepoImport=''; VerifyImport=$true; VerifyExport=$false
  ExpInstaller=$true; ExpApp=$true; AutoRepo=$false; AutoResume=$true; RateKB=0; Proxy=''; Notify=$true; HwManual=$false; MRam=16; MVram=0; MGpuOk=$false; MRamBw=35; MGpuBw=250; Bench=@{} }
function Load-Config {
  if (Test-Path -LiteralPath $CfgFile) { try { $j = Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $Script:Cfg[$p.Name] = $p.Value } } catch {} }
  $bh = @{}; $b = $Script:Cfg.Bench
  if ($b -is [System.Management.Automation.PSCustomObject]) { foreach ($p in $b.PSObject.Properties) { $bh[$p.Name] = [double]$p.Value } } elseif ($b -is [hashtable]) { $bh = $b }
  $Script:Cfg.Bench = $bh
}
function Save-Config { try { ($Script:Cfg | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $CfgFile -Encoding UTF8 } catch {} }
Load-Config
function EnvU([string]$n){ return [string][Environment]::GetEnvironmentVariable($n,'User') }
function Vulkan-On { return ((EnvU 'OLLAMA_VULKAN') -eq '1' -or $env:OLLAMA_VULKAN -eq '1') }

# ---------- Modulo de imagen (stable-diffusion.cpp) ----------
$ImgDir    = Join-Path $DataDir 'imagen'
$ImgMotor  = Join-Path $ImgDir 'motor'
$ImgModels = Join-Path $ImgDir 'modelos'
$ImgOut    = Join-Path $ImgDir 'salidas'
$ImgTmp    = Join-Path $ImgDir 'tmp'
foreach ($d in @($ImgDir,$ImgModels,$ImgOut,$ImgTmp)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }
$ImgPacks = [ordered]@{
  zimage = @{ name='Z-Image Turbo'; approx=6.6; desc='GENERAR imágenes fotorrealistas desde texto en 8 pasos. Licencia Apache 2.0 (uso comercial).'
    files=@( @{ key='diff'; repo='leejet/Z-Image-Turbo-GGUF'; path='z_image_turbo-Q4_K.gguf' },
             @{ key='vae';  repo='Comfy-Org/z_image_turbo'; path='split_files/vae/ae.safetensors'; local='zimage-ae.safetensors' },
             @{ key='llm';  repo='unsloth/Qwen3-4B-Instruct-2507-GGUF'; path='Qwen3-4B-Instruct-2507-Q4_K_M.gguf' } ) }
  klein = @{ name='FLUX.2 Klein 4B'; approx=5.2; desc='GENERAR y EDITAR con instrucciones: cambiar fondo, objetos, texto o estilo de una foto. Apache 2.0.'
    files=@( @{ key='diff'; repo='leejet/FLUX.2-klein-4B-GGUF'; path='flux-2-klein-4b-Q4_0.gguf' },
             @{ key='vae';  repo='Comfy-Org/flux2-klein-4B'; path='split_files/vae/flux2-vae.safetensors'; local='flux2-vae.safetensors' },
             @{ key='llm';  repo='unsloth/Qwen3-4B-GGUF'; path='Qwen3-4B-Q4_K_M.gguf' } ) }
  upscale = @{ name='Real-ESRGAN x4 (ampliar)'; approx=0.02; desc='Amplía el resultado x4. Ideal para ilustración; en fotos puede suavizar detalles.'
    files=@( @{ key='up'; url='https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth'; local='RealESRGAN_x4plus_anime_6B.pth' } ) }
}

function Resolve-ModelsDir {
  if ($Script:Cfg.ModelsDir) { return [string]$Script:Cfg.ModelsDir }
  if ($env:OLLAMA_MODELS) { return $env:OLLAMA_MODELS }
  $u = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS','User'); if ($u) { return $u }
  $m = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS','Machine'); if ($m) { return $m }
  return (Join-Path $env:USERPROFILE '.ollama\models')
}
$Script:Models = Resolve-ModelsDir
function Get-Staging { $par = Split-Path -Path $Script:Models -Parent; if (-not $par) { return (Join-Path $Base 'staging') }; return (Join-Path $par 'manager-staging') }
$Script:Registry = 'https://registry.ollama.ai'
if ($Script:Cfg.Registry) { $Script:Registry = ([string]$Script:Cfg.Registry).TrimEnd('/') } elseif ($env:OLLAMA_REGISTRY) { $Script:Registry = $env:OLLAMA_REGISTRY.TrimEnd('/') }

$curlCmd = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $curlCmd) {
  [System.Windows.Forms.MessageBox]::Show('No se encontro curl.exe. Necesitas Windows 10 (1803+) o Windows 11.',$AppName,'OK','Error') | Out-Null
  return
}
$CurlPath = $curlCmd.Source
$QueueFile = Join-Path $DataDir 'cola-pendiente.json'
function Update-CurlX { $Script:CurlX = @(); if ([string]$Script:Cfg.Proxy) { $Script:CurlX = @('-x',[string]$Script:Cfg.Proxy) } }
Update-CurlX
$Script:OllamaExe = $null
$oc = Get-Command ollama -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($oc) { $Script:OllamaExe = $oc.Source } else { $cand = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'; if (Test-Path -LiteralPath $cand) { $Script:OllamaExe = $cand } }
$OllamaApp = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'

$Script:LogBox = $null
function Write-Log([string]$lvl,[string]$cat,[string]$msg){
  $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $lvl, $cat, $msg
  try { [IO.File]::AppendAllText((Join-Path $LogDir ('ollama-manager_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))), $line + "`r`n", [Text.Encoding]::UTF8) } catch {}
  if ($Script:LogBox) { try { if ($Script:LogBox.TextLength -gt 300000) { $Script:LogBox.Clear() }; $Script:LogBox.AppendText($line + "`r`n") } catch {} }
}
$Script:HistLV = $null
function Add-History([string]$accion,[string]$modelo,[string]$resultado,[double]$bytes,[double]$secs,[string]$detalle){
  $o = [pscustomobject]@{ Fecha=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Accion=$accion; Modelo=$modelo; Resultado=$resultado; Tamano=$(if ($bytes -gt 0) { Human $bytes } else { '' }); Duracion=$(if ($secs -gt 0) { Fmt-Dur $secs } else { '' }); Detalle=$detalle }
  try { $o | Export-Csv -LiteralPath $HistFile -Append -NoTypeInformation -Encoding UTF8 } catch {}
  if ($Script:HistLV) { try { Add-HistRow $o 0 } catch {} }
}

# =====================================================================
#  CATALOGO  (id|categoria|nombre|tipo|params(B)|activos(B)|GB|capacidades|destacado|para que sirve|fortaleza)
#  Capacidades: Chat Codigo Vision Video Audio OCR Razonamiento Herramientas Embeddings Multilingue
#  Los tamanos son aproximados; "Verificar catalogo" los sustituye por los reales del registro.
#  Puedes anadir CUALQUIER modelo de ollama.com con "Buscar en ollama.com" o "Descargar por ID".
# =====================================================================
$CatalogRaw = @'
# ---------- USO GENERAL ----------
qwen3.5:0.8b|General|Qwen3.5 0.8B|Denso multimodal|0.8|0.8|1.3|Chat,Vision,Herramientas,Razonamiento,Multilingue|0|Clasificar textos, respuestas cortas y pruebas en equipos muy modestos.|Ultraligero y aun asi entiende imagenes
qwen3.5:2b|General|Qwen3.5 2B|Denso multimodal|2|2|2.7|Chat,Vision,Herramientas,Razonamiento,Multilingue|0|Asistente ligero que tambien lee capturas e imagenes.|Muy rapido incluso sin GPU
qwen3.5:4b|General|Qwen3.5 4B|Denso multimodal|4|4|3.3|Chat,Vision,Herramientas,Razonamiento,Multilingue|1|Asistente diario: redactar, resumir, traducir y leer capturas.|Gran calidad por GB; cabe en GPUs de 6-8 GB
qwen3.5:9b|General|Qwen3.5 9B|Denso multimodal|9|9|6.6|Chat,Vision,Codigo,Herramientas,Razonamiento,Multilingue|1|Asistente principal de uso general con vision, herramientas y razonamiento.|El mejor equilibrio calidad/velocidad para 8 GB de VRAM
qwen3.5:27b|General|Qwen3.5 27B|Denso multimodal|27|27|17|Chat,Vision,Codigo,Herramientas,Razonamiento,Multilingue|0|Analisis profundo, redaccion larga y documentos complejos.|Calidad alta; necesita mucha memoria
qwen3.5:35b|General|Qwen3.5 35B-A3B|MoE multimodal (3B activos)|35|3|22|Chat,Vision,Codigo,Herramientas,Razonamiento,Multilingue|1|La maxima inteligencia local manteniendo buena velocidad.|MoE: piensa como un modelo grande y corre como uno pequeno
gemma4:e2b|General|Gemma 4 E2B|Multimodal eficiente (2B efectivos)|5|2|4.6|Chat,Vision,Audio,Herramientas,Razonamiento,Multilingue|0|Asistente de Google que entiende texto, imagen y audio en equipos modestos.|Imagen + audio con muy pocos recursos
gemma4:e4b|General|Gemma 4 E4B|Multimodal eficiente (4B efectivos)|8|4|6.6|Chat,Vision,Audio,Herramientas,Razonamiento,Multilingue|1|Asistente multimodal diario: texto, imagenes y audio.|Multimodal completo dentro de una GPU de 8 GB
gemma4:12b|General|Gemma 4 12B|Denso multimodal|12|12|8.0|Chat,Vision,Herramientas,Razonamiento,Multilingue|0|Redaccion de calidad y analisis de imagenes.|Excelente redaccion en espanol
gemma4:26b|General|Gemma 4 26B-A4B|MoE multimodal (4B activos)|26|4|18|Chat,Vision,Codigo,Herramientas,Razonamiento,Multilingue|1|Inteligencia alta con velocidad de modelo pequeno.|MoE eficiente: ideal con 32 GB de RAM
gemma4:31b|General|Gemma 4 31B|Denso multimodal|31|31|20|Chat,Vision,Codigo,Herramientas,Razonamiento,Multilingue|0|Maxima calidad Gemma para tareas exigentes.|Tope de gama de Google en local; lento sin GPU grande
qwen3:4b|General|Qwen3 4B|Denso|4|4|2.5|Chat,Codigo,Herramientas,Razonamiento|0|Chat y codigo basico con modo pensamiento activable.|Rapido y capaz; solo texto
qwen3:8b|General|Qwen3 8B|Denso|8|8|5.2|Chat,Codigo,Herramientas,Razonamiento|0|Asistente de texto general y programacion.|Probado y estable; solo texto
qwen3:14b|General|Qwen3 14B|Denso|14|14|9.3|Chat,Codigo,Herramientas,Razonamiento|0|Texto, logica y codigo de mayor nivel.|Mas inteligente que el 8B; usa GPU + RAM
qwen3:30b|General|Qwen3 30B-A3B|MoE (3B activos)|30|3|19|Chat,Codigo,Herramientas,Razonamiento|0|Texto, codigo y logica con velocidad alta.|MoE de texto muy rapido con 32 GB de RAM
gpt-oss:20b|General|GPT-OSS 20B|MoE (3.6B activos)|21|3.6|14|Chat,Codigo,Herramientas,Razonamiento|1|Razonamiento, agentes y uso de herramientas (modelo abierto de OpenAI).|Esfuerzo de razonamiento ajustable; rapido por ser MoE
llama3.1:8b|General|Llama 3.1 8B|Denso|8|8|4.9|Chat,Herramientas,Multilingue|0|Chat general; compatible con casi todas las apps y tutoriales.|El clasico de Meta, muy soportado
llama3.2:3b|General|Llama 3.2 3B|Denso|3|3|2.0|Chat,Herramientas|0|Chat ligero, resumenes y asistentes rapidos.|Pequeno y veloz
llama3.2:1b|General|Llama 3.2 1B|Denso|1|1|1.3|Chat|0|Tareas simples en equipos sin GPU ni mucha RAM.|Corre practicamente en cualquier PC
mistral:7b|General|Mistral 7B|Denso|7|7|4.4|Chat,Herramientas|0|Chat general y textos cortos.|Ligero y veterano
mistral-nemo:12b|General|Mistral Nemo 12B|Denso|12|12|7.1|Chat,Herramientas,Multilingue|0|Chat multilingue con contexto largo.|Bueno en idiomas europeos
mistral-small3.2:24b|General|Mistral Small 3.2 24B|Denso multimodal|24|24|15|Chat,Vision,Codigo,Herramientas|0|Asistente versatil con vision y llamadas a herramientas.|Muy equilibrado; pesado para 8 GB
ministral-3:3b|General|Ministral 3 3B|Denso multimodal|3|3|3.0|Chat,Vision,Herramientas,Multilingue|0|Asistente compacto de Mistral con vision.|Eficiente para equipos pequenos
ministral-3:8b|General|Ministral 3 8B|Denso multimodal|8|8|6.0|Chat,Vision,Herramientas,Multilingue|0|Asistente de Mistral con vision para uso diario.|Equilibrado y multilingue
ministral-3:14b|General|Ministral 3 14B|Denso multimodal|14|14|9.1|Chat,Vision,Herramientas,Multilingue|0|Mayor calidad Ministral con vision.|Buen nivel en espanol
phi4-mini:3.8b|General|Phi-4 Mini 3.8B|Denso|3.8|3.8|2.5|Chat,Razonamiento,Herramientas|0|Matematicas y logica en equipos pequenos.|Gran razonamiento para su tamano
granite4:3b|General|IBM Granite 4 3B|Hibrido|3|3|2.1|Chat,Herramientas,Multilingue|0|Asistente empresarial: RAG, extraccion y herramientas.|Licencia Apache, orientado a empresa
granite3.3:8b|General|IBM Granite 3.3 8B|Denso|8|8|4.9|Chat,Herramientas,Razonamiento|0|Documentos empresariales, resumen y RAG.|Fiable y bien documentado
cogito:8b|General|Cogito 8B|Denso|8|8|4.9|Chat,Codigo,Herramientas,Razonamiento|0|Asistente hibrido con razonamiento opcional.|Modo pensar / no pensar
smollm2:1.7b|General|SmolLM2 1.7B|Denso|1.7|1.7|1.8|Chat,Herramientas|0|Pruebas, PCs antiguos y tareas muy simples.|Minimo consumo
dolphin3:8b|General|Dolphin 3 8B|Denso|8|8|4.9|Chat,Codigo,Herramientas|0|Asistente que sigue al pie de la letra el prompt de sistema.|Muy obediente y configurable
hermes3:8b|General|Hermes 3 8B|Denso|8|8|4.7|Chat,Herramientas|0|Rol, escritura creativa y agentes.|Buen formato estructurado y rol
aya-expanse:8b|General|Aya Expanse 8B|Denso|8|8|5.1|Chat,Multilingue,Herramientas|0|Chat y traduccion en 23 idiomas.|Fuerte en multilingue
qwen2.5:7b|General|Qwen2.5 7B|Denso|7|7|4.7|Chat,Codigo,Herramientas,Multilingue|0|Chat y salida JSON estructurada; base de muchas apps.|Salida estructurada fiable
olmo-3:7b|General|OLMo 3 7B|Denso|7|7|4.5|Chat,Razonamiento,Herramientas|0|Uso general con un modelo 100% abierto (datos y codigo).|Totalmente abierto y auditable
llama3.3:70b|General|Llama 3.3 70B|Denso|70|70|43|Chat,Herramientas,Multilingue|0|Calidad de modelo grande; requiere 64 GB o mas de memoria.|Muy capaz; solo estaciones potentes
gpt-oss:120b|General|GPT-OSS 120B|MoE (5.1B activos)|117|5.1|65|Chat,Codigo,Herramientas,Razonamiento|0|Servidores o estaciones con 80 GB o mas de memoria.|Nivel muy alto; enorme
qwen3.5:122b|General|Qwen3.5 122B-A10B|MoE multimodal (10B activos)|122|10|81|Chat,Vision,Codigo,Herramientas,Razonamiento,Multilingue|0|Servidores con mucha memoria.|Calidad de frontera en local
# ---------- VISION (analizar imagenes / video / documentos) ----------
qwen3-vl:2b|Vision|Qwen3-VL 2B|Denso + vision|2|2|1.9|Vision,Video,OCR,Chat,Herramientas|0|Describir imagenes y leer texto en capturas con muy pocos recursos.|Vision ultraligera
qwen3-vl:4b|Vision|Qwen3-VL 4B|Denso + vision|4|4|3.3|Vision,Video,OCR,Chat,Codigo,Herramientas|1|Analizar imagenes y video; generar HTML a partir de una captura.|Vision rapida; cabe en tu GPU
qwen3-vl:8b|Vision|Qwen3-VL 8B|Denso + vision|8|8|6.1|Vision,Video,OCR,Chat,Codigo,Herramientas,Razonamiento|1|Analisis de imagenes, video, documentos y diagramas.|La mejor vision para 8 GB de VRAM
qwen3-vl:30b|Vision|Qwen3-VL 30B-A3B|MoE + vision (3B activos)|30|3|20|Vision,Video,OCR,Chat,Codigo,Herramientas,Razonamiento|0|Vision profunda: graficos, planos, documentos largos.|Vision de maxima calidad con velocidad MoE
qwen3-vl:32b|Vision|Qwen3-VL 32B|Denso + vision|32|32|21|Vision,Video,OCR,Chat,Codigo,Razonamiento|0|Vision densa de maxima precision.|Precision alta; lento sin GPU grande
qwen2.5vl:3b|Vision|Qwen2.5-VL 3B|Denso + vision|3|3|3.2|Vision,OCR,Chat|0|OCR de documentos y facturas en equipos modestos.|OCR ligero
qwen2.5vl:7b|Vision|Qwen2.5-VL 7B|Denso + vision|7|7|6.0|Vision,Video,OCR,Chat|1|Leer documentos, tablas y analizar videos largos.|OCR y documentos muy solidos
gemma3:4b|Vision|Gemma 3 4B|Denso + vision|4|4|3.3|Vision,Chat,Multilingue|0|Describir imagenes y conversar en muchos idiomas.|Ligero y multilingue
gemma3:12b|Vision|Gemma 3 12B|Denso + vision|12|12|8.1|Vision,Chat,Multilingue|0|Vision y redaccion de calidad.|Muy buena redaccion
gemma3:27b|Vision|Gemma 3 27B|Denso + vision|27|27|17|Vision,Chat,Multilingue|0|Maxima calidad Gemma 3.|Vision y texto excelentes; lento
gemma3n:e4b|Vision|Gemma 3n E4B|Multimodal movil|8|4|7.5|Vision,Chat,Multilingue|0|Multimodal disenado para equipos modestos.|Eficiente en memoria
llama3.2-vision:11b|Vision|Llama 3.2 Vision 11B|Denso + vision|11|11|7.8|Vision,Chat|0|Preguntas sobre imagenes, graficos y capturas.|Vision de Meta bien soportada
minicpm-v:8b|Vision|MiniCPM-V 8B|Denso + vision|8|8|5.5|Vision,Video,OCR,Chat|0|Imagenes, video y OCR en formato compacto.|Buen nivel en poco peso
llava:7b|Vision|LLaVA 7B|Denso + vision|7|7|4.7|Vision,Chat|0|Conversar sobre imagenes (clasico).|Muy compatible con apps antiguas
llava:13b|Vision|LLaVA 13B|Denso + vision|13|13|8.0|Vision,Chat|0|Imagenes mas complejas que el 7B.|Mejor comprension visual
llava-llama3:8b|Vision|LLaVA Llama3 8B|Denso + vision|8|8|5.5|Vision,Chat|0|LLaVA con base Llama 3.|Mejor que LLaVA original
llava-phi3:3.8b|Vision|LLaVA-Phi3 3.8B|Denso + vision|3.8|3.8|2.9|Vision,Chat|0|Vision ligera y rapida.|Rapido en equipos modestos
bakllava:7b|Vision|BakLLaVA 7B|Denso + vision|7|7|4.7|Vision,Chat|0|LLaVA con base Mistral.|Razona algo mejor sobre imagenes
moondream:1.8b|Vision|Moondream 1.8B|Denso + vision|1.8|1.8|1.7|Vision,Chat|1|Respuestas instantaneas sobre imagenes; ideal sin GPU.|El mas rapido analizando imagenes
granite3.2-vision:2b|Vision|Granite 3.2 Vision 2B|Denso + vision|2|2|2.4|Vision,OCR,Chat,Herramientas|0|Extraer datos de documentos, tablas y graficos.|Especialista en documentos
deepseek-ocr:3b|Vision|DeepSeek-OCR 3B|OCR multimodal|3|3|6.7|Vision,OCR|0|Convertir documentos escaneados e imagenes a texto/Markdown.|OCR de alta precision
glm-ocr:latest|Vision|GLM-OCR|OCR multimodal|1|1|2.2|Vision,OCR,Herramientas|0|Reconocimiento de texto en imagenes y PDFs escaneados.|OCR moderno y ligero
# ---------- PROGRAMACION ----------
qwen3-coder:30b|Codigo|Qwen3 Coder 30B-A3B|MoE (3B activos)|30|3|19|Codigo,Herramientas|1|Programar, revisar repositorios y agentes de codigo.|El mejor para programar en un PC de 32 GB
qwen2.5-coder:1.5b|Codigo|Qwen2.5 Coder 1.5B|Denso|1.5|1.5|1.0|Codigo|0|Autocompletado de codigo en el editor (Continue, etc.).|Latencia minima para autocompletar
qwen2.5-coder:3b|Codigo|Qwen2.5 Coder 3B|Denso|3|3|1.9|Codigo|0|Autocompletado y fragmentos cortos.|Rapido y preciso para completar
qwen2.5-coder:7b|Codigo|Qwen2.5 Coder 7B|Denso|7|7|4.7|Codigo,Herramientas|1|Generar, explicar y revisar codigo.|Especialista en codigo dentro de la GPU
qwen2.5-coder:14b|Codigo|Qwen2.5 Coder 14B|Denso|14|14|9.0|Codigo,Herramientas|0|Programacion de mayor nivel.|Mas preciso que el 7B
qwen2.5-coder:32b|Codigo|Qwen2.5 Coder 32B|Denso|32|32|20|Codigo,Herramientas|0|Codigo de calidad profesional.|Muy preciso; lento sin GPU grande
devstral:24b|Codigo|Devstral 24B|Denso|24|24|14|Codigo,Herramientas|0|Agentes de ingenieria de software (editar proyectos completos).|Disenado para agentes de codigo
devstral-small-2:24b|Codigo|Devstral Small 2 24B|Denso multimodal|24|24|15|Codigo,Vision,Herramientas|0|Agente de codigo que tambien entiende capturas.|Agente + vision
deepseek-coder-v2:16b|Codigo|DeepSeek Coder V2 16B|MoE (2.4B activos)|16|2.4|8.9|Codigo|0|Codigo en muchos lenguajes con buena velocidad.|MoE rapido para codigo
codellama:7b|Codigo|Code Llama 7B|Denso|7|7|3.8|Codigo|0|Codigo clasico y relleno (fill-in-the-middle).|Muy compatible
starcoder2:3b|Codigo|StarCoder2 3B|Denso|3|3|1.7|Codigo|0|Autocompletado en 600+ lenguajes.|Ligero para autocompletar
starcoder2:7b|Codigo|StarCoder2 7B|Denso|7|7|4.0|Codigo|0|Autocompletado de mayor calidad.|Amplia cobertura de lenguajes
codegemma:7b|Codigo|CodeGemma 7B|Denso|7|7|5.0|Codigo|0|Completar y generar codigo.|Bueno en Python y JS
deepcoder:14b|Codigo|DeepCoder 14B|Denso|14|14|9.0|Codigo,Razonamiento|0|Resolver problemas de programacion paso a paso.|Razonamiento aplicado al codigo
opencoder:8b|Codigo|OpenCoder 8B|Denso|8|8|4.7|Codigo|0|Codigo con modelo totalmente abierto.|Transparente y reproducible
sqlcoder:7b|Codigo|SQLCoder 7B|Denso|7|7|4.1|Codigo|0|Convertir preguntas en consultas SQL.|Especialista en SQL
granite-code:8b|Codigo|Granite Code 8B|Denso|8|8|4.6|Codigo|0|Codigo empresarial (IBM).|Licencia permisiva
yi-coder:9b|Codigo|Yi-Coder 9B|Denso|9|9|5.0|Codigo|0|Codigo con contexto largo.|Bueno leyendo archivos grandes
# ---------- RAZONAMIENTO / MATEMATICAS ----------
deepseek-r1:1.5b|Razonamiento|DeepSeek R1 1.5B|Destilado|1.5|1.5|1.1|Razonamiento|0|Razonamiento paso a paso en equipos minimos.|Muestra su cadena de pensamiento
deepseek-r1:7b|Razonamiento|DeepSeek R1 7B|Destilado|7|7|4.7|Razonamiento,Codigo|0|Logica y matematicas paso a paso.|Razonamiento visible
deepseek-r1:8b|Razonamiento|DeepSeek R1 8B|Destilado|8|8|5.2|Razonamiento,Codigo,Herramientas|1|Logica, matematicas y depuracion razonada.|Razona a velocidad de GPU
deepseek-r1:14b|Razonamiento|DeepSeek R1 14B|Destilado|14|14|9.0|Razonamiento,Codigo,Herramientas|0|Razonamiento mas profundo.|Mejor en problemas largos
deepseek-r1:32b|Razonamiento|DeepSeek R1 32B|Destilado|32|32|20|Razonamiento,Codigo,Herramientas|0|Razonamiento de alto nivel.|Muy capaz; lento
qwq:32b|Razonamiento|QwQ 32B|Denso|32|32|20|Razonamiento,Herramientas|0|Matematicas y logica profunda.|Razonamiento muy profundo
phi4:14b|Razonamiento|Phi-4 14B|Denso|14|14|9.1|Razonamiento,Chat|0|Matematicas, ciencias y logica.|Sobresale en matematicas
phi4-reasoning:14b|Razonamiento|Phi-4 Reasoning 14B|Denso|14|14|11|Razonamiento|0|Problemas complejos de STEM.|Razonamiento entrenado a fondo
phi4-mini-reasoning:3.8b|Razonamiento|Phi-4 Mini Reasoning|Denso|3.8|3.8|3.2|Razonamiento|0|Matematicas en equipos pequenos.|Razonamiento compacto
magistral:24b|Razonamiento|Magistral 24B|Denso|24|24|14|Razonamiento,Herramientas,Multilingue|0|Razonamiento multilingue de Mistral.|Razona bien en espanol
openthinker:7b|Razonamiento|OpenThinker 7B|Destilado|7|7|4.7|Razonamiento|0|Razonamiento abierto de proposito general.|Datos de entrenamiento abiertos
exaone-deep:7.8b|Razonamiento|EXAONE Deep 7.8B|Denso|7.8|7.8|4.8|Razonamiento,Codigo|0|Matematicas y codigo razonados.|Fuerte en matematicas
mathstral:7b|Razonamiento|Mathstral 7B|Denso|7|7|4.1|Razonamiento|0|Matematicas y ciencias.|Especialista matematico
qwen2-math:7b|Razonamiento|Qwen2 Math 7B|Denso|7|7|4.4|Razonamiento|0|Resolver ejercicios de matematicas.|Matematicas competitivas
# ---------- EMBEDDINGS (busqueda semantica / RAG offline) ----------
nomic-embed-text:latest|Embeddings|Nomic Embed Text|Embeddings|0.14|0.14|0.27|Embeddings|1|Indexar tus documentos para buscar por significado (RAG).|Estandar de facto en apps RAG
mxbai-embed-large:335m|Embeddings|MxBai Embed Large|Embeddings|0.34|0.34|0.67|Embeddings|0|Embeddings de alta calidad en ingles.|Muy preciso en busquedas
bge-m3:567m|Embeddings|BGE-M3|Embeddings|0.57|0.57|1.2|Embeddings,Multilingue|1|RAG multilingue: busca en documentos en espanol.|Excelente en espanol y textos largos
embeddinggemma:300m|Embeddings|EmbeddingGemma 300M|Embeddings|0.3|0.3|0.62|Embeddings,Multilingue|0|Embeddings ligeros multilingues de Google.|Pequeno y multilingue
qwen3-embedding:0.6b|Embeddings|Qwen3 Embedding 0.6B|Embeddings|0.6|0.6|0.64|Embeddings,Multilingue|0|Busqueda semantica multilingue ligera.|Gran calidad por tamano
qwen3-embedding:4b|Embeddings|Qwen3 Embedding 4B|Embeddings|4|4|2.5|Embeddings,Multilingue|0|Busqueda semantica de alta precision.|Muy preciso
qwen3-embedding:8b|Embeddings|Qwen3 Embedding 8B|Embeddings|8|8|4.7|Embeddings,Multilingue|0|Embeddings de maxima calidad.|Tope de gama en embeddings
all-minilm:33m|Embeddings|All-MiniLM|Embeddings|0.03|0.03|0.07|Embeddings|0|Embeddings minimos para pruebas o equipos viejos.|Diminuto y rapidisimo
snowflake-arctic-embed2:568m|Embeddings|Arctic Embed 2|Embeddings|0.57|0.57|1.2|Embeddings,Multilingue|0|Busqueda multilingue empresarial.|Robusto en recuperacion
granite-embedding:278m|Embeddings|Granite Embedding 278M|Embeddings|0.28|0.28|0.56|Embeddings,Multilingue|0|Embeddings multilingues de IBM.|Licencia permisiva
paraphrase-multilingual:278m|Embeddings|Paraphrase Multilingual|Embeddings|0.28|0.28|0.56|Embeddings,Multilingue|0|Similitud de frases en 50+ idiomas.|Bueno detectando parafrasis
# ---------- ESPECIALIZADOS ----------
translategemma:4b|Especializado|TranslateGemma 4B|Traduccion|4|4|3.3|Chat,Multilingue,Vision|0|Traducir textos (y texto en imagenes) entre muchos idiomas.|Traduccion offline de calidad
translategemma:12b|Especializado|TranslateGemma 12B|Traduccion|12|12|8.1|Chat,Multilingue,Vision|0|Traduccion profesional offline.|Mayor fidelidad de traduccion
reader-lm:1.5b|Especializado|Reader-LM 1.5B|Conversion|1.5|1.5|0.94|Chat|0|Convertir paginas HTML guardadas a Markdown limpio.|Limpia HTML para RAG
nuextract:3.8b|Especializado|NuExtract 3.8B|Extraccion|3.8|3.8|2.2|Chat|0|Extraer datos de textos a JSON (facturas, contratos).|Extraccion estructurada
bespoke-minicheck:7b|Especializado|Bespoke MiniCheck 7B|Verificacion|7|7|4.7|Chat|0|Comprobar si una afirmacion esta respaldada por un documento.|Reduce alucinaciones en RAG
command-r7b:7b|Especializado|Command R7B|RAG|7|7|5.1|Chat,Herramientas,Multilingue|0|Responder sobre documentos citando fuentes.|RAG con citas
duckdb-nsql:7b|Especializado|DuckDB NSQL 7B|Texto a SQL|7|7|3.8|Codigo|0|Preguntas en lenguaje natural a SQL de DuckDB.|SQL analitico
llama-guard3:1b|Especializado|Llama Guard 3 1B|Moderacion|1|1|1.6|Chat|0|Filtrar contenido inseguro en tus apps.|Moderacion ligera
medgemma:4b|Especializado|MedGemma 4B|Medico multimodal|4|4|3.3|Vision,Chat|0|Investigacion y estudio de textos e imagenes medicas (orientativo).|Especializado en medicina; no sustituye a un profesional
'@

function ConvertTo-HT($o){ $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }; return $h }
function Build-Catalog {
  $list = New-Object System.Collections.ArrayList
  foreach ($line in ($CatalogRaw -split "`n")) {
    $l = $line.Trim(); if (-not $l -or $l.StartsWith('#')) { continue }
    $f = $l.Split('|'); if ($f.Count -lt 11) { continue }
    [void]$list.Add(@{ id=$f[0]; cat=$f[1]; name=$f[2]; kind=$f[3]; p=[double]$f[4]; act=[double]$f[5]; gb=[double]$f[6]
      caps=@($f[7].Split(',') | Where-Object { $_ }); rec=($f[8] -eq '1'); uso=$f[9]; fuerte=$f[10]; user=$false; verified=$false })
  }
  if (Test-Path -LiteralPath $UserCatFile) {
    try {
      foreach ($o in @(Get-Content -LiteralPath $UserCatFile -Raw -Encoding UTF8 | ConvertFrom-Json)) {
        $h = ConvertTo-HT $o; $h.caps = @($h.caps); $h.user = $true; $h.verified = $false
        $dup = $null; foreach ($x in $list) { if ($x.id -eq $h.id) { $dup = $x } }
        if ($dup) { [void]$list.Remove($dup) }
        [void]$list.Add($h)
      }
    } catch {}
  }
  $sizes = @{}
  if (Test-Path -LiteralPath $SizeFile) { try { $sj = Get-Content -LiteralPath $SizeFile -Raw | ConvertFrom-Json; foreach ($p in $sj.PSObject.Properties) { $sizes[$p.Name] = [double]$p.Value } } catch {} }
  $Script:VerSizes = $sizes
  $Script:CatMap = @{}
  foreach ($e in $list) { if ($sizes.ContainsKey($e.id)) { $e.gb = [Math]::Round($sizes[$e.id]/1GB,2); $e.verified = $true }; $Script:CatMap[$e.id] = $e }
  $Script:Catalog = $list
}
function Save-UserCatalog {
  $arr = @(); foreach ($e in $Script:Catalog) { if ($e.user) { $arr += [pscustomobject]@{ id=$e.id; cat=$e.cat; name=$e.name; kind=$e.kind; p=$e.p; act=$e.act; gb=$e.gb; caps=@($e.caps); rec=$false; uso=$e.uso; fuerte=$e.fuerte } } }
  try { (ConvertTo-Json -InputObject @($arr) -Depth 4) | Set-Content -LiteralPath $UserCatFile -Encoding UTF8 } catch {}
}
function Save-VerSizes { try { $o = New-Object PSObject; foreach ($k in $Script:VerSizes.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue ([int64]$Script:VerSizes[$k]) }; ($o | ConvertTo-Json) | Set-Content -LiteralPath $SizeFile -Encoding UTF8 } catch {} }
Build-Catalog

$CapNames = @{ Chat='Chat'; Codigo='Código'; Vision='Visión'; Video='Video'; Audio='Audio'; OCR='OCR'; Razonamiento='Razonamiento'; Herramientas='Herramientas'; Embeddings='Embeddings'; Multilingue='Multilingüe' }
$CatNames = @{ Todas='Todas'; General='General'; Vision='Visión'; Codigo='Código'; Razonamiento='Razonamiento'; Embeddings='Embeddings (RAG)'; Especializado='Especializados'; Personalizado='Añadidos por mí' }

# =====================================================================
#  HARDWARE Y COMPATIBILIDAD
# =====================================================================
function Detect-Hardware {
  $hw = @{ Cpu='Desconocida'; Cores=0; Threads=0; Ram=0.0; Gpu='Ninguna'; Vram=0.0; Vendor=''; GpuOk=$false; Gpus=@(); Disk=0.0; RamBw=35.0; GpuBw=250.0; Integrated=$false; Note=''; Family=''; NeedVulkan=$false }
  try { $p = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1; $hw.Cpu = ([string]$p.Name).Trim(); $hw.Cores = [int]$p.NumberOfCores; $hw.Threads = [int]$p.NumberOfLogicalProcessors } catch {}
  try { $hw.Ram = [Math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory/1GB,1) } catch {}
  try {
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
    $spd = 0; foreach ($m in $mods) { $s = [int]$m.ConfiguredClockSpeed; if ($s -le 0) { $s = [int]$m.Speed }; if ($s -gt $spd) { $spd = $s } }
    $ch = [Math]::Min(2,[Math]::Max(1,$mods.Count))
    if ($spd -gt 0) { $hw.RamBw = [Math]::Round($spd * 8 * $ch / 1000 * 0.75,0) }
  } catch {}
  $list = New-Object System.Collections.ArrayList
  try {
    $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in (Get-ChildItem -LiteralPath $cls -ErrorAction SilentlyContinue)) {
      if ($k.PSChildName -notmatch '^\d{4}$') { continue }
      try {
        $pr = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
        $name = [string]$pr.DriverDesc; if (-not $name) { continue }
        [double]$mem = 0
        $q = $pr.'HardwareInformation.qwMemorySize'
        if ($q -is [byte[]]) { $mem = [double][BitConverter]::ToUInt64($q,0) / 1GB }
        elseif ($q) { $mem = [double]$q / 1GB }
        else { $v = $pr.'HardwareInformation.MemorySize'; if ($v -is [byte[]]) { $mem = [double][BitConverter]::ToUInt32($v,0) / 1GB } elseif ($v) { $mem = [double]([int64]$v -band 0xFFFFFFFFL) / 1GB } }
        [void]$list.Add(@{ Name=$name; Vram=[Math]::Round($mem,1) })
      } catch {}
    }
  } catch {}
  if ($list.Count -eq 0) { try { foreach ($g in (Get-CimInstance Win32_VideoController -ErrorAction Stop)) { [void]$list.Add(@{ Name=[string]$g.Name; Vram=[Math]::Round(([double]([int64]$g.AdapterRAM -band 0xFFFFFFFFL))/1GB,1) }) } } catch {} }
  $smi = Get-Command nvidia-smi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($smi) { try { $out = & $smi.Source --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null; foreach ($ln in @($out)) { $pp = ([string]$ln).Split(','); if ($pp.Count -ge 2) { foreach ($g in $list) { if ($g.Name -like ('*' + $pp[0].Trim().Replace('NVIDIA ','') + '*')) { $g.Vram = [Math]::Round([double]$pp[1].Trim()/1024,1) } } } } } catch {} }
  $real = @($list | Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual|Parsec|Mirror|Hyper-V|Meta|Citrix|DisplayLink|Indirect' })
  $hw.Gpus = $real
  if ($real.Count -gt 0) {
    $best = $real | Sort-Object { $_.Vram } -Descending | Select-Object -First 1
    $hw.Gpu = $best.Name; $hw.Vram = $best.Vram
    if ($best.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Tesla') { $hw.Vendor = 'NVIDIA' } elseif ($best.Name -match 'AMD|Radeon') { $hw.Vendor = 'AMD' } elseif ($best.Name -match 'Intel') { $hw.Vendor = 'Intel' }
    $integ = ($hw.Vendor -eq 'Intel' -and $best.Name -notmatch 'Arc') -or ($hw.Vendor -eq 'AMD' -and $best.Name -match 'Radeon\(TM\) Graphics|Radeon Graphics|Vega \d+ Graphics|780M|760M|680M|660M') -or ($hw.Vram -lt 1.5)
    $hw.Integrated = $integ
    if ($integ) { $hw.GpuOk = $false; $hw.Note = 'GPU integrada: Ollama usará sobre todo CPU + RAM.' }
    elseif ($hw.Vendor -eq 'NVIDIA') { $hw.GpuOk = $true; $hw.Note = 'NVIDIA: Ollama usa CUDA automáticamente.' }
    elseif ($hw.Vendor -eq 'AMD') { $hw.GpuOk = $true; $hw.Note = 'AMD: Ollama usa ROCm en GPUs soportadas. Si no acelera, activa Vulkan en Ajustes.' }
    elseif ($hw.Vendor -eq 'Intel') { $hw.GpuOk = $true; $hw.Note = 'Intel Arc: aceleración vía Vulkan (experimental, ver Ajustes).' }
    if ($hw.Vendor -eq 'AMD' -and -not $integ) {
      if ($best.Name -match 'RX\s*5\d{3}') { $hw.Family = 'RDNA1' } elseif ($best.Name -match 'RX\s*6\d{3}') { $hw.Family = 'RDNA2' } elseif ($best.Name -match 'RX\s*7\d{3}') { $hw.Family = 'RDNA3' } elseif ($best.Name -match 'RX\s*9\d{3}') { $hw.Family = 'RDNA4' }
    }
    if ($hw.Family -eq 'RDNA1' -or $hw.Family -eq 'RDNA2') { $hw.NeedVulkan = $true; $hw.Note = ('Radeon {0}: ROCm NO soporta esta GPU en Windows. Ollama solo la acelera con Vulkan activado (Ajustes).' -f $hw.Family) }
    if ($hw.Vendor -eq 'Intel' -and -not $integ) { $hw.NeedVulkan = $true }
    if ($hw.Vram -ge 24) { $hw.GpuBw = 800 } elseif ($hw.Vram -ge 16) { $hw.GpuBw = 450 } elseif ($hw.Vram -ge 10) { $hw.GpuBw = 360 } elseif ($hw.Vram -ge 6) { $hw.GpuBw = 250 } else { $hw.GpuBw = 160 }
  }
  $hw.Disk = Get-FreeDiskGB $Script:Models
  return $hw
}
function Get-FreeDiskGB([string]$path){
  try { $root = [IO.Path]::GetPathRoot($path); if (-not $root) { return 0.0 }; return [Math]::Round((New-Object IO.DriveInfo($root)).AvailableFreeSpace/1GB,1) } catch { return 0.0 }
}
function Build-HwEff {
  $d = $Script:HwDet
  if ($Script:Cfg.HwManual) {
    $Script:HwEff = @{ Ram=[double]$Script:Cfg.MRam; Vram=[double]$Script:Cfg.MVram; GpuOk=[bool]$Script:Cfg.MGpuOk; RamBw=[double]$Script:Cfg.MRamBw; GpuBw=[double]$Script:Cfg.MGpuBw; Disk=$d.Disk; Manual=$true }
  } else {
    $gok = [bool]$d.GpuOk; $vm = $false
    if ($d.NeedVulkan -and -not (Vulkan-On)) { $gok = $false; $vm = $true }
    $Script:HwEff = @{ Ram=[double]$d.Ram; Vram=[double]$d.Vram; GpuOk=$gok; RamBw=[double]$d.RamBw; GpuBw=[double]$d.GpuBw; Disk=$d.Disk; Manual=$false; VulkanMissing=$vm }
  }
  if ($Script:HwEff.RamBw -le 0) { $Script:HwEff.RamBw = 35 }
  if ($Script:HwEff.GpuBw -le 0) { $Script:HwEff.GpuBw = 250 }
  $g = 'sin GPU utilizable'; if ($Script:HwEff.GpuOk -and $Script:HwEff.Vram -gt 0) { $g = ('{0} GB VRAM' -f $Script:HwEff.Vram) }
  if ($Script:HwEff.VulkanMissing) { $g = ('GPU INACTIVA hasta activar Vulkan ({0} GB)' -f $Script:HwEff.Vram) }
  $pre = 'Equipo detectado'; if ($Script:HwEff.Manual) { $pre = 'Perfil manual' }
  $Script:HwEff.Label = ('{0}: {1} GB RAM, {2}' -f $pre, $Script:HwEff.Ram, $g)
  $Script:FitCache = @{}
}
function Get-Fit($e){
  if ($Script:FitCache.ContainsKey($e.id)) { return $Script:FitCache[$e.id] }
  $h = $Script:HwEff
  $gb = [double]$e.gb; if ($gb -le 0) { $gb = 1 }
  $isEmb = (@($e.caps) -contains 'Embeddings')
  $need = $gb * 1.12 + 0.6; if ($isEmb) { $need = $gb * 1.1 + 0.2 }
  $vram = 0.0; if ($h.GpuOk) { $vram = [Math]::Max(0.0, [double]$h.Vram - 0.7) }
  $ram = [Math]::Max(0.5, [double]$h.Ram * 0.85 - 2.5)
  $f = @{ need=[Math]::Round($need,1); mode='NoCabe'; gpuFrac=0.0; tps=0.0; ok=$false; speed='No cabe'; disk=($gb -le ([double]$h.Disk - 0.5)) }
  if ($vram -gt 0 -and $need -le $vram) { $f.mode = 'GPU'; $f.gpuFrac = 1.0; $f.ok = $true }
  elseif ($need -le ($vram + $ram)) { $f.ok = $true; if ($vram -gt 0.5) { $f.mode = 'Hibrido'; $f.gpuFrac = $vram / $need } else { $f.mode = 'CPU' } }
  if ($f.ok) {
    $act = $gb; if ([double]$e.p -gt 0 -and [double]$e.act -gt 0) { $act = $gb * ([double]$e.act / [double]$e.p) }
    if ($act -lt 0.05) { $act = 0.05 }
    $t = ($act * $f.gpuFrac / [double]$h.GpuBw) + ($act * (1 - $f.gpuFrac) / [double]$h.RamBw)
    $f.tps = [Math]::Round(0.75 / $t, 0)
    if ($isEmb) { $f.speed = 'Rápido (embeddings)' }
    elseif ($f.tps -ge 30) { $f.speed = 'Muy rápida' } elseif ($f.tps -ge 12) { $f.speed = 'Rápida' } elseif ($f.tps -ge 5) { $f.speed = 'Usable' } else { $f.speed = 'Lenta' }
  }
  $Script:FitCache[$e.id] = $f
  return $f
}
$ModeTxt = @{ GPU='GPU completa'; Hibrido='GPU + RAM'; CPU='Solo CPU + RAM'; NoCabe='No cabe en memoria' }
$ModeCol = @{ GPU=$Col.Green; Hibrido=$Col.Cyan; CPU=$Col.Amber; NoCabe=$Col.Red }
function Speed-Color($f){ if (-not $f.ok) { return $Col.Red }; if ($f.tps -ge 30) { return $Col.Green }; if ($f.tps -ge 12) { return $Col.Cyan }; if ($f.tps -ge 5) { return $Col.Amber }; return $Col.Red }
function Pseudo-Entry([string]$id,[double]$bytes){ return @{ id=$id; cat='Personalizado'; name=$id; kind='Desconocido'; p=1; act=1; gb=($bytes/1GB); caps=@(); rec=$false; uso=''; fuerte=''; user=$true; verified=$true } }

# =====================================================================
#  TRABAJADOR EN SEGUNDO PLANO (todas las tareas largas)
# =====================================================================
$JobCode = {
param($A)
. ([scriptblock]::Create($A.Shared))
$Q = $A.Q; $F = $A.F; $J = $A.Job
$CurlX = @($A.CurlX); $XS = [string]$A.XtraStr
function Post($m){ $null = $Q.Add($m) }
function Log([string]$lvl,[string]$txt){ Post @{ t='log'; lvl=$lvl; cat=$J.cat; text=$txt } }
function St([string]$txt){ Post @{ t='status'; text=$txt } }
function Prog([double]$cur,[double]$total,[double]$speed,[string]$detail){ Post @{ t='prog'; cur=$cur; total=$total; speed=$speed; detail=$detail } }
function HistP([string]$accion,[string]$modelo,[string]$res,[double]$bytes,[string]$det){ Post @{ t='hist'; accion=$accion; modelo=$modelo; res=$res; bytes=$bytes; det=$det } }
function Cancelled { return [bool]$F.Cancel }
function Wait-Retry([int]$s){ for ($i = 0; $i -lt $s; $i++) { if (Cancelled) { return $false }; Start-Sleep -Seconds 1 }; return $true }

function Hash-File([string]$path,[string]$label){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $fs = [IO.File]::Open($path,'Open','Read','Read')
  try {
    $buf = New-Object byte[] (4MB); [int64]$len = $fs.Length; [int64]$done = 0; $last = [DateTime]::UtcNow
    while ($true) {
      if (Cancelled) { return $null }
      $n = $fs.Read($buf,0,$buf.Length); if ($n -le 0) { break }
      [void]$sha.TransformBlock($buf,0,$n,$null,0); $done += $n
      if (([DateTime]::UtcNow - $last).TotalMilliseconds -ge 400) { $last = [DateTime]::UtcNow; Prog $done $len 0 ('Verificando SHA-256 de {0}: {1} / {2}' -f $label,(Human $done),(Human $len)) }
    }
    [void]$sha.TransformFinalBlock($buf,0,0)
    return ([BitConverter]::ToString($sha.Hash) -replace '-','').ToLower()
  } finally { $fs.Close(); $sha.Dispose() }
}

function Copy-Resume([string]$src,[string]$dst,[double]$baseDone,[double]$grand,[string]$label){
  $part = $dst + '.part'
  [int64]$size = (Get-Item -LiteralPath $src -Force).Length
  [int64]$have = SizeOf $part
  if ($have -gt $size) { Remove-Item -LiteralPath $part -Force; $have = 0 }
  if ($have -gt 4MB) { $have = $have - 4MB }
  $in = [IO.File]::Open($src,'Open','Read','Read')
  $out = [IO.File]::Open($part,'OpenOrCreate','Write','None')
  try {
    $out.SetLength($have)
    [void]$in.Seek($have,'Begin'); [void]$out.Seek($have,'Begin')
    $buf = New-Object byte[] (4MB); [int64]$done = $have; $last = [DateTime]::UtcNow; [int64]$lastB = $done
    while ($true) {
      if (Cancelled) { return $false }
      $n = $in.Read($buf,0,$buf.Length); if ($n -le 0) { break }
      $out.Write($buf,0,$n); $done += $n
      $dt = ([DateTime]::UtcNow - $last).TotalSeconds
      if ($dt -ge 0.4) { $sp = ($done - $lastB) / $dt; $last = [DateTime]::UtcNow; $lastB = $done; Prog ($baseDone + $done) $grand $sp ('Copiando {0}: {1} / {2}  |  {3}' -f $label,(Human $done),(Human $size),(SpeedFmt $sp)) }
    }
    $out.Flush()
  } finally { $in.Close(); $out.Close() }
  Move-Item -LiteralPath $part -Destination $dst -Force
  return $true
}

function Download-Blob($p,$b,[string]$Work,[double]$baseDone,[double]$grand,[int]$i,[int]$count){
  $hex = $b.digest.Split(':')[1]; [int64]$size = $b.size
  $ok = Join-Path $Work ('sha256-' + $hex); $part = $ok + '.part'
  $inst = Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hex)
  if ((SizeOf $inst) -eq $size) { St ('Archivo {0}/{1}: ya estaba en Ollama.' -f $i,$count); return 'ok' }
  if ((SizeOf $ok) -eq $size) { St ('Archivo {0}/{1}: ya descargado.' -f $i,$count); return 'ok' }
  $reg = Get-RegUrl $p $A.Registry
  $firstPass = $true; $bad = 0; $httpErr = 0
  while ($true) {
    if (Cancelled) { return 'cancel' }
    [int64]$cur = SizeOf $part
    if ($cur -gt $size) { Remove-Item -LiteralPath $part -Force; $cur = 0 }
    if ($firstPass -and $cur -gt 2MB -and $cur -lt $size) {
      try { $fs = [IO.File]::Open($part,'Open','ReadWrite'); $fs.SetLength($cur - 1MB); $fs.Close() } catch {}
      $cur = SizeOf $part
      Log 'INFO' ('Reanudando archivo {0}/{1} desde {2} de {3}.' -f $i,$count,(Human $cur),(Human $size))
    }
    $firstPass = $false
    if ($cur -lt $size) {
      $url = '{0}/v2/{1}/{2}/blobs/{3}' -f $reg,$p.ns,$p.name,$b.digest
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $A.Curl
      $psi.Arguments = ('-L -f -s -S -C - {2} --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "{0}" "{1}"' -f $part,$url,$XS)
      $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
      $proc = [System.Diagnostics.Process]::Start($psi)
      [int64]$lastSize = $cur; $lastT = [DateTime]::UtcNow; [double]$speed = 0
      while (-not $proc.HasExited) {
        if (Cancelled) { try { $proc.Kill() } catch {}; return 'cancel' }
        Start-Sleep -Milliseconds 400
        [int64]$now = SizeOf $part; $nowT = [DateTime]::UtcNow
        $dt = ($nowT - $lastT).TotalSeconds
        if ($dt -ge 1.0) { $speed = [Math]::Max([double]0, [double](($now - $lastSize) / $dt)); $lastSize = $now; $lastT = $nowT }
        $doneAll = $baseDone + $now; $eta = '--'; if ($speed -gt 0) { $eta = EtaSec (($grand - $doneAll) / $speed) }
        Prog $doneAll $grand $speed ('Archivo {0} de {1}  |  {2} / {3}  |  {4}  |  restante: {5}' -f $i,$count,(Human $doneAll),(Human $grand),(SpeedFmt $speed),$eta)
      }
      [int64]$now = SizeOf $part; $exit = $proc.ExitCode
      if ($exit -eq 33) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; continue }
      if ($now -lt $size) {
        if ($exit -eq 22) { $httpErr++ } else { $httpErr = 0 }
        if ($httpErr -ge 20) { return 'error:El servidor rechaza la descarga (HTTP) repetidamente.' }
        St ('Se cortó la conexión. Reintento en {0}s... (lo descargado se conserva)' -f $A.Wait)
        Log 'WARN' ('Descarga interrumpida (curl {0}) en {1} de {2}; se reanudará.' -f $exit,(Human $now),(Human $size))
        if (-not (Wait-Retry $A.Wait)) { return 'cancel' }
        continue
      }
    }
    St ('Archivo {0}/{1}: comprobando integridad SHA-256...' -f $i,$count)
    $h = @(Hash-File $part ('archivo {0}/{1}' -f $i,$count))[-1]
    if ($null -eq $h) { return 'cancel' }
    if ($h -eq $hex) { Move-Item -LiteralPath $part -Destination $ok -Force; Log 'INFO' ('Archivo {0}/{1} verificado ({2}).' -f $i,$count,(Human $size)); return 'ok' }
    $bad++; Log 'WARN' ('Archivo {0}/{1} con hash incorrecto; se vuelve a descargar.' -f $i,$count); Remove-Item -LiteralPath $part -Force
    if ($bad -ge 2) { return 'error:El archivo llega dañado repetidamente. Prueba más tarde.' }
  }
}

function Job-Download {
  $id = $J.id; $p = Split-ModelId $id
  $Work = Join-Path $A.Base (('{0}-{1}-{2}' -f $p.ns,$p.name,$p.tag) -replace '[^A-Za-z0-9._-]','_')
  New-Item -ItemType Directory -Force -Path $Work | Out-Null
  try { [IO.File]::WriteAllText((Join-Path $Work 'id.txt'), $id) } catch {}
  $manifest = Join-Path $Work 'manifest.json'
  if ($J.fresh -and (Test-Path -LiteralPath $manifest)) { Remove-Item -LiteralPath $manifest -Force }
  if (-not (Test-Path -LiteralPath $manifest)) {
    while ($true) {
      if (Cancelled) { return 'cancel' }
      St 'Consultando el registro de Ollama...'
      $code = Get-RegistryManifest $A.Curl $A.Registry $id $manifest
      if ($code -eq '200') { break }
      if ($code -eq '404') { return ('error:El modelo {0} no existe en el registro (404).' -f $id) }
      if ($code -eq '000') { St ('Sin conexión. Reintento en {0}s...' -f $A.Wait) } else { St ('El servidor respondió {0}. Reintento en {1}s...' -f $code,$A.Wait) }
      Log 'WARN' ('No se pudo obtener el manifiesto (código {0}); reintentando.' -f $code)
      if (-not (Wait-Retry $A.Wait)) { return 'cancel' }
    }
  } else { Log 'INFO' 'Reanudando con el manifiesto guardado de una sesión anterior.' }
  $mj = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
  $blobs = @(Get-ManifestBlobs $mj)
  [int64]$total = 0; foreach ($b in $blobs) { $total += $b.size }
  Post @{ t='size'; id=$id; bytes=$total }
  Log 'INFO' ('{0}: {1} archivos, {2} en total.' -f $id,$blobs.Count,(Human $total))
  try {
    [int64]$have = 0
    foreach ($b in $blobs) {
      $hex = $b.digest.Split(':')[1]
      $s = (SizeOf (Join-Path $Work ('sha256-' + $hex + '.part'))) + (SizeOf (Join-Path $Work ('sha256-' + $hex))) + (SizeOf (Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hex)))
      $have += [Math]::Min([int64]$b.size, [int64]$s)
    }
    [int64]$need = $total - $have
    [int64]$free = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Work).Path))).AvailableFreeSpace
    if ($free -lt ($need + 300MB)) { return ('error:Espacio insuficiente: faltan {0} y quedan {1} libres.' -f (Human $need),(Human $free)) }
  } catch {}
  $i = 0; [double]$doneBytes = 0
  foreach ($b in $blobs) {
    $i++
    $r = [string](@(Download-Blob $p $b $Work $doneBytes $total $i $blobs.Count)[-1])
    if ($r -ne 'ok') { return $r }
    $doneBytes += $b.size
  }
  St 'Instalando el modelo en Ollama...'
  $blobDir = Join-Path $A.Models 'blobs'; $mp = Get-LocalManifestPath $A.Models $p
  New-Item -ItemType Directory -Force -Path $blobDir, (Split-Path $mp -Parent) | Out-Null
  foreach ($b in $blobs) {
    $hex = $b.digest.Split(':')[1]; $src = Join-Path $Work ('sha256-' + $hex); $dst = Join-Path $blobDir ('sha256-' + $hex)
    if (Test-Path -LiteralPath $src) { if ((SizeOf $dst) -eq $b.size) { Remove-Item -LiteralPath $src -Force } else { Move-Item -LiteralPath $src -Destination $dst -Force } }
  }
  Copy-Item -LiteralPath $manifest -Destination $mp -Force
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
  Log 'INFO' ('{0} instalado en {1}' -f $id,$A.Models)
  return ('ok:' + $total)
}

function Job-Export {
  $repo = $J.repo; $ids = @($J.ids)
  $rb = Join-Path $repo 'blobs'; New-Item -ItemType Directory -Force -Path $rb | Out-Null
  $items = @(); $uniq = @{}; [double]$grand = 0
  foreach ($id in $ids) {
    $p = Split-ModelId $id; $mp = Get-LocalManifestPath $A.Models $p
    if (-not (Test-Path -LiteralPath $mp)) { Log 'ERROR' ('{0}: no está instalado; se omite.' -f $id); HistP 'Exportar' $id 'Error' 0 'No instalado'; continue }
    $bl = @(Get-ManifestBlobs (Get-Content -LiteralPath $mp -Raw | ConvertFrom-Json))
    $miss = 0; [double]$sz = 0
    foreach ($b in $bl) { $sz += $b.size; if ((SizeOf (Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $b.digest.Split(':')[1]))) -ne $b.size) { $miss++ } }
    if ($miss -gt 0) { Log 'ERROR' ('{0}: faltan {1} archivos en Ollama (instalación dañada); se omite. Usa Reparar.' -f $id,$miss); HistP 'Exportar' $id 'Error' 0 'Instalación incompleta'; continue }
    $items += @{ id=$id; p=$p; mp=$mp; blobs=$bl; bytes=$sz }
    foreach ($b in $bl) { if (-not $uniq.ContainsKey($b.digest)) { $uniq[$b.digest] = $b.size; $grand += $b.size } }
  }
  if ($items.Count -eq 0) { return 'error:No hay modelos válidos para exportar.' }
  try {
    [double]$need = 0; foreach ($d in $uniq.Keys) { if ((SizeOf (Join-Path $rb ('sha256-' + $d.Split(':')[1]))) -ne $uniq[$d]) { $need += $uniq[$d] } }
    $free = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $repo).Path))).AvailableFreeSpace
    if ($free -lt ($need + 100MB)) { return ('error:Espacio insuficiente en el destino: se necesitan {0} y hay {1}.' -f (Human $need),(Human $free)) }
    Log 'INFO' ('Exportando {0} modelo(s): {1} únicos, {2} a copiar.' -f $items.Count,(Human $grand),(Human $need))
  } catch {}
  [double]$done = 0; $n = 0; $errs = @{}
  foreach ($d in @($uniq.Keys)) {
    $n++; $hex = $d.Split(':')[1]; [int64]$size = $uniq[$d]
    $src = Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hex); $dst = Join-Path $rb ('sha256-' + $hex)
    if ((SizeOf $dst) -eq $size) { St ('Archivo {0}/{1}: ya estaba en el repositorio.' -f $n,$uniq.Count) }
    else {
      St ('Copiando archivo {0}/{1} ({2})...' -f $n,$uniq.Count,(Human $size))
      $r = @(Copy-Resume $src $dst $done $grand ('archivo {0}/{1}' -f $n,$uniq.Count))[-1]
      if (-not $r) { return 'cancel' }
    }
    if ($J.verify) {
      St ('Verificando archivo {0}/{1}...' -f $n,$uniq.Count)
      $h = @(Hash-File $dst ('archivo {0}/{1}' -f $n,$uniq.Count))[-1]
      if ($null -eq $h) { return 'cancel' }
      if ($h -ne $hex) { $errs[$d] = $true; Remove-Item -LiteralPath $dst -Force; Log 'ERROR' ('Archivo {0} dañado tras copiar (¿origen dañado o USB defectuoso?).' -f $hex.Substring(0,12)) }
    }
    $done += $size
    Prog $done $grand 0 ('{0} / {1}' -f (Human $done),(Human $grand))
  }
  $meta = @(); $rj = Join-Path $repo 'repo.json'
  if (Test-Path -LiteralPath $rj) { try { $meta = @(Get-Content -LiteralPath $rj -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $meta = @() } }
  foreach ($it in $items) {
    $bad = $false; foreach ($b in $it.blobs) { if ($errs.ContainsKey($b.digest)) { $bad = $true } }
    if ($bad) { HistP 'Exportar' $it.id 'Error' $it.bytes 'Archivos dañados al copiar'; continue }
    $rmp = Get-LocalManifestPath $repo $it.p
    New-Item -ItemType Directory -Force -Path (Split-Path $rmp -Parent) | Out-Null
    Copy-Item -LiteralPath $it.mp -Destination $rmp -Force
    $info = $J.meta[$it.id]
    $entry = [pscustomobject]@{ id=$it.id; bytes=[int64]$it.bytes; fecha=(Get-Date -Format 'yyyy-MM-dd HH:mm'); nombre=$(if ($info) { $info.name } else { $it.id }); categoria=$(if ($info) { $info.cat } else { '' }); uso=$(if ($info) { $info.uso } else { '' }); equipo=$env:COMPUTERNAME }
    $meta = @($meta | Where-Object { $_.id -ne $it.id }) + $entry
    HistP 'Exportar' $it.id 'OK' $it.bytes $repo
    Log 'INFO' ('{0} exportado.' -f $it.id)
  }
  try { (ConvertTo-Json -InputObject @($meta) -Depth 4) | Set-Content -LiteralPath $rj -Encoding UTF8 } catch {}
  if ($J.installer) {
    $si = Join-Path $A.InstDir 'OllamaSetup.exe'
    if (Test-Path -LiteralPath $si) { $di = Join-Path $repo 'instalador'; New-Item -ItemType Directory -Force -Path $di | Out-Null; $dd = Join-Path $di 'OllamaSetup.exe'; if ((SizeOf $dd) -ne (SizeOf $si)) { St 'Copiando instalador de Ollama...'; Copy-Item -LiteralPath $si -Destination $dd -Force }; Log 'INFO' 'Instalador de Ollama incluido en el repositorio.' }
    else { Log 'WARN' 'No hay instalador descargado; usa "Descargar instalador de Ollama" para incluirlo.' }
  }
  if ($J.app -and $A.Self -and (Test-Path -LiteralPath $A.Self)) {
    try { Copy-Item -LiteralPath $A.Self -Destination (Join-Path $repo (Split-Path $A.Self -Leaf)) -Force; if ($A.UserCat -and (Test-Path -LiteralPath $A.UserCat)) { Copy-Item -LiteralPath $A.UserCat -Destination (Join-Path $repo 'catalogo-usuario.json') -Force } } catch {}
  }
  $leeme = @(
    'REPOSITORIO OFFLINE DE MODELOS OLLAMA  (creado con Ollama Manager Pro)',
    '',
    'Contenido:',
    '  blobs\        archivos de pesos de los modelos (compartidos entre modelos)',
    '  manifests\    descripcion de cada modelo',
    '  repo.json     lista de modelos con fecha y descripcion',
    '  instalador\   OllamaSetup.exe (si se incluyo)',
    '',
    'Para instalar en otro PC SIN internet:',
    '  1. Instala Ollama (instalador\OllamaSetup.exe).',
    '  2. Ejecuta el .bat de Ollama Manager Pro (copiado aqui) en ese PC.',
    '  3. Pestana "Offline" > Importar > elige esta carpeta > Importar.',
    '',
    'Instalacion manual alternativa: copia blobs\ y manifests\ dentro de',
    '  %USERPROFILE%\.ollama\models\  (fusionando carpetas).'
  )
  try { [IO.File]::WriteAllLines((Join-Path $repo 'LEEME.txt'), $leeme) } catch {}
  if ($errs.Count -gt 0) { return ('error:{0} archivo(s) se copiaron dañados. Revisa el log.' -f $errs.Count) }
  return ('ok:' + $grand)
}

function Job-Import {
  $repo = $J.repo; $ids = @($J.ids); $stg = $A.Staging
  New-Item -ItemType Directory -Force -Path $stg, (Join-Path $A.Models 'blobs') | Out-Null
  $items = @(); $uniq = @{}; [double]$grand = 0
  foreach ($id in $ids) {
    $p = Split-ModelId $id; $rmp = Get-LocalManifestPath $repo $p
    if (-not (Test-Path -LiteralPath $rmp)) { Log 'ERROR' ('{0}: no está en el repositorio.' -f $id); continue }
    $bl = @(Get-ManifestBlobs (Get-Content -LiteralPath $rmp -Raw | ConvertFrom-Json))
    $miss = 0; [double]$sz = 0
    foreach ($b in $bl) { $sz += $b.size; $hx = $b.digest.Split(':')[1]; if ((SizeOf (Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hx))) -ne $b.size -and (SizeOf (Join-Path (Join-Path $repo 'blobs') ('sha256-' + $hx))) -ne $b.size) { $miss++ } }
    if ($miss -gt 0) { Log 'ERROR' ('{0}: el repositorio está incompleto (faltan {1} archivos); se omite.' -f $id,$miss); HistP 'Importar' $id 'Error' 0 'Repositorio incompleto'; continue }
    $items += @{ id=$id; p=$p; rmp=$rmp; blobs=$bl; bytes=$sz }
    foreach ($b in $bl) { $hx = $b.digest.Split(':')[1]; if ((SizeOf (Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hx))) -ne $b.size -and -not $uniq.ContainsKey($b.digest)) { $uniq[$b.digest] = $b.size; $grand += $b.size } }
  }
  if ($items.Count -eq 0) { return 'error:No hay modelos válidos para importar.' }
  try {
    $free = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot($A.Models))).AvailableFreeSpace
    if ($free -lt ($grand + 300MB)) { return ('error:Espacio insuficiente: se necesitan {0} y hay {1}.' -f (Human $grand),(Human $free)) }
  } catch {}
  Log 'INFO' ('Importando {0} modelo(s): {1} a copiar.' -f $items.Count,(Human $grand))
  [double]$done = 0; $n = 0; $errs = @{}
  foreach ($d in @($uniq.Keys)) {
    $n++; $hex = $d.Split(':')[1]; [int64]$size = $uniq[$d]
    $src = Join-Path (Join-Path $repo 'blobs') ('sha256-' + $hex); $stf = Join-Path $stg ('sha256-' + $hex); $dst = Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hex)
    if ((SizeOf $stf) -ne $size) {
      St ('Copiando archivo {0}/{1} ({2})...' -f $n,$uniq.Count,(Human $size))
      $r = @(Copy-Resume $src $stf $done $grand ('archivo {0}/{1}' -f $n,$uniq.Count))[-1]
      if (-not $r) { return 'cancel' }
    }
    if ($J.verify) {
      St ('Verificando archivo {0}/{1}...' -f $n,$uniq.Count)
      $h = @(Hash-File $stf ('archivo {0}/{1}' -f $n,$uniq.Count))[-1]
      if ($null -eq $h) { return 'cancel' }
      if ($h -ne $hex) { $errs[$d] = $true; Remove-Item -LiteralPath $stf -Force; Log 'ERROR' ('Archivo {0} dañado en el repositorio.' -f $hex.Substring(0,12)); $done += $size; continue }
    }
    Move-Item -LiteralPath $stf -Destination $dst -Force
    $done += $size
    Prog $done $grand 0 ('{0} / {1}' -f (Human $done),(Human $grand))
  }
  $okc = 0
  foreach ($it in $items) {
    $bad = $false; foreach ($b in $it.blobs) { if ($errs.ContainsKey($b.digest)) { $bad = $true } }
    if ($bad) { HistP 'Importar' $it.id 'Error' $it.bytes 'Archivos dañados en el repositorio'; continue }
    $mp = Get-LocalManifestPath $A.Models $it.p
    New-Item -ItemType Directory -Force -Path (Split-Path $mp -Parent) | Out-Null
    Copy-Item -LiteralPath $it.rmp -Destination $mp -Force
    $okc++; HistP 'Importar' $it.id 'OK' $it.bytes $repo; Log 'INFO' ('{0} importado e instalado en Ollama.' -f $it.id)
  }
  Remove-Item -LiteralPath $stg -Recurse -Force -ErrorAction SilentlyContinue
  if ($errs.Count -gt 0) { return ('error:{0} archivo(s) dañados; {1} modelo(s) importados.' -f $errs.Count,$okc) }
  return ('ok:' + $grand)
}

function Job-Verify {
  $ids = @($J.ids); $n = 0
  foreach ($id in $ids) {
    $n++; if (Cancelled) { return 'cancel' }
    St ('Verificando {0} ({1} de {2})...' -f $id,$n,$ids.Count)
    Prog $n $ids.Count 0 ('Modelo {0} de {1}' -f $n,$ids.Count)
    $p = Split-ModelId $id; $mp = Get-LocalManifestPath $A.Models $p
    $miss = @(); $bad = @(); [double]$sz = 0
    try {
      $bl = @(Get-ManifestBlobs (Get-Content -LiteralPath $mp -Raw | ConvertFrom-Json))
      foreach ($b in $bl) {
        $sz += $b.size; $hx = $b.digest.Split(':')[1]; $bfile = Join-Path (Join-Path $A.Models 'blobs') ('sha256-' + $hx)
        $s = SizeOf $bfile
        if ($s -eq 0) { $miss += $b.digest; continue }
        if ($s -ne $b.size) { $bad += $b.digest; continue }
        if ($J.deep) { $h = @(Hash-File $bfile ('{0}' -f $id))[-1]; if ($null -eq $h) { return 'cancel' }; if ($h -ne $hx) { $bad += $b.digest } }
      }
      if ($miss.Count -eq 0 -and $bad.Count -eq 0) { $st = 'OK'; if ($J.deep) { $st = 'OK (SHA-256)' }; $lvl = 'ok' }
      elseif ($miss.Count -gt 0) { $st = ('INCOMPLETO: faltan {0}' -f $miss.Count); $lvl = 'err' }
      else { $st = ('DAÑADO: {0} archivo(s)' -f $bad.Count); $lvl = 'err' }
    } catch { $st = 'Manifiesto ilegible'; $lvl = 'err' }
    Post @{ t='verifyres'; id=$id; status=$st; lvl=$lvl; bad=@($miss + $bad) }
    $acc = 'Verificar'; if ($J.deep) { $acc = 'Verificar SHA-256' }
    $res = 'OK'; if ($lvl -ne 'ok') { $res = 'Error' }
    HistP $acc $id $res $sz $st
    Log $(if ($lvl -eq 'ok') { 'INFO' } else { 'ERROR' }) ('{0}: {1}' -f $id,$st)
  }
  return 'ok:0'
}

function Job-Updates {
  $ids = @($J.ids); $n = 0
  foreach ($id in $ids) {
    $n++; if (Cancelled) { return 'cancel' }
    St ('Consultando {0} ({1} de {2})...' -f $id,$n,$ids.Count)
    Prog $n $ids.Count 0 ('Modelo {0} de {1}' -f $n,$ids.Count)
    $p = Split-ModelId $id; $mp = Get-LocalManifestPath $A.Models $p
    $tmp = Join-Path $A.Base ('upd-' + [Guid]::NewGuid().ToString('N') + '.json')
    $st = ''; $lvl = 'warn'; [double]$rsz = 0
    try {
      $code = Get-RegistryManifest $A.Curl $A.Registry $id $tmp
      if ($code -eq '200') {
        $rb = @(Get-ManifestBlobs (Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json)); foreach ($b in $rb) { $rsz += $b.size }
        $lb = @(Get-ManifestBlobs (Get-Content -LiteralPath $mp -Raw | ConvertFrom-Json))
        $rk = (@($rb | ForEach-Object { $_.digest }) | Sort-Object) -join ','; $lk = (@($lb | ForEach-Object { $_.digest }) | Sort-Object) -join ','
        if ($rk -eq $lk) { $st = 'Al día'; $lvl = 'ok' } else { $st = ('Actualización disponible ({0})' -f (Human $rsz)); $lvl = 'upd' }
      } elseif ($code -eq '404') { $st = 'No está en el registro' } elseif ($code -eq '000') { $st = 'Sin conexión' } else { $st = ('Error HTTP {0}' -f $code) }
    } catch { $st = 'Error: ' + $_.Exception.Message }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Post @{ t='updres'; id=$id; status=$st; lvl=$lvl }
    Log 'INFO' ('{0}: {1}' -f $id,$st)
  }
  return 'ok:0'
}

function Job-Check {
  $ids = @($J.ids); $n = 0; $okc = 0; $bad = @()
  foreach ($id in $ids) {
    $n++; if (Cancelled) { return 'cancel' }
    St ('Comprobando {0} ({1} de {2})...' -f $id,$n,$ids.Count)
    Prog $n $ids.Count 0 ('Modelo {0} de {1}' -f $n,$ids.Count)
    $tmp = Join-Path $A.Base ('chk-' + [Guid]::NewGuid().ToString('N') + '.json'); [double]$sz = 0
    $code = '000'
    try { $code = Get-RegistryManifest $A.Curl $A.Registry $id $tmp; if ($code -eq '200') { foreach ($b in @(Get-ManifestBlobs (Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json))) { $sz += $b.size } } } catch {}
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if ($code -eq '200') { $okc++ } else { $bad += ('{0} ({1})' -f $id,$code) }
    Post @{ t='checkres'; id=$id; code=[string]$code; bytes=$sz }
  }
  Log 'INFO' ('Catálogo: {0} disponibles, {1} con problemas.' -f $okc,$bad.Count)
  foreach ($x in $bad) { Log 'WARN' ('No disponible: {0}' -f $x) }
  return ('ok:0')
}

function Job-Installer {
  $url = 'https://ollama.com/download/OllamaSetup.exe'
  New-Item -ItemType Directory -Force -Path $A.InstDir | Out-Null
  $dst = Join-Path $A.InstDir 'OllamaSetup.exe'; $part = $dst + '.part'
  if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
  [double]$total = 0
  try { $hdr = & $A.Curl @CurlX -sIL --max-time 30 $url; foreach ($h in @($hdr)) { if ([string]$h -match '^(?i)content-length:\s*(\d+)') { $total = [double]$matches[1] } } } catch {}
  $httpErr = 0
  while ($true) {
    if (Cancelled) { return 'cancel' }
    St 'Descargando instalador de Ollama...'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $A.Curl; $psi.Arguments = ('-L -f -s -S -C - {2} --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "{0}" "{1}"' -f $part,$url,$XS)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    [int64]$lastSize = SizeOf $part; $lastT = [DateTime]::UtcNow; [double]$speed = 0
    while (-not $proc.HasExited) {
      if (Cancelled) { try { $proc.Kill() } catch {}; return 'cancel' }
      Start-Sleep -Milliseconds 400
      [int64]$now = SizeOf $part; $dt = ([DateTime]::UtcNow - $lastT).TotalSeconds
      if ($dt -ge 1) { $speed = [Math]::Max(0,($now - $lastSize) / $dt); $lastSize = $now; $lastT = [DateTime]::UtcNow }
      Prog $now $total $speed ('{0} / {1}  |  {2}' -f (Human $now),$(if ($total -gt 0) { Human $total } else { '?' }),(SpeedFmt $speed))
    }
    $exit = $proc.ExitCode
    if ($exit -eq 0 -and (SizeOf $part) -gt 10MB) { Move-Item -LiteralPath $part -Destination $dst -Force; Log 'INFO' ('Instalador guardado en {0}' -f $dst); return ('ok:' + (SizeOf $dst)) }
    if ($exit -eq 33) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; continue }
    if ($exit -eq 22) { $httpErr++ } else { $httpErr = 0 }
    if ($httpErr -ge 10) { return 'error:El servidor rechaza la descarga del instalador.' }
    St ('Conexión interrumpida. Reintento en {0}s...' -f $A.Wait); Log 'WARN' ('Descarga del instalador interrumpida (curl {0}); se reanudará.' -f $exit)
    if (-not (Wait-Retry $A.Wait)) { return 'cancel' }
  }
}

function Job-Gguf {
  if (-not $A.Ollama) { return 'error:Ollama no está instalado.' }
  $dir = Join-Path $A.Base ('gguf-' + ($J.id -replace '[^A-Za-z0-9._-]','_')); New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $mf = Join-Path $dir 'Modelfile'; $from = $J.file; if ($from -match '\s') { $from = '"' + $from + '"' }
  [IO.File]::WriteAllText($mf, ('FROM {0}' -f $from) + "`n")
  St ('Creando {0} a partir del GGUF (puede tardar)...' -f $J.id)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'cmd.exe'; $psi.Arguments = ('/c ""{0}" create "{1}" -f "{2}" 2>&1"' -f $A.Ollama,$J.id,$mf)
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
  $proc = [System.Diagnostics.Process]::Start($psi); $sr = $proc.StandardOutput
  while (-not $sr.EndOfStream) { if (Cancelled) { try { $proc.Kill() } catch {}; return 'cancel' }; $ln = $sr.ReadLine(); if ($ln -and $ln.Trim()) { St $ln.Trim(); if ($ln -notmatch '\d+%') { Log 'INFO' $ln.Trim() } } }
  $proc.WaitForExit()
  Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
  if ($proc.ExitCode -eq 0) { return ('ok:' + (SizeOf $J.file)) }
  return ('error:ollama create terminó con código {0}' -f $proc.ExitCode)
}

function Get-HfMeta([string]$repo,[string]$path){
  $dir = ''; $ix = $path.LastIndexOf('/'); if ($ix -gt 0) { $dir = '/' + $path.Substring(0,$ix) }
  $url = 'https://huggingface.co/api/models/{0}/tree/main{1}' -f $repo,$dir
  $tmp = Join-Path $A.Base ('hf-' + [Guid]::NewGuid().ToString('N') + '.json')
  $res = @{ size=0.0; sha=''; ok=$false; code='000' }
  try {
    $res.code = [string](& $A.Curl @CurlX -s -L --connect-timeout 20 --max-time 60 -o $tmp -w '%{http_code}' $url)
    if ($res.code -eq '200') {
      foreach ($ent in @(Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json)) {
        if ([string]$ent.path -eq $path) { $res.ok = $true; $res.size = [double]$ent.size; if ($ent.lfs) { $res.sha = ([string]$ent.lfs.oid).ToLower(); if ([double]$ent.lfs.size -gt 0) { $res.size = [double]$ent.lfs.size } } }
      }
    }
  } catch {}
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  return $res
}

function Download-File([string]$url,[string]$dest,[double]$size,[string]$sha,[double]$baseDone,[double]$grand,[string]$label){
  New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
  $part = $dest + '.part'
  $have = SizeOf $dest
  if ($have -gt 0 -and ($size -le 0 -or $have -eq $size)) { St ('{0}: ya descargado.' -f $label); return 'ok' }
  $bad = 0; $httpErr = 0
  while ($true) {
    if (Cancelled) { return 'cancel' }
    [int64]$cur = SizeOf $part
    if ($size -gt 0 -and $cur -gt $size) { Remove-Item -LiteralPath $part -Force; $cur = 0 }
    if (-not ($size -gt 0 -and $cur -eq $size)) {
      if ($cur -gt 0) { Log 'INFO' ('Reanudando {0} desde {1}.' -f $label,(Human $cur)) }
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $A.Curl; $psi.Arguments = ('-L -f -s -S -C - -A "OllamaManagerPro" {2} --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "{0}" "{1}"' -f $part,$url,$XS)
      $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
      $proc = [System.Diagnostics.Process]::Start($psi)
      [int64]$lastSize = $cur; $lastT = [DateTime]::UtcNow; [double]$speed = 0
      while (-not $proc.HasExited) {
        if (Cancelled) { try { $proc.Kill() } catch {}; return 'cancel' }
        Start-Sleep -Milliseconds 400
        [int64]$now = SizeOf $part; $dt = ([DateTime]::UtcNow - $lastT).TotalSeconds
        if ($dt -ge 1) { $speed = [Math]::Max(0,($now - $lastSize) / $dt); $lastSize = $now; $lastT = [DateTime]::UtcNow }
        $doneAll = $baseDone + $now; $eta = '--'; if ($speed -gt 0 -and $grand -gt 0) { $eta = EtaSec (($grand - $doneAll) / $speed) }
        Prog $doneAll $grand $speed ('{0}  |  {1} / {2}  |  {3}  |  restante: {4}' -f $label,(Human $doneAll),$(if ($grand -gt 0) { Human $grand } else { '?' }),(SpeedFmt $speed),$eta)
      }
      $exit = $proc.ExitCode; $now = SizeOf $part
      if ($exit -eq 33) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; continue }
      if ($exit -ne 0 -or ($size -gt 0 -and $now -lt $size)) {
        if ($exit -eq 22) { $httpErr++ } else { $httpErr = 0 }
        if ($httpErr -ge 15) { return ('error:El servidor rechaza la descarga de {0}.' -f $label) }
        St ('Conexión interrumpida. Reintento en {0}s... (lo descargado se conserva)' -f $A.Wait)
        Log 'WARN' ('{0}: interrumpido (curl {1}) en {2}; se reanudará.' -f $label,$exit,(Human $now))
        if (-not (Wait-Retry $A.Wait)) { return 'cancel' }
        continue
      }
    }
    if ($sha) {
      St ('{0}: verificando SHA-256...' -f $label)
      $hh = @(Hash-File $part $label)[-1]
      if ($null -eq $hh) { return 'cancel' }
      if ($hh -ne $sha.ToLower()) { $bad++; Log 'WARN' ('{0}: hash incorrecto; se descarga de nuevo.' -f $label); Remove-Item -LiteralPath $part -Force; if ($bad -ge 2) { return ('error:{0} llega dañado repetidamente.' -f $label) }; continue }
    }
    Move-Item -LiteralPath $part -Destination $dest -Force
    Log 'INFO' ('{0} descargado ({1}){2}.' -f $label,(Human (SizeOf $dest)),$(if ($sha) { ', SHA-256 verificado' } else { '' }))
    return 'ok'
  }
}

function Job-Files {
  $items = @($J.items)
  foreach ($it in $items) {
    if ($it.repo) {
      $it.url = 'https://huggingface.co/{0}/resolve/main/{1}' -f $it.repo,$it.path
      while ($true) {
        if (Cancelled) { return 'cancel' }
        St ('Consultando {0} en Hugging Face...' -f $it.name)
        $m = Get-HfMeta $it.repo $it.path
        if ($m.ok) { $it.size = $m.size; $it.sha = $m.sha; break }
        if ($m.code -and $m.code -ne '000') { Log 'WARN' ('Sin metadatos de {0} (HTTP {1}); se descargará sin verificar el hash.' -f $it.name,$m.code); $it.size = 0.0; $it.sha = ''; break }
        St ('Sin conexión. Reintento en {0}s...' -f $A.Wait)
        if (-not (Wait-Retry $A.Wait)) { return 'cancel' }
      }
    } else { if (-not $it.size) { $it.size = 0.0 }; if (-not $it.sha) { $it.sha = '' } }
  }
  [double]$grand = 0; [double]$need = 0
  foreach ($it in $items) { $grand += [double]$it.size; if ((SizeOf $it.dest) -ne [double]$it.size) { $need += [double]$it.size - (SizeOf ($it.dest + '.part')) } }
  try { $free = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot($items[0].dest))).AvailableFreeSpace; if ($free -lt ($need + 300MB)) { return ('error:Espacio insuficiente: faltan {0} y quedan {1} libres.' -f (Human $need),(Human $free)) } } catch {}
  Log 'INFO' ('{0}: {1} archivo(s), {2}.' -f $J.label,$items.Count,(Human $grand))
  [double]$done = 0; $n = 0
  foreach ($it in $items) {
    $n++
    $r = [string](@(Download-File $it.url $it.dest ([double]$it.size) ([string]$it.sha) $done $grand ('{0} ({1}/{2})' -f $it.name,$n,$items.Count))[-1])
    if ($r -ne 'ok') { return $r }
    $done += [double](SizeOf $it.dest)
  }
  return ('ok:' + $grand)
}

function Job-Engine {
  $api = 'https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/latest'
  $tmp = Join-Path $A.Base 'sdcpp-release.json'; $rel = $null
  while ($true) {
    if (Cancelled) { return 'cancel' }
    St 'Consultando la última versión de stable-diffusion.cpp en GitHub...'
    $code = [string](& $A.Curl @CurlX -s -L --connect-timeout 20 --max-time 60 -H 'User-Agent: OllamaManagerPro' -H 'Accept: application/vnd.github+json' -o $tmp -w '%{http_code}' $api)
    if ($code -eq '200') { $rel = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json; break }
    if ($code -eq '403' -or $code -eq '429') { return 'error:GitHub limitó las consultas. Espera una hora y vuelve a intentarlo.' }
    St ('Sin conexión con GitHub (código {0}). Reintento en {1}s...' -f $code,$A.Wait)
    if (-not (Wait-Retry $A.Wait)) { return 'cancel' }
  }
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $assets = @($rel.assets)
  $main = $assets | Where-Object { [string]$_.name -like ('*-bin-' + $J.variant + '.zip') } | Select-Object -First 1
  if (-not $main) { $main = $assets | Where-Object { [string]$_.name -like ('*' + $J.variant + '*.zip') } | Select-Object -First 1 }
  if (-not $main) { return ('error:No se encontró el paquete {0} en la versión {1}.' -f $J.variant,$rel.tag_name) }
  $list = @($main)
  if ($J.variant -like '*cuda*') { $cr = $assets | Where-Object { [string]$_.name -like 'cudart-*win*.zip' } | Select-Object -First 1; if ($cr) { $list += $cr } }
  [double]$grand = 0; foreach ($asset in $list) { $grand += [double]$asset.size }
  Log 'INFO' ('stable-diffusion.cpp {0}: {1}' -f $rel.tag_name,(($list | ForEach-Object { $_.name }) -join ', '))
  [double]$done = 0
  foreach ($asset in $list) {
    $sha = ''; $dg = [string]$asset.digest; if ($dg -like 'sha256:*') { $sha = $dg.Substring(7) }
    $dest = Join-Path $A.Base ([string]$asset.name)
    $r = [string](@(Download-File ([string]$asset.browser_download_url) $dest ([double]$asset.size) $sha $done $grand ([string]$asset.name))[-1])
    if ($r -ne 'ok') { return $r }
    $done += [double]$asset.size
  }
  St 'Instalando el motor...'
  $dir = $J.dir
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  foreach ($asset in $list) { $zp = Join-Path $A.Base ([string]$asset.name); Expand-Archive -LiteralPath $zp -DestinationPath $dir -Force; Remove-Item -LiteralPath $zp -Force -ErrorAction SilentlyContinue }
  [IO.File]::WriteAllText((Join-Path $dir 'version.txt'), ('{0} | {1} | {2}' -f $rel.tag_name,$J.variant,(Get-Date -Format 'yyyy-MM-dd')))
  Log 'INFO' ('Motor instalado en {0}' -f $dir)
  return ('ok:' + $grand)
}

function Job-CopyTree {
  $list = @(); [double]$grand = 0
  foreach ($pr in @($J.pairs)) {
    if (-not (Test-Path -LiteralPath $pr.src)) { continue }
    foreach ($fi in (Get-ChildItem -LiteralPath $pr.src -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      if ($fi.Name -like '*.part') { continue }
      $rel = $fi.FullName.Substring(([string]$pr.src).TrimEnd('\').Length).TrimStart('\')
      $list += @{ src=$fi.FullName; dst=(Join-Path $pr.dst $rel); size=[double]$fi.Length }; $grand += $fi.Length
    }
  }
  if ($list.Count -eq 0) { return 'error:No hay archivos que copiar.' }
  try { [double]$need = 0; foreach ($it in $list) { if ((SizeOf $it.dst) -ne $it.size) { $need += $it.size } }; $free = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot($list[0].dst))).AvailableFreeSpace; if ($free -lt ($need + 100MB)) { return ('error:Espacio insuficiente: se necesitan {0} y hay {1}.' -f (Human $need),(Human $free)) } } catch {}
  [double]$done = 0; $n = 0
  foreach ($it in $list) {
    $n++; New-Item -ItemType Directory -Force -Path (Split-Path $it.dst -Parent) | Out-Null
    if ((SizeOf $it.dst) -ne $it.size) {
      St ('Copiando {0} ({1}/{2})...' -f (Split-Path $it.src -Leaf),$n,$list.Count)
      $r = @(Copy-Resume $it.src $it.dst $done $grand ('archivo {0}/{1}' -f $n,$list.Count))[-1]
      if (-not $r) { return 'cancel' }
    }
    $done += $it.size; Prog $done $grand 0 ('{0} / {1}' -f (Human $done),(Human $grand))
  }
  Log 'INFO' ('{0}: {1} archivo(s), {2}.' -f $J.label,$list.Count,(Human $grand))
  return ('ok:' + $grand)
}

try {
  $res = @()
  switch ($J.type) {
    'files'     { $res = @(Job-Files) }
    'engine'    { $res = @(Job-Engine) }
    'copytree'  { $res = @(Job-CopyTree) }
    'download'  { $res = @(Job-Download) }
    'export'    { $res = @(Job-Export) }
    'import'    { $res = @(Job-Import) }
    'verify'    { $res = @(Job-Verify) }
    'updates'   { $res = @(Job-Updates) }
    'check'     { $res = @(Job-Check) }
    'installer' { $res = @(Job-Installer) }
    'gguf'      { $res = @(Job-Gguf) }
  }
  $st = 'error:Resultado vacío'; if ($res.Count -gt 0) { $st = [string]$res[-1] }
  Post @{ t='jobdone'; st=$st }
} catch {
  Post @{ t='log'; lvl='ERROR'; cat=$J.cat; text=('Error inesperado: {0}' -f $_.Exception.Message) }
  Post @{ t='jobdone'; st=('error:' + $_.Exception.Message) }
}
}

$ChatCode = {
param($A)
$Q = $A.Q
try {
  $body = @{ model=$A.Model; messages=@($A.Messages); stream=$true } | ConvertTo-Json -Depth 8 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($body)
  $req = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:11434/api/chat')
  $req.Method = 'POST'; $req.ContentType = 'application/json'; $req.Timeout = 900000; $req.ReadWriteTimeout = 900000; $req.ContentLength = $bytes.Length
  $rs = $req.GetRequestStream(); $rs.Write($bytes,0,$bytes.Length); $rs.Close()
  $resp = $req.GetResponse(); $sr = New-Object IO.StreamReader($resp.GetResponseStream(),[Text.Encoding]::UTF8)
  while (-not $sr.EndOfStream) {
    if ($A.F.Stop) { break }
    $line = $sr.ReadLine(); if (-not $line) { continue }
    $j = $line | ConvertFrom-Json
    if ($j.error) { $null = $Q.Add(@{ t='err'; text=[string]$j.error }) }
    if ($j.message) {
      if ($j.message.thinking) { $null = $Q.Add(@{ t='think'; text=[string]$j.message.thinking }) }
      if ($j.message.content) { $null = $Q.Add(@{ t='tok'; text=[string]$j.message.content }) }
    }
    if ($j.done) { $tps = 0; if ([double]$j.eval_duration -gt 0) { $tps = [double]$j.eval_count / ([double]$j.eval_duration / 1e9) }; $null = $Q.Add(@{ t='end'; tps=$tps; n=[int]$j.eval_count; load=([double]$j.load_duration / 1e9) }) }
  }
  $sr.Close(); $resp.Close()
} catch { $null = $Q.Add(@{ t='err'; text=$_.Exception.Message }) }
$null = $Q.Add(@{ t='fin' })
}

$ImgCode = {
param($A)
$Q = $A.Q
try {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $A.Exe; $psi.Arguments = $A.Args; $psi.WorkingDirectory = $A.WorkDir
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $errTask = $proc.StandardError.ReadToEndAsync()
  $sr = $proc.StandardOutput
  while (-not $sr.EndOfStream) {
    if ($A.F.Stop) { try { $proc.Kill() } catch {}; break }
    $ln = $sr.ReadLine(); if ($ln -and $ln.Trim()) { $null = $Q.Add(@{ t='line'; text=$ln }) }
  }
  $proc.WaitForExit()
  $err = ''; try { $err = [string]$errTask.Result } catch {}
  foreach ($l in ($err -split "`r?`n")) { if ($l.Trim()) { $null = $Q.Add(@{ t='line'; text=$l }) } }
  $null = $Q.Add(@{ t='done'; code=$proc.ExitCode; stopped=[bool]$A.F.Stop })
} catch { $null = $Q.Add(@{ t='done'; code=-1; stopped=$false; err=$_.Exception.Message }) }
}

function Start-Worker($code,$argBundle){
  $ps = [powershell]::Create(); $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.Open()
  $ps.Runspace = $rs; [void]$ps.AddScript($code.ToString()); [void]$ps.AddArgument($argBundle)
  return @{ Ps=$ps; Async=$ps.BeginInvoke() }
}

# =====================================================================
#  ESTADO GLOBAL
# =====================================================================
$Script:Installed = @{}
$Script:Jobs = New-Object System.Collections.ArrayList
$Script:CurJob = $null; $Script:JobPs = $null; $Script:JobAsync = $null; $Script:JobStart = Get-Date
$Script:MsgQ = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Script:Flags = [System.Collections.Hashtable]::Synchronized(@{ Cancel=$false })
$Script:ChatQ = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Script:ChatF = [System.Collections.Hashtable]::Synchronized(@{ Stop=$false })
$Script:VerifyState = @{}; $Script:VerifyBad = @{}; $Script:UpdState = @{}; $Script:CheckState = @{}; $Script:CheckBad = @()
$Script:F_Cat = 'Todas'; $Script:F_Cap = 'Todas'; $Script:F_Size = 'Todos'; $Script:F_Fit = 'Todos'
$Script:F_Rec = $false; $Script:F_HideInst = $false; $Script:F_Search = ''; $Script:F_Sort = 0
$Script:ChipGroups = @{}; $Script:CardMap = @{}; $Script:FitCache = @{}
$Script:RepoModels = @{}

function Is-Busy { return ($null -ne $Script:CurJob) }
function Is-Queued([string]$id){ foreach ($j in $Script:Jobs) { if ($j.type -eq 'download' -and $j.id -eq $id) { return $true } }; return $false }
function Is-Downloading([string]$id){ return ($Script:CurJob -and $Script:CurJob.type -eq 'download' -and $Script:CurJob.id -eq $id) }
function Refresh-Installed { $Script:Installed = Get-ManifestMap $Script:Models; $Script:HwDet.Disk = Get-FreeDiskGB $Script:Models; if ($Script:HwEff) { $Script:HwEff.Disk = $Script:HwDet.Disk } }
function Get-Entry([string]$id){ if ($Script:CatMap.ContainsKey($id)) { return $Script:CatMap[$id] }; return $null }
function Test-OllamaApi {
  try { $r = [System.Net.WebRequest]::Create('http://127.0.0.1:11434/api/version'); $r.Timeout = 1500; $resp = $r.GetResponse(); $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd(); $resp.Close(); try { $Script:OllamaVer = ($t | ConvertFrom-Json).version } catch {}; return $true } catch { return $false }
}
function MsgInfo([string]$t){ [void][System.Windows.Forms.MessageBox]::Show($t,$AppName,'OK','Information') }
function MsgWarn([string]$t){ [void][System.Windows.Forms.MessageBox]::Show($t,$AppName,'OK','Warning') }
function MsgYes([string]$t){ return ([System.Windows.Forms.MessageBox]::Show($t,$AppName,'YesNo','Question') -eq 'Yes') }
function Set-Status([string]$t){ $statusBar.Text = '  ' + $t }

# =====================================================================
#  AYUDANTES DE INTERFAZ
# =====================================================================
function New-Btn([string]$text,[System.Drawing.Color]$fg,[System.Drawing.Color]$border,[bool]$filled){
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text; $b.AutoSize = $true; $b.Font = $FSm; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
  $b.MinimumSize = New-Object System.Drawing.Size(0,30); $b.Padding = New-Object System.Windows.Forms.Padding(6,0,6,0)
  $b.Margin = New-Object System.Windows.Forms.Padding(0,0,6,6)
  if ($filled) { $b.BackColor = $border; $b.ForeColor = $Col.White; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $Col.AccH }
  else { $b.BackColor = $Col.Card; $b.ForeColor = $fg; $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = $border; $b.FlatAppearance.MouseOverBackColor = $Col.CardH }
  return $b
}
function New-Lbl([string]$text,$font,[System.Drawing.Color]$color){
  $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Font = $font; $l.ForeColor = $color; $l.AutoSize = $true
  $l.Margin = New-Object System.Windows.Forms.Padding(0,6,8,0); return $l
}
function New-Flow([string]$dir){
  $f = New-Object System.Windows.Forms.FlowLayoutPanel; $f.FlowDirection = $dir; $f.WrapContents = $true; $f.AutoSize = $true; $f.AutoSizeMode = 'GrowAndShrink'
  $f.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6); return $f
}
function New-Txt([int]$w,[string]$text){
  $t = New-Object System.Windows.Forms.TextBox; $t.Width = $w; $t.Text = $text; $t.BackColor = $Col.Card; $t.ForeColor = $Col.Txt; $t.BorderStyle = 'FixedSingle'; $t.Font = $FNorm
  $t.Margin = New-Object System.Windows.Forms.Padding(0,3,6,3); return $t
}
function New-Chk([string]$text,[bool]$val){
  $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $text; $c.Checked = $val; $c.AutoSize = $true; $c.ForeColor = $Col.Txt; $c.Font = $FSm
  $c.Margin = New-Object System.Windows.Forms.Padding(0,4,14,4); return $c
}
function New-Num([double]$min,[double]$max,[double]$val,[int]$dec,[double]$inc){
  $n = New-Object System.Windows.Forms.NumericUpDown; $n.Minimum = [decimal]$min; $n.Maximum = [decimal]$max; $n.DecimalPlaces = $dec; $n.Increment = [decimal]$inc
  $v = [Math]::Min($max,[Math]::Max($min,$val)); $n.Value = [decimal]$v; $n.Width = 90; $n.BackColor = $Col.Card; $n.ForeColor = $Col.Txt; return $n
}
function New-SideLbl([string]$txt){ $l = New-Object System.Windows.Forms.Label; $l.Text = $txt; $l.Font = $FSmB; $l.ForeColor = $Col.Sub; $l.AutoSize = $false; $l.Height = 18; $l.Width = 236; $l.Margin = New-Object System.Windows.Forms.Padding(0,8,0,3); return $l }
$Script:HdrBrush = New-Object System.Drawing.SolidBrush($Col.Panel)
function New-LV($cols){
  $lv = New-Object System.Windows.Forms.ListView
  $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true; $lv.HideSelection = $false; $lv.MultiSelect = $true
  $lv.BackColor = $Col.Card; $lv.ForeColor = $Col.Txt; $lv.BorderStyle = 'None'; $lv.Font = $FSm; $lv.Dock = 'Fill'
  foreach ($c in $cols) { $pp = ([string]$c).Split('='); [void]$lv.Columns.Add($pp[0], [int]$pp[1]) }
  $lv.OwnerDraw = $true
  $lv.Add_DrawColumnHeader({ param($s,$e)
    $e.Graphics.FillRectangle($Script:HdrBrush, $e.Bounds)
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, ($e.Bounds.Width - 6), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $FSmB, $r, $Col.Sub, [System.Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis') })
  $lv.Add_DrawItem({ param($s,$e) $e.DrawDefault = $true })
  $lv.Add_DrawSubItem({ param($s,$e) $e.DrawDefault = $true })
  return $lv
}
function Set-ChipActive([string]$grp,[string]$key){
  foreach ($b in $Script:ChipGroups[$grp]) {
    $k = ([string]$b.Tag).Split('|')[1]
    if ($k -eq $key) { $b.BackColor = $Col.Acc; $b.ForeColor = $Col.White; $b.FlatAppearance.BorderColor = $Col.Acc }
    else { $b.BackColor = $Col.Card; $b.ForeColor = $Col.Sub; $b.FlatAppearance.BorderColor = $Col.Border }
  }
}
function New-ChipFlow($keys,$names,[string]$grp){
  $fl = New-Object System.Windows.Forms.FlowLayoutPanel; $fl.WrapContents = $true; $fl.AutoSize = $true; $fl.AutoSizeMode = 'GrowAndShrink'
  $fl.MaximumSize = New-Object System.Drawing.Size(240,0); $fl.MinimumSize = New-Object System.Drawing.Size(240,0); $fl.Margin = New-Object System.Windows.Forms.Padding(0,0,0,4)
  $Script:ChipGroups[$grp] = New-Object System.Collections.ArrayList
  foreach ($k in $keys) {
    $txt = $k; if ($names -and $names.ContainsKey($k)) { $txt = $names[$k] }
    $b = New-Object System.Windows.Forms.Button; $b.Text = $txt; $b.AutoSize = $true; $b.Font = $FSm
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = $Col.Border
    $b.FlatAppearance.MouseOverBackColor = $Col.CardH; $b.BackColor = $Col.Card; $b.ForeColor = $Col.Sub
    $b.Cursor = 'Hand'; $b.Margin = New-Object System.Windows.Forms.Padding(0,0,5,5); $b.Tag = ($grp + '|' + $k)
    $b.Add_Click({ param($s,$ev)
      $pp = ([string]$s.Tag).Split('|'); $g = $pp[0]; $k2 = $pp[1]; Set-ChipActive $g $k2
      switch ($g) { 'cat' { $Script:F_Cat = $k2 } 'cap' { $Script:F_Cap = $k2 } 'size' { $Script:F_Size = $k2 } 'fit' { $Script:F_Fit = $k2 } }
      ApplyFilters })
    [void]$Script:ChipGroups[$grp].Add($b); $fl.Controls.Add($b)
  }
  return $fl
}
function New-Box([int]$w,[int]$h,[string]$title){
  $bx = New-RP 10 $Col.Border; $bx.Size = New-Object System.Drawing.Size($w,$h); $bx.BackColor = $Col.Card; $bx.Margin = New-Object System.Windows.Forms.Padding(0,0,12,12)
  $t = New-Object System.Windows.Forms.Label; $t.Text = $title; $t.Font = $FSmB; $t.ForeColor = $Col.Sub; $t.AutoSize = $true; $t.Location = New-Object System.Drawing.Point(14,10); $bx.Controls.Add($t)
  return $bx
}

# =====================================================================
#  VENTANA PRINCIPAL
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = ('{0} v{1}' -f $AppName,$AppVer); $form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(1340,860); $form.MinimumSize = New-Object System.Drawing.Size(1120,720)
$form.BackColor = $Col.Bg; $form.ForeColor = $Col.Txt; $form.Font = $FNorm; $form.AutoScaleMode = 'Dpi'
$Script:Tray = New-Object System.Windows.Forms.NotifyIcon
try { if (Test-Path -LiteralPath $OllamaApp) { $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($OllamaApp); $Script:Tray.Icon = $ic; $form.Icon = $ic } else { $Script:Tray.Icon = [System.Drawing.SystemIcons]::Application } } catch { $Script:Tray.Icon = [System.Drawing.SystemIcons]::Application }
$Script:Tray.Text = $AppName; $Script:Tray.Visible = $true
$Script:Tray.Add_BalloonTipClicked({ if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal' }; $form.Activate() })
$Script:Tray.Add_DoubleClick({ if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal' }; $form.Activate() })

# ---------- Cabecera ----------
$header = New-Object System.Windows.Forms.Panel; $header.Dock = 'Top'; $header.Height = 66; $header.BackColor = $Col.Panel
$hdrLeft = New-Object System.Windows.Forms.Panel; $hdrLeft.Dock = 'Fill'; $hdrLeft.BackColor = $Col.Panel
$lblTitle = New-Object System.Windows.Forms.Label; $lblTitle.Text = $AppName; $lblTitle.Font = $FTitle; $lblTitle.ForeColor = $Col.Txt; $lblTitle.AutoSize = $true; $lblTitle.Location = New-Object System.Drawing.Point(18,8)
$lblSub = New-Object System.Windows.Forms.Label; $lblSub.Text = 'Descarga reanudable  ·  Compatibilidad por hardware  ·  Repositorio offline  ·  Verificación y actualizaciones'; $lblSub.Font = $FSm; $lblSub.ForeColor = $Col.Sub; $lblSub.AutoSize = $true; $lblSub.Location = New-Object System.Drawing.Point(20,40)
$hdrLeft.Controls.Add($lblTitle); $hdrLeft.Controls.Add($lblSub)
$hdrRight = New-Object System.Windows.Forms.FlowLayoutPanel; $hdrRight.Dock = 'Right'; $hdrRight.FlowDirection = 'RightToLeft'; $hdrRight.WrapContents = $false; $hdrRight.Width = 620; $hdrRight.Padding = New-Object System.Windows.Forms.Padding(0,16,14,0); $hdrRight.BackColor = $Col.Panel
$btnSrv = New-Btn 'Iniciar Ollama' $Col.Txt $Col.Border $false
$btnSrv.Add_Click({ if (Test-OllamaApi) { if (MsgYes '¿Reiniciar el servicio de Ollama? (aplica los ajustes de entorno)') { Restart-Ollama } } else { Start-OllamaSvc; Set-Status 'Iniciando Ollama...' }; $Script:StatTimer.Interval = 2500 })
$lblOllamaStatus = New-Lbl 'Comprobando Ollama...' $FSm $Col.Sub; $lblOllamaStatus.Margin = New-Object System.Windows.Forms.Padding(4,8,12,0)
$dotOllama = New-Object System.Windows.Forms.Panel; $dotOllama.Size = New-Object System.Drawing.Size(10,10); $dotOllama.BackColor = $Col.Amber; $dotOllama.Margin = New-Object System.Windows.Forms.Padding(0,11,0,0)
$hdrRight.Controls.Add($btnSrv); $hdrRight.Controls.Add($lblOllamaStatus); $hdrRight.Controls.Add($dotOllama)
$header.Controls.Add($hdrLeft); $header.Controls.Add($hdrRight)

# ---------- Navegacion ----------
$nav = New-Object System.Windows.Forms.FlowLayoutPanel; $nav.Dock = 'Top'; $nav.Height = 42; $nav.BackColor = $Col.Panel; $nav.WrapContents = $false; $nav.Padding = New-Object System.Windows.Forms.Padding(12,5,0,0)
$Script:NavBtns = New-Object System.Collections.ArrayList
foreach ($pg in @(@('cat','Catálogo'),@('img','Imagen: generar / editar'),@('inst','Instalados'),@('off','Offline: exportar / importar'),@('hw','Mi equipo'),@('hist','Historial y log'),@('cfg','Ajustes'))) {
  $b = New-Object System.Windows.Forms.Button; $b.Text = $pg[1]; $b.Tag = $pg[0]; $b.AutoSize = $true; $b.Font = $FBold; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $Col.Panel; $b.ForeColor = $Col.Sub; $b.Cursor = 'Hand'; $b.MinimumSize = New-Object System.Drawing.Size(0,30); $b.Padding = New-Object System.Windows.Forms.Padding(10,0,10,0); $b.Margin = New-Object System.Windows.Forms.Padding(0,0,4,0)
  $b.FlatAppearance.MouseOverBackColor = $Col.CardH
  $b.Add_Click({ param($s,$ev) Show-Page ([string]$s.Tag) })
  [void]$Script:NavBtns.Add($b); $nav.Controls.Add($b)
}
$sep = New-Object System.Windows.Forms.Panel; $sep.Height = 1; $sep.BackColor = $Col.Border; $sep.Dock = 'Top'

# ---------- Barra de estado ----------
$statusBar = New-Object System.Windows.Forms.Label; $statusBar.Dock = 'Bottom'; $statusBar.Height = 26; $statusBar.BackColor = $Col.Panel
$statusBar.ForeColor = $Col.Sub; $statusBar.Font = $FSm; $statusBar.TextAlign = 'MiddleLeft'; $statusBar.Text = '  Listo.'

# ---------- Panel de tareas ----------
$jobPanel = New-Object System.Windows.Forms.Panel; $jobPanel.Dock = 'Bottom'; $jobPanel.Height = 104; $jobPanel.BackColor = $Col.Panel; $jobPanel.Visible = $false
$jobRight = New-Object System.Windows.Forms.FlowLayoutPanel; $jobRight.Dock = 'Right'; $jobRight.Width = 440; $jobRight.FlowDirection = 'TopDown'; $jobRight.WrapContents = $false; $jobRight.Padding = New-Object System.Windows.Forms.Padding(8,10,14,0); $jobRight.BackColor = $Col.Panel
$lblQueue = New-Lbl '' $FSm $Col.Sub; $lblQueue.AutoSize = $false; $lblQueue.Width = 410; $lblQueue.Height = 36
$jobBtns = New-Flow 'LeftToRight'; $jobBtns.WrapContents = $false
$btnPause = New-Btn 'Pausar' $Col.Cyan $Col.Cyan $false
$btnCancel = New-Btn 'Cancelar actual' $Col.Red $Col.Red $false
$btnViewQ = New-Btn 'Ver cola' $Col.Txt $Col.Border $false
$btnClearQ = New-Btn 'Vaciar cola' $Col.Amber $Col.Amber $false
$Script:Paused = $false; $Script:PausePending = $false
$btnPause.Add_Click({ Toggle-Pause })
$btnCancel.Add_Click({ if ($Script:CurJob) { if (MsgYes ('¿Cancelar "{0}"?{1}Lo ya descargado se conserva en disco, pero la tarea sale de la cola. (Para seguir más tarde usa "Pausar".)' -f $Script:CurJob.label,"`n")) { $Script:Flags.Cancel = $true; Set-Status 'Cancelando...' } } })
$btnViewQ.Add_Click({ Open-QueueViewer })
$btnClearQ.Add_Click({ if (MsgYes '¿Quitar todas las tareas pendientes de la cola? (la actual sigue)') { $Script:Jobs.Clear(); Save-Queue; Update-QueueLabel; Update-CardStates; Refresh-ImgState; Write-Log 'INFO' 'COLA' 'Cola vaciada por el usuario.' } })
$jobBtns.Controls.Add($btnPause); $jobBtns.Controls.Add($btnCancel); $jobBtns.Controls.Add($btnViewQ); $jobBtns.Controls.Add($btnClearQ)
$jobRight.Controls.Add($lblQueue); $jobRight.Controls.Add($jobBtns)
$jobLeft = New-Object System.Windows.Forms.Panel; $jobLeft.Dock = 'Fill'; $jobLeft.BackColor = $Col.Panel; $jobLeft.Padding = New-Object System.Windows.Forms.Padding(16,8,8,0)
$lblJobTitle = New-Object System.Windows.Forms.Label; $lblJobTitle.Font = $FBold; $lblJobTitle.ForeColor = $Col.Txt; $lblJobTitle.Dock = 'Top'; $lblJobTitle.Height = 22
$barOut = New-Object System.Windows.Forms.Panel; $barOut.Dock = 'Top'; $barOut.Height = 14; $barOut.BackColor = $Col.Card
$barInner = New-Object System.Windows.Forms.Panel; $barInner.Location = New-Object System.Drawing.Point(2,2); $barInner.Size = New-Object System.Drawing.Size(0,10); $barInner.BackColor = $Col.Acc; $barOut.Controls.Add($barInner)
$lblJobDetail = New-Object System.Windows.Forms.Label; $lblJobDetail.Font = $FSm; $lblJobDetail.ForeColor = $Col.Sub; $lblJobDetail.Dock = 'Top'; $lblJobDetail.Height = 22; $lblJobDetail.TextAlign = 'BottomLeft'
$lblJobStatus = New-Object System.Windows.Forms.Label; $lblJobStatus.Font = $FSm; $lblJobStatus.ForeColor = $Col.Cyan; $lblJobStatus.Dock = 'Top'; $lblJobStatus.Height = 20
$jobLeft.Controls.Add($lblJobStatus); $jobLeft.Controls.Add($lblJobDetail); $jobLeft.Controls.Add($barOut); $jobLeft.Controls.Add($lblJobTitle)
$jobPanel.Controls.Add($jobLeft); $jobPanel.Controls.Add($jobRight)
$Script:BarFrac = 0.0
function Set-Bar([double]$frac){ if ($frac -lt 0) { $frac = 0 }; if ($frac -gt 1) { $frac = 1 }; $Script:BarFrac = $frac; $barInner.Width = [int](($barOut.Width - 4) * $frac) }
$barOut.Add_Resize({ Set-Bar $Script:BarFrac })

# ---------- Contenedor de paginas ----------
$content = New-Object System.Windows.Forms.Panel; $content.Dock = 'Fill'; $content.BackColor = $Col.Bg
$Script:Pages = @{}
function New-Page([string]$key){ $p = New-Object System.Windows.Forms.Panel; $p.Dock = 'Fill'; $p.BackColor = $Col.Bg; $p.Visible = $false; $content.Controls.Add($p); $Script:Pages[$key] = $p; return $p }

# =====================================================================
#  PAGINA: CATALOGO
# =====================================================================
$pgCat = New-Page 'cat'
$catFlow = New-Object System.Windows.Forms.FlowLayoutPanel; $catFlow.Dock = 'Fill'; $catFlow.AutoScroll = $true; $catFlow.WrapContents = $true; $catFlow.BackColor = $Col.Bg; $catFlow.Padding = New-Object System.Windows.Forms.Padding(10,10,10,10)
$catSide = New-Object System.Windows.Forms.Panel; $catSide.Dock = 'Left'; $catSide.Width = 276; $catSide.BackColor = $Col.Panel
$catSideFlow = New-Object System.Windows.Forms.FlowLayoutPanel; $catSideFlow.Dock = 'Fill'; $catSideFlow.AutoScroll = $true; $catSideFlow.FlowDirection = 'TopDown'; $catSideFlow.WrapContents = $false; $catSideFlow.Padding = New-Object System.Windows.Forms.Padding(14,6,4,12); $catSideFlow.BackColor = $Col.Panel
$catSide.Controls.Add($catSideFlow)
$pgCat.Controls.Add($catFlow); $pgCat.Controls.Add($catSide)

$catSideFlow.Controls.Add((New-SideLbl 'BUSCAR'))
$txtSearch = New-Txt 236 ''; $catSideFlow.Controls.Add($txtSearch)
$catSideFlow.Controls.Add((New-SideLbl 'ORDENAR POR'))
$cmbSort = New-Object System.Windows.Forms.ComboBox; $cmbSort.DropDownStyle = 'DropDownList'; $cmbSort.Width = 236; $cmbSort.BackColor = $Col.Card; $cmbSort.ForeColor = $Col.Txt; $cmbSort.FlatStyle = 'Flat'
foreach ($s in @('Mejor para mi equipo','Más rápidos primero','Tamaño (menor a mayor)','Tamaño (mayor a menor)','Nombre')) { [void]$cmbSort.Items.Add($s) }
$cmbSort.SelectedIndex = 0; $catSideFlow.Controls.Add($cmbSort)
$catSideFlow.Controls.Add((New-SideLbl 'CATEGORÍA'))
$catSideFlow.Controls.Add((New-ChipFlow @('Todas','General','Vision','Codigo','Razonamiento','Embeddings','Especializado','Personalizado') $CatNames 'cat'))
$catSideFlow.Controls.Add((New-SideLbl 'CAPACIDAD'))
$capKeys = @('Todas','Chat','Codigo','Vision','Video','Audio','OCR','Razonamiento','Herramientas','Embeddings','Multilingue'); $capNm = @{ Todas='Todas' }; foreach ($k in $CapNames.Keys) { $capNm[$k] = $CapNames[$k] }
$catSideFlow.Controls.Add((New-ChipFlow $capKeys $capNm 'cap'))
$catSideFlow.Controls.Add((New-SideLbl 'TAMAÑO DE DESCARGA'))
$catSideFlow.Controls.Add((New-ChipFlow @('Todos','< 3 GB','3-8 GB','8-20 GB','> 20 GB') $null 'size'))
$catSideFlow.Controls.Add((New-SideLbl 'COMPATIBILIDAD CON EL EQUIPO'))
$catSideFlow.Controls.Add((New-ChipFlow @('Todos','Compatibles','Solo GPU completa','Rápidos (12+ tok/s)') $null 'fit'))
$chkRec = New-Chk 'Solo destacados' $false; $chkRec.ForeColor = $Col.Amber; $catSideFlow.Controls.Add($chkRec)
$chkHideInst = New-Chk 'Ocultar instalados' $false; $catSideFlow.Controls.Add($chkHideInst)
$lblCount = New-Lbl '' $FSm $Col.Cyan; $catSideFlow.Controls.Add($lblCount)
$lblHwMini = New-Lbl '' $FSm $Col.Sub; $lblHwMini.AutoSize = $false; $lblHwMini.Size = New-Object System.Drawing.Size(236,34); $catSideFlow.Controls.Add($lblHwMini)
$catSideFlow.Controls.Add((New-SideLbl 'AÑADIR MÁS MODELOS'))
$btnExplore = New-Btn 'Buscar en ollama.com...' $Col.Cyan $Col.Cyan $false; $btnExplore.MinimumSize = New-Object System.Drawing.Size(236,30); $catSideFlow.Controls.Add($btnExplore)
$btnById = New-Btn 'Descargar por ID (ej. qwen3:8b)...' $Col.Txt $Col.Border $false; $btnById.MinimumSize = New-Object System.Drawing.Size(236,30); $catSideFlow.Controls.Add($btnById)
$btnCheckCat = New-Btn 'Verificar catálogo (tamaños reales)' $Col.Txt $Col.Border $false; $btnCheckCat.MinimumSize = New-Object System.Drawing.Size(236,30); $catSideFlow.Controls.Add($btnCheckCat)
$catSideFlow.Controls.Add((New-SideLbl 'KITS RÁPIDOS'))
$btnCodeKit = New-Btn 'Kit de programación (VS Code)...' $Col.White $Col.Acc $true; $btnCodeKit.MinimumSize = New-Object System.Drawing.Size(236,30); $catSideFlow.Controls.Add($btnCodeKit)
$btnImgKit = New-Btn 'Generar / editar imágenes...' $Col.Amber $Col.Amber $false; $btnImgKit.MinimumSize = New-Object System.Drawing.Size(236,30); $catSideFlow.Controls.Add($btnImgKit)
$legend = New-Lbl ("Velocidad = estimación según tu perfil de hardware (tok/s). Pulsa 'Probar' > 'Medir velocidad' para obtener la real.`n`nVisión/Video/Audio = ENTIENDEN esos contenidos, no los generan.") $FSm $Col.Sub
$legend.AutoSize = $false; $legend.Size = New-Object System.Drawing.Size(236,110); $catSideFlow.Controls.Add($legend)

$Script:SearchTimer = New-Object System.Windows.Forms.Timer; $Script:SearchTimer.Interval = 350
$Script:SearchTimer.Add_Tick({ $Script:SearchTimer.Stop(); $Script:F_Search = $txtSearch.Text.Trim(); ApplyFilters })
$txtSearch.Add_TextChanged({ $Script:SearchTimer.Stop(); $Script:SearchTimer.Start() })
$cmbSort.Add_SelectedIndexChanged({ $Script:F_Sort = $cmbSort.SelectedIndex; ApplyFilters })
$chkRec.Add_CheckedChanged({ $Script:F_Rec = $chkRec.Checked; ApplyFilters })
$chkHideInst.Add_CheckedChanged({ $Script:F_HideInst = $chkHideInst.Checked; ApplyFilters })
$btnExplore.Add_Click({ Open-Explorer })
$btnById.Add_Click({ Download-ById })
$btnCodeKit.Add_Click({ Open-CodeKit })
$btnImgKit.Add_Click({ Show-Page 'img' })
$btnCheckCat.Add_Click({
  $ids = @(); foreach ($e in $Script:Catalog) { $ids += $e.id }
  Add-Job @{ type='check'; cat='CATALOGO'; label=('Verificar catálogo ({0} modelos)' -f $ids.Count); ids=$ids } })

function New-CapChip([string]$t){
  $fg = $Col.Cyan; $bg = [System.Drawing.Color]::FromArgb(26,42,60)
  switch ($t) {
    'Codigo' { $fg = $Col.Green; $bg = [System.Drawing.Color]::FromArgb(20,50,40) }
    'Vision' { $fg = $Col.Amber; $bg = [System.Drawing.Color]::FromArgb(55,45,20) }
    'Video' { $fg = $Col.Purple; $bg = [System.Drawing.Color]::FromArgb(45,30,60) }
    'Audio' { $fg = $Col.Purple; $bg = [System.Drawing.Color]::FromArgb(45,30,60) }
    'OCR' { $fg = $Col.Amber; $bg = [System.Drawing.Color]::FromArgb(55,45,20) }
    'Razonamiento' { $fg = $Col.Red; $bg = [System.Drawing.Color]::FromArgb(55,25,30) }
    'Embeddings' { $fg = $Col.Orange; $bg = [System.Drawing.Color]::FromArgb(55,35,20) }
    'Herramientas' { $fg = $Col.Sub; $bg = [System.Drawing.Color]::FromArgb(40,44,60) }
  }
  $nm = $t; if ($CapNames.ContainsKey($t)) { $nm = $CapNames[$t] }
  $l = New-Object System.Windows.Forms.Label; $l.Text = $nm; $l.Font = $FSm; $l.ForeColor = $fg; $l.BackColor = $bg
  $l.AutoSize = $true; $l.Padding = New-Object System.Windows.Forms.Padding(5,1,5,1); $l.Margin = New-Object System.Windows.Forms.Padding(0,0,5,0); return $l
}

function New-SmallBtn([string]$text,[int]$x,[int]$w,[System.Drawing.Color]$fg,[System.Drawing.Color]$border,[bool]$filled){
  $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x,3); $b.Size = New-Object System.Drawing.Size($w,28)
  $b.FlatStyle = 'Flat'; $b.Font = $FSm; $b.Cursor = 'Hand'
  if ($filled) { $b.BackColor = $border; $b.ForeColor = $Col.White; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $Col.AccH }
  else { $b.BackColor = $Col.Card; $b.ForeColor = $fg; $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = $border }
  return $b
}
function Build-CardActions($e,$pn){
  foreach ($c in @($pn.Controls)) { try { $c.Dispose() } catch {} }; $pn.Controls.Clear()
  $id = $e.id
  if ($Script:Installed.ContainsKey($id)) {
    $l = New-Object System.Windows.Forms.Label; $l.Text = 'Instalado'; $l.Font = $FSmB; $l.ForeColor = $Col.Green; $l.AutoSize = $true; $l.Location = New-Object System.Drawing.Point(2,9); $pn.Controls.Add($l)
    $bT = New-SmallBtn 'Probar' 86 80 $Col.Green $Col.Green $false; $bT.Tag = $id; $bT.Add_Click({ param($s,$ev) Open-Chat ([string]$s.Tag) }); $pn.Controls.Add($bT)
    $bR = New-SmallBtn 'Quitar' 172 72 $Col.Red $Col.Red $false; $bR.Tag = $id; $bR.Add_Click({ param($s,$ev) Remove-Models @([string]$s.Tag) }); $pn.Controls.Add($bR)
  } elseif (Is-Downloading $id) {
    $bD = New-SmallBtn 'Descargando...' 0 160 $Col.White $Col.Acc $true; $bD.Enabled = $false; $pn.Controls.Add($bD)
  } elseif (Is-Queued $id) {
    $bD = New-SmallBtn 'En cola...' 0 100 $Col.Amber $Col.Amber $false; $bD.Enabled = $false; $pn.Controls.Add($bD)
    $bX = New-SmallBtn 'Quitar de cola' 106 110 $Col.Sub $Col.Border $false; $bX.Tag = $id; $bX.Add_Click({ param($s,$ev) Remove-FromQueue ([string]$s.Tag) }); $pn.Controls.Add($bX)
  } else {
    $f = Get-Fit $e
    $txt = ('Descargar ({0})' -f (Human ($e.gb * 1GB)))
    $bD = New-SmallBtn $txt 0 170 $Col.White $Col.Acc $true
    if (-not $f.ok) { $bD.BackColor = [System.Drawing.Color]::FromArgb(90,60,30); $bD.Text = ('Descargar igual ({0})' -f (Human ($e.gb * 1GB))) }
    $bD.Tag = $id; $bD.Add_Click({ param($s,$ev) Enqueue-Download ([string]$s.Tag) $false }); $pn.Controls.Add($bD)
  }
  $bI = New-SmallBtn 'Info' 262 58 $Col.Cyan $Col.Border $false; $bI.Tag = $id; $bI.Add_Click({ param($s,$ev) Open-Info ([string]$s.Tag) }); $pn.Controls.Add($bI)
}
function New-ModelCard($e){
  $f = Get-Fit $e
  $card = New-RP 12 $Col.Border; $card.Size = New-Object System.Drawing.Size(344,256); $card.BackColor = $Col.Card; $card.Margin = New-Object System.Windows.Forms.Padding(6)
  $nm = New-Object System.Windows.Forms.Label; $nm.Text = $(if ($e.rec) { '★ ' + $e.name } else { $e.name }); $nm.Font = $FBold; $nm.ForeColor = $(if ($e.rec) { $Col.Amber } else { $Col.Txt }); $nm.AutoSize = $false; $nm.AutoEllipsis = $true; $nm.Size = New-Object System.Drawing.Size(196,20); $nm.Location = New-Object System.Drawing.Point(12,10); $card.Controls.Add($nm)
  $bg = New-Object System.Windows.Forms.Label; $bg.Text = $ModeTxt[$f.mode]; $bg.Font = $FSmB; $bg.ForeColor = $ModeCol[$f.mode]; $bg.AutoSize = $true; $bg.BackColor = $Col.Bg; $bg.Padding = New-Object System.Windows.Forms.Padding(5,1,5,1)
  $card.Controls.Add($bg); $bg.Location = New-Object System.Drawing.Point((344 - 12 - $bg.PreferredWidth), 11)
  $vtxt = '≈'; if ($e.verified) { $vtxt = '✓' }
  $chk = ''; if ($Script:CheckState.ContainsKey($e.id) -and $Script:CheckState[$e.id] -ne '200') { $chk = '   ✗ NO DISPONIBLE (' + $Script:CheckState[$e.id] + ')' }
  $l1 = New-Object System.Windows.Forms.Label; $l1.Text = ('{0}   ·   {1} {2}{3}' -f $e.id,(Human ($e.gb * 1GB)),$vtxt,$chk); $l1.Font = $FMono; $l1.ForeColor = $(if ($chk) { $Col.Red } else { $Col.Sub }); $l1.AutoSize = $true; $l1.Location = New-Object System.Drawing.Point(12,33); $card.Controls.Add($l1)
  $ptxt = ''; if ([double]$e.p -gt 0 -and -not $e.user) { $ptxt = ('  ·  {0}B parámetros' -f $e.p) }
  $l2 = New-Object System.Windows.Forms.Label; $l2.Text = ($e.kind + $ptxt); $l2.Font = $FSm; $l2.ForeColor = $Col.Sub; $l2.AutoSize = $true; $l2.Location = New-Object System.Drawing.Point(12,52); $card.Controls.Add($l2)
  $sp = 'No cabe con este perfil de hardware'
  if ($f.ok) { $sp = ('≈ {0} tok/s ({1})  ·  memoria ≈ {2} GB' -f $f.tps,$f.speed,$f.need); if (@($e.caps) -contains 'Embeddings') { $sp = ('{0}  ·  memoria ≈ {1} GB' -f $f.speed,$f.need) } }
  if ($Script:Cfg.Bench.ContainsKey($e.id)) { $sp += ('  ·  medido {0:N0} tok/s' -f $Script:Cfg.Bench[$e.id]) }
  if (-not $f.disk -and -not $Script:Installed.ContainsKey($e.id)) { $sp += '  ·  SIN ESPACIO EN DISCO' }
  $l3 = New-Object System.Windows.Forms.Label; $l3.Text = $sp; $l3.Font = $FSm; $l3.ForeColor = (Speed-Color $f); $l3.AutoSize = $true; $l3.Location = New-Object System.Drawing.Point(12,70); $card.Controls.Add($l3)
  $cf = New-Object System.Windows.Forms.FlowLayoutPanel; $cf.Location = New-Object System.Drawing.Point(12,92); $cf.Size = New-Object System.Drawing.Size(320,22); $cf.WrapContents = $false; $cf.BackColor = $Col.Card
  $nC = 0; foreach ($c in @($e.caps)) { $nC++; if ($nC -le 5) { $cf.Controls.Add((New-CapChip $c)) } }
  if ($nC -gt 5) { $cf.Controls.Add((New-CapChip ('+' + ($nC - 5)))) }
  $card.Controls.Add($cf)
  $u = New-Object System.Windows.Forms.Label; $u.Text = ('Para qué: ' + $e.uso); $u.Font = $FSm; $u.ForeColor = $Col.Txt; $u.AutoSize = $false; $u.Size = New-Object System.Drawing.Size(320,46); $u.Location = New-Object System.Drawing.Point(12,120); $card.Controls.Add($u)
  if ($e.fuerte) { $fu = New-Object System.Windows.Forms.Label; $fu.Text = ('★ Fuerte: ' + $e.fuerte); $fu.Font = $FSmB; $fu.ForeColor = $Col.Green; $fu.AutoSize = $false; $fu.Size = New-Object System.Drawing.Size(320,34); $fu.Location = New-Object System.Drawing.Point(12,168); $card.Controls.Add($fu) }
  $pn = New-Object System.Windows.Forms.Panel; $pn.Location = New-Object System.Drawing.Point(12,212); $pn.Size = New-Object System.Drawing.Size(322,34); $pn.BackColor = $Col.Card; $card.Controls.Add($pn)
  $card.Tag = @{ e=$e; pn=$pn }
  Build-CardActions $e $pn
  return $card
}
function Sort-Key-Fit($e){ $f = Get-Fit $e; $r = 3; switch ($f.mode) { 'GPU' { $r = 0 } 'Hibrido' { $r = 1 } 'CPU' { $r = 2 } }; return $r }
function ApplyFilters {
  $catFlow.SuspendLayout()
  foreach ($ctl in @($catFlow.Controls)) { try { $ctl.Dispose() } catch {} }; $catFlow.Controls.Clear(); $Script:CardMap = @{}
  $q = $Script:F_Search.ToLower(); $sel = New-Object System.Collections.ArrayList
  foreach ($e in $Script:Catalog) {
    $cat = $e.cat; if ($e.user) { $cat = 'Personalizado' }
    if ($Script:F_Cat -ne 'Todas' -and $cat -ne $Script:F_Cat -and $e.cat -ne $Script:F_Cat) { continue }
    if ($Script:F_Cap -ne 'Todas' -and @($e.caps) -notcontains $Script:F_Cap) { continue }
    if ($Script:F_Rec -and -not $e.rec) { continue }
    if ($Script:F_HideInst -and $Script:Installed.ContainsKey($e.id)) { continue }
    $gb = [double]$e.gb; $fs = $Script:F_Size
    if ($fs -eq '< 3 GB' -and $gb -ge 3) { continue }
    if ($fs -eq '3-8 GB' -and ($gb -lt 3 -or $gb -gt 8)) { continue }
    if ($fs -eq '8-20 GB' -and ($gb -le 8 -or $gb -gt 20)) { continue }
    if ($fs -eq '> 20 GB' -and $gb -le 20) { continue }
    $f = Get-Fit $e; $ff = $Script:F_Fit
    if ($ff -eq 'Compatibles' -and -not $f.ok) { continue }
    if ($ff -eq 'Solo GPU completa' -and $f.mode -ne 'GPU') { continue }
    if ($ff -like 'R*pidos*' -and (-not $f.ok -or $f.tps -lt 12)) { continue }
    if ($q -and ($e.name + ' ' + $e.id + ' ' + $e.uso + ' ' + $e.fuerte + ' ' + (@($e.caps) -join ' ') + ' ' + $e.kind).ToLower().IndexOf($q) -lt 0) { continue }
    [void]$sel.Add($e)
  }
  $sorted = @()
  switch ($Script:F_Sort) {
    1 { $sorted = @($sel | Sort-Object @{ Expression={ (Get-Fit $_).tps }; Descending=$true }) }
    2 { $sorted = @($sel | Sort-Object @{ Expression={ [double]$_.gb } }) }
    3 { $sorted = @($sel | Sort-Object @{ Expression={ [double]$_.gb }; Descending=$true }) }
    4 { $sorted = @($sel | Sort-Object @{ Expression={ $_.name } }) }
    default { $sorted = @($sel | Sort-Object @{ Expression={ if ((Get-Fit $_).ok) { 0 } else { 1 } } }, @{ Expression={ if ($_.rec) { 0 } else { 1 } } }, @{ Expression={ Sort-Key-Fit $_ } }, @{ Expression={ $_.name } }) }
  }
  foreach ($e in $sorted) { $c = New-ModelCard $e; $Script:CardMap[$e.id] = $c; $catFlow.Controls.Add($c) }
  if ($q -and $q.Length -ge 2) {
    $catFlow.Controls.Add((New-SearchPanel $q $sorted.Count))
    if ($sorted.Count -eq 0) { Set-Status ('"{0}" no está en el catálogo: buscando en internet...' -f $q) }
  } elseif ($sorted.Count -eq 0) { $nr = New-Lbl 'No hay modelos que coincidan con los filtros.' $FNorm $Col.Sub; $nr.Margin = New-Object System.Windows.Forms.Padding(20,40,0,0); $catFlow.Controls.Add($nr) }
  $catFlow.ResumeLayout($true)
  $lblCount.Text = ('Mostrando {0} de {1} modelos' -f $sorted.Count,$Script:Catalog.Count)
}
function Update-CardStates { $Script:LastPct = -1; foreach ($k in @($Script:CardMap.Keys)) { $c = $Script:CardMap[$k]; try { Build-CardActions $c.Tag.e $c.Tag.pn } catch {} } }

# =====================================================================
#  PAGINA: INSTALADOS
# =====================================================================
$pgInst = New-Page 'inst'
$instBar = New-Object System.Windows.Forms.FlowLayoutPanel; $instBar.Dock = 'Top'; $instBar.AutoSize = $true; $instBar.AutoSizeMode = 'GrowAndShrink'; $instBar.WrapContents = $true; $instBar.Padding = New-Object System.Windows.Forms.Padding(12,10,12,4); $instBar.BackColor = $Col.Bg
$lvInst = New-LV @('Modelo=280','Tamaño=90','Instalado=130','Integridad=190','Actualización=210','Compatibilidad=150','Velocidad est.=110')
$lblInstInfo = New-Object System.Windows.Forms.Label; $lblInstInfo.Dock = 'Bottom'; $lblInstInfo.Height = 26; $lblInstInfo.ForeColor = $Col.Sub; $lblInstInfo.Font = $FSm; $lblInstInfo.TextAlign = 'MiddleLeft'; $lblInstInfo.Padding = New-Object System.Windows.Forms.Padding(12,0,0,0)
$instWrap = New-Object System.Windows.Forms.Panel; $instWrap.Dock = 'Fill'; $instWrap.Padding = New-Object System.Windows.Forms.Padding(12,4,12,4); $instWrap.Controls.Add($lvInst)
$pgInst.Controls.Add($instWrap); $pgInst.Controls.Add($lblInstInfo); $pgInst.Controls.Add($instBar)
function Inst-Btn([string]$t,[System.Drawing.Color]$c,[scriptblock]$a){ $b = New-Btn $t $c $c $false; $b.Add_Click($a); $instBar.Controls.Add($b); return $b }
function Get-Checked($lv){ $r = @(); foreach ($it in $lv.CheckedItems) { $r += [string]$it.Tag }; return $r }
function Get-Target($lv){ $r = @(Get-Checked $lv); if ($r.Count -eq 0 -and $lv.SelectedItems.Count -gt 0) { foreach ($it in $lv.SelectedItems) { $r += [string]$it.Tag } }; return $r }
[void](Inst-Btn 'Actualizar lista' $Col.Txt { Refresh-Installed; Refresh-InstalledLV })
[void](Inst-Btn 'Marcar todos' $Col.Sub { foreach ($it in $lvInst.Items) { $it.Checked = $true } })
[void](Inst-Btn 'Desmarcar' $Col.Sub { foreach ($it in $lvInst.Items) { $it.Checked = $false } })
[void](Inst-Btn 'Verificar (rápido)' $Col.Cyan { $ids = @(Get-Target $lvInst); if ($ids.Count -eq 0) { $ids = @($Script:Installed.Keys) }; if ($ids.Count -gt 0) { Add-Job @{ type='verify'; cat='VERIFICAR'; label=('Verificar {0} modelo(s)' -f $ids.Count); ids=$ids; deep=$false } } })
[void](Inst-Btn 'Verificar SHA-256 (completo)' $Col.Cyan { $ids = @(Get-Target $lvInst); if ($ids.Count -eq 0) { $ids = @($Script:Installed.Keys) }; if ($ids.Count -gt 0) { Add-Job @{ type='verify'; cat='VERIFICAR'; label=('Verificar SHA-256 de {0} modelo(s)' -f $ids.Count); ids=$ids; deep=$true } } })
[void](Inst-Btn 'Buscar actualizaciones' $Col.Amber { $ids = @(Get-Target $lvInst); if ($ids.Count -eq 0) { $ids = @($Script:Installed.Keys) }; if ($ids.Count -gt 0) { Add-Job @{ type='updates'; cat='ACTUALIZACIONES'; label=('Buscar actualizaciones ({0})' -f $ids.Count); ids=$ids } } })
[void](Inst-Btn 'Actualizar marcados' $Col.Amber { Update-Models })
[void](Inst-Btn 'Reparar dañados' $Col.Orange { Repair-Models })
[void](Inst-Btn 'Probar' $Col.Green { $t = @(Get-Target $lvInst); if ($t.Count -gt 0) { Open-Chat $t[0] } })
[void](Inst-Btn 'Exportar marcados' $Col.Purple { $t = @(Get-Target $lvInst); if ($t.Count -gt 0) { Export-Models $t } else { MsgInfo 'Marca uno o más modelos.' } })
[void](Inst-Btn 'Copiar "ollama run"' $Col.Sub { $t = @(Get-Target $lvInst); if ($t.Count -gt 0) { [System.Windows.Forms.Clipboard]::SetText(('ollama run {0}' -f $t[0])); Set-Status ('Copiado: ollama run {0}' -f $t[0]) } })
[void](Inst-Btn 'Quitar marcados' $Col.Red { $t = @(Get-Target $lvInst); if ($t.Count -gt 0) { Remove-Models $t } })
$lvInst.Add_DoubleClick({ if ($lvInst.SelectedItems.Count -gt 0) { Open-Chat ([string]$lvInst.SelectedItems[0].Tag) } })

function Refresh-InstalledLV {
  $lvInst.BeginUpdate(); $lvInst.Items.Clear(); [double]$tot = 0
  foreach ($id in ($Script:Installed.Keys | Sort-Object)) {
    $m = $Script:Installed[$id]; $tot += $m.bytes
    $e = Get-Entry $id; if (-not $e) { $e = Pseudo-Entry $id $m.bytes }
    $f = Get-Fit $e
    $it = New-Object System.Windows.Forms.ListViewItem($id); $it.Tag = $id; $it.UseItemStyleForSubItems = $false
    [void]$it.SubItems.Add((Human $m.bytes)); [void]$it.SubItems.Add($m.date.ToString('yyyy-MM-dd HH:mm'))
    $vs = '—'; if ($Script:VerifyState.ContainsKey($id)) { $vs = $Script:VerifyState[$id] }
    $us = '—'; if ($Script:UpdState.ContainsKey($id)) { $us = $Script:UpdState[$id] }
    $s1 = $it.SubItems.Add($vs); $s2 = $it.SubItems.Add($us)
    $s3 = $it.SubItems.Add($ModeTxt[$f.mode]); $s3.ForeColor = $ModeCol[$f.mode]
    $sp = '—'; if ($Script:Cfg.Bench.ContainsKey($id)) { $sp = ('{0:N0} tok/s (medido)' -f $Script:Cfg.Bench[$id]) } elseif ($f.ok -and @($e.caps) -notcontains 'Embeddings') { $sp = ('≈ {0} tok/s' -f $f.tps) }
    [void]$it.SubItems.Add($sp)
    if ($vs -like 'OK*') { $s1.ForeColor = $Col.Green } elseif ($vs -ne '—') { $s1.ForeColor = $Col.Red } else { $s1.ForeColor = $Col.Sub }
    if ($us -like 'Al d*') { $s2.ForeColor = $Col.Green } elseif ($us -like 'Actualizaci*') { $s2.ForeColor = $Col.Amber } else { $s2.ForeColor = $Col.Sub }
    [void]$lvInst.Items.Add($it)
  }
  $lvInst.EndUpdate()
  $lblInstInfo.Text = ('{0} modelos instalados  ·  {1} en total  ·  Carpeta: {2}  ·  Libre en disco: {3} GB' -f $Script:Installed.Count,(Human $tot),$Script:Models,$Script:HwDet.Disk)
}

# =====================================================================
#  PAGINA: OFFLINE (EXPORTAR / IMPORTAR)
# =====================================================================
$pgOff = New-Page 'off'
$offExp = New-Object System.Windows.Forms.Panel; $offExp.Dock = 'Top'; $offExp.Height = 236; $offExp.Padding = New-Object System.Windows.Forms.Padding(12,10,12,6); $offExp.BackColor = $Col.Bg
$expBox = New-RP 10 $Col.Purple; $expBox.Dock = 'Fill'; $expBox.BackColor = $Col.Card; $expBox.Padding = New-Object System.Windows.Forms.Padding(16,12,16,8); $offExp.Controls.Add($expBox)
$expFlow = New-Object System.Windows.Forms.FlowLayoutPanel; $expFlow.Dock = 'Fill'; $expFlow.FlowDirection = 'LeftToRight'; $expFlow.WrapContents = $true; $expFlow.BackColor = $Col.Card; $expBox.Controls.Add($expFlow)
$t1 = New-Lbl 'EXPORTAR A UN REPOSITORIO OFFLINE  (USB, disco externo, carpeta de red)' $FH2 $Col.Purple; $expFlow.Controls.Add($t1); $expFlow.SetFlowBreak($t1,$true)
$d1 = New-Lbl 'Guarda los modelos instalados para reinstalarlos en este u otros PCs sin internet. Los archivos compartidos entre modelos se guardan una sola vez y la copia se reanuda si se interrumpe.' $FSm $Col.Sub; $d1.MaximumSize = New-Object System.Drawing.Size(1000,0); $expFlow.Controls.Add($d1); $expFlow.SetFlowBreak($d1,$true)
$expFlow.Controls.Add((New-Lbl 'Carpeta destino:' $FSm $Col.Txt))
$txtExp = New-Txt 560 ([string]$Script:Cfg.RepoExport); $expFlow.Controls.Add($txtExp)
$btnExpBrowse = New-Btn 'Examinar...' $Col.Txt $Col.Border $false; $expFlow.Controls.Add($btnExpBrowse)
$btnExpOpen = New-Btn 'Abrir' $Col.Sub $Col.Border $false; $expFlow.Controls.Add($btnExpOpen); $expFlow.SetFlowBreak($btnExpOpen,$true)
$chkExpInst = New-Chk 'Incluir instalador de Ollama' ([bool]$Script:Cfg.ExpInstaller); $expFlow.Controls.Add($chkExpInst)
$chkExpApp = New-Chk 'Incluir esta app (.bat)' ([bool]$Script:Cfg.ExpApp); $expFlow.Controls.Add($chkExpApp)
$chkExpVer = New-Chk 'Verificar SHA-256 tras copiar (más lento, más seguro)' ([bool]$Script:Cfg.VerifyExport); $expFlow.Controls.Add($chkExpVer)
$chkAutoRepo = New-Chk 'Guardar copia automática de cada modelo que descargue' ([bool]$Script:Cfg.AutoRepo); $expFlow.Controls.Add($chkAutoRepo); $expFlow.SetFlowBreak($chkAutoRepo,$true)
$btnExpSel = New-Btn 'Exportar los marcados en "Instalados"' $Col.White $Col.Purple $true; $expFlow.Controls.Add($btnExpSel)
$btnExpAll = New-Btn 'Exportar TODOS los instalados' $Col.Purple $Col.Purple $false; $expFlow.Controls.Add($btnExpAll)
$btnInstDl = New-Btn 'Descargar / actualizar instalador de Ollama' $Col.Cyan $Col.Cyan $false; $expFlow.Controls.Add($btnInstDl)
$btnExpImg = New-Btn 'Exportar paquete de IMAGEN (motor + modelos)' $Col.Amber $Col.Amber $false; $expFlow.Controls.Add($btnExpImg)
$lblInstState = New-Lbl '' $FSm $Col.Sub; $expFlow.Controls.Add($lblInstState)

$offImp = New-Object System.Windows.Forms.Panel; $offImp.Dock = 'Fill'; $offImp.Padding = New-Object System.Windows.Forms.Padding(12,6,12,10); $offImp.BackColor = $Col.Bg
$impBox = New-RP 10 $Col.Green; $impBox.Dock = 'Fill'; $impBox.BackColor = $Col.Card; $impBox.Padding = New-Object System.Windows.Forms.Padding(16,12,16,12); $offImp.Controls.Add($impBox)
$impTop = New-Object System.Windows.Forms.FlowLayoutPanel; $impTop.Dock = 'Top'; $impTop.AutoSize = $true; $impTop.AutoSizeMode = 'GrowAndShrink'; $impTop.WrapContents = $true; $impTop.BackColor = $Col.Card
$t2 = New-Lbl 'IMPORTAR DESDE UN REPOSITORIO OFFLINE' $FH2 $Col.Green; $impTop.Controls.Add($t2); $impTop.SetFlowBreak($t2,$true)
$impTop.Controls.Add((New-Lbl 'Repositorio origen:' $FSm $Col.Txt))
$txtImp = New-Txt 520 ([string]$Script:Cfg.RepoImport); $impTop.Controls.Add($txtImp)
$btnImpBrowse = New-Btn 'Examinar...' $Col.Txt $Col.Border $false; $impTop.Controls.Add($btnImpBrowse)
$btnImpRead = New-Btn 'Leer repositorio' $Col.Green $Col.Green $false; $impTop.Controls.Add($btnImpRead); $impTop.SetFlowBreak($btnImpRead,$true)
$chkImpVer = New-Chk 'Verificar SHA-256 al importar (recomendado)' ([bool]$Script:Cfg.VerifyImport); $impTop.Controls.Add($chkImpVer)
$btnImpSel = New-Btn 'Importar marcados' $Col.White $Col.Green $true; $btnImpSel.BackColor = [System.Drawing.Color]::FromArgb(22,120,90); $impTop.Controls.Add($btnImpSel)
$btnImpNew = New-Btn 'Importar todos los nuevos' $Col.Green $Col.Green $false; $impTop.Controls.Add($btnImpNew)
$btnImpOll = New-Btn 'Instalar Ollama desde el repositorio' $Col.Cyan $Col.Cyan $false; $impTop.Controls.Add($btnImpOll)
$btnGguf = New-Btn 'Importar archivo GGUF...' $Col.Orange $Col.Orange $false; $impTop.Controls.Add($btnGguf)
$btnImpImg = New-Btn 'Importar paquete de IMAGEN' $Col.Amber $Col.Amber $false; $impTop.Controls.Add($btnImpImg)
$lvRepo = New-LV @('Modelo=280','Tamaño=90','Estado=170','Exportado=130','Desde equipo=120','Para qué sirve=420')
$repoWrap = New-Object System.Windows.Forms.Panel; $repoWrap.Dock = 'Fill'; $repoWrap.Padding = New-Object System.Windows.Forms.Padding(0,8,0,0); $repoWrap.BackColor = $Col.Card; $repoWrap.Controls.Add($lvRepo)
$lblRepoInfo = New-Lbl '' $FSm $Col.Sub; $lblRepoInfo.Dock = 'Bottom'; $lblRepoInfo.AutoSize = $false; $lblRepoInfo.Height = 22
$impBox.Controls.Add($repoWrap); $impBox.Controls.Add($lblRepoInfo); $impBox.Controls.Add($impTop)
$pgOff.Controls.Add($offImp); $pgOff.Controls.Add($offExp)

function Pick-Folder([string]$desc,[string]$start){
  $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = $desc; $d.ShowNewFolderButton = $true
  if ($start -and (Test-Path -LiteralPath $start)) { $d.SelectedPath = $start }
  if ($d.ShowDialog($form) -eq 'OK') { return $d.SelectedPath }; return $null
}
function Save-OffCfg { $Script:Cfg.RepoExport = $txtExp.Text.Trim(); $Script:Cfg.RepoImport = $txtImp.Text.Trim(); $Script:Cfg.ExpInstaller = $chkExpInst.Checked; $Script:Cfg.ExpApp = $chkExpApp.Checked; $Script:Cfg.VerifyExport = $chkExpVer.Checked; $Script:Cfg.VerifyImport = $chkImpVer.Checked; $Script:Cfg.AutoRepo = $chkAutoRepo.Checked; Save-Config }
$btnExpBrowse.Add_Click({ $p = Pick-Folder 'Elige la carpeta (o unidad USB) donde guardar el repositorio offline' $txtExp.Text; if ($p) { if ((Split-Path $p -Leaf) -ne 'OllamaRepo' -and -not (Test-Path -LiteralPath (Join-Path $p 'repo.json'))) { $p = Join-Path $p 'OllamaRepo' }; $txtExp.Text = $p; Save-OffCfg } })
$btnExpOpen.Add_Click({ $p = $txtExp.Text.Trim(); if ($p -and (Test-Path -LiteralPath $p)) { Start-Process explorer.exe $p } })
$btnImpBrowse.Add_Click({ $p = Pick-Folder 'Elige la carpeta del repositorio offline (la que contiene blobs y manifests)' $txtImp.Text; if ($p) { $txtImp.Text = $p; Save-OffCfg; Read-Repo } })
$btnImpRead.Add_Click({ Save-OffCfg; Read-Repo })
foreach ($c in @($chkExpInst,$chkExpApp,$chkExpVer,$chkImpVer,$chkAutoRepo)) { $c.Add_CheckedChanged({ Save-OffCfg }) }
$btnExpSel.Add_Click({ $t = @(Get-Checked $lvInst); if ($t.Count -eq 0) { MsgInfo 'Ve a la pestaña "Instalados" y marca los modelos que quieres exportar.'; Show-Page 'inst'; return }; Export-Models $t })
$btnExpAll.Add_Click({ $t = @($Script:Installed.Keys); if ($t.Count -eq 0) { MsgInfo 'No hay modelos instalados.'; return }; Export-Models $t })
$btnInstDl.Add_Click({ Add-Job @{ type='installer'; cat='INSTALADOR'; label='Descargar instalador de Ollama'; id='OllamaSetup.exe' } })
$btnImpSel.Add_Click({ $t = @(Get-Checked $lvRepo); if ($t.Count -eq 0) { MsgInfo 'Marca los modelos a importar en la lista.'; return }; Import-Models $t })
$btnImpNew.Add_Click({ $t = @(); foreach ($it in $lvRepo.Items) { if ($it.SubItems[2].Text -ne 'Ya instalado') { $t += [string]$it.Tag } }; if ($t.Count -eq 0) { MsgInfo 'No hay modelos nuevos en el repositorio.'; return }; Import-Models $t })
$btnImpOll.Add_Click({
  $p = Join-Path $txtImp.Text.Trim() 'instalador\OllamaSetup.exe'
  if (-not (Test-Path -LiteralPath $p)) { $p = Join-Path $InstDir 'OllamaSetup.exe' }
  if (Test-Path -LiteralPath $p) { if (MsgYes ('Se ejecutará el instalador de Ollama:' + "`n" + $p + "`n`n¿Continuar?")) { Start-Process -FilePath $p; Write-Log 'INFO' 'INSTALADOR' ('Ejecutado ' + $p); Add-History 'Instalar Ollama' 'OllamaSetup.exe' 'Lanzado' 0 0 $p } }
  else { MsgWarn 'No se encontró OllamaSetup.exe en el repositorio ni en esta app. Descárgalo primero (requiere internet una vez).' } })
$btnGguf.Add_Click({ Import-Gguf })
$btnExpImg.Add_Click({
  $repo = $txtExp.Text.Trim()
  if (-not $repo) { $p = Pick-Folder 'Elige la carpeta (o unidad USB) donde guardar el repositorio offline' ''; if (-not $p) { return }; $repo = Join-Path $p 'OllamaRepo'; $txtExp.Text = $repo; Save-OffCfg }
  if (-not (Get-SdExe) -and (Get-ChildItem -LiteralPath $ImgModels -File -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) { MsgInfo 'Aún no has descargado el motor ni modelos de imagen (pestaña Imagen).'; return }
  New-Item -ItemType Directory -Force -Path $repo | Out-Null
  Add-Job @{ type='copytree'; cat='EXPORTAR'; label=('Exportar paquete de imagen a ' + $repo); id='Paquete de imagen'; acc='Paquete imagen'; pairs=@(@{ src=$ImgMotor; dst=(Join-Path $repo 'imagen\motor') }, @{ src=$ImgModels; dst=(Join-Path $repo 'imagen\modelos') }) } })
$btnImpImg.Add_Click({
  $repo = $txtImp.Text.Trim(); $src = Join-Path $repo 'imagen'
  if (-not $repo -or -not (Test-Path -LiteralPath $src)) { MsgInfo 'Este repositorio no contiene un paquete de imagen (carpeta "imagen").'; return }
  if ($Script:ImgBusy) { MsgWarn 'Espera a que termine la generación.'; return }
  Add-Job @{ type='copytree'; cat='IMPORTAR'; label='Importar paquete de imagen'; id='Paquete de imagen'; acc='Paquete imagen'; pairs=@(@{ src=(Join-Path $src 'motor'); dst=$ImgMotor }, @{ src=(Join-Path $src 'modelos'); dst=$ImgModels }) } })
function Update-InstallerLabel { $p = Join-Path $InstDir 'OllamaSetup.exe'; if (Test-Path -LiteralPath $p) { $fi = Get-Item -LiteralPath $p; $lblInstState.Text = ('Instalador guardado: {0} ({1})' -f (Human $fi.Length),$fi.LastWriteTime.ToString('yyyy-MM-dd')); $lblInstState.ForeColor = $Col.Green } else { $lblInstState.Text = 'Instalador de Ollama: no descargado'; $lblInstState.ForeColor = $Col.Sub } }

function Read-Repo {
  $repo = $txtImp.Text.Trim(); $lvRepo.Items.Clear(); $Script:RepoModels = @{}
  if (-not $repo -or -not (Test-Path -LiteralPath (Join-Path $repo 'manifests'))) { $lblRepoInfo.Text = 'Elige una carpeta que contenga "manifests" y "blobs" (creada con Exportar).'; return }
  $map = Get-ManifestMap $repo; $Script:RepoModels = $map
  $meta = @{}; $rj = Join-Path $repo 'repo.json'
  if (Test-Path -LiteralPath $rj) { try { foreach ($o in @(Get-Content -LiteralPath $rj -Raw -Encoding UTF8 | ConvertFrom-Json)) { $meta[[string]$o.id] = $o } } catch {} }
  [double]$tot = 0; $nNew = 0
  $lvRepo.BeginUpdate()
  foreach ($id in ($map.Keys | Sort-Object)) {
    $m = $map[$id]; $tot += $m.bytes
    $miss = 0; foreach ($d in $m.digests) { if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $repo 'blobs') ('sha256-' + $d.Split(':')[1])))) { $miss++ } }
    $st = 'Nuevo'; $stc = $Col.Cyan
    if ($Script:Installed.ContainsKey($id)) { if ($Script:Installed[$id].key -eq $m.key) { $st = 'Ya instalado'; $stc = $Col.Green } else { $st = 'Versión distinta'; $stc = $Col.Amber } }
    if ($miss -gt 0) { $st = ('Incompleto (faltan {0})' -f $miss); $stc = $Col.Red }
    if ($st -eq 'Nuevo') { $nNew++ }
    $it = New-Object System.Windows.Forms.ListViewItem($id); $it.Tag = $id; $it.UseItemStyleForSubItems = $false
    [void]$it.SubItems.Add((Human $m.bytes)); $s = $it.SubItems.Add($st); $s.ForeColor = $stc
    $fe = $m.date.ToString('yyyy-MM-dd HH:mm'); $eq = ''; $uso = ''
    if ($meta.ContainsKey($id)) { $fe = [string]$meta[$id].fecha; $eq = [string]$meta[$id].equipo; $uso = [string]$meta[$id].uso }
    if (-not $uso) { $ce = Get-Entry $id; if ($ce) { $uso = $ce.uso } }
    [void]$it.SubItems.Add($fe); [void]$it.SubItems.Add($eq); [void]$it.SubItems.Add($uso)
    if ($st -eq 'Nuevo' -or $st -eq 'Versión distinta') { $it.Checked = $true }
    [void]$lvRepo.Items.Add($it)
  }
  $lvRepo.EndUpdate()
  $hasInst = Test-Path -LiteralPath (Join-Path $repo 'instalador\OllamaSetup.exe')
  $lblRepoInfo.Text = ('{0} modelos en el repositorio ({1})  ·  {2} nuevos para este PC  ·  Instalador de Ollama: {3}' -f $map.Count,(Human $tot),$nNew,$(if ($hasInst) { 'incluido' } else { 'no incluido' }))
  Write-Log 'INFO' 'IMPORTAR' ('Repositorio leído: {0} ({1} modelos)' -f $repo,$map.Count)
}
function Export-Models($ids){
  $repo = $txtExp.Text.Trim()
  if (-not $repo) { $p = Pick-Folder 'Elige la carpeta (o unidad USB) donde guardar el repositorio offline' ''; if (-not $p) { return }; $repo = Join-Path $p 'OllamaRepo'; $txtExp.Text = $repo }
  try { New-Item -ItemType Directory -Force -Path $repo | Out-Null } catch { MsgWarn ('No se puede crear la carpeta: ' + $repo); return }
  Save-OffCfg
  $meta = @{}; foreach ($id in $ids) { $e = Get-Entry $id; if ($e) { $meta[$id] = @{ name=$e.name; cat=$e.cat; uso=$e.uso } } }
  Add-Job @{ type='export'; cat='EXPORTAR'; label=('Exportar {0} modelo(s) a {1}' -f @($ids).Count,$repo); ids=@($ids); repo=$repo; verify=$chkExpVer.Checked; installer=$chkExpInst.Checked; app=$chkExpApp.Checked; meta=$meta }
}
function Import-Models($ids){
  $repo = $txtImp.Text.Trim(); if (-not $repo) { return }
  Add-Job @{ type='import'; cat='IMPORTAR'; label=('Importar {0} modelo(s) desde {1}' -f @($ids).Count,$repo); ids=@($ids); repo=$repo; verify=$chkImpVer.Checked }
}
function Import-Gguf {
  $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Modelos GGUF (*.gguf)|*.gguf'; $d.Title = 'Elige un archivo GGUF (por ejemplo descargado de Hugging Face)'
  if ($d.ShowDialog($form) -ne 'OK') { return }
  if (-not $Script:OllamaExe) { MsgWarn 'Ollama no está instalado en este PC.'; return }
  if (-not (Test-OllamaApi)) { MsgWarn 'El servicio de Ollama debe estar activo para importar un GGUF. Pulsa "Iniciar Ollama".'; return }
  $def = ([IO.Path]::GetFileNameWithoutExtension($d.FileName)).ToLower() -replace '[^a-z0-9._-]','-'
  $name = [Microsoft.VisualBasic.Interaction]::InputBox('Nombre para el modelo en Ollama (ej. mimodelo:q4):','Importar GGUF',$def)
  if (-not $name) { return }; $name = $name.Trim().ToLower()
  if ($name -notmatch '^[a-z0-9][a-z0-9._\-/]*(:[a-z0-9._\-]+)?$') { MsgWarn 'Nombre no válido. Usa letras minúsculas, números, guiones y opcionalmente :etiqueta.'; return }
  Add-Job @{ type='gguf'; cat='GGUF'; label=('Importar GGUF como {0}' -f $name); id=$name; file=$d.FileName }
}

# =====================================================================
#  PAGINA: MI EQUIPO
# =====================================================================
$pgHw = New-Page 'hw'
$hwTop = New-Object System.Windows.Forms.FlowLayoutPanel; $hwTop.Dock = 'Top'; $hwTop.Height = 372; $hwTop.WrapContents = $false; $hwTop.Padding = New-Object System.Windows.Forms.Padding(12,12,12,0); $hwTop.BackColor = $Col.Bg; $hwTop.AutoScroll = $true
$boxDet = New-Box 400 352 'EQUIPO DETECTADO'
$lblDet = New-Object System.Windows.Forms.Label; $lblDet.Font = $FSm; $lblDet.ForeColor = $Col.Txt; $lblDet.Location = New-Object System.Drawing.Point(14,34); $lblDet.Size = New-Object System.Drawing.Size(372,270); $boxDet.Controls.Add($lblDet)
$btnRedetect = New-SmallBtn 'Volver a detectar' 14 140 $Col.Cyan $Col.Cyan $false; $btnRedetect.Location = New-Object System.Drawing.Point(14,310); $boxDet.Controls.Add($btnRedetect)
$boxProf = New-Box 440 352 'PERFIL PARA CALCULAR LA COMPATIBILIDAD'
$rbDet = New-Object System.Windows.Forms.RadioButton; $rbDet.Text = 'Usar el equipo detectado (este PC)'; $rbDet.ForeColor = $Col.Txt; $rbDet.Font = $FSm; $rbDet.AutoSize = $true; $rbDet.Location = New-Object System.Drawing.Point(14,34); $boxProf.Controls.Add($rbDet)
$rbMan = New-Object System.Windows.Forms.RadioButton; $rbMan.Text = 'Usar datos manuales (para preparar modelos para OTRO PC)'; $rbMan.ForeColor = $Col.Txt; $rbMan.Font = $FSm; $rbMan.AutoSize = $true; $rbMan.Location = New-Object System.Drawing.Point(14,58); $boxProf.Controls.Add($rbMan)
$lp = New-Object System.Windows.Forms.Label; $lp.Text = 'Perfil rápido:'; $lp.ForeColor = $Col.Sub; $lp.Font = $FSm; $lp.AutoSize = $true; $lp.Location = New-Object System.Drawing.Point(14,92); $boxProf.Controls.Add($lp)
$cmbPreset = New-Object System.Windows.Forms.ComboBox; $cmbPreset.DropDownStyle = 'DropDownList'; $cmbPreset.Width = 320; $cmbPreset.Location = New-Object System.Drawing.Point(104,88); $cmbPreset.BackColor = $Col.Card; $cmbPreset.ForeColor = $Col.Txt; $cmbPreset.FlatStyle = 'Flat'; $boxProf.Controls.Add($cmbPreset)
$Presets = @(
  @{ n='(elegir perfil...)'; r=-1 },
  @{ n='Portátil básico: 8 GB RAM, sin GPU'; r=8; v=0; g=$false; rb=25; gb=0 },
  @{ n='PC de oficina: 16 GB RAM, sin GPU'; r=16; v=0; g=$false; rb=35; gb=0 },
  @{ n='PC gaming: 16 GB RAM + GPU 8 GB'; r=16; v=8; g=$true; rb=40; gb=250 },
  @{ n='PC potente: 32 GB RAM + GPU 8 GB'; r=32; v=8; g=$true; rb=45; gb=250 },
  @{ n='Alta gama: 32 GB RAM + GPU 16 GB'; r=32; v=16; g=$true; rb=50; gb=450 },
  @{ n='Workstation: 64 GB RAM + GPU 24 GB'; r=64; v=24; g=$true; rb=60; gb=900 },
  @{ n='Servidor: 128 GB RAM + 2x GPU 24 GB'; r=128; v=48; g=$true; rb=80; gb=900 }
)
foreach ($pr in $Presets) { [void]$cmbPreset.Items.Add($pr.n) }; $cmbPreset.SelectedIndex = 0
function Add-NumRow([string]$label,[int]$y,$num){ $l = New-Object System.Windows.Forms.Label; $l.Text = $label; $l.ForeColor = $Col.Txt; $l.Font = $FSm; $l.AutoSize = $true; $l.Location = New-Object System.Drawing.Point(14,($y + 3)); $boxProf.Controls.Add($l); $num.Location = New-Object System.Drawing.Point(300,$y); $boxProf.Controls.Add($num) }
$numRam = New-Num 1 1024 ([double]$Script:Cfg.MRam) 0 1; Add-NumRow 'Memoria RAM (GB):' 126 $numRam
$numVram = New-Num 0 512 ([double]$Script:Cfg.MVram) 0 1; Add-NumRow 'Memoria de la GPU / VRAM (GB):' 156 $numVram
$chkGpuOk = New-Chk 'La GPU es utilizable por Ollama (NVIDIA, AMD ROCm/Vulkan, Intel Arc)' ([bool]$Script:Cfg.MGpuOk); $chkGpuOk.Location = New-Object System.Drawing.Point(14,186); $boxProf.Controls.Add($chkGpuOk)
$numRamBw = New-Num 5 1000 ([double]$Script:Cfg.MRamBw) 0 5; Add-NumRow 'Ancho de banda RAM (GB/s) [avanzado]:' 214 $numRamBw
$numGpuBw = New-Num 20 4000 ([double]$Script:Cfg.MGpuBw) 0 10; Add-NumRow 'Ancho de banda GPU (GB/s) [avanzado]:' 244 $numGpuBw
$btnHwApply = New-SmallBtn 'Aplicar perfil' 14 140 $Col.White $Col.Acc $true; $btnHwApply.Location = New-Object System.Drawing.Point(14,284); $boxProf.Controls.Add($btnHwApply)
$lnote = New-Object System.Windows.Forms.Label; $lnote.Text = 'El catálogo marcará cada modelo según este perfil.'; $lnote.ForeColor = $Col.Sub; $lnote.Font = $FSm; $lnote.AutoSize = $false; $lnote.Size = New-Object System.Drawing.Size(260,40); $lnote.Location = New-Object System.Drawing.Point(164,286); $boxProf.Controls.Add($lnote)
$boxSum = New-Box 380 352 'RESUMEN CON ESTE PERFIL'
$lblSum = New-Object System.Windows.Forms.Label; $lblSum.Font = $FSm; $lblSum.ForeColor = $Col.Txt; $lblSum.Location = New-Object System.Drawing.Point(14,34); $lblSum.Size = New-Object System.Drawing.Size(352,306); $boxSum.Controls.Add($lblSum)
$hwTop.Controls.Add($boxDet); $hwTop.Controls.Add($boxProf); $hwTop.Controls.Add($boxSum)
$hwBot = New-Object System.Windows.Forms.Panel; $hwBot.Dock = 'Fill'; $hwBot.Padding = New-Object System.Windows.Forms.Padding(12,4,12,10); $hwBot.BackColor = $Col.Bg
$hwBar = New-Object System.Windows.Forms.FlowLayoutPanel; $hwBar.Dock = 'Top'; $hwBar.AutoSize = $true; $hwBar.AutoSizeMode = 'GrowAndShrink'; $hwBar.BackColor = $Col.Bg
$hwBar.Controls.Add((New-Lbl 'RECOMENDADOS PARA ESTE PERFIL (el más capaz que funciona con fluidez en cada categoría)' $FSmB $Col.Sub))
$btnDlRec = New-Btn 'Descargar los marcados' $Col.White $Col.Acc $true; $hwBar.Controls.Add($btnDlRec)
$lvRec = New-LV @('Categoría=150','Modelo recomendado=240','ID=200','Modo=150','Velocidad est.=120','Tamaño=90','Por qué=420')
$hwBot.Controls.Add($lvRec); $hwBot.Controls.Add($hwBar)
$pgHw.Controls.Add($hwBot); $pgHw.Controls.Add($hwTop)

$cmbPreset.Add_SelectedIndexChanged({ $pr = $Presets[$cmbPreset.SelectedIndex]; if ($pr.r -lt 0) { return }; $rbMan.Checked = $true; $numRam.Value = [decimal]$pr.r; $numVram.Value = [decimal]$pr.v; $chkGpuOk.Checked = $pr.g; $numRamBw.Value = [decimal]$pr.rb; if ($pr.gb -gt 0) { $numGpuBw.Value = [decimal]$pr.gb } })
$btnHwApply.Add_Click({
  $Script:Cfg.HwManual = $rbMan.Checked; $Script:Cfg.MRam = [double]$numRam.Value; $Script:Cfg.MVram = [double]$numVram.Value; $Script:Cfg.MGpuOk = $chkGpuOk.Checked
  $Script:Cfg.MRamBw = [double]$numRamBw.Value; $Script:Cfg.MGpuBw = [double]$numGpuBw.Value; Save-Config
  Build-HwEff; Refresh-Compat; Write-Log 'INFO' 'EQUIPO' ('Perfil aplicado: ' + $Script:HwEff.Label); Set-Status $Script:HwEff.Label })
$btnRedetect.Add_Click({ [System.Windows.Forms.Cursor]::Current = 'WaitCursor'; $Script:HwDet = Detect-Hardware; Build-HwEff; Fill-HwPage; Refresh-Compat })
$btnDlRec.Add_Click({ $t = @(Get-Checked $lvRec); foreach ($id in $t) { Enqueue-Download $id $true } })

function Fill-HwPage {
  $d = $Script:HwDet; $nl = [Environment]::NewLine
  $g = ''; foreach ($x in $d.Gpus) { $g += ('   · {0}  ({1} GB){2}' -f $x.Name,$x.Vram,$nl) }; if (-not $g) { $g = '   · (no detectada)' + $nl }
  $ov = 'no detectado'; if ($Script:OllamaExe) { $ov = 'instalado'; if ($Script:OllamaVer) { $ov = 'v' + $Script:OllamaVer + ' (activo)' } }
  $lblDet.Text = ('Procesador:{0}   {1}{0}   {2} núcleos / {3} hilos{0}{0}Memoria RAM: {4} GB   (ancho de banda est. {5} GB/s){0}{0}Tarjetas gráficas:{0}{6}{0}GPU para IA: {7}{0}{8}{0}{0}Disco libre (carpeta de modelos): {9} GB{0}Ollama: {10}' -f $nl,$d.Cpu,$d.Cores,$d.Threads,$d.Ram,$d.RamBw,$g,$(if ($d.GpuOk) { ('{0} ({1} GB)' -f $d.Gpu,$d.Vram) } else { 'ninguna utilizable' }),$d.Note,$d.Disk,$ov)
  if ($d.NeedVulkan) { $lblDet.Text += $nl + ('Vulkan en Ollama: {0}' -f $(if (Vulkan-On) { 'ACTIVADO ✓' } else { 'DESACTIVADO (la GPU no se usa: actívalo en Ajustes)' })) }
  if ($Script:Cfg.HwManual) { $rbMan.Checked = $true } else { $rbDet.Checked = $true }
  if (-not $Script:Cfg.HwManual) { $numRam.Value = [decimal][Math]::Min(1024,[Math]::Max(1,[Math]::Round($d.Ram))); $numVram.Value = [decimal][Math]::Min(512,[Math]::Round($d.Vram)); $chkGpuOk.Checked = $d.GpuOk; $numRamBw.Value = [decimal][Math]::Min(1000,[Math]::Max(5,$d.RamBw)); $numGpuBw.Value = [decimal][Math]::Min(4000,[Math]::Max(20,$d.GpuBw)) }
}
function Update-HwSummary {
  $c = @{ GPU=0; Hibrido=0; CPU=0; NoCabe=0 }
  foreach ($e in $Script:Catalog) { $f = Get-Fit $e; $c[$f.mode]++ }
  $h = $Script:HwEff; $nl = [Environment]::NewLine
  $lblSum.Text = ('{0}{1}{1}De {2} modelos del catálogo:{1}{1}   ●  {3}  caben completos en la GPU (máxima velocidad){1}   ●  {4}  funcionan con GPU + RAM{1}   ●  {5}  funcionan solo con CPU + RAM (más lentos){1}   ●  {6}  no caben en memoria{1}{1}Memoria útil estimada: {7:N1} GB VRAM + {8:N1} GB RAM{1}{1}Las velocidades son estimaciones (Q4, contexto corto). La real depende del driver, la GPU y el contexto: mídela con "Probar".' -f $h.Label,$nl,$Script:Catalog.Count,$c.GPU,$c.Hibrido,$c.CPU,$c.NoCabe,$(if ($h.GpuOk) { [Math]::Max(0,$h.Vram - 0.7) } else { 0 }),[Math]::Max(0.5,$h.Ram * 0.85 - 2.5))
  $lblHwMini.Text = $h.Label
  $lvRec.BeginUpdate(); $lvRec.Items.Clear()
  foreach ($cat in @(@('General','Asistente general'),@('Vision','Visión / OCR'),@('Codigo','Programación'),@('Razonamiento','Razonamiento'),@('Embeddings','Embeddings (RAG)'),@('Especializado','Traducción / otros'))) {
    $best = $null; $bestF = $null; $fast = $null; $fastF = $null
    foreach ($e in $Script:Catalog) {
      if ($e.cat -ne $cat[0]) { continue }; $f = Get-Fit $e; if (-not $f.ok) { continue }
      $minT = 10; if ($cat[0] -eq 'Embeddings') { $minT = 0 }
      if ($f.tps -ge $minT) { if (-not $best -or [double]$e.p -gt [double]$best.p -or ([double]$e.p -eq [double]$best.p -and $f.tps -gt $bestF.tps)) { $best = $e; $bestF = $f } }
      if (-not $fast -or $f.tps -gt $fastF.tps) { $fast = $e; $fastF = $f }
    }
    if (-not $best) { $best = $fast; $bestF = $fastF }
    if (-not $best) { continue }
    $it = New-Object System.Windows.Forms.ListViewItem($cat[1]); $it.Tag = $best.id; $it.UseItemStyleForSubItems = $false
    [void]$it.SubItems.Add($best.name); [void]$it.SubItems.Add($best.id)
    $s = $it.SubItems.Add($ModeTxt[$bestF.mode]); $s.ForeColor = $ModeCol[$bestF.mode]
    $spt = ('≈ {0} tok/s' -f $bestF.tps); if ($cat[0] -eq 'Embeddings') { $spt = 'rápido' }
    [void]$it.SubItems.Add($spt); [void]$it.SubItems.Add((Human ($best.gb * 1GB))); [void]$it.SubItems.Add($best.fuerte)
    if ($Script:Installed.ContainsKey($best.id)) { $it.SubItems[1].Text = $best.name + '  (instalado)'; $it.SubItems[1].ForeColor = $Col.Green }
    [void]$lvRec.Items.Add($it)
  }
  $lvRec.EndUpdate()
}
function Refresh-Compat { ApplyFilters; Update-HwSummary; Refresh-InstalledLV }

# =====================================================================
#  PAGINA: HISTORIAL Y LOG
# =====================================================================
$pgHist = New-Page 'hist'
$histBar = New-Object System.Windows.Forms.FlowLayoutPanel; $histBar.Dock = 'Top'; $histBar.AutoSize = $true; $histBar.AutoSizeMode = 'GrowAndShrink'; $histBar.Padding = New-Object System.Windows.Forms.Padding(12,10,12,4); $histBar.BackColor = $Col.Bg
$histBar.Controls.Add((New-Lbl 'Acción:' $FSm $Col.Txt))
$cmbHistAct = New-Object System.Windows.Forms.ComboBox; $cmbHistAct.DropDownStyle = 'DropDownList'; $cmbHistAct.Width = 170; $cmbHistAct.BackColor = $Col.Card; $cmbHistAct.ForeColor = $Col.Txt; $cmbHistAct.FlatStyle = 'Flat'; $cmbHistAct.Margin = New-Object System.Windows.Forms.Padding(0,3,10,3)
foreach ($a in @('Todas','Descargar','Actualizar','Exportar','Importar','Verificar','Verificar SHA-256','Quitar','Benchmark','GGUF','Instalador','Imagen','Imagen: descarga','Imagen: motor','Paquete imagen','Reparar','Mantenimiento')) { [void]$cmbHistAct.Items.Add($a) }; $cmbHistAct.SelectedIndex = 0
$histBar.Controls.Add($cmbHistAct)
$histBar.Controls.Add((New-Lbl 'Buscar:' $FSm $Col.Txt)); $txtHist = New-Txt 220 ''; $histBar.Controls.Add($txtHist)
$bH1 = New-Btn 'Refrescar' $Col.Txt $Col.Border $false; $histBar.Controls.Add($bH1)
$bH2 = New-Btn 'Abrir historial (CSV / Excel)' $Col.Cyan $Col.Cyan $false; $histBar.Controls.Add($bH2)
$bH3 = New-Btn 'Abrir carpeta de logs' $Col.Cyan $Col.Cyan $false; $histBar.Controls.Add($bH3)
$bH4 = New-Btn 'Vaciar historial' $Col.Red $Col.Red $false; $histBar.Controls.Add($bH4)
$split = New-Object System.Windows.Forms.SplitContainer; $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'; $split.BackColor = $Col.Border; $split.SplitterWidth = 5
$lvHist = New-LV @('Fecha=140','Acción=130','Modelo=240','Resultado=100','Tamaño=90','Duración=80','Detalle=520'); $lvHist.CheckBoxes = $false
$split.Panel1.Controls.Add($lvHist); $split.Panel1.BackColor = $Col.Card
$logBox = New-Object System.Windows.Forms.TextBox; $logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Both'; $logBox.WordWrap = $false; $logBox.Dock = 'Fill'
$logBox.BackColor = $Col.Panel; $logBox.ForeColor = $Col.Txt; $logBox.Font = $FMono; $logBox.BorderStyle = 'None'
$logHdr = New-Lbl '  LOG EN VIVO (se guarda en OllamaManager-datos\logs\)' $FSmB $Col.Sub; $logHdr.Dock = 'Top'; $logHdr.AutoSize = $false; $logHdr.Height = 20
$split.Panel2.Controls.Add($logBox); $split.Panel2.Controls.Add($logHdr); $split.Panel2.BackColor = $Col.Panel
$histWrap = New-Object System.Windows.Forms.Panel; $histWrap.Dock = 'Fill'; $histWrap.Padding = New-Object System.Windows.Forms.Padding(12,4,12,10); $histWrap.Controls.Add($split)
$pgHist.Controls.Add($histWrap); $pgHist.Controls.Add($histBar)
$Script:LogBox = $logBox
$Script:HistLV = $lvHist

function Add-HistRow($o,[int]$at){
  $it = New-Object System.Windows.Forms.ListViewItem([string]$o.Fecha); $it.UseItemStyleForSubItems = $false
  [void]$it.SubItems.Add([string]$o.Accion); [void]$it.SubItems.Add([string]$o.Modelo)
  $s = $it.SubItems.Add([string]$o.Resultado)
  switch -Wildcard ([string]$o.Resultado) { 'OK*' { $s.ForeColor = $Col.Green } 'Error*' { $s.ForeColor = $Col.Red } 'Cancel*' { $s.ForeColor = $Col.Amber } default { $s.ForeColor = $Col.Txt } }
  [void]$it.SubItems.Add([string]$o.Tamano); [void]$it.SubItems.Add([string]$o.Duracion); [void]$it.SubItems.Add([string]$o.Detalle)
  if ($at -ge 0) { [void]$lvHist.Items.Insert($at,$it) } else { [void]$lvHist.Items.Add($it) }
}
function Load-History {
  $lvHist.BeginUpdate(); $lvHist.Items.Clear()
  if (Test-Path -LiteralPath $HistFile) {
    try {
      $rows = @(Import-Csv -LiteralPath $HistFile -Encoding UTF8)
      $act = [string]$cmbHistAct.SelectedItem; $q = $txtHist.Text.Trim().ToLower(); $n = 0
      for ($i = $rows.Count - 1; $i -ge 0; $i--) {
        $o = $rows[$i]
        if ($act -ne 'Todas' -and [string]$o.Accion -ne $act) { continue }
        if ($q -and (([string]$o.Modelo + ' ' + [string]$o.Detalle + ' ' + [string]$o.Resultado).ToLower().IndexOf($q) -lt 0)) { continue }
        Add-HistRow $o -1; $n++; if ($n -ge 3000) { break }
      }
    } catch {}
  }
  $lvHist.EndUpdate()
}
$cmbHistAct.Add_SelectedIndexChanged({ Load-History })
$txtHist.Add_TextChanged({ Load-History })
$bH1.Add_Click({ Load-History })
$bH2.Add_Click({ if (Test-Path -LiteralPath $HistFile) { Start-Process -FilePath $HistFile } else { MsgInfo 'Aún no hay historial.' } })
$bH3.Add_Click({ Start-Process explorer.exe $LogDir })
$bH4.Add_Click({ if (MsgYes '¿Vaciar el historial? (los logs diarios se conservan)') { $bk = Join-Path $DataDir ('historial-{0}.bak.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')); try { if (Test-Path -LiteralPath $HistFile) { Move-Item -LiteralPath $HistFile -Destination $bk -Force } } catch {}; Load-History; Write-Log 'INFO' 'HISTORIAL' ('Historial vaciado (copia en ' + $bk + ')') } })

# =====================================================================
#  PAGINA: AJUSTES
# =====================================================================
$pgCfg = New-Page 'cfg'
$cfgFlow = New-Object System.Windows.Forms.FlowLayoutPanel; $cfgFlow.Dock = 'Fill'; $cfgFlow.AutoScroll = $true; $cfgFlow.FlowDirection = 'TopDown'; $cfgFlow.WrapContents = $false; $cfgFlow.Padding = New-Object System.Windows.Forms.Padding(20,14,20,14); $cfgFlow.BackColor = $Col.Bg
$pgCfg.Controls.Add($cfgFlow)
function Cfg-Row { $r = New-Flow 'LeftToRight'; $r.WrapContents = $false; $cfgFlow.Controls.Add($r); return $r }
function Cfg-Title([string]$t){ $l = New-Lbl $t $FH2 $Col.Acc; $l.Margin = New-Object System.Windows.Forms.Padding(0,14,0,6); $cfgFlow.Controls.Add($l) }
function Cfg-Note([string]$t){ $l = New-Lbl $t $FSm $Col.Sub; $l.MaximumSize = New-Object System.Drawing.Size(1000,0); $l.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6); $cfgFlow.Controls.Add($l) }

Cfg-Title 'Carpetas'
$r = Cfg-Row; $r.Controls.Add((New-Lbl 'Modelos de Ollama:' $FSm $Col.Txt)); $lblModelsDir = New-Lbl $Script:Models $FMono $Col.Cyan; $r.Controls.Add($lblModelsDir)
$r = Cfg-Row
$bC1 = New-Btn 'Cambiar carpeta de modelos...' $Col.Txt $Col.Border $false; $r.Controls.Add($bC1)
$bC2 = New-Btn 'Restablecer predeterminada' $Col.Sub $Col.Border $false; $r.Controls.Add($bC2)
$bC3 = New-Btn 'Abrir carpeta de modelos' $Col.Sub $Col.Border $false; $r.Controls.Add($bC3)
Cfg-Note 'Útil para guardar los modelos en otro disco con más espacio. Cambiarla NO mueve los modelos existentes: expórtalos e impórtalos, o muévelos a mano con Ollama cerrado. Requiere reiniciar Ollama.'
$r = Cfg-Row; $r.Controls.Add((New-Lbl 'Descargas parciales:' $FSm $Col.Txt)); $r.Controls.Add((New-Lbl $Base $FMono $Col.Cyan))
$r = Cfg-Row
$bC4 = New-Btn 'Abrir' $Col.Sub $Col.Border $false; $r.Controls.Add($bC4)
$bC5 = New-Btn 'Borrar descargas parciales' $Col.Amber $Col.Amber $false; $r.Controls.Add($bC5)
$bC6 = New-Btn 'Limpiar archivos huérfanos de Ollama' $Col.Amber $Col.Amber $false; $r.Controls.Add($bC6)
$bC7 = New-Btn 'Abrir carpeta de datos de la app' $Col.Sub $Col.Border $false; $r.Controls.Add($bC7)

Cfg-Title 'Descargas'
$r = Cfg-Row; $r.Controls.Add((New-Lbl 'Servidor de registro:' $FSm $Col.Txt)); $txtReg = New-Txt 360 $Script:Registry; $r.Controls.Add($txtReg)
$r.Controls.Add((New-Lbl 'Segundos entre reintentos:' $FSm $Col.Txt)); $numWait = New-Num 3 600 ([double]$Script:Cfg.WaitSec) 0 1; $r.Controls.Add($numWait)
$r = Cfg-Row; $r.Controls.Add((New-Lbl 'Límite de velocidad (KB/s, 0 = sin límite):' $FSm $Col.Txt)); $numRate = New-Num 0 1000000 ([double]$Script:Cfg.RateKB) 0 50; $numRate.Width = 100; $r.Controls.Add($numRate)
$r.Controls.Add((New-Lbl '   Proxy (opcional):' $FSm $Col.Txt)); $txtProxy = New-Txt 260 ([string]$Script:Cfg.Proxy); $r.Controls.Add($txtProxy)
$chkAutoRes = New-Chk 'Al abrir la app, continuar automáticamente las descargas y tareas que quedaron a medias' ([bool]$Script:Cfg.AutoResume); $cfgFlow.Controls.Add($chkAutoRes)
$chkNotif = New-Chk 'Mostrar notificaciones de Windows (descarga terminada, errores, nueva versión de Ollama)' ([bool]$Script:Cfg.Notify); $cfgFlow.Controls.Add($chkNotif)
$r = Cfg-Row; $bC8 = New-Btn 'Guardar ajustes de descarga' $Col.White $Col.Acc $true; $r.Controls.Add($bC8)
Cfg-Note 'Deja https://registry.ollama.ai salvo que uses un espejo (mirror) propio. Las descargas se reintentan indefinidamente ante cortes de red o de luz. El límite de velocidad deja ancho de banda para otros usos (se aplica desde el siguiente archivo). Proxy: formato http://usuario:clave@servidor:puerto o http://servidor:puerto.'

Cfg-Title 'Optimización de Ollama (variables de entorno del usuario)'
Cfg-Note 'Se guardan en Windows para tu usuario y se aplican al REINICIAR Ollama (botón de abajo o en la cabecera).'
$chkFA   = New-Chk 'Flash Attention (OLLAMA_FLASH_ATTENTION=1): menos memoria y más velocidad en GPUs compatibles' ((EnvU 'OLLAMA_FLASH_ATTENTION') -eq '1'); $cfgFlow.Controls.Add($chkFA)
$chkKV   = New-Chk 'Caché de contexto comprimida (OLLAMA_KV_CACHE_TYPE=q8_0): ~mitad de memoria para el contexto (usa Flash Attention)' ((EnvU 'OLLAMA_KV_CACHE_TYPE') -eq 'q8_0'); $cfgFlow.Controls.Add($chkKV)
$chkVK   = New-Chk 'Vulkan (OLLAMA_VULKAN=1) [experimental]: acelera GPUs AMD/Intel que ROCm no soporta' ((EnvU 'OLLAMA_VULKAN') -eq '1'); $cfgFlow.Controls.Add($chkVK)
$chkNP   = New-Chk 'No borrar archivos al iniciar (OLLAMA_NOPRUNE=1): protege importaciones a medias' ((EnvU 'OLLAMA_NOPRUNE') -eq '1'); $cfgFlow.Controls.Add($chkNP)
$chkLAN  = New-Chk 'Compartir en la red local (OLLAMA_HOST=0.0.0.0:11434): otros PCs de tu red podrán usar tus modelos' ((EnvU 'OLLAMA_HOST') -like '0.0.0.0*'); $chkLAN.ForeColor = $Col.Amber; $cfgFlow.Controls.Add($chkLAN)
Cfg-Note '   ⚠ Compartir en red: cualquiera en tu red podrá usar Ollama sin contraseña. Actívalo solo en redes de confianza y revisa el firewall de Windows.'
$r = Cfg-Row; $r.Controls.Add((New-Lbl 'Longitud de contexto (OLLAMA_CONTEXT_LENGTH):' $FSm $Col.Txt))
$cmbCtx = New-Object System.Windows.Forms.ComboBox; $cmbCtx.DropDownStyle = 'DropDownList'; $cmbCtx.Width = 140; $cmbCtx.BackColor = $Col.Card; $cmbCtx.ForeColor = $Col.Txt; $cmbCtx.FlatStyle = 'Flat'
foreach ($v in @('Predeterminado','2048','4096','8192','16384','32768','65536')) { [void]$cmbCtx.Items.Add($v) }; $cv = EnvU 'OLLAMA_CONTEXT_LENGTH'; $cmbCtx.SelectedIndex = [Math]::Max(0,$cmbCtx.Items.IndexOf($(if ($cv) { $cv } else { 'Predeterminado' }))); $r.Controls.Add($cmbCtx)
$r.Controls.Add((New-Lbl '   Mantener modelo en memoria (OLLAMA_KEEP_ALIVE):' $FSm $Col.Txt))
$cmbKA = New-Object System.Windows.Forms.ComboBox; $cmbKA.DropDownStyle = 'DropDownList'; $cmbKA.Width = 140; $cmbKA.BackColor = $Col.Card; $cmbKA.ForeColor = $Col.Txt; $cmbKA.FlatStyle = 'Flat'
foreach ($v in @('Predeterminado','1m','5m','30m','1h','4h','-1')) { [void]$cmbKA.Items.Add($v) }; $kv = EnvU 'OLLAMA_KEEP_ALIVE'; $cmbKA.SelectedIndex = [Math]::Max(0,$cmbKA.Items.IndexOf($(if ($kv) { $kv } else { 'Predeterminado' }))); $r.Controls.Add($cmbKA)
Cfg-Note 'Más contexto = el modelo recuerda conversaciones/documentos más largos, pero usa más memoria. "-1" mantiene el modelo cargado siempre (respuesta inmediata, ocupa memoria).'
$r = Cfg-Row
$bC9 = New-Btn 'Aplicar variables' $Col.White $Col.Acc $true; $r.Controls.Add($bC9)
$bC10 = New-Btn 'Reiniciar Ollama ahora' $Col.Amber $Col.Amber $false; $r.Controls.Add($bC10)
Cfg-Title 'Acerca de'
Cfg-Note ('{0} v{1}  ·  Datos de la app: {2}' -f $AppName,$AppVer,$DataDir)

function Set-UserEnv([string]$n,[string]$v){
  if ($v) { [Environment]::SetEnvironmentVariable($n,$v,'User'); Set-Item -Path ('env:' + $n) -Value $v }
  else { [Environment]::SetEnvironmentVariable($n,$null,'User'); Remove-Item -Path ('env:' + $n) -ErrorAction SilentlyContinue }
}
function Start-OllamaSvc {
  if (Test-Path -LiteralPath $OllamaApp) { Start-Process -FilePath $OllamaApp }
  elseif ($Script:OllamaExe) { Start-Process -FilePath $Script:OllamaExe -ArgumentList 'serve' -WindowStyle Hidden }
  else { Start-Process 'https://ollama.com/download'; Set-Status 'Ollama no está instalado: abriendo ollama.com/download (o usa el instalador del repositorio offline).' }
}
function Restart-Ollama {
  if ($Script:CurJob -and $Script:CurJob.type -eq 'gguf') { MsgWarn 'Espera a que termine la importación GGUF.'; return }
  try { Get-Process -Name 'ollama app','ollama' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
  Start-Sleep -Milliseconds 1500; Start-OllamaSvc; Write-Log 'INFO' 'OLLAMA' 'Servicio reiniciado.'; Set-Status 'Reiniciando Ollama...'
}
$bC1.Add_Click({
  if (Is-Busy) { MsgWarn 'Espera a que terminen las tareas en curso.'; return }
  $p = Pick-Folder 'Elige la nueva carpeta para los modelos de Ollama' $Script:Models; if (-not $p) { return }
  if (-not (MsgYes ('Ollama usará:' + "`n" + $p + "`n`nLos modelos actuales NO se mueven. ¿Continuar? (se reiniciará Ollama)"))) { return }
  $Script:Cfg.ModelsDir = $p; Save-Config; Set-UserEnv 'OLLAMA_MODELS' $p; $Script:Models = $p; $lblModelsDir.Text = $p
  Write-Log 'INFO' 'AJUSTES' ('Carpeta de modelos cambiada a ' + $p); Refresh-Installed; Refresh-InstalledLV; Update-CardStates; Restart-Ollama })
$bC2.Add_Click({
  if (Is-Busy) { MsgWarn 'Espera a que terminen las tareas en curso.'; return }
  $Script:Cfg.ModelsDir = ''; Save-Config; Set-UserEnv 'OLLAMA_MODELS' ''; $Script:Models = Join-Path $env:USERPROFILE '.ollama\models'; $lblModelsDir.Text = $Script:Models
  Write-Log 'INFO' 'AJUSTES' 'Carpeta de modelos restablecida.'; Refresh-Installed; Refresh-InstalledLV; Update-CardStates; Restart-Ollama })
$bC3.Add_Click({ if (Test-Path -LiteralPath $Script:Models) { Start-Process explorer.exe $Script:Models } })
$bC4.Add_Click({ Start-Process explorer.exe $Base })
$bC5.Add_Click({
  if (Is-Busy) { MsgWarn 'Espera a que terminen las tareas en curso.'; return }
  [double]$sz = 0; foreach ($f in (Get-ChildItem -LiteralPath $Base -Recurse -File -Force -ErrorAction SilentlyContinue)) { $sz += $f.Length }
  if ($sz -le 0) { MsgInfo 'No hay descargas parciales.'; return }
  if (MsgYes ('Se borrarán {0} de descargas a medias (tendrás que empezar esas descargas de cero). ¿Continuar?' -f (Human $sz))) {
    foreach ($d in (Get-ChildItem -LiteralPath $Base -Force -ErrorAction SilentlyContinue)) { try { Remove-Item -LiteralPath $d.FullName -Recurse -Force } catch {} }
    Write-Log 'INFO' 'MANTENIMIENTO' ('Descargas parciales borradas: ' + (Human $sz)); Add-History 'Mantenimiento' '(parciales)' 'OK' $sz 0 'Descargas parciales borradas' } })
$bC6.Add_Click({ Clean-Orphans $true })
$bC7.Add_Click({ Start-Process explorer.exe $DataDir })
$bC8.Add_Click({ $reg = $txtReg.Text.Trim().TrimEnd('/'); if ($reg -notmatch '^https?://') { MsgWarn 'El registro debe empezar por https://'; return }; $Script:Registry = $reg; $Script:Cfg.Registry = $(if ($reg -eq 'https://registry.ollama.ai') { '' } else { $reg }); $Script:Cfg.WaitSec = [int]$numWait.Value; $Script:Cfg.RateKB = [int]$numRate.Value; $pxy = $txtProxy.Text.Trim(); if ($pxy -and $pxy -notmatch '^(https?|socks5h?)://') { MsgWarn 'El proxy debe empezar por http://, https:// o socks5://'; return }; $Script:Cfg.Proxy = $pxy; $Script:Cfg.AutoResume = $chkAutoRes.Checked; $Script:Cfg.Notify = $chkNotif.Checked; Save-Config; Update-CurlX; Write-Log 'INFO' 'AJUSTES' ('Descargas: límite {0} KB/s, proxy "{1}", reanudar al abrir {2}' -f $Script:Cfg.RateKB,$pxy,$Script:Cfg.AutoResume); Set-Status 'Ajustes de descarga guardados.' })
$bC9.Add_Click({
  Set-UserEnv 'OLLAMA_FLASH_ATTENTION' $(if ($chkFA.Checked -or $chkKV.Checked) { '1' } else { '' })
  Set-UserEnv 'OLLAMA_KV_CACHE_TYPE' $(if ($chkKV.Checked) { 'q8_0' } else { '' })
  Set-UserEnv 'OLLAMA_VULKAN' $(if ($chkVK.Checked) { '1' } else { '' })
  Set-UserEnv 'OLLAMA_NOPRUNE' $(if ($chkNP.Checked) { '1' } else { '' })
  Set-UserEnv 'OLLAMA_HOST' $(if ($chkLAN.Checked) { '0.0.0.0:11434' } else { '' })
  Set-UserEnv 'OLLAMA_CONTEXT_LENGTH' $(if ($cmbCtx.SelectedIndex -gt 0) { [string]$cmbCtx.SelectedItem } else { '' })
  Set-UserEnv 'OLLAMA_KEEP_ALIVE' $(if ($cmbKA.SelectedIndex -gt 0) { [string]$cmbKA.SelectedItem } else { '' })
  if ($chkKV.Checked) { $chkFA.Checked = $true }
  Write-Log 'INFO' 'AJUSTES' 'Variables de entorno de Ollama actualizadas.'
  Build-HwEff; Fill-HwPage; Refresh-Compat
  if (MsgYes 'Variables guardadas. ¿Reiniciar Ollama ahora para aplicarlas?') { Restart-Ollama } })
$bC10.Add_Click({ Restart-Ollama })

# =====================================================================
#  PAGINA: IMAGEN (generar y editar)  -  stable-diffusion.cpp
# =====================================================================
$pgImg = New-Page 'img'
$Script:PackUI = @{}; $Script:ImgIn = $null; $Script:ImgMask = $null; $Script:ImgSel = $null; $Script:ImgBusy = $false; $Script:ImgRun = $null
$Script:ImgQ = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Script:ImgF = [System.Collections.Hashtable]::Synchronized(@{ Stop=$false })

$imgTop = New-Object System.Windows.Forms.FlowLayoutPanel; $imgTop.Dock = 'Top'; $imgTop.Height = 172; $imgTop.WrapContents = $false; $imgTop.AutoScroll = $true; $imgTop.Padding = New-Object System.Windows.Forms.Padding(12,10,12,0); $imgTop.BackColor = $Col.Bg
$bxMotor = New-Box 330 152 'MOTOR (stable-diffusion.cpp)'
$lblMotor = New-Object System.Windows.Forms.Label; $lblMotor.Font = $FSm; $lblMotor.ForeColor = $Col.Txt; $lblMotor.Location = New-Object System.Drawing.Point(14,30); $lblMotor.Size = New-Object System.Drawing.Size(304,36); $bxMotor.Controls.Add($lblMotor)
$cmbVariant = New-Object System.Windows.Forms.ComboBox; $cmbVariant.DropDownStyle = 'DropDownList'; $cmbVariant.Location = New-Object System.Drawing.Point(14,72); $cmbVariant.Width = 302; $cmbVariant.BackColor = $Col.Card; $cmbVariant.ForeColor = $Col.Txt; $cmbVariant.FlatStyle = 'Flat'
foreach ($v in @('Vulkan (AMD / Intel / NVIDIA) - recomendado','CUDA 12 (solo NVIDIA)','Solo CPU (muy lento)')) { [void]$cmbVariant.Items.Add($v) }; $cmbVariant.SelectedIndex = 0; $bxMotor.Controls.Add($cmbVariant)
$btnMotor = New-SmallBtn 'Instalar / actualizar motor' 14 200 $Col.White $Col.Acc $true; $btnMotor.Location = New-Object System.Drawing.Point(14,110); $bxMotor.Controls.Add($btnMotor)
$imgTop.Controls.Add($bxMotor)
function New-PackBox([string]$key){
  $p = $ImgPacks[$key]
  $bx = New-Box 300 152 ($p.name.ToUpper())
  $d = New-Object System.Windows.Forms.Label; $d.Text = $p.desc; $d.Font = $FSm; $d.ForeColor = $Col.Sub; $d.Location = New-Object System.Drawing.Point(14,30); $d.Size = New-Object System.Drawing.Size(274,48); $bx.Controls.Add($d)
  $s = New-Object System.Windows.Forms.Label; $s.Font = $FSmB; $s.Location = New-Object System.Drawing.Point(14,82); $s.Size = New-Object System.Drawing.Size(274,20); $bx.Controls.Add($s)
  $b = New-SmallBtn 'Descargar' 14 150 $Col.White $Col.Acc $true; $b.Location = New-Object System.Drawing.Point(14,110); $b.Tag = $key; $b.Add_Click({ param($sn,$ev) Download-Pack ([string]$sn.Tag) }); $bx.Controls.Add($b)
  $x = New-SmallBtn 'Quitar' 170 70 $Col.Red $Col.Red $false; $x.Location = New-Object System.Drawing.Point(170,110); $x.Tag = $key; $x.Add_Click({ param($sn,$ev) Remove-Pack ([string]$sn.Tag) }); $bx.Controls.Add($x)
  $Script:PackUI[$key] = @{ status=$s; dl=$b; rm=$x }
  return $bx
}
foreach ($k in $ImgPacks.Keys) { $imgTop.Controls.Add((New-PackBox $k)) }

$imgLeft = New-Object System.Windows.Forms.Panel; $imgLeft.Dock = 'Left'; $imgLeft.Width = 392; $imgLeft.BackColor = $Col.Panel
$il = New-Object System.Windows.Forms.FlowLayoutPanel; $il.Dock = 'Fill'; $il.AutoScroll = $true; $il.FlowDirection = 'TopDown'; $il.WrapContents = $false; $il.Padding = New-Object System.Windows.Forms.Padding(14,6,6,12); $il.BackColor = $Col.Panel
$imgLeft.Controls.Add($il)
function Img-Lbl([string]$t){ $l = New-SideLbl $t; $l.Width = 350; return $l }
function Img-Row { $r = New-Flow 'LeftToRight'; $r.WrapContents = $false; $r.Margin = New-Object System.Windows.Forms.Padding(0,2,0,2); return $r }
$il.Controls.Add((Img-Lbl 'QUÉ QUIERES HACER'))
$cmbMode = New-Object System.Windows.Forms.ComboBox; $cmbMode.DropDownStyle = 'DropDownList'; $cmbMode.Width = 350; $cmbMode.BackColor = $Col.Card; $cmbMode.ForeColor = $Col.Txt; $cmbMode.FlatStyle = 'Flat'
foreach ($v in @('Generar una imagen desde texto','Editar una foto con instrucciones (FLUX.2 Klein)','Transformar una imagen (estilo / variación)','Cambiar solo una zona (pintar máscara)')) { [void]$cmbMode.Items.Add($v) }
$il.Controls.Add($cmbMode)
$il.Controls.Add((Img-Lbl 'MODELO'))
$cmbImgModel = New-Object System.Windows.Forms.ComboBox; $cmbImgModel.DropDownStyle = 'DropDownList'; $cmbImgModel.Width = 350; $cmbImgModel.BackColor = $Col.Card; $cmbImgModel.ForeColor = $Col.Txt; $cmbImgModel.FlatStyle = 'Flat'; $il.Controls.Add($cmbImgModel)
$il.Controls.Add((Img-Lbl 'DESCRIPCIÓN / INSTRUCCIÓN'))
$txtPrompt = New-Txt 350 ''; $txtPrompt.Multiline = $true; $txtPrompt.Height = 96; $txtPrompt.ScrollBars = 'Vertical'; $il.Controls.Add($txtPrompt)
$lblPromptHint = New-Lbl '' $FSm $Col.Sub; $lblPromptHint.MaximumSize = New-Object System.Drawing.Size(350,0); $lblPromptHint.Margin = New-Object System.Windows.Forms.Padding(0,0,0,4); $il.Controls.Add($lblPromptHint)
$il.Controls.Add((Img-Lbl 'TAMAÑO  (al editar: lado mayor del resultado)'))
$cmbSize = New-Object System.Windows.Forms.ComboBox; $cmbSize.DropDownStyle = 'DropDownList'; $cmbSize.Width = 350; $cmbSize.BackColor = $Col.Card; $cmbSize.ForeColor = $Col.Txt; $cmbSize.FlatStyle = 'Flat'
foreach ($v in @('1024x1024  cuadrado','768x768  cuadrado (más rápido)','512x512  borrador rápido','1024x576  horizontal 16:9','576x1024  vertical 9:16 (historias)','1152x896  horizontal 4:3','896x1152  vertical 3:4')) { [void]$cmbSize.Items.Add($v) }; $cmbSize.SelectedIndex = 1; $il.Controls.Add($cmbSize)
$r1 = Img-Row; $r1.Controls.Add((New-Lbl 'Pasos' $FSm $Col.Txt)); $numSteps = New-Num 1 60 8 0 1; $numSteps.Width = 60; $r1.Controls.Add($numSteps)
$r1.Controls.Add((New-Lbl '  Semilla (-1 = azar)' $FSm $Col.Txt)); $numSeed = New-Num -1 2147483647 -1 0 1; $numSeed.Width = 110; $r1.Controls.Add($numSeed); $il.Controls.Add($r1)
$r2 = Img-Row; $r2.Controls.Add((New-Lbl 'Intensidad del cambio' $FSm $Col.Txt)); $numStrength = New-Num 0.05 1 0.6 2 0.05; $numStrength.Width = 70; $r2.Controls.Add($numStrength)
$r2.Controls.Add((New-Lbl '(bajo = parecido al original)' $FSm $Col.Sub)); $il.Controls.Add($r2)
$il.Controls.Add((Img-Lbl 'IMAGEN DE ENTRADA'))
$r3 = Img-Row; $btnPickIn = New-Btn 'Elegir imagen...' $Col.Txt $Col.Border $false; $r3.Controls.Add($btnPickIn); $btnClearIn = New-Btn 'Quitar' $Col.Sub $Col.Border $false; $r3.Controls.Add($btnClearIn); $il.Controls.Add($r3)
$picIn = New-Object System.Windows.Forms.PictureBox; $picIn.Size = New-Object System.Drawing.Size(350,150); $picIn.SizeMode = 'Zoom'; $picIn.BackColor = $Col.Card; $il.Controls.Add($picIn)
$lblIn = New-Lbl 'Sin imagen' $FSm $Col.Sub; $il.Controls.Add($lblIn)
$il.Controls.Add((Img-Lbl 'MÁSCARA (zona a cambiar, en blanco)'))
$r4 = Img-Row; $btnPaint = New-Btn 'Pintar máscara...' $Col.Amber $Col.Amber $false; $r4.Controls.Add($btnPaint); $btnPickMask = New-Btn 'Cargar máscara...' $Col.Sub $Col.Border $false; $r4.Controls.Add($btnPickMask); $il.Controls.Add($r4)
$lblMask = New-Lbl 'Sin máscara' $FSm $Col.Sub; $il.Controls.Add($lblMask)
$il.Controls.Add((Img-Lbl 'OPCIONES'))
$chkLowVram = New-Chk 'Modo baja VRAM (recomendado con 8 GB o menos)' $true; $il.Controls.Add($chkLowVram)
$chkImgFA = New-Chk 'Flash attention (más rápido; desmárcalo si da error)' $true; $il.Controls.Add($chkImgFA)
$chkUpscale = New-Chk 'Ampliar x4 al terminar (Real-ESRGAN)' $false; $il.Controls.Add($chkUpscale)
$r5 = Img-Row; $btnGen = New-Btn '   GENERAR   ' $Col.White $Col.Acc $true; $btnGen.Font = $FBold; $btnGen.MinimumSize = New-Object System.Drawing.Size(170,38); $r5.Controls.Add($btnGen)
$btnStopGen = New-Btn 'Detener' $Col.Red $Col.Red $false; $btnStopGen.MinimumSize = New-Object System.Drawing.Size(90,38); $r5.Controls.Add($btnStopGen); $il.Controls.Add($r5)
$lblImgStatus = New-Lbl '' $FSmB $Col.Cyan; $lblImgStatus.MaximumSize = New-Object System.Drawing.Size(350,0); $il.Controls.Add($lblImgStatus)

$imgRight = New-Object System.Windows.Forms.Panel; $imgRight.Dock = 'Fill'; $imgRight.Padding = New-Object System.Windows.Forms.Padding(10,8,12,8); $imgRight.BackColor = $Col.Bg
$picOut = New-Object System.Windows.Forms.PictureBox; $picOut.Dock = 'Fill'; $picOut.SizeMode = 'Zoom'; $picOut.BackColor = $Col.Panel
$imgActions = New-Object System.Windows.Forms.FlowLayoutPanel; $imgActions.Dock = 'Bottom'; $imgActions.AutoSize = $true; $imgActions.AutoSizeMode = 'GrowAndShrink'; $imgActions.Padding = New-Object System.Windows.Forms.Padding(0,6,0,0); $imgActions.BackColor = $Col.Bg
$btnUseIn = New-Btn 'Usar como entrada (seguir editando)' $Col.Amber $Col.Amber $false; $imgActions.Controls.Add($btnUseIn)
$btnOpenImg = New-Btn 'Abrir' $Col.Txt $Col.Border $false; $imgActions.Controls.Add($btnOpenImg)
$btnCopyImg = New-Btn 'Copiar' $Col.Txt $Col.Border $false; $imgActions.Controls.Add($btnCopyImg)
$btnOpenOut = New-Btn 'Abrir carpeta de imágenes' $Col.Cyan $Col.Cyan $false; $imgActions.Controls.Add($btnOpenOut)
$lblImgInfo = New-Lbl '' $FSm $Col.Sub; $imgActions.Controls.Add($lblImgInfo)
$gallery = New-Object System.Windows.Forms.FlowLayoutPanel; $gallery.Dock = 'Bottom'; $gallery.Height = 118; $gallery.AutoScroll = $true; $gallery.WrapContents = $false; $gallery.BackColor = $Col.Panel; $gallery.Padding = New-Object System.Windows.Forms.Padding(4)
$imgLog = New-Object System.Windows.Forms.TextBox; $imgLog.Multiline = $true; $imgLog.ReadOnly = $true; $imgLog.ScrollBars = 'Vertical'; $imgLog.Dock = 'Bottom'; $imgLog.Height = 78; $imgLog.BackColor = $Col.Panel; $imgLog.ForeColor = $Col.Sub; $imgLog.Font = $FMono; $imgLog.BorderStyle = 'None'
$imgRight.Controls.Add($picOut); $imgRight.Controls.Add($imgActions); $imgRight.Controls.Add($gallery); $imgRight.Controls.Add($imgLog)
$pgImg.Controls.Add($imgRight); $pgImg.Controls.Add($imgLeft); $pgImg.Controls.Add($imgTop)

function Get-PackFile($f){ $n = $f.local; if (-not $n) { if ($f.path) { $n = Split-Path $f.path -Leaf } else { $n = Split-Path $f.url -Leaf } }; return (Join-Path $ImgModels $n) }
function Pack-State([string]$key){
  $st = 'ready'; [double]$b = 0; $any = $false
  foreach ($f in $ImgPacks[$key].files) { $pf = Get-PackFile $f; $s = SizeOf $pf; $b += $s; if ($s -gt 0) { $any = $true } else { $st = 'none'; if ((SizeOf ($pf + '.part')) -gt 0) { $any = $true } } }
  if ($st -ne 'ready' -and $any) { $st = 'partial' }
  return @{ state=$st; bytes=$b }
}
function Get-PackPath([string]$key,[string]$fk){ foreach ($f in $ImgPacks[$key].files) { if ($f.key -eq $fk) { return (Get-PackFile $f) } }; return $null }
function Get-SdExe {
  if (-not (Test-Path -LiteralPath $ImgMotor)) { return $null }
  $x = Get-ChildItem -LiteralPath $ImgMotor -Recurse -File -Filter 'sd-cli.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $x) { $x = Get-ChildItem -LiteralPath $ImgMotor -Recurse -File -Filter 'sd.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 }
  if ($x) { return $x.FullName }; return $null
}
function Refresh-ImgState {
  $exe = Get-SdExe
  if ($exe) { $v = ''; $vf = Join-Path $ImgMotor 'version.txt'; if (Test-Path -LiteralPath $vf) { $v = (Get-Content -LiteralPath $vf -Raw).Trim() }; $lblMotor.Text = ('Instalado ✓  ' + $v); $lblMotor.ForeColor = $Col.Green }
  else { $lblMotor.Text = 'No instalado. Necesario para generar (≈ 50-200 MB).'; $lblMotor.ForeColor = $Col.Amber }
  foreach ($k in $ImgPacks.Keys) {
    $ui = $Script:PackUI[$k]; $ps = Pack-State $k; $busy = $false
    foreach ($j in @($Script:Jobs) + @($Script:CurJob)) { if ($j -and $j.type -eq 'files' -and $j.pack -eq $k) { $busy = $true } }
    if ($busy) { $ui.status.Text = 'Descargando / en cola...'; $ui.status.ForeColor = $Col.Cyan; $ui.dl.Enabled = $false }
    elseif ($ps.state -eq 'ready') { $ui.status.Text = ('Listo ✓  ({0})' -f (Human $ps.bytes)); $ui.status.ForeColor = $Col.Green; $ui.dl.Enabled = $false; $ui.dl.Text = 'Descargado' }
    elseif ($ps.state -eq 'partial') { $ui.status.Text = 'Descarga a medias: pulsa para reanudar'; $ui.status.ForeColor = $Col.Amber; $ui.dl.Enabled = $true; $ui.dl.Text = 'Reanudar' }
    else { $ui.status.Text = ('No descargado  (≈ {0})' -f (Human ($ImgPacks[$k].approx * 1GB))); $ui.status.ForeColor = $Col.Sub; $ui.dl.Enabled = $true; $ui.dl.Text = 'Descargar' }
    $ui.rm.Enabled = ($ps.state -ne 'none' -and -not $busy)
  }
  $chkUpscale.Enabled = ((Pack-State 'upscale').state -eq 'ready'); if (-not $chkUpscale.Enabled) { $chkUpscale.Checked = $false }
}
function New-PackJob([string]$key){
  $p = $ImgPacks[$key]; $items = @()
  foreach ($f in $p.files) { $items += @{ name=(Split-Path (Get-PackFile $f) -Leaf); dest=(Get-PackFile $f); repo=$f.repo; path=$f.path; url=$f.url; size=0.0; sha='' } }
  return @{ type='files'; cat='IMAGEN'; label=('Descargar modelo de imagen: ' + $p.name); items=$items; pack=$key; id=$p.name }
}
function Download-Pack([string]$key){ Add-Job (New-PackJob $key); Refresh-ImgState }
function Remove-Pack([string]$key){
  if ($Script:ImgBusy) { MsgWarn 'Espera a que termine la generación.'; return }
  $p = $ImgPacks[$key]; if (-not (MsgYes ('¿Borrar los archivos de {0} ({1})?' -f $p.name,(Human (Pack-State $key).bytes)))) { return }
  foreach ($f in $p.files) { $pf = Get-PackFile $f; foreach ($x in @($pf,($pf + '.part'))) { try { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } } catch {} } }
  Write-Log 'INFO' 'IMAGEN' ('Modelo de imagen borrado: ' + $p.name); Add-History 'Quitar' $p.name 'OK' 0 0 'Modelo de imagen'; Refresh-ImgState
}
$btnMotor.Add_Click({
  $var = @('win-vulkan-x64','win-cuda12-x64','win-cpu-x64')[$cmbVariant.SelectedIndex]
  if ($Script:ImgBusy) { MsgWarn 'Espera a que termine la generación.'; return }
  Add-Job @{ type='engine'; cat='IMAGEN'; label=('Instalar motor stable-diffusion.cpp (' + $var + ')'); variant=$var; dir=$ImgMotor; id='stable-diffusion.cpp' } })

function Get-ImgModelKey { if ([string]$cmbImgModel.SelectedItem -like 'Z-Image*') { return 'zimage' }; return 'klein' }
function Update-ImgMode {
  $m = $cmbMode.SelectedIndex
  $prev = [string]$cmbImgModel.SelectedItem
  $cmbImgModel.Items.Clear(); if ($m -ne 1) { [void]$cmbImgModel.Items.Add('Z-Image Turbo  (mejor calidad fotográfica)') }; [void]$cmbImgModel.Items.Add('FLUX.2 Klein 4B  (genera y edita)')
  $cmbImgModel.SelectedIndex = 0; foreach ($it in $cmbImgModel.Items) { if ([string]$it -eq $prev) { $cmbImgModel.SelectedItem = $it } }
  $needIn = ($m -ge 1); $btnPickIn.Enabled = $needIn; $btnClearIn.Enabled = $needIn; $picIn.Enabled = $needIn
  $btnPaint.Enabled = ($m -eq 3); $btnPickMask.Enabled = ($m -eq 3); $numStrength.Enabled = ($m -ge 2)
  if ($m -eq 2) { $numStrength.Value = [decimal]0.6 } elseif ($m -eq 3) { $numStrength.Value = [decimal]0.9 }
  switch ($m) {
    0 { $lblPromptHint.Text = 'Describe la imagen: sujeto, lugar, luz, estilo. Ej: "retrato de un pescador cubano al atardecer, foto realista, luz dorada".' }
    1 { $lblPromptHint.Text = 'Di qué cambiar: "cambia el fondo por una playa", "pon el texto OFERTA en el cartel", "conviértelo en dibujo animado".' }
    2 { $lblPromptHint.Text = 'Describe cómo debe quedar. Intensidad baja = se parece más al original.' }
    3 { $lblPromptHint.Text = 'Pinta en blanco la zona y describe qué debe aparecer ahí. Ej: "una maceta con flores rojas".' }
  }
  $lblPromptHint.Text += '  (Mejor en inglés; las tildes se quitan solas.)'
}
$cmbMode.Add_SelectedIndexChanged({ Update-ImgMode })
$cmbImgModel.Add_SelectedIndexChanged({ if ((Get-ImgModelKey) -eq 'zimage') { $numSteps.Value = 8 } else { $numSteps.Value = 4 } })
$cmbMode.SelectedIndex = 0; Update-ImgMode

function Load-Bitmap([string]$path){
  $bytes = [IO.File]::ReadAllBytes($path); $ms = New-Object IO.MemoryStream(,$bytes)
  try { $img = [System.Drawing.Image]::FromStream($ms); $bmp = New-Object System.Drawing.Bitmap($img); $img.Dispose(); return $bmp } finally { $ms.Dispose() }
}
function Set-PicImage($pb,$bmp){ $old = $pb.Image; $pb.Image = $bmp; if ($old) { try { $old.Dispose() } catch {} } }
function Set-ImgIn([string]$path){
  if (-not $path) { $Script:ImgIn = $null; Set-PicImage $picIn $null; $lblIn.Text = 'Sin imagen'; $Script:ImgMask = $null; $lblMask.Text = 'Sin máscara'; return }
  try { $bmp = Load-Bitmap $path } catch { MsgWarn ('No se pudo abrir la imagen: ' + $_.Exception.Message); return }
  $Script:ImgIn = $path; $Script:ImgInW = $bmp.Width; $Script:ImgInH = $bmp.Height
  Set-PicImage $picIn $bmp; $lblIn.Text = ('{0}  ({1}x{2})' -f (Split-Path $path -Leaf),$bmp.Width,$bmp.Height)
  $Script:ImgMask = $null; $lblMask.Text = 'Sin máscara'
}
$btnPickIn.Add_Click({ $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Imágenes|*.png;*.jpg;*.jpeg;*.webp;*.bmp'; if ($d.ShowDialog($form) -eq 'OK') { Set-ImgIn $d.FileName } })
$btnClearIn.Add_Click({ Set-ImgIn $null })
$btnPickMask.Add_Click({ $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Máscara (blanco = cambiar)|*.png;*.jpg;*.bmp'; if ($d.ShowDialog($form) -eq 'OK') { $Script:ImgMask = $d.FileName; $lblMask.Text = ('Máscara: ' + (Split-Path $d.FileName -Leaf)); $lblMask.ForeColor = $Col.Green } })
$btnPaint.Add_Click({ Open-MaskPainter })

function Open-MaskPainter {
  if (-not $Script:ImgIn) { MsgInfo 'Primero elige la imagen de entrada.'; return }
  $src = Load-Bitmap $Script:ImgIn; $W = $src.Width; $H = $src.Height
  $sc = [Math]::Min(1.0, [Math]::Min(900.0 / $W, 620.0 / $H)); $dw = [int]($W * $sc); $dh = [int]($H * $sc)
  $disp = New-Object System.Drawing.Bitmap($dw,$dh); $g = [System.Drawing.Graphics]::FromImage($disp); $g.InterpolationMode = 'HighQualityBicubic'; $g.DrawImage($src,0,0,$dw,$dh); $g.Dispose(); $src.Dispose()
  $mask = New-Object System.Drawing.Bitmap($W,$H); $g = [System.Drawing.Graphics]::FromImage($mask); $g.Clear([System.Drawing.Color]::Black); $g.Dispose()
  $mf = New-Object System.Windows.Forms.Form; $mf.Text = 'Pinta en la zona que quieres cambiar'; $mf.StartPosition = 'CenterParent'; $mf.BackColor = $Col.Bg; $mf.ForeColor = $Col.Txt; $mf.Font = $FNorm
  $mf.ClientSize = New-Object System.Drawing.Size(([Math]::Max(620,$dw + 20)),($dh + 70))
  $bar = New-Object System.Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Top'; $bar.Height = 44; $bar.Padding = New-Object System.Windows.Forms.Padding(8,8,8,0); $bar.BackColor = $Col.Panel
  $bar.Controls.Add((New-Lbl 'Pincel:' $FSm $Col.Txt))
  $tb = New-Object System.Windows.Forms.TrackBar; $tb.Minimum = 4; $tb.Maximum = 160; $tb.Value = 40; $tb.Width = 180; $tb.TickStyle = 'None'; $bar.Controls.Add($tb)
  $bClr = New-Btn 'Limpiar' $Col.Sub $Col.Border $false; $bar.Controls.Add($bClr)
  $bOk = New-Btn 'Guardar máscara' $Col.White $Col.Acc $true; $bar.Controls.Add($bOk)
  $bCan = New-Btn 'Cancelar' $Col.Sub $Col.Border $false; $bar.Controls.Add($bCan)
  $pb = New-Object System.Windows.Forms.PictureBox; $pb.Size = New-Object System.Drawing.Size($dw,$dh); $pb.Location = New-Object System.Drawing.Point(10,54); $pb.Image = $disp; $pb.Cursor = 'Cross'
  $mf.Controls.Add($pb); $mf.Controls.Add($bar)
  $Script:MP = @{ disp=$disp; mask=$mask; sc=$sc; tb=$tb; pb=$pb; orig=$Script:ImgIn; painted=$false }
  $paint = { param($s,$ev)
    if ($ev.Button -ne 'Left') { return }
    $mp = $Script:MP; $r = $mp.tb.Value
    $g1 = [System.Drawing.Graphics]::FromImage($mp.disp); $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,255,60,60)); $g1.FillEllipse($br, [float]($ev.X - $r/2), [float]($ev.Y - $r/2), [float]$r, [float]$r); $br.Dispose(); $g1.Dispose()
    $g2 = [System.Drawing.Graphics]::FromImage($mp.mask); $rr = $r / $mp.sc; $g2.FillEllipse([System.Drawing.Brushes]::White, [float]($ev.X / $mp.sc - $rr/2), [float]($ev.Y / $mp.sc - $rr/2), [float]$rr, [float]$rr); $g2.Dispose()
    $mp.painted = $true; $mp.pb.Invalidate()
  }
  $pb.Add_MouseDown($paint); $pb.Add_MouseMove($paint)
  $bClr.Add_Click({ $mp = $Script:MP; $src2 = Load-Bitmap $mp.orig; $g3 = [System.Drawing.Graphics]::FromImage($mp.disp); $g3.DrawImage($src2,0,0,$mp.disp.Width,$mp.disp.Height); $g3.Dispose(); $src2.Dispose(); $g4 = [System.Drawing.Graphics]::FromImage($mp.mask); $g4.Clear([System.Drawing.Color]::Black); $g4.Dispose(); $mp.painted = $false; $mp.pb.Invalidate() })
  $bOk.Add_Click({ param($s,$ev)
    $mp = $Script:MP; if (-not $mp.painted) { MsgInfo 'Pinta primero la zona a cambiar.'; return }
    $out = Join-Path $ImgTmp ('mask_{0}.png' -f (Get-Date -Format 'yyyyMMdd_HHmmss')); $mp.mask.Save($out,[System.Drawing.Imaging.ImageFormat]::Png)
    $Script:ImgMask = $out; $lblMask.Text = 'Máscara pintada ✓'; $lblMask.ForeColor = $Col.Green; $s.FindForm().Close() })
  $bCan.Add_Click({ param($s,$ev) $s.FindForm().Close() })
  [void]$mf.ShowDialog($form)
  try { $pb.Image = $null; $disp.Dispose(); $mask.Dispose() } catch {}
}

function Quote-Arg([string]$a){
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $s = $a -replace '(\\*)"', '$1$1\"'
  $s = $s -replace '(\\+)$', '$1$1'
  return '"' + $s + '"'
}
function Strip-Accents([string]$s){
  $n = $s.Normalize([Text.NormalizationForm]::FormD); $sb = New-Object Text.StringBuilder
  foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) } }
  return (($sb.ToString().Normalize([Text.NormalizationForm]::FormC)) -replace '[^\x20-\x7E]',' ')
}
function Resize-ToFile([string]$src,[int]$w,[int]$h,[string]$dst){
  $b = Load-Bitmap $src; $o = New-Object System.Drawing.Bitmap($w,$h); $g = [System.Drawing.Graphics]::FromImage($o); $g.InterpolationMode = 'HighQualityBicubic'; $g.DrawImage($b,0,0,$w,$h); $g.Dispose(); $b.Dispose()
  $o.Save($dst,[System.Drawing.Imaging.ImageFormat]::Png); $o.Dispose()
}
function R16([double]$x){ $v = [int]([Math]::Round($x / 16.0) * 16); if ($v -lt 256) { $v = 256 }; return $v }

function Start-ImgGen {
  if ($Script:ImgBusy) { return }
  $exe = Get-SdExe; if (-not $exe) { MsgWarn 'Primero instala el MOTOR (recuadro de arriba a la izquierda).'; return }
  $mk = Get-ImgModelKey; if ((Pack-State $mk).state -ne 'ready') { MsgWarn ('Falta descargar el modelo {0} (recuadros de arriba).' -f $ImgPacks[$mk].name); return }
  $m = $cmbMode.SelectedIndex; $prompt = ($txtPrompt.Text -replace "[\r\n]+",' ').Trim()
  if (-not $prompt) { MsgInfo 'Escribe una descripción o instrucción.'; return }
  if ($m -ge 1 -and -not $Script:ImgIn) { MsgInfo 'Elige la imagen de entrada.'; return }
  if ($m -eq 3 -and -not $Script:ImgMask) { MsgInfo 'Pinta o carga una máscara (zona en blanco = se cambia).'; return }
  $p2 = Strip-Accents $prompt
  $sz = ([string]$cmbSize.SelectedItem).Split(' ')[0].Split('x'); $sw = [int]$sz[0]; $sh = [int]$sz[1]
  if ($m -ge 1) { $long = [Math]::Max($sw,$sh); $k = $long / [double][Math]::Max($Script:ImgInW,$Script:ImgInH); $sw = R16 ($Script:ImgInW * $k); $sh = R16 ($Script:ImgInH * $k) }
  $seed = [int64]$numSeed.Value; if ($seed -lt 0) { $seed = Get-Random -Minimum 1 -Maximum 2147483647 }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'; $out = Join-Path $ImgOut ('img_{0}.png' -f $stamp)
  $al = New-Object System.Collections.ArrayList
  foreach ($x in @('--diffusion-model',(Get-PackPath $mk 'diff'),'--vae',(Get-PackPath $mk 'vae'),'--llm',(Get-PackPath $mk 'llm'),'-p',$p2,'--cfg-scale','1.0','--steps',[string][int]$numSteps.Value,'-W',[string]$sw,'-H',[string]$sh,'-s',[string]$seed)) { [void]$al.Add($x) }
  try {
    if ($m -ge 1) { $inR = Join-Path $ImgTmp ('in_{0}.png' -f $stamp); Resize-ToFile $Script:ImgIn $sw $sh $inR }
    if ($m -eq 1) { foreach ($x in @('-r',$inR,'--sampling-method','euler')) { [void]$al.Add($x) } }
    if ($m -ge 2) { foreach ($x in @('-i',$inR,'--strength',([double]$numStrength.Value).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture))) { [void]$al.Add($x) } }
    if ($m -eq 3) { $mkR = Join-Path $ImgTmp ('mask_{0}_r.png' -f $stamp); Resize-ToFile $Script:ImgMask $sw $sh $mkR; foreach ($x in @('--mask',$mkR)) { [void]$al.Add($x) } }
  } catch { MsgWarn ('No se pudo preparar la imagen: ' + $_.Exception.Message); return }
  if ($chkImgFA.Checked) { [void]$al.Add('--diffusion-fa') }
  if ($chkLowVram.Checked) { [void]$al.Add('--offload-to-cpu'); [void]$al.Add('--vae-tiling') }
  if ($chkUpscale.Checked) { [void]$al.Add('--upscale-model'); [void]$al.Add((Get-PackPath 'upscale' 'up')) }
  foreach ($x in @('-v','-o',$out)) { [void]$al.Add($x) }
  $argStr = (@($al) | ForEach-Object { Quote-Arg ([string]$_) }) -join ' '
  $modeTxt = @('Generar','Editar','Transformar','Cambiar zona')[$m]
  $Script:ImgRun = @{ out=$out; start=(Get-Date); prompt=$prompt; mode=$modeTxt; model=$ImgPacks[$mk].name; seed=$seed; w=$sw; h=$sh; steps=[int]$numSteps.Value; lines=(New-Object System.Collections.ArrayList); step='' }
  $imgLog.Clear(); $imgLog.AppendText('sd-cli ' + $argStr + "`r`n")
  $Script:ImgQ.Clear(); $Script:ImgF.Stop = $false; $Script:ImgBusy = $true; $btnGen.Enabled = $false
  $lblImgStatus.Text = 'Cargando modelo... (la primera vez tarda más)'; $lblImgStatus.ForeColor = $Col.Cyan
  Write-Log 'INFO' 'IMAGEN' ('{0} con {1} {2}x{3}, semilla {4}: {5}' -f $modeTxt,$ImgPacks[$mk].name,$sw,$sh,$seed,$prompt)
  $w = Start-Worker $ImgCode @{ Q=$Script:ImgQ; F=$Script:ImgF; Exe=$exe; Args=$argStr; WorkDir=(Split-Path $exe -Parent) }
  $Script:ImgPs = $w.Ps; $Script:ImgAsync = $w.Async
}
$btnGen.Add_Click({ Start-ImgGen })
$btnStopGen.Add_Click({ if ($Script:ImgBusy) { $Script:ImgF.Stop = $true; $lblImgStatus.Text = 'Deteniendo...' } })
function Finish-ImgGen($m){
  try { [void]$Script:ImgPs.EndInvoke($Script:ImgAsync) } catch {}; try { $Script:ImgPs.Runspace.Close(); $Script:ImgPs.Dispose() } catch {}
  $Script:ImgBusy = $false; $btnGen.Enabled = $true
  $run = $Script:ImgRun; $secs = ((Get-Date) - $run.start).TotalSeconds
  if ($m.code -eq 0 -and (Test-Path -LiteralPath $run.out)) {
    $meta = @('Modo: ' + $run.mode, 'Modelo: ' + $run.model, 'Descripcion: ' + $run.prompt, ('Tamano: {0}x{1}  Pasos: {2}  Semilla: {3}' -f $run.w,$run.h,$run.steps,$run.seed), ('Tiempo: {0}' -f (Fmt-Dur $secs)))
    if ($Script:ImgIn -and $run.mode -ne 'Generar') { $meta += ('Imagen de entrada: ' + $Script:ImgIn) }
    try { [IO.File]::WriteAllLines(([IO.Path]::ChangeExtension($run.out,'.txt')), $meta) } catch {}
    Show-ImgOut $run.out; Refresh-Gallery
    $lblImgStatus.Text = ('Listo en {0}  ·  semilla {1} (reutilízala para variaciones parecidas)' -f (Fmt-Dur $secs),$run.seed); $lblImgStatus.ForeColor = $Col.Green
    Add-History 'Imagen' $run.model 'OK' (SizeOf $run.out) $secs ($run.mode + ': ' + $run.prompt)
    Write-Log 'INFO' 'IMAGEN' ('Imagen creada en {0}: {1}' -f (Fmt-Dur $secs),$run.out)
  } elseif ($m.stopped) {
    $lblImgStatus.Text = 'Detenido.'; $lblImgStatus.ForeColor = $Col.Amber; Write-Log 'WARN' 'IMAGEN' 'Generación detenida por el usuario.'
  } else {
    $all = ($run.lines -join "`n"); $hint = ''
    if ($all -match '(?i)out of memory|OutOfDeviceMemory|failed to allocate|alloc') { $hint = ' Falta memoria de GPU: baja el tamaño, deja "Modo baja VRAM" marcado o usa 512x512.' }
    elseif ($all -match '(?i)unknown argument|invalid argument|unrecognized') { $hint = ' El motor no reconoce una opción: actualiza el motor.' }
    elseif ($all -match '(?i)vulkan|vk_') { $hint = ' Problema con Vulkan: actualiza el driver de AMD o desmarca "Flash attention".' }
    $msg = ('Falló (código {0}).{1} Revisa el registro de abajo.' -f $m.code,$hint); if ($m.err) { $msg += ' ' + $m.err }
    $lblImgStatus.Text = $msg; $lblImgStatus.ForeColor = $Col.Red
    Add-History 'Imagen' $run.model 'Error' 0 $secs ($run.mode + ': ' + $msg)
    Write-Log 'ERROR' 'IMAGEN' $msg
  }
}
$Script:ImgTimer = New-Object System.Windows.Forms.Timer; $Script:ImgTimer.Interval = 250
$Script:ImgTimer.Add_Tick({
  try {
    while ($Script:ImgQ.Count -gt 0) {
      $m = $Script:ImgQ[0]; $Script:ImgQ.RemoveAt(0)
      if ($m.t -eq 'line') {
        $ln = [string]$m.text; [void]$Script:ImgRun.lines.Add($ln); if ($Script:ImgRun.lines.Count -gt 400) { $Script:ImgRun.lines.RemoveAt(0) }
        $pm = [regex]::Match($ln,'\|\s*(\d+)/(\d+)')
        if ($pm.Success) { $Script:ImgRun.step = ('paso {0} de {1}' -f $pm.Groups[1].Value,$pm.Groups[2].Value) }
        elseif ($ln -notmatch '\|[=> ]*\|') { if ($imgLog.TextLength -gt 60000) { $imgLog.Clear() }; $imgLog.AppendText($ln + "`r`n") }
      } elseif ($m.t -eq 'done') { Finish-ImgGen $m }
    }
    if ($Script:ImgBusy) { $el = ((Get-Date) - $Script:ImgRun.start).TotalSeconds; $lblImgStatus.Text = ('Generando... {0}  {1}' -f (Fmt-Dur $el),$Script:ImgRun.step) }
  } catch {}
})
$Script:ImgTimer.Start()

function Show-ImgOut([string]$path){
  try { $bmp = Load-Bitmap $path } catch { return }
  Set-PicImage $picOut $bmp; $Script:ImgSel = $path
  $info = ('{0}  ({1}x{2})' -f (Split-Path $path -Leaf),$bmp.Width,$bmp.Height)
  $tf = [IO.Path]::ChangeExtension($path,'.txt'); if (Test-Path -LiteralPath $tf) { try { $info += '  ·  ' + ((Get-Content -LiteralPath $tf -TotalCount 3) -join '  ·  ') } catch {} }
  $lblImgInfo.Text = $info; $lblImgInfo.MaximumSize = New-Object System.Drawing.Size(700,0)
}
function Refresh-Gallery {
  foreach ($c in @($gallery.Controls)) { try { if ($c.Image) { $c.Image.Dispose() }; $c.Dispose() } catch {} }; $gallery.Controls.Clear()
  $files = @(Get-ChildItem -LiteralPath $ImgOut -File -Filter '*.png' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 40)
  foreach ($fi in $files) {
    try {
      $b = Load-Bitmap $fi.FullName; $tw = 100; $th = [int](100.0 * $b.Height / $b.Width); if ($th -gt 100) { $th = 100; $tw = [int](100.0 * $b.Width / $b.Height) }
      $t = New-Object System.Drawing.Bitmap($b,$tw,$th); $b.Dispose()
      $pbx = New-Object System.Windows.Forms.PictureBox; $pbx.Size = New-Object System.Drawing.Size(102,102); $pbx.SizeMode = 'Zoom'; $pbx.Image = $t; $pbx.Tag = $fi.FullName; $pbx.Cursor = 'Hand'; $pbx.Margin = New-Object System.Windows.Forms.Padding(3)
      $pbx.Add_Click({ param($s,$ev) Show-ImgOut ([string]$s.Tag) }); $gallery.Controls.Add($pbx)
    } catch {}
  }
}
$btnUseIn.Add_Click({ if ($Script:ImgSel) { Set-ImgIn $Script:ImgSel; if ($cmbMode.SelectedIndex -eq 0) { $cmbMode.SelectedIndex = 1 }; Set-Status 'Imagen puesta como entrada: escribe la siguiente instrucción.' } })
$btnOpenImg.Add_Click({ if ($Script:ImgSel) { Start-Process -FilePath $Script:ImgSel } })
$btnCopyImg.Add_Click({ if ($Script:ImgSel) { $b = Load-Bitmap $Script:ImgSel; [System.Windows.Forms.Clipboard]::SetImage($b); Set-Status 'Imagen copiada al portapapeles.' } })
$btnOpenOut.Add_Click({ Start-Process explorer.exe $ImgOut })

# =====================================================================
#  KIT DE PROGRAMACION (VS Code + Continue)
# =====================================================================
function Build-ContinueYaml($chat,$fast,$auto,$emb){
  $L = New-Object System.Collections.ArrayList
  foreach ($x in @('name: Ollama local (Ollama Manager Pro)','version: 1.0.0','schema: v1','models:')) { [void]$L.Add($x) }
  if ($chat) { foreach ($x in @(('  - name: {0}' -f $chat),'    provider: ollama',('    model: {0}' -f $chat),'    roles: [chat, edit, apply]')) { [void]$L.Add($x) } }
  if ($fast -and $fast -ne $chat) { foreach ($x in @(('  - name: {0} (rápido)' -f $fast),'    provider: ollama',('    model: {0}' -f $fast),'    roles: [chat, edit, apply]')) { [void]$L.Add($x) } }
  if ($auto) { foreach ($x in @(('  - name: {0} (autocompletar)' -f $auto),'    provider: ollama',('    model: {0}' -f $auto),'    roles: [autocomplete]')) { [void]$L.Add($x) } }
  if ($emb) { foreach ($x in @(('  - name: {0} (indexar proyecto)' -f $emb),'    provider: ollama',('    model: {0}' -f $emb),'    roles: [embed]')) { [void]$L.Add($x) } }
  return ($L -join "`r`n")
}
function Open-CodeKit {
  $kit = @(@('qwen3-coder:30b','Chat y agente de código principal (el más capaz)'),@('qwen2.5-coder:7b','Respuestas rápidas, cabe en la GPU'),@('qwen2.5-coder:1.5b','Autocompletado mientras escribes'),@('nomic-embed-text:latest','Indexa tu proyecto para preguntar sobre el código'))
  $kf = New-Object System.Windows.Forms.Form; $kf.Text = 'Kit de programación offline'; $kf.StartPosition = 'CenterParent'; $kf.ClientSize = New-Object System.Drawing.Size(760,600); $kf.BackColor = $Col.Bg; $kf.ForeColor = $Col.Txt; $kf.Font = $FNorm
  $fl = New-Object System.Windows.Forms.FlowLayoutPanel; $fl.Dock = 'Fill'; $fl.FlowDirection = 'TopDown'; $fl.WrapContents = $false; $fl.AutoScroll = $true; $fl.Padding = New-Object System.Windows.Forms.Padding(16,12,16,12)
  $fl.Controls.Add((New-Lbl 'PROGRAMAR CON IA SIN INTERNET' $FH2 $Col.Acc))
  $tx = New-Lbl "1) Descarga los modelos marcados.   2) Instala Visual Studio Code y su extensión 'Continue' (una vez con internet, o desde un archivo .vsix).`n3) Guarda la configuración de abajo: Continue usará tus modelos de Ollama para chatear, editar y autocompletar código." $FSm $Col.Sub
  $tx.MaximumSize = New-Object System.Drawing.Size(720,0); $fl.Controls.Add($tx)
  $clb = New-Object System.Windows.Forms.CheckedListBox; $clb.Width = 720; $clb.Height = 96; $clb.BackColor = $Col.Card; $clb.ForeColor = $Col.Txt; $clb.BorderStyle = 'None'; $clb.CheckOnClick = $true; $clb.Font = $FSm
  foreach ($k in $kit) {
    $e = Get-Entry $k[0]; $st = 'no instalado'; if ($Script:Installed.ContainsKey($k[0])) { $st = 'INSTALADO' }
    $md = ''; if ($e) { $md = $ModeTxt[(Get-Fit $e).mode] }
    $i = $clb.Items.Add(('{0}  —  {1}  [{2} · {3}]' -f $k[0],$k[1],$md,$st)); $clb.SetItemChecked($i, -not $Script:Installed.ContainsKey($k[0]))
  }
  $fl.Controls.Add($clb)
  $chatM = 'qwen3-coder:30b'; $e0 = Get-Entry $chatM; if ($e0 -and -not (Get-Fit $e0).ok) { $chatM = 'qwen2.5-coder:7b' }
  $yaml = Build-ContinueYaml $chatM 'qwen2.5-coder:7b' 'qwen2.5-coder:1.5b' 'nomic-embed-text:latest'
  $fl.Controls.Add((New-Lbl 'CONFIGURACIÓN PARA CONTINUE (config.yaml)' $FSmB $Col.Sub))
  $ty = New-Object System.Windows.Forms.TextBox; $ty.Multiline = $true; $ty.ReadOnly = $true; $ty.ScrollBars = 'Vertical'; $ty.Width = 720; $ty.Height = 230; $ty.BackColor = $Col.Panel; $ty.ForeColor = $Col.Txt; $ty.Font = $FMono; $ty.Text = $yaml; $fl.Controls.Add($ty)
  $row = New-Flow 'LeftToRight'; $row.WrapContents = $false
  $b1 = New-Btn 'Descargar marcados' $Col.White $Col.Acc $true; $row.Controls.Add($b1)
  $b2 = New-Btn 'Guardar configuración de Continue' $Col.Green $Col.Green $false; $row.Controls.Add($b2)
  $b3 = New-Btn 'Copiar' $Col.Sub $Col.Border $false; $row.Controls.Add($b3)
  $fl.Controls.Add($row)
  $kf.Controls.Add($fl)
  $Script:KitState = @{ clb=$clb; kit=$kit; yaml=$yaml }
  $b1.Add_Click({ $ks = $Script:KitState; $n = 0; for ($i = 0; $i -lt $ks.clb.Items.Count; $i++) { if ($ks.clb.GetItemChecked($i)) { Enqueue-Download $ks.kit[$i][0] $true; $n++ } }; Set-Status ('{0} modelo(s) de programación en cola.' -f $n) })
  $b3.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($Script:KitState.yaml); Set-Status 'Configuración copiada.' })
  $b2.Add_Click({
    $dir = Join-Path $env:USERPROFILE '.continue'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dst = Join-Path $dir 'config.yaml'; $note = ''
    if (Test-Path -LiteralPath $dst) { $dst = Join-Path $dir 'config.ollama-manager.yaml'; $note = "`n`nYa tenías un config.yaml: NO lo he tocado. Copia el contenido de este archivo dentro del tuyo." }
    [IO.File]::WriteAllText($dst, $Script:KitState.yaml, (New-Object Text.UTF8Encoding($false)))
    Write-Log 'INFO' 'CODIGO' ('Configuración de Continue guardada en ' + $dst); MsgInfo ('Guardado en:' + "`n" + $dst + $note) })
  [void]$kf.ShowDialog($form)
}

# =====================================================================
#  BUSQUEDA EN INTERNET (ollama.com + Hugging Face) Y CONSULTAS EN SEGUNDO PLANO
# =====================================================================
$FetchCode = {
param($A)
$Q = $A.Q; $CurlX = @($A.CurlX)
foreach ($r in @($A.Reqs)) {
  $tmp = [IO.Path]::GetTempFileName(); $code = '000'; $body = ''
  try {
    $al = @('-s','-L','--connect-timeout','10','--max-time','30','-A','OllamaManagerPro') + $CurlX
    foreach ($hd in @($r.hdr)) { if ($hd) { $al += @('-H',[string]$hd) } }
    $al += @('-o',$tmp,'-w','%{http_code}',[string]$r.url)
    $code = [string](& $A.Curl @al)
    if ($code -eq '200') { $body = [IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8) }
  } catch {}
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $null = $Q.Add(@{ t='fetch'; seq=$A.Seq; key=[string]$r.key; code=$code; body=$body })
}
$null = $Q.Add(@{ t='fetchdone'; seq=$A.Seq })
}
$Script:FetchQ = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Script:Fetches = @{}; $Script:FetchSeq = 0; $Script:SrchCache = @{}; $Script:SrchRunning = @{}
function Start-Fetch([string]$tag,$reqs,$ctx){
  $Script:FetchSeq++; $seq = $Script:FetchSeq
  $w = Start-Worker $FetchCode @{ Q=$Script:FetchQ; Seq=$seq; Reqs=@($reqs); Curl=$CurlPath; CurlX=@($Script:CurlX) }
  $Script:Fetches[$seq] = @{ tag=$tag; ctx=$ctx; res=@{}; ps=$w.Ps; async=$w.Async }
  return $seq
}
function Handle-FetchMsg($m){
  if (-not $Script:Fetches.ContainsKey($m.seq)) { return }
  $fj = $Script:Fetches[$m.seq]
  if ($m.t -eq 'fetch') { $fj.res[$m.key] = @{ code=$m.code; body=$m.body }; return }
  try { [void]$fj.ps.EndInvoke($fj.async) } catch {}; try { $fj.ps.Runspace.Close(); $fj.ps.Dispose() } catch {}
  $Script:Fetches.Remove($m.seq)
  switch ($fj.tag) { 'search' { Finish-Search $fj } 'ollamarel' { Finish-OllamaRel $fj } }
}
function UrlEnc([string]$s){ return [Uri]::EscapeDataString($s) }
function Start-OnlineSearch([string]$q){
  $q = $q.Trim().ToLower(); if ($q.Length -lt 2) { return }
  if ($Script:SrchCache.ContainsKey($q) -or $Script:SrchRunning.ContainsKey($q)) { return }
  $base = $q; $tag = ''
  if ($q -match '^(.+):([A-Za-z0-9._\-]+)$') { $base = $matches[1]; $tag = $matches[2] }
  $term = $base -replace '^hf\.co/',''
  $reqs = @(
    @{ key='ol'; url=('https://ollama.com/search?q=' + (UrlEnc $term)) },
    @{ key='hf'; url=('https://huggingface.co/api/models?search={0}&filter=gguf&sort=downloads&direction=-1&limit=8' -f (UrlEnc $term)) } )
  if ($base -match '^[a-z0-9][a-z0-9._\-]*$') { $reqs += @{ key='lib'; url=('https://ollama.com/library/' + $base) } }
  elseif ($base -match '^[a-z0-9_\-]+/[a-z0-9._\-]+$') { $reqs += @{ key='comm'; url=('https://ollama.com/' + $base) } }
  if ($tag -and $base -notmatch '^hf\.co/') {
    $p = Split-ModelId ($base + ':' + $tag)
    $reqs += @{ key='reg'; url=('{0}/v2/{1}/{2}/manifests/{3}' -f $Script:Registry,$p.ns,$p.name,$p.tag); hdr=@('Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json') }
  }
  $Script:SrchRunning[$q] = $true
  [void](Start-Fetch 'search' $reqs @{ q=$q; base=$base; tag=$tag })
  Write-Log 'INFO' 'BUSCAR' ('Buscando en internet: ' + $q)
}
function Get-HtmlDesc([string]$html){ $dm = [regex]::Match($html,'<meta name="description" content="([^"]*)"'); if ($dm.Success) { return [System.Net.WebUtility]::HtmlDecode($dm.Groups[1].Value) }; return '' }
function Finish-Search($fj){
  $q = $fj.ctx.q; $Script:SrchRunning.Remove($q)
  $r = @{ q=$q; ol=@(); hf=@(); exact=''; exactId=''; offline=$false }
  if (@($fj.res.Values | Where-Object { $_.code -ne '000' }).Count -eq 0) { $r.offline = $true }
  $ol = $fj.res['ol']
  if ($ol -and $ol.code -eq '200') {
    $seen = @{}
    foreach ($m in [regex]::Matches($ol.body,'href="/library/([A-Za-z0-9._\-]+)"')) {
      $n = $m.Groups[1].Value; if ($seen.ContainsKey($n)) { continue }; $seen[$n] = $true
      $desc = ''; $dm = [regex]::Match($ol.body,('href="/library/' + [regex]::Escape($n) + '"[\s\S]{0,2500}?<p[^>]*>\s*([^<]{8,300}?)\s*</p>'))
      if ($dm.Success) { $desc = [System.Net.WebUtility]::HtmlDecode($dm.Groups[1].Value.Trim()) }
      $r.ol += @{ name=$n; desc=$desc }; if ($r.ol.Count -ge 10) { break }
    }
  }
  foreach ($k in @('lib','comm')) {
    $x = $fj.res[$k]
    if ($x -and $x.code -eq '200' -and -not (@($r.ol) | Where-Object { $_.name -eq $fj.ctx.base })) { $r.ol = @(@{ name=$fj.ctx.base; desc=(Get-HtmlDesc $x.body) }) + @($r.ol) }
  }
  $hf = $fj.res['hf']
  if ($hf -and $hf.code -eq '200') { try { foreach ($o in @($hf.body | ConvertFrom-Json)) { if ($o.id) { $r.hf += @{ id=[string]$o.id; dl=[int64]$o.downloads } } } } catch {} }
  $rg = $fj.res['reg']; if ($rg) { $r.exact = [string]$rg.code; $r.exactId = ('{0}:{1}' -f $fj.ctx.base,$fj.ctx.tag) }
  $Script:SrchCache[$q] = $r
  if ($r.offline) { Write-Log 'WARN' 'BUSCAR' ('Sin conexión al buscar: ' + $q) }
  elseif ($r.ol.Count -eq 0 -and $r.hf.Count -eq 0 -and $r.exact -ne '200') { Notify 'Modelo no encontrado' ('"{0}" no existe en ollama.com ni en Hugging Face. Revisa la ortografía.' -f $q) 'Warning'; Write-Log 'WARN' 'BUSCAR' ('No encontrado en internet: ' + $q); Set-Status ('"{0}" no existe en ollama.com ni en Hugging Face.' -f $q) }
  else { Write-Log 'INFO' 'BUSCAR' ('{0}: {1} resultado(s) en ollama.com, {2} en Hugging Face' -f $q,$r.ol.Count,$r.hf.Count); Set-Status ('"{0}": {1} resultado(s) en ollama.com y {2} en Hugging Face.' -f $q,$r.ol.Count,$r.hf.Count) }
  if ($Script:F_Search.ToLower() -eq $q) { ApplyFilters }
}
function LevDist([string]$a,[string]$b){
  $m = $a.Length; $n = $b.Length; if ($m -eq 0) { return $n }; if ($n -eq 0) { return $m }
  $prev = New-Object int[] ($n + 1); $cur = New-Object int[] ($n + 1)
  for ($j = 0; $j -le $n; $j++) { $prev[$j] = $j }
  for ($i = 1; $i -le $m; $i++) {
    $cur[0] = $i
    for ($j = 1; $j -le $n; $j++) { $c = 1; if ($a[$i-1] -eq $b[$j-1]) { $c = 0 }; $cur[$j] = [Math]::Min([Math]::Min($prev[$j] + 1, $cur[$j-1] + 1), $prev[$j-1] + $c) }
    $tmp = $prev; $prev = $cur; $cur = $tmp
  }
  return $prev[$n]
}
function Get-Suggestions([string]$q){
  $b = ($q -replace '^hf\.co/','') -replace ':.*$',''
  $names = @{}; foreach ($e in $Script:Catalog) { $names[(([string]$e.id).Split(':')[0])] = $true }
  $res = @()
  foreach ($n in $names.Keys) {
    $d = LevDist $b $n; $lim = [Math]::Max(2,[int]($b.Length / 4))
    if ($d -le $lim -or ($b.Length -ge 3 -and $n.StartsWith($b.Substring(0,3)))) { $res += @{ n=$n; d=$d } }
  }
  return @($res | Sort-Object { $_.d } | Select-Object -First 6 | ForEach-Object { $_.n })
}
function Srch-Lbl([string]$t,$font,[System.Drawing.Color]$c){ $l = New-Lbl $t $font $c; $l.MaximumSize = New-Object System.Drawing.Size(($Script:SrchW - 40),0); return $l }
function Srch-Row([string]$name,[string]$desc,[string]$btxt,[string]$tag,[scriptblock]$act){
  $row = New-Flow 'LeftToRight'; $row.WrapContents = $false; $row.Margin = New-Object System.Windows.Forms.Padding(0,2,0,2)
  $l1 = New-Object System.Windows.Forms.Label; $l1.Text = $name; $l1.Font = $FBold; $l1.ForeColor = $Col.Txt; $l1.AutoSize = $false; $l1.AutoEllipsis = $true; $l1.Size = New-Object System.Drawing.Size(280,22); $l1.Margin = New-Object System.Windows.Forms.Padding(0,6,6,0); $row.Controls.Add($l1)
  $l2 = New-Object System.Windows.Forms.Label; $l2.Text = $desc; $l2.Font = $FSm; $l2.ForeColor = $Col.Sub; $l2.AutoSize = $false; $l2.AutoEllipsis = $true; $l2.Size = New-Object System.Drawing.Size(([Math]::Max(200,$Script:SrchW - 560)),22); $l2.Margin = New-Object System.Windows.Forms.Padding(0,7,6,0); $row.Controls.Add($l2)
  $b = New-Btn $btxt $Col.Cyan $Col.Cyan $false; $b.Tag = $tag; $b.Add_Click($act); $row.Controls.Add($b)
  return $row
}
function New-SearchPanel([string]$q,[int]$localCount){
  $Script:SrchW = [Math]::Max(620, $catFlow.ClientSize.Width - 40)
  $r = $null; if ($Script:SrchCache.ContainsKey($q)) { $r = $Script:SrchCache[$q] }
  $box = New-RP 12 $(if ($localCount -eq 0) { $Col.Amber } else { $Col.Border }); $box.BackColor = $Col.Card; $box.Margin = New-Object System.Windows.Forms.Padding(6)
  $fl = New-Object System.Windows.Forms.FlowLayoutPanel; $fl.FlowDirection = 'TopDown'; $fl.WrapContents = $false; $fl.AutoSize = $true; $fl.AutoSizeMode = 'GrowAndShrink'; $fl.BackColor = $Col.Card; $fl.Location = New-Object System.Drawing.Point(16,12)
  $box.Controls.Add($fl)
  if ($localCount -eq 0) { $fl.Controls.Add((Srch-Lbl ('"{0}" no está en el catálogo de la app' -f $q) $FH2 $Col.Amber)) }
  else { $fl.Controls.Add((Srch-Lbl ('¿No es lo que buscas? Busca "{0}" en internet' -f $q) $FBold $Col.Sub)) }
  $filt = ($Script:F_Cat -ne 'Todas' -or $Script:F_Cap -ne 'Todas' -or $Script:F_Size -ne 'Todos' -or $Script:F_Fit -ne 'Todos' -or $Script:F_Rec -or $Script:F_HideInst)
  if ($localCount -eq 0 -and $filt) { $fl.Controls.Add((Srch-Lbl 'Ojo: hay filtros activos (categoría, capacidad, tamaño, compatibilidad...) que pueden estar ocultando modelos del catálogo.' $FSm $Col.Amber)) }
  if (-not $r) {
    if ($Script:SrchRunning.ContainsKey($q)) { $fl.Controls.Add((Srch-Lbl 'Buscando en ollama.com y en Hugging Face...' $FSm $Col.Cyan)) }
    elseif ($localCount -eq 0) { $fl.Controls.Add((Srch-Lbl 'Buscando en ollama.com y en Hugging Face...' $FSm $Col.Cyan)); Start-OnlineSearch $q }
    else { $b = New-Btn ('Buscar "{0}" en ollama.com y Hugging Face' -f $q) $Col.Cyan $Col.Cyan $false; $b.Tag = $q; $b.Add_Click({ param($s,$ev) Start-OnlineSearch ([string]$s.Tag); ApplyFilters }); $fl.Controls.Add($b) }
  } elseif ($r.offline) {
    $fl.Controls.Add((Srch-Lbl 'Sin conexión a internet: no se pudo buscar fuera del catálogo.' $FSm $Col.Red))
    $b = New-Btn 'Reintentar' $Col.Txt $Col.Border $false; $b.Tag = $q; $b.Add_Click({ param($s,$ev) $Script:SrchCache.Remove([string]$s.Tag); Start-OnlineSearch ([string]$s.Tag); ApplyFilters }); $fl.Controls.Add($b)
  } else {
    if ($r.exact -eq '200') {
      $fl.Controls.Add((Srch-Row ('✓ ' + $r.exactId) 'Existe en el registro de Ollama: se puede descargar con esta app.' 'Añadir y descargar' $r.exactId { param($s,$ev) $id = [string]$s.Tag; [System.Windows.Forms.Cursor]::Current = 'WaitCursor'; $sz = Get-RemoteSize $id; if ($sz -lt 0) { $sz = 0 }; Add-UserEntry $id $sz '' @() 'Personalizado'; $Script:FitCache = @{}; ApplyFilters; Enqueue-Download $id $false }))
    } elseif ($r.exact -eq '404') { $fl.Controls.Add((Srch-Lbl ('La versión "{0}" NO existe. Elige una de las versiones disponibles abajo.' -f $r.exactId) $FSm $Col.Amber)) }
    if ($r.ol.Count -gt 0) {
      $fl.Controls.Add((Srch-Lbl 'OLLAMA.COM  —  se descargan con esta app (con reanudación)' $FSmB $Col.Green))
      foreach ($o in @($r.ol | Select-Object -First 8)) { $fl.Controls.Add((Srch-Row $o.name $o.desc 'Ver versiones y añadir...' $o.name { param($s,$ev) Open-Explorer ([string]$s.Tag) })) }
    }
    if ($r.hf.Count -gt 0) {
      $fl.Controls.Add((Srch-Lbl 'HUGGING FACE  —  archivos GGUF (descarga vía hf.co, experimental)' $FSmB $Col.Orange))
      foreach ($o in @($r.hf | Select-Object -First 6)) { $fl.Controls.Add((Srch-Row $o.id ('{0:N0} descargas' -f $o.dl) 'Elegir versión...' $o.id { param($s,$ev) Open-HfPicker ([string]$s.Tag) })) }
    }
    if ($r.ol.Count -eq 0 -and $r.hf.Count -eq 0 -and $r.exact -ne '200') {
      $fl.Controls.Add((Srch-Lbl ('✗ No existe ningún modelo "{0}" en ollama.com ni en Hugging Face.' -f $q) $FBold $Col.Red))
      $sug = @(Get-Suggestions $q)
      if ($sug.Count -gt 0) {
        $fl.Controls.Add((Srch-Lbl '¿Quizás quisiste decir...?' $FSm $Col.Txt))
        $rs = New-Flow 'LeftToRight'; foreach ($n in $sug) { $b = New-Btn $n $Col.Cyan $Col.Border $false; $b.Tag = $n; $b.Add_Click({ param($s,$ev) $txtSearch.Text = [string]$s.Tag }); $rs.Controls.Add($b) }; $fl.Controls.Add($rs)
      }
      $fl.Controls.Add((Srch-Lbl 'Revisa la ortografía o busca solo una parte del nombre (ej. "qwen" en vez de "qwen-3-vl-8b").' $FSm $Col.Sub))
    }
    $fl.Controls.Add((Srch-Lbl 'Otras vías: escribe el ID exacto (nombre:etiqueta) y la app comprueba si existe; o descarga un .gguf desde el navegador y usa Offline > "Importar archivo GGUF".' $FSm $Col.Sub))
  }
  $fl.PerformLayout()
  $box.Size = New-Object System.Drawing.Size($Script:SrchW, ([Math]::Max(70, $fl.PreferredSize.Height + 26)))
  return $box
}
function Open-HfPicker([string]$repo){
  [System.Windows.Forms.Cursor]::Current = 'WaitCursor'; Set-Status ('Consultando ' + $repo + ' en Hugging Face...')
  $js = Curl-Text ('https://huggingface.co/api/models/{0}/tree/main' -f $repo) 30
  if (-not $js) { MsgWarn 'No se pudo consultar Hugging Face (¿sin conexión?).'; return }
  $rows = @()
  try {
    foreach ($o in @($js | ConvertFrom-Json)) {
      $pth = [string]$o.path; if ($pth -notmatch '(?i)\.gguf$' -or $pth -match '(?i)mmproj') { continue }
      $qm = [regex]::Match($pth,'(?i)(IQ\d_[A-Z]+|Q\d_K_[SML]|Q\d_K|Q\d_\d|F16|BF16|F32)')
      $sz = [double]$o.size; if ($o.lfs) { $sz = [double]$o.lfs.size }
      $rows += @{ file=$pth; quant=$(if ($qm.Success) { $qm.Groups[1].Value.ToUpper() } else { '' }); size=$sz; split=($pth -match '-\d{5}-of-\d{5}') }
    }
  } catch {}
  if ($rows.Count -eq 0) { if (MsgYes ('{0} no tiene archivos GGUF en su carpeta principal. ¿Abrirlo en el navegador para revisarlo?' -f $repo)) { Start-Process ('https://huggingface.co/' + $repo) }; return }
  $hf = New-Object System.Windows.Forms.Form; $hf.Text = ('Hugging Face: ' + $repo); $hf.StartPosition = 'CenterParent'; $hf.ClientSize = New-Object System.Drawing.Size(820,520); $hf.BackColor = $Col.Bg; $hf.ForeColor = $Col.Txt; $hf.Font = $FNorm
  $top = New-Lbl ("Elige la versión (cuantización). Q4_K_M suele ser el mejor equilibrio calidad/tamaño; Q8_0 = más calidad y más pesado.`nLa descarga usa el protocolo de Ollama desde hf.co (experimental). Si fallara, descarga el .gguf con el navegador y usa Offline > Importar archivo GGUF.") $FSm $Col.Sub
  $top.Dock = 'Top'; $top.AutoSize = $false; $top.Height = 50; $top.Padding = New-Object System.Windows.Forms.Padding(12,8,12,0)
  $lv = New-LV @('Versión=110','Tamaño=90','Con tu perfil=150','Archivo=440'); $lv.CheckBoxes = $false; $lv.MultiSelect = $false
  foreach ($rw in ($rows | Sort-Object { $_.size })) {
    $it = New-Object System.Windows.Forms.ListViewItem($(if ($rw.quant) { $rw.quant } else { '?' })); $it.Tag = $rw; $it.UseItemStyleForSubItems = $false
    [void]$it.SubItems.Add((Human $rw.size))
    $pe = @{ id=('hfpick:' + $rw.file); gb=($rw.size / 1GB); p=1; act=1; caps=@() }; $ft = Get-Fit $pe; $Script:FitCache.Remove($pe.id)
    $s3 = $it.SubItems.Add($ModeTxt[$ft.mode]); $s3.ForeColor = $ModeCol[$ft.mode]
    $s4 = $it.SubItems.Add($rw.file); if ($rw.split -or -not $rw.quant) { $s4.Text = $rw.file + '   (no compatible: archivo dividido o sin versión)'; $s4.ForeColor = $Col.Red }
    [void]$lv.Items.Add($it)
  }
  $wrap = New-Object System.Windows.Forms.Panel; $wrap.Dock = 'Fill'; $wrap.Padding = New-Object System.Windows.Forms.Padding(12,4,12,4); $wrap.Controls.Add($lv)
  $bar = New-Object System.Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 48; $bar.Padding = New-Object System.Windows.Forms.Padding(12,8,12,0); $bar.BackColor = $Col.Bg
  $b1 = New-Btn 'Añadir y descargar' $Col.White $Col.Acc $true; $b2 = New-Btn 'Solo añadir al catálogo' $Col.Txt $Col.Border $false; $b3 = New-Btn 'Copiar comando "ollama pull"' $Col.Sub $Col.Border $false; $b4 = New-Btn 'Abrir en el navegador' $Col.Cyan $Col.Cyan $false
  foreach ($b in @($b1,$b2,$b3,$b4)) { $bar.Controls.Add($b) }
  $hf.Controls.Add($wrap); $hf.Controls.Add($top); $hf.Controls.Add($bar)
  $Script:HfState = @{ repo=$repo; lv=$lv }
  $pick = {
    param([int]$mode)
    $st = $Script:HfState; if ($st.lv.SelectedItems.Count -eq 0) { MsgInfo 'Elige una versión de la lista.'; return }
    $rw = $st.lv.SelectedItems[0].Tag; if ($rw.split -or -not $rw.quant) { MsgWarn 'Esa versión no se puede descargar por esta vía (archivo dividido o sin etiqueta de versión). Descárgala con el navegador e impórtala como GGUF.'; return }
    $id = ('hf.co/{0}:{1}' -f $st.repo,$rw.quant)
    if ($mode -eq 3) { [System.Windows.Forms.Clipboard]::SetText(('ollama pull ' + $id)); Set-Status ('Copiado: ollama pull ' + $id); return }
    Add-UserEntry $id $rw.size 'Modelo GGUF de Hugging Face (descarga vía hf.co, experimental).' @('Chat') 'Personalizado'
    $ne = Get-Entry $id; if ($ne) { $ne.name = ('{0} {1}' -f ($st.repo.Split('/')[-1]),$rw.quant); $ne.kind = 'GGUF de Hugging Face'; Save-UserCatalog }
    Write-Log 'INFO' 'CATALOGO' ('Añadido desde Hugging Face: ' + $id); $Script:FitCache = @{}; ApplyFilters
    if ($mode -eq 1) { Enqueue-Download $id $false } else { Set-Status ('Añadido al catálogo: ' + $id) }
  }
  $Script:HfPick = $pick
  $b1.Add_Click({ & $Script:HfPick 1 }); $b2.Add_Click({ & $Script:HfPick 2 }); $b3.Add_Click({ & $Script:HfPick 3 })
  $b4.Add_Click({ Start-Process ('https://huggingface.co/' + $Script:HfState.repo) })
  [void]$hf.ShowDialog($form)
}
function Start-OllamaRelCheck { [void](Start-Fetch 'ollamarel' @(@{ key='rel'; url='https://api.github.com/repos/ollama/ollama/releases/latest'; hdr=@('Accept: application/vnd.github+json') }) @{}) }
function Finish-OllamaRel($fj){
  $r = $fj.res['rel']; if (-not $r -or $r.code -ne '200') { return }
  try { $tag = [string]($r.body | ConvertFrom-Json).tag_name } catch { return }
  $latest = $tag.TrimStart('v'); $Script:OllamaLatest = $latest
  if (-not $Script:OllamaVer) { return }
  try {
    $vl = [version](($latest -replace '[^0-9.].*$','').TrimEnd('.')); $vi = [version](($Script:OllamaVer -replace '[^0-9.].*$','').TrimEnd('.'))
    if ($vl -gt $vi) {
      $Script:OllamaUpd = $true; Update-OllamaStatus
      Write-Log 'INFO' 'OLLAMA' ('Nueva versión de Ollama disponible: {0} (tienes {1}).' -f $latest,$Script:OllamaVer)
      Notify 'Nueva versión de Ollama' ('Disponible la {0} (tienes la {1}). Descárgala en la pestaña Offline > "Descargar / actualizar instalador".' -f $latest,$Script:OllamaVer) 'Info'
    }
  } catch {}
}

# ---------- Montaje (orden de docking) ----------
$form.SuspendLayout()
$form.Controls.Add($content)
$form.Controls.Add($nav)
$form.Controls.Add($sep)
$form.Controls.Add($header)
$form.Controls.Add($jobPanel)
$form.Controls.Add($statusBar)
$form.ResumeLayout($true)

function Show-Page([string]$key){
  foreach ($k in @($Script:Pages.Keys)) { $Script:Pages[$k].Visible = ($k -eq $key) }
  foreach ($b in $Script:NavBtns) { if ([string]$b.Tag -eq $key) { $b.BackColor = $Col.Acc; $b.ForeColor = $Col.White } else { $b.BackColor = $Col.Panel; $b.ForeColor = $Col.Sub } }
  $Script:CurPage = $key
  if ($key -eq 'hist') { Load-History }
  if ($key -eq 'inst') { Refresh-InstalledLV }
  if ($key -eq 'off') { Update-InstallerLabel; if ($txtImp.Text.Trim() -and $lvRepo.Items.Count -eq 0) { Read-Repo } }
  if ($key -eq 'img') { Refresh-ImgState; if ($gallery.Controls.Count -eq 0) { Refresh-Gallery } }
}

# =====================================================================
#  ACCIONES
# =====================================================================
$PersistTypes = @('download','files','engine','installer','export','import','copytree')
function Get-XtraStr { $x = ''; if ([int]$Script:Cfg.RateKB -gt 0) { $x += ('--limit-rate {0}k ' -f [int]$Script:Cfg.RateKB) }; if ([string]$Script:Cfg.Proxy) { $x += ('-x "{0}"' -f [string]$Script:Cfg.Proxy) }; return $x.Trim() }
function ConvertTo-HTDeep($o){
  if ($null -eq $o) { return $null }
  if ($o -is [System.Management.Automation.PSCustomObject]) { $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-HTDeep $p.Value }; return $h }
  if ($o -is [string]) { return $o }
  if ($o -is [System.Collections.IEnumerable]) { $arr = @(); foreach ($x in $o) { $arr += ,(ConvertTo-HTDeep $x) }; return ,$arr }
  return $o
}
function Save-Queue {
  try {
    $list = @()
    if ($Script:CurJob -and $PersistTypes -contains $Script:CurJob.type) { $list += $Script:CurJob }
    foreach ($j in $Script:Jobs) { if ($PersistTypes -contains $j.type) { $list += $j } }
    if ($list.Count -eq 0) { if (Test-Path -LiteralPath $QueueFile) { Remove-Item -LiteralPath $QueueFile -Force }; return }
    $o = @{ guardado=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); pausado=[bool]$Script:Paused; tareas=@($list) }
    ($o | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $QueueFile -Encoding UTF8
  } catch { Write-Log 'WARN' 'COLA' ('No se pudo guardar la cola: ' + $_.Exception.Message) }
}
function Load-Queue {
  if (-not (Test-Path -LiteralPath $QueueFile)) { return }
  try { $h = ConvertTo-HTDeep (Get-Content -LiteralPath $QueueFile -Raw -Encoding UTF8 | ConvertFrom-Json); if ($h.pausado -eq $true) { $Script:Paused = $true }; foreach ($j in @($h.tareas)) { if ($j -is [hashtable] -and $j.type) { $j.fresh = $false; $j } } }
  catch { Write-Log 'WARN' 'COLA' ('Cola guardada ilegible; se ignora: ' + $_.Exception.Message) }
}
function Update-QueueLabel {
  $n = $Script:Jobs.Count
  if ($n -eq 0) { $lblQueue.Text = 'Cola vacía' } else { $nx = $Script:Jobs[0].label; $lblQueue.Text = ('En cola: {0}{1}Siguiente: {2}' -f $n,[Environment]::NewLine,$nx) }
  if ($Script:Paused) { $lblQueue.Text = ('EN PAUSA  ·  ' + $lblQueue.Text); $btnPause.Text = 'Reanudar' } else { $btnPause.Text = 'Pausar' }
  $btnClearQ.Enabled = ($n -gt 0); $btnPause.Enabled = ($Script:CurJob -or $n -gt 0 -or $Script:Paused); $btnViewQ.Enabled = ($n -gt 0 -or $Script:CurJob)
}
function Toggle-Pause {
  if ($Script:Paused) {
    $Script:Paused = $false; Write-Log 'INFO' 'COLA' 'Cola reanudada.'; Set-Status 'Reanudando...'; Save-Queue; Update-QueueLabel; Start-NextJob; return
  }
  if ($Script:CurJob) { $Script:PausePending = $true; $Script:Flags.Cancel = $true; Set-Status 'Pausando... (lo descargado se conserva)' }
  else { $Script:Paused = $true; Update-QueueLabel; Save-Queue }
}
function Add-Job($job){
  if ($job.type -eq 'download' -and ((Is-Queued $job.id) -or (Is-Downloading $job.id))) { return }
  [void]$Script:Jobs.Add($job); Write-Log 'INFO' 'COLA' ('Añadido a la cola: ' + $job.label)
  Save-Queue; Update-QueueLabel; if ($job.type -eq 'download') { Update-CardStates }
  if ($Script:Paused) { $jobPanel.Visible = $true; $lblJobTitle.Text = 'Cola en pausa'; $lblJobStatus.Text = 'Pulsa "Reanudar" para continuar.' }
  Start-NextJob
}
function Remove-FromQueue([string]$id){ foreach ($j in @($Script:Jobs)) { if ($j.type -eq 'download' -and $j.id -eq $id) { $Script:Jobs.Remove($j) } }; Save-Queue; Update-QueueLabel; Update-CardStates }
function Open-QueueViewer {
  $qf = New-Object System.Windows.Forms.Form; $qf.Text = 'Cola de tareas'; $qf.StartPosition = 'CenterParent'; $qf.ClientSize = New-Object System.Drawing.Size(720,420); $qf.BackColor = $Col.Bg; $qf.ForeColor = $Col.Txt; $qf.Font = $FNorm
  $cur = New-Lbl '' $FBold $Col.Cyan; $cur.Dock = 'Top'; $cur.AutoSize = $false; $cur.Height = 30; $cur.Padding = New-Object System.Windows.Forms.Padding(10,8,0,0)
  if ($Script:CurJob) { $cur.Text = ('En curso: ' + $Script:CurJob.label) } elseif ($Script:Paused) { $cur.Text = 'Cola en pausa' } else { $cur.Text = 'Nada en curso' }
  $lb = New-Object System.Windows.Forms.ListBox; $lb.Dock = 'Fill'; $lb.BackColor = $Col.Card; $lb.ForeColor = $Col.Txt; $lb.BorderStyle = 'None'; $lb.Font = $FNorm
  $bar = New-Object System.Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 46; $bar.Padding = New-Object System.Windows.Forms.Padding(10,8,10,0); $bar.BackColor = $Col.Bg
  $bU = New-Btn 'Subir' $Col.Txt $Col.Border $false; $bD = New-Btn 'Bajar' $Col.Txt $Col.Border $false; $bF = New-Btn 'Poner primero' $Col.Cyan $Col.Cyan $false; $bX = New-Btn 'Quitar de la cola' $Col.Red $Col.Red $false
  foreach ($b in @($bU,$bD,$bF,$bX)) { $bar.Controls.Add($b) }
  $qf.Controls.Add($lb); $qf.Controls.Add($cur); $qf.Controls.Add($bar)
  $Script:QV = $lb
  $fill = { $lbx = $Script:QV; $sel = $lbx.SelectedIndex; $lbx.Items.Clear(); $i = 0; foreach ($j in $Script:Jobs) { $i++; [void]$lbx.Items.Add(('{0}. {1}' -f $i,$j.label)) }; if ($sel -ge 0 -and $sel -lt $lbx.Items.Count) { $lbx.SelectedIndex = $sel } }
  $Script:QVFill = $fill; & $fill
  $move = { param([int]$d) $i = $Script:QV.SelectedIndex; if ($i -lt 0) { return }; $k = $i + $d; if ($d -eq -999) { $k = 0 }; if ($k -lt 0 -or $k -ge $Script:Jobs.Count -or $k -eq $i) { return }; $j = $Script:Jobs[$i]; $Script:Jobs.RemoveAt($i); $Script:Jobs.Insert($k,$j); & $Script:QVFill; $Script:QV.SelectedIndex = $k; Save-Queue; Update-QueueLabel }
  $Script:QVMove = $move
  $bU.Add_Click({ & $Script:QVMove -1 }); $bD.Add_Click({ & $Script:QVMove 1 }); $bF.Add_Click({ & $Script:QVMove -999 })
  $bX.Add_Click({ $i = $Script:QV.SelectedIndex; if ($i -lt 0) { return }; $j = $Script:Jobs[$i]; $Script:Jobs.RemoveAt($i); Write-Log 'INFO' 'COLA' ('Quitado de la cola: ' + $j.label); & $Script:QVFill; Save-Queue; Update-QueueLabel; Update-CardStates; Refresh-ImgState })
  [void]$qf.ShowDialog($form)
}
function Notify([string]$title,[string]$text,[string]$kind){
  if (-not $Script:Cfg.Notify -or -not $Script:Tray) { return }
  try { $Script:Tray.BalloonTipTitle = $title; $Script:Tray.BalloonTipText = $(if ($text.Length -gt 240) { $text.Substring(0,240) + '...' } else { $text }); $Script:Tray.BalloonTipIcon = $kind; $Script:Tray.ShowBalloonTip(7000) } catch {}
}
function Resume-Pending {
  $pend = @(Load-Queue)
  $known = @{}; foreach ($j in $pend) { if ($j.type -eq 'download') { $known[[string]$j.id] = $true } }
  foreach ($d in (Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'manifest.json'))) { continue }
    $id = $null; $idf = Join-Path $d.FullName 'id.txt'
    if (Test-Path -LiteralPath $idf) { try { $id = ([IO.File]::ReadAllText($idf)).Trim() } catch {} }
    if (-not $id) { foreach ($e in $Script:Catalog) { $p = Split-ModelId $e.id; if ((('{0}-{1}-{2}' -f $p.ns,$p.name,$p.tag) -replace '[^A-Za-z0-9._-]','_') -eq $d.Name) { $id = $e.id; break } } }
    if (-not $id) { Write-Log 'WARN' 'COLA' ('Descarga a medias sin identificar en ' + $d.FullName); continue }
    if ($known.ContainsKey($id) -or $Script:Installed.ContainsKey($id)) { continue }
    $known[$id] = $true; $e = Get-Entry $id; $nm = $id; if ($e) { $nm = $e.name }
    $pend += @{ type='download'; cat='DESCARGA'; label=('Descargar {0} ({1})' -f $nm,$id); id=$id; fresh=$false; force=$false; acc='Descargar' }
  }
  foreach ($k in $ImgPacks.Keys) {
    if ((Pack-State $k).state -ne 'partial') { continue }
    $dup = $false; foreach ($j in $pend) { if ($j.type -eq 'files' -and $j.pack -eq $k) { $dup = $true } }
    if (-not $dup) { $pend += (New-PackJob $k) }
  }
  if ($pend.Count -eq 0) { return }
  $lista = ($pend | ForEach-Object { '  · ' + $_.label }) -join "`n"
  if (-not $Script:Cfg.AutoResume) {
    if (-not (MsgYes ('Hay {0} tarea(s) sin terminar de la última vez:{1}{2}{1}{1}¿Continuarlas ahora?' -f $pend.Count,"`n",$lista))) { $Script:Paused = $true }
  }
  foreach ($j in $pend) { [void]$Script:Jobs.Add($j) }
  Write-Log 'INFO' 'COLA' ('Recuperadas {0} tarea(s) pendientes de la sesión anterior.' -f $pend.Count)
  if (-not $Script:Paused) { Notify 'Reanudando descargas' ('Continuando {0} tarea(s) donde se quedaron:{1}{2}' -f $pend.Count,"`n",$lista) 'Info'; Set-Status ('Reanudando {0} tarea(s) pendientes de la última vez (lo ya descargado se conserva).' -f $pend.Count) }
  Save-Queue; Update-QueueLabel; Update-CardStates
  if ($Script:Paused) { $jobPanel.Visible = $true; $lblJobTitle.Text = ('Cola en pausa: {0} tarea(s) pendientes' -f $pend.Count); $lblJobStatus.Text = 'Pulsa "Reanudar" para continuar.' } else { Start-NextJob }
}
function Enqueue-Download([string]$id,[bool]$quiet){
  $e = Get-Entry $id
  if ($e -and -not $quiet) {
    $f = Get-Fit $e
    if (-not $f.ok) { if (-not (MsgYes ('{0} necesita unos {1} GB de memoria y NO cabe con el perfil actual ({2}).{3}{3}¿Descargarlo igualmente? (útil para exportarlo a un PC más potente)' -f $e.name,$f.need,$Script:HwEff.Label,"`n"))) { return } }
    elseif (-not $f.disk) { if (-not (MsgYes ('Puede que no haya espacio suficiente en disco ({0} GB libres). ¿Intentarlo igualmente?' -f $Script:HwDet.Disk))) { return } }
  }
  $nm = $id; if ($e) { $nm = $e.name }
  Add-Job @{ type='download'; cat='DESCARGA'; label=('Descargar {0} ({1})' -f $nm,$id); id=$id; fresh=$false; force=$false; acc='Descargar' }
  Set-Status ('En cola: ' + $nm)
}
function Start-NextJob {
  if ($Script:CurJob) { return }
  if ($Script:Paused) { Update-QueueLabel; return }
  if ($Script:Jobs.Count -eq 0) { if ($jobPanel.Visible) { $jobPanel.Visible = $false }; $form.Text = ('{0} v{1}' -f $AppName,$AppVer); Update-QueueLabel; Save-Queue; return }
  $job = $Script:Jobs[0]; $Script:Jobs.RemoveAt(0)
  if ($job.type -eq 'download' -and -not $job.force -and $Script:Installed.ContainsKey($job.id)) { Write-Log 'INFO' 'DESCARGA' ($job.id + ' ya estaba instalado; se omite.'); Start-NextJob; return }
  $Script:CurJob = $job; $Script:JobStart = Get-Date; $Script:Flags.Cancel = $false
  if (-not $jobPanel.Visible) { $jobPanel.Visible = $true }
  $lblJobTitle.Text = $job.label; $lblJobStatus.Text = 'Preparando...'; $lblJobStatus.ForeColor = $Col.Cyan; $lblJobDetail.Text = ''; Set-Bar 0
  Update-QueueLabel
  $bundle = @{ Q=$Script:MsgQ; F=$Script:Flags; Job=$job; Shared=$SharedText; Models=$Script:Models; Base=$Base; Staging=(Get-Staging); Registry=$Script:Registry; Curl=$CurlPath
    Wait=[int]$Script:Cfg.WaitSec; Self=$env:SELF; UserCat=$UserCatFile; InstDir=$InstDir; Ollama=$Script:OllamaExe; CurlX=@($Script:CurlX); XtraStr=(Get-XtraStr) }
  $w = Start-Worker $JobCode $bundle; $Script:JobPs = $w.Ps; $Script:JobAsync = $w.Async
  $Script:LastPct = -1; Save-Queue
  Write-Log 'INFO' $job.cat ('Inicio: ' + $job.label)
  if ($job.type -eq 'download') { Update-CardStates }
}
function Finish-Job([string]$st){
  try { [void]$Script:JobPs.EndInvoke($Script:JobAsync) } catch {}
  try { $Script:JobPs.Runspace.Close(); $Script:JobPs.Dispose() } catch {}
  $job = $Script:CurJob; $secs = ((Get-Date) - $Script:JobStart).TotalSeconds
  $Script:JobPs = $null; $Script:JobAsync = $null; $Script:CurJob = $null
  $kind = 'error'; $bytes = 0.0; $msg = ''
  if ($st -like 'ok*') { $kind = 'ok'; try { $bytes = [double]($st.Split(':')[1]) } catch {} }
  elseif ($st -eq 'cancel') { $kind = 'cancel' }
  else { $msg = $st -replace '^error:','' }
  $form.Text = ('{0} v{1}' -f $AppName,$AppVer)
  if ($kind -eq 'cancel' -and $Script:PausePending) {
    $Script:PausePending = $false; $Script:Paused = $true; $Script:Jobs.Insert(0,$job); $job.fresh = $false
    Write-Log 'INFO' $job.cat ('En pausa: ' + $job.label); Set-Status ('En pausa: {0}. Pulsa "Reanudar" para continuar donde se quedó.' -f $job.label)
    $lblJobTitle.Text = ('En pausa: ' + $job.label); $lblJobStatus.Text = 'Lo descargado se conserva.'; $lblJobStatus.ForeColor = $Col.Amber
    Save-Queue; Update-QueueLabel; Update-CardStates; Refresh-ImgState; return
  }
  if ($Script:PausePending) { $Script:PausePending = $false; $Script:Paused = $true; Set-Status 'Cola en pausa (la tarea terminó antes de poder pausarla).' }
  if ($PersistTypes -contains $job.type -and $job.type -ne 'export' -and $job.type -ne 'copytree') {
    if ($kind -eq 'ok') { Notify 'Completado' ($job.label) 'Info' } elseif ($kind -eq 'error') { Notify 'Error' ($job.label + ': ' + $msg) 'Error' }
  }
  switch ($kind) {
    'ok' { Write-Log 'INFO' $job.cat ('Completado: {0} ({1})' -f $job.label,(Fmt-Dur $secs)); Set-Status ('Completado: ' + $job.label) }
    'cancel' { Write-Log 'WARN' $job.cat ('Cancelado: ' + $job.label); Set-Status ('Cancelado: {0}. Lo ya transferido se conserva y se reanudará.' -f $job.label) }
    default { Write-Log 'ERROR' $job.cat ('Error en {0}: {1}' -f $job.label,$msg); Set-Status ('ERROR: ' + $msg); $lblJobStatus.ForeColor = $Col.Red; $lblJobStatus.Text = $msg }
  }
  $resTxt = 'OK'; if ($kind -eq 'cancel') { $resTxt = 'Cancelado' } elseif ($kind -eq 'error') { $resTxt = 'Error' }
  switch ($job.type) {
    'download'  { Add-History $job.acc $job.id $resTxt $bytes $secs $msg }
    'installer' { Add-History 'Instalador' 'OllamaSetup.exe' $resTxt $bytes $secs $msg; Update-InstallerLabel }
    'files'     { Add-History 'Imagen: descarga' $job.id $resTxt $bytes $secs $msg; Refresh-ImgState }
    'engine'    { Add-History 'Imagen: motor' $job.variant $resTxt $bytes $secs $msg; Refresh-ImgState }
    'copytree'  { Add-History $job.acc $job.id $resTxt $bytes $secs $msg; Refresh-ImgState }
    'gguf'      { Add-History 'GGUF' $job.id $resTxt $bytes $secs ($job.file + ' ' + $msg) }
    'export'    { if ($kind -ne 'ok') { Add-History 'Exportar' ('{0} modelo(s)' -f @($job.ids).Count) $resTxt 0 $secs $msg } }
    'import'    { if ($kind -ne 'ok') { Add-History 'Importar' ('{0} modelo(s)' -f @($job.ids).Count) $resTxt 0 $secs $msg }; Read-Repo }
    'check'     { Save-VerSizes; Build-Catalog; $Script:FitCache = @{}; ApplyFilters; Update-HwSummary
                  $nNet = @($Script:CheckState.Values | Where-Object { $_ -eq '000' }).Count
                  if ($kind -eq 'ok' -and $nNet -ge $Script:CheckState.Count) { MsgWarn 'Sin conexión con el registro de Ollama: no se pudo verificar el catálogo.'; $Script:CheckState = @{}; ApplyFilters }
                  elseif ($kind -eq 'ok') { $bad = @($Script:CheckState.Keys | Where-Object { $Script:CheckState[$_] -ne '200' }); if ($bad.Count -gt 0) { MsgWarn ('Verificación terminada. No disponibles ({0}):{1}{2}{1}{1}Si el código es 000 era un problema de red.' -f $bad.Count,"`n",(($bad | ForEach-Object { $_ + ' (' + $Script:CheckState[$_] + ')' }) -join "`n")) } else { MsgInfo 'Verificación terminada: todos los modelos del catálogo están disponibles. Tamaños actualizados con los reales.' } } }
    'verify'    { $bad = @($Script:VerifyBad.Keys | Where-Object { @($Script:VerifyBad[$_]).Count -gt 0 }); if ($kind -eq 'ok' -and $bad.Count -gt 0) { if (MsgYes ('{0} modelo(s) dañados o incompletos:{1}{2}{1}{1}¿Repararlos ahora? (solo se descargan los archivos dañados)' -f $bad.Count,"`n",($bad -join "`n"))) { Repair-Models } } }
    'updates'   { $up = @($Script:UpdState.Keys | Where-Object { $Script:UpdState[$_] -like 'Actualizaci*' }); if ($kind -eq 'ok') { if ($up.Count -gt 0) { if (MsgYes ('Hay actualizaciones para {0} modelo(s):{1}{2}{1}{1}¿Actualizarlos ahora?' -f $up.Count,"`n",($up -join "`n"))) { foreach ($id in $up) { Add-Job @{ type='download'; cat='ACTUALIZAR'; label=('Actualizar ' + $id); id=$id; fresh=$true; force=$true; acc='Actualizar' } } } } else { Set-Status 'Todos los modelos consultados están al día.' } } }
  }
  if ($kind -eq 'ok' -and $job.type -eq 'download' -and $Script:Cfg.AutoRepo -and $Script:Cfg.RepoExport) {
    $e = Get-Entry $job.id; $meta = @{}; if ($e) { $meta[$job.id] = @{ name=$e.name; cat=$e.cat; uso=$e.uso } }
    Add-Job @{ type='export'; cat='EXPORTAR'; label=('Copia automática de {0} al repositorio' -f $job.id); ids=@($job.id); repo=[string]$Script:Cfg.RepoExport; verify=$false; installer=$false; app=$false; meta=$meta }
  }
  if ($job.type -in @('download','import','gguf')) {
    Refresh-Installed; Update-CardStates; if ($Script:F_HideInst) { ApplyFilters }
    if ($kind -eq 'ok' -and $job.type -eq 'download' -and -not (Get-Entry $job.id) -and $Script:Installed.ContainsKey($job.id)) { Add-UserEntry $job.id $Script:Installed[$job.id].bytes '' @() 'Personalizado'; ApplyFilters }
  }
  if ($Script:CurPage -eq 'inst') { Refresh-InstalledLV }
  if ($Script:CurPage -eq 'hw') { Update-HwSummary }
  Update-OllamaStatus
  Save-Queue
  Start-NextJob
  if (-not $Script:CurJob -and $Script:Jobs.Count -eq 0 -and $kind -eq 'ok' -and $PersistTypes -contains $job.type) { Notify 'Cola terminada' 'Todas las descargas y tareas han terminado.' 'Info' }
  if (-not $Script:CurJob -and $kind -eq 'error') { $jobPanel.Visible = $true; $lblJobTitle.Text = ('Falló: ' + $job.label) }
}
function Remove-Models($ids){
  if (Is-Busy) { MsgWarn 'Espera a que termine la tarea en curso antes de quitar modelos.'; return }
  $ids = @($ids); if ($ids.Count -eq 0) { return }
  if (-not (MsgYes ('¿Quitar de Ollama?{0}{1}{0}{0}Consejo: expórtalos antes al repositorio offline si quieres conservarlos.' -f "`n",($ids -join "`n")))) { return }
  foreach ($id in $ids) {
    try {
      $p = Split-ModelId $id; $mp = Get-LocalManifestPath $Script:Models $p
      if (Test-Path -LiteralPath $mp) { $b = 0.0; if ($Script:Installed.ContainsKey($id)) { $b = $Script:Installed[$id].bytes }; Remove-Item -LiteralPath $mp -Force; Write-Log 'INFO' 'QUITAR' ($id + ' eliminado.'); Add-History 'Quitar' $id 'OK' $b 0 '' }
    } catch { Write-Log 'ERROR' 'QUITAR' ('{0}: {1}' -f $id,$_.Exception.Message) }
  }
  Clean-Orphans $false
  Refresh-Installed; Refresh-InstalledLV; Update-CardStates; if ($Script:F_HideInst) { ApplyFilters }; Set-Status ('{0} modelo(s) quitados.' -f $ids.Count)
}
function Clean-Orphans([bool]$ask){
  if (Is-Busy) { MsgWarn 'Espera a que terminen las tareas en curso.'; return }
  $keep = @{}
  foreach ($m in (Get-ManifestMap $Script:Models).Values) { foreach ($d in $m.digests) { $keep[$d] = $true } }
  $blobDir = Join-Path $Script:Models 'blobs'; if (-not (Test-Path -LiteralPath $blobDir)) { return }
  $orph = @(); [double]$sz = 0; $lim = (Get-Date).AddMinutes(-15)
  foreach ($bf in (Get-ChildItem -LiteralPath $blobDir -File -Force -ErrorAction SilentlyContinue)) {
    if ($bf.Name -notmatch '^sha256-[0-9a-f]{64}$') { continue }
    if ($bf.LastWriteTime -gt $lim) { continue }
    if (-not $keep.ContainsKey('sha256:' + $bf.Name.Substring(7))) { $orph += $bf; $sz += $bf.Length }
  }
  if ($orph.Count -eq 0) { if ($ask) { MsgInfo 'No hay archivos huérfanos.' }; return }
  if ($ask -and -not (MsgYes ('Hay {0} archivo(s) que ningún modelo usa ({1}). ¿Borrarlos?' -f $orph.Count,(Human $sz)))) { return }
  foreach ($bf in $orph) { try { Remove-Item -LiteralPath $bf.FullName -Force } catch {} }
  Write-Log 'INFO' 'MANTENIMIENTO' ('Huérfanos borrados: {0} archivo(s), {1}' -f $orph.Count,(Human $sz))
  if ($ask) { Add-History 'Mantenimiento' '(huérfanos)' 'OK' $sz 0 ('{0} archivos' -f $orph.Count) }
}
function Update-Models {
  $ids = @(Get-Target $lvInst)
  if ($ids.Count -eq 0) { $ids = @($Script:UpdState.Keys | Where-Object { $Script:UpdState[$_] -like 'Actualizaci*' }) }
  if ($ids.Count -eq 0) { MsgInfo 'Marca modelos o pulsa antes "Buscar actualizaciones".'; return }
  foreach ($id in $ids) { Add-Job @{ type='download'; cat='ACTUALIZAR'; label=('Actualizar ' + $id); id=$id; fresh=$true; force=$true; acc='Actualizar' } }
}
function Repair-Models {
  if (Is-Busy) { MsgWarn 'Espera a que termine la tarea en curso.'; return }
  $ids = @($Script:VerifyBad.Keys | Where-Object { @($Script:VerifyBad[$_]).Count -gt 0 })
  if ($ids.Count -eq 0) { MsgInfo 'No hay modelos marcados como dañados. Ejecuta primero una verificación.'; return }
  foreach ($id in $ids) {
    foreach ($d in @($Script:VerifyBad[$id])) { $f = Join-Path (Join-Path $Script:Models 'blobs') ('sha256-' + $d.Split(':')[1]); try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } } catch {} }
    $Script:VerifyBad[$id] = @(); $Script:VerifyState[$id] = 'Reparando...'
    Add-Job @{ type='download'; cat='REPARAR'; label=('Reparar ' + $id); id=$id; fresh=$false; force=$true; acc='Reparar' }
  }
  Refresh-InstalledLV
}
function Add-UserEntry([string]$id,[double]$bytes,[string]$uso,$caps,[string]$cat){
  if ($Script:CatMap.ContainsKey($id)) { return }
  $e = @{ id=$id; cat=$cat; name=$id; kind='Añadido por ti'; p=1; act=1; gb=[Math]::Round($bytes/1GB,2); caps=@($caps); rec=$false; uso=$uso; fuerte=''; user=$true; verified=($bytes -gt 0) }
  [void]$Script:Catalog.Add($e); $Script:CatMap[$id] = $e; Save-UserCatalog
  if ($bytes -gt 0) { $Script:VerSizes[$id] = $bytes; Save-VerSizes }
}
function Curl-Text([string]$url,[int]$timeout){
  $tmp = [IO.Path]::GetTempFileName()
  try { $code = [string](& $CurlPath @CurlX -s -L --connect-timeout 10 --max-time $timeout -o $tmp -w '%{http_code}' $url); if ($code -eq '200') { return [IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8) }; return $null }
  catch { return $null } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
function Get-RemoteSize([string]$id){
  $tmp = Join-Path $Base ('sz-' + [Guid]::NewGuid().ToString('N') + '.json'); [double]$sz = -1
  try { $code = Get-RegistryManifest $CurlPath $Script:Registry $id $tmp; if ($code -eq '200') { $sz = 0; foreach ($b in @(Get-ManifestBlobs (Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json))) { $sz += $b.size } } elseif ($code -eq '404') { $sz = -404 } } catch {}
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  return $sz
}
function Download-ById {
  $id = [Microsoft.VisualBasic.Interaction]::InputBox("ID del modelo tal como aparece en ollama.com`n`nEjemplos:  qwen3:8b   gemma4:e4b   llama3.2   usuario/modelo:tag`nTambién Hugging Face: hf.co/usuario/repositorio:Q4_K_M (experimental)",'Descargar por ID','')
  if (-not $id) { return }; $id = $id.Trim(); if ($id -notmatch ':') { $id = $id + ':latest' }
  if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._\-/]*:[A-Za-z0-9._\-]+$') { MsgWarn 'ID no válido.'; return }
  [System.Windows.Forms.Cursor]::Current = 'WaitCursor'; Set-Status ('Consultando ' + $id + '...')
  $sz = Get-RemoteSize $id
  if ($sz -eq -404) { MsgWarn ('{0} no existe en el registro.' -f $id); return }
  if ($sz -gt 0) { Add-UserEntry $id $sz '' @() 'Personalizado'; $Script:FitCache = @{}; ApplyFilters; Set-Status ('{0}: {1}' -f $id,(Human $sz)) }
  elseif ($sz -lt 0) { if (-not (MsgYes 'No se pudo consultar el registro (¿sin internet?). ¿Poner en cola igualmente? Se reintentará hasta que haya conexión.')) { return } }
  Enqueue-Download $id $false
}

# ---------- Ventana: info del modelo ----------
function Open-Info([string]$id){
  $e = Get-Entry $id; if (-not $e) { return }; $f = Get-Fit $e; $nl = [Environment]::NewLine
  $df = New-Object System.Windows.Forms.Form; $df.Text = $e.name; $df.StartPosition = 'CenterParent'; $df.ClientSize = New-Object System.Drawing.Size(640,500); $df.BackColor = $Col.Bg; $df.ForeColor = $Col.Txt; $df.Font = $FNorm
  $rt = New-Object System.Windows.Forms.RichTextBox; $rt.Dock = 'Fill'; $rt.ReadOnly = $true; $rt.BackColor = $Col.Panel; $rt.ForeColor = $Col.Txt; $rt.BorderStyle = 'None'; $rt.Font = $FNorm
  $caps = (@($e.caps) | ForEach-Object { if ($CapNames.ContainsKey($_)) { $CapNames[$_] } else { $_ } }) -join ', '
  $inst = 'No'; if ($Script:Installed.ContainsKey($id)) { $inst = ('Sí ({0})' -f $Script:Installed[$id].date.ToString('yyyy-MM-dd')) }
  $bench = ''; if ($Script:Cfg.Bench.ContainsKey($id)) { $bench = ('{0}Velocidad medida: {1:N1} tok/s' -f $nl,$Script:Cfg.Bench[$id]) }
  $rt.Text = ('{0}{1}ID: {2}{1}Categoría: {3}   ·   Tipo: {4}{1}Parámetros: {5}B (activos por token: {6}B){1}Descarga: {7} {8}{1}Capacidades: {9}{1}{1}PARA QUÉ SIRVE{1}{10}{1}{1}FORTALEZA{1}{11}{1}{1}CON TU PERFIL ({12}){1}Modo: {13}{1}Memoria necesaria aprox.: {14} GB{1}Velocidad estimada: {15} tok/s ({16}){17}{1}{1}Instalado: {18}{1}{1}USO DESDE CONSOLA{1}ollama run {2}{1}{1}API local: http://127.0.0.1:11434  (compatible con OpenAI en /v1)' -f $e.name,$nl,$e.id,$e.cat,$e.kind,$e.p,$e.act,(Human ($e.gb * 1GB)),$(if ($e.verified) { '(verificado)' } else { '(aprox.)' }),$caps,$e.uso,$e.fuerte,$Script:HwEff.Label,$ModeTxt[$f.mode],$f.need,$f.tps,$f.speed,$bench,$inst)
  $bar = New-Object System.Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 44; $bar.Padding = New-Object System.Windows.Forms.Padding(10,8,10,0); $bar.BackColor = $Col.Bg
  $b1 = New-Btn 'Copiar comando' $Col.Txt $Col.Border $false; $b1.Tag = $id; $b1.Add_Click({ param($s,$ev) [System.Windows.Forms.Clipboard]::SetText(('ollama run {0}' -f $s.Tag)); Set-Status 'Comando copiado.' }); $bar.Controls.Add($b1)
  $b2 = New-Btn 'Ver en ollama.com' $Col.Cyan $Col.Cyan $false; $b2.Tag = $id; $b2.Add_Click({ param($s,$ev) $p = Split-ModelId ([string]$s.Tag); if ($p.host -eq 'registry.ollama.ai') { $u = 'https://ollama.com/library/' + $p.name; if ($p.ns -ne 'library') { $u = ('https://ollama.com/{0}/{1}' -f $p.ns,$p.name) }; Start-Process $u } }); $bar.Controls.Add($b2)
  if ($Script:Installed.ContainsKey($id)) {
    $b3 = New-Btn 'Abrir en terminal' $Col.Green $Col.Green $false; $b3.Tag = $id; $b3.Add_Click({ param($s,$ev) if ($Script:OllamaExe) { Start-Process cmd.exe -ArgumentList ('/k "{0}" run {1}' -f $Script:OllamaExe,$s.Tag) } }); $bar.Controls.Add($b3)
  } elseif ($e.user) {
    $b4 = New-Btn 'Quitar del catálogo' $Col.Red $Col.Red $false; $b4.Tag = $id; $b4.Add_Click({ param($s,$ev) $x = Get-Entry ([string]$s.Tag); if ($x) { [void]$Script:Catalog.Remove($x); $Script:CatMap.Remove([string]$s.Tag); Save-UserCatalog; ApplyFilters; $s.FindForm().Close() } }); $bar.Controls.Add($b4)
  }
  $df.Controls.Add($rt); $df.Controls.Add($bar)
  [void]$df.ShowDialog($form)
}

# ---------- Ventana: explorador de ollama.com ----------
function Open-Explorer([string]$pre) {
  [System.Windows.Forms.Cursor]::Current = 'WaitCursor'; Set-Status 'Consultando ollama.com/library...'
  $html = Curl-Text 'https://ollama.com/library' 30
  if (-not $html) { MsgWarn 'No se pudo conectar con ollama.com. Comprueba tu conexión.'; return }
  $names = New-Object System.Collections.ArrayList; $seen = @{}
  foreach ($m in [regex]::Matches($html,'href="/library/([A-Za-z0-9._\-]+)"')) { $n = $m.Groups[1].Value; if (-not $seen.ContainsKey($n)) { $seen[$n] = $true; [void]$names.Add($n) } }
  if ($pre -and -not $seen.ContainsKey($pre)) { [void]$names.Insert(0,$pre) }
  Set-Status ('ollama.com: {0} familias de modelos' -f $names.Count)
  $xf = New-Object System.Windows.Forms.Form; $xf.Text = 'Explorar todos los modelos de ollama.com'; $xf.StartPosition = 'CenterParent'; $xf.ClientSize = New-Object System.Drawing.Size(980,620); $xf.BackColor = $Col.Bg; $xf.ForeColor = $Col.Txt; $xf.Font = $FNorm
  $Script:XNames = $names
  $lp = New-Object System.Windows.Forms.Panel; $lp.Dock = 'Left'; $lp.Width = 280; $lp.Padding = New-Object System.Windows.Forms.Padding(10)
  $xs = New-Txt 256 ''; $xs.Dock = 'Top'
  $lbN = New-Object System.Windows.Forms.ListBox; $lbN.Dock = 'Fill'; $lbN.BackColor = $Col.Card; $lbN.ForeColor = $Col.Txt; $lbN.BorderStyle = 'None'; $lbN.Font = $FNorm
  foreach ($n in $names) { [void]$lbN.Items.Add($n) }
  $lp.Controls.Add($lbN); $lp.Controls.Add($xs)
  $mp = New-Object System.Windows.Forms.Panel; $mp.Dock = 'Left'; $mp.Width = 290; $mp.Padding = New-Object System.Windows.Forms.Padding(0,10,10,10)
  $chkAll = New-Chk 'Mostrar variantes especiales (mlx, bf16, fp8...)' $false; $chkAll.Dock = 'Top'
  $lbT = New-Object System.Windows.Forms.ListBox; $lbT.Dock = 'Fill'; $lbT.BackColor = $Col.Card; $lbT.ForeColor = $Col.Txt; $lbT.BorderStyle = 'None'; $lbT.Font = $FMono
  $mp.Controls.Add($lbT); $mp.Controls.Add($chkAll)
  $rp = New-Object System.Windows.Forms.FlowLayoutPanel; $rp.Dock = 'Fill'; $rp.FlowDirection = 'TopDown'; $rp.WrapContents = $false; $rp.Padding = New-Object System.Windows.Forms.Padding(4,10,10,10); $rp.AutoScroll = $true
  $lD = New-Lbl 'Elige un modelo a la izquierda.' $FSm $Col.Sub; $lD.MaximumSize = New-Object System.Drawing.Size(370,0); $rp.Controls.Add($lD)
  $lSz = New-Lbl '' $FBold $Col.Cyan; $rp.Controls.Add($lSz)
  $rp.Controls.Add((New-Lbl 'Categoría:' $FSm $Col.Txt))
  $cbCat = New-Object System.Windows.Forms.ComboBox; $cbCat.DropDownStyle = 'DropDownList'; $cbCat.Width = 250; $cbCat.BackColor = $Col.Card; $cbCat.ForeColor = $Col.Txt
  foreach ($c in @('General','Vision','Codigo','Razonamiento','Embeddings','Especializado')) { [void]$cbCat.Items.Add($c) }; $cbCat.SelectedIndex = 0; $rp.Controls.Add($cbCat)
  $rp.Controls.Add((New-Lbl 'Capacidades:' $FSm $Col.Txt))
  $clb = New-Object System.Windows.Forms.CheckedListBox; $clb.Width = 250; $clb.Height = 150; $clb.BackColor = $Col.Card; $clb.ForeColor = $Col.Txt; $clb.BorderStyle = 'None'; $clb.CheckOnClick = $true
  foreach ($k in @('Chat','Codigo','Vision','Video','Audio','OCR','Razonamiento','Herramientas','Embeddings','Multilingue')) { [void]$clb.Items.Add($k) }; $rp.Controls.Add($clb)
  $rp.Controls.Add((New-Lbl 'Para qué sirve (tu nota):' $FSm $Col.Txt))
  $tU = New-Txt 360 ''; $tU.Multiline = $true; $tU.Height = 54; $rp.Controls.Add($tU)
  $bAdd = New-Btn 'Añadir al catálogo' $Col.Txt $Col.Border $false; $rp.Controls.Add($bAdd)
  $bAddDl = New-Btn 'Añadir y descargar' $Col.White $Col.Acc $true; $rp.Controls.Add($bAddDl)
  $xf.Controls.Add($rp); $xf.Controls.Add($mp); $xf.Controls.Add($lp)
  $Script:XState = @{ name=''; tags=@(); desc=''; size=0; lbT=$lbT; lbN=$lbN; lD=$lD; lSz=$lSz; chkAll=$chkAll; cbCat=$cbCat; clb=$clb; tU=$tU; form=$xf }
  $xs.Add_TextChanged({ param($s,$ev) $q = $s.Text.Trim().ToLower(); $Script:XState.lbN.BeginUpdate(); $Script:XState.lbN.Items.Clear(); foreach ($n in $Script:XNames) { if (-not $q -or $n.ToLower().Contains($q)) { [void]$Script:XState.lbN.Items.Add($n) } }; $Script:XState.lbN.EndUpdate() })
  $fillTags = {
    $x = $Script:XState; $x.lbT.BeginUpdate(); $x.lbT.Items.Clear()
    foreach ($t in $x.tags) { if ($x.chkAll.Checked -or $t -notmatch '(mlx|nvfp4|mxfp8|cloud|bf16|fp16|int4|int8)') { [void]$x.lbT.Items.Add($x.name + ':' + $t) } }
    $x.lbT.EndUpdate()
  }
  $Script:XFill = $fillTags
  $lbN.Add_SelectedIndexChanged({
    $x = $Script:XState; if ($x.lbN.SelectedIndex -lt 0) { return }
    $n = [string]$x.lbN.SelectedItem; $x.name = $n; $x.lD.Text = 'Cargando etiquetas...'; $x.lSz.Text = ''; $x.form.Refresh()
    [System.Windows.Forms.Cursor]::Current = 'WaitCursor'
    $pg = $n; $pfx = $n; if ($n -notmatch '/') { $pg = 'library/' + $n; $pfx = 'library/' + $n }
    $h = Curl-Text ('https://ollama.com/' + $pg + '/tags') 30
    $tags = New-Object System.Collections.ArrayList; $sn = @{}
    if ($h) {
      foreach ($m in [regex]::Matches($h,('/' + [regex]::Escape($pfx) + ':([A-Za-z0-9._\-]+)'))) { $t = $m.Groups[1].Value; if (-not $sn.ContainsKey($t)) { $sn[$t] = $true; [void]$tags.Add($t) } }
      $dm = [regex]::Match($h,'<meta name="description" content="([^"]*)"'); if ($dm.Success) { $x.desc = [System.Net.WebUtility]::HtmlDecode($dm.Groups[1].Value) } else { $x.desc = '' }
    }
    if ($tags.Count -eq 0) { [void]$tags.Add('latest') }
    $x.tags = @($tags); $x.lD.Text = $(if ($x.desc) { $x.desc } else { $n }); $x.tU.Text = $x.desc
    $p = $h; if (-not $p) { $p = '' }; $pl = $p.ToLower()
    for ($i = 0; $i -lt $x.clb.Items.Count; $i++) { $x.clb.SetItemChecked($i,$false) }
    if ($pl.Contains('>vision<')) { $x.clb.SetItemChecked(2,$true) }; if ($pl.Contains('>tools<')) { $x.clb.SetItemChecked(7,$true) }; if ($pl.Contains('>thinking<')) { $x.clb.SetItemChecked(6,$true) }; if ($pl.Contains('>embedding<')) { $x.clb.SetItemChecked(8,$true); $x.cbCat.SelectedIndex = 4 } else { $x.clb.SetItemChecked(0,$true) }; if ($pl.Contains('>audio<')) { $x.clb.SetItemChecked(4,$true) }
    if ($n -match 'coder|code') { $x.cbCat.SelectedIndex = 2; $x.clb.SetItemChecked(1,$true) } elseif ($pl.Contains('>vision<')) { $x.cbCat.SelectedIndex = 1 }
    & $Script:XFill
  })
  $chkAll.Add_CheckedChanged({ & $Script:XFill })
  $lbT.Add_SelectedIndexChanged({
    $x = $Script:XState; if ($x.lbT.SelectedIndex -lt 0) { return }
    $id = [string]$x.lbT.SelectedItem; $x.lSz.Text = 'Consultando tamaño...'; $x.form.Refresh(); [System.Windows.Forms.Cursor]::Current = 'WaitCursor'
    $sz = Get-RemoteSize $id; $x.size = $sz
    if ($sz -gt 0) { $e = @{ id=$id; gb=($sz/1GB); p=1; act=1; caps=@() }; $Script:FitCache.Remove($id); $f = Get-Fit $e; $Script:FitCache.Remove($id); $x.lSz.Text = ('{0}   ·   {1}   ·   {2}' -f $id,(Human $sz),$ModeTxt[$f.mode]); $x.lSz.ForeColor = $ModeCol[$f.mode] }
    else { $x.lSz.Text = ('{0}: no disponible ({1})' -f $id,$sz); $x.lSz.ForeColor = $Col.Red }
  })
  $addAction = {
    param([bool]$dl)
    $x = $Script:XState; if ($x.lbT.SelectedIndex -lt 0) { MsgInfo 'Elige una etiqueta (versión) en la lista central.'; return }
    $id = [string]$x.lbT.SelectedItem; $caps = @(); foreach ($c in $x.clb.CheckedItems) { $caps += [string]$c }
    if (-not $Script:CatMap.ContainsKey($id)) { $sz = [double]$x.size; if ($sz -lt 0) { $sz = 0 }; Add-UserEntry $id $sz $x.tU.Text.Trim() $caps ([string]$x.cbCat.SelectedItem); $ne = Get-Entry $id; if ($ne) { $ne.name = $id; $ne.kind = 'Añadido desde ollama.com' }; Save-UserCatalog; Write-Log 'INFO' 'CATALOGO' ('Añadido al catálogo: ' + $id) }
    $Script:FitCache = @{}; ApplyFilters
    if ($dl) { Enqueue-Download $id $false } else { Set-Status ('Añadido al catálogo: ' + $id) }
  }
  $Script:XAdd = $addAction
  $bAdd.Add_Click({ & $Script:XAdd $false })
  $bAddDl.Add_Click({ & $Script:XAdd $true })
  $Script:XPre = $pre
  if ($pre) { $xf.Add_Shown({ $x = $Script:XState; $i = $x.lbN.Items.IndexOf($Script:XPre); if ($i -ge 0) { $x.lbN.SelectedIndex = $i } }) }
  [void]$xf.ShowDialog($form)
}

# ---------- Ventana: chat de prueba ----------
function Rtb-Append([string]$t,[System.Drawing.Color]$c){ $r = $Script:ChatRtb; $r.SelectionStart = $r.TextLength; $r.SelectionLength = 0; $r.SelectionColor = $c; $r.AppendText($t); $r.SelectionColor = $r.ForeColor; $r.ScrollToCaret() }
function Send-Chat([string]$text){
  if ($Script:ChatBusy -or -not $text) { return }
  $msg = @{ role='user'; content=$text }; if ($Script:ChatImg) { $msg.images = @($Script:ChatImg) }
  [void]$Script:ChatHist.Add($msg)
  Rtb-Append ([Environment]::NewLine + 'Tú: ') $Col.Cyan; Rtb-Append ($text + [Environment]::NewLine) $Col.Txt
  if ($Script:ChatImg) { Rtb-Append ('[imagen adjunta: ' + $Script:ChatImgName + ']' + [Environment]::NewLine) $Col.Amber }
  Rtb-Append ($Script:ChatModel + ': ') $Col.Green
  $Script:ChatImg = $null; $Script:ChatLblImg.Text = ''; $Script:ChatAcc = ''; $Script:ChatThinking = $false
  $Script:ChatQ.Clear(); $Script:ChatF.Stop = $false; $Script:ChatBusy = $true; $Script:ChatSend.Enabled = $false; $Script:ChatStat.Text = 'Generando... (la primera respuesta tarda más: se carga el modelo)'
  $bundle = @{ Q=$Script:ChatQ; F=$Script:ChatF; Model=$Script:ChatModel; Messages=@($Script:ChatHist.ToArray()) }
  $w = Start-Worker $ChatCode $bundle; $Script:ChatPs = $w.Ps; $Script:ChatAsync = $w.Async
}
function Open-Chat([string]$id){
  if (-not (Test-OllamaApi)) { MsgWarn 'El servicio de Ollama no está activo. Pulsa "Iniciar Ollama" (arriba a la derecha) y espera unos segundos.'; return }
  $Script:ChatModel = $id; $Script:ChatHist = New-Object System.Collections.ArrayList; $Script:ChatImg = $null; $Script:ChatBusy = $false; $Script:ChatBench = $false
  $cf = New-Object System.Windows.Forms.Form; $cf.Text = ('Probar ' + $id); $cf.StartPosition = 'CenterParent'; $cf.ClientSize = New-Object System.Drawing.Size(860,640); $cf.MinimumSize = New-Object System.Drawing.Size(600,420); $cf.BackColor = $Col.Bg; $cf.ForeColor = $Col.Txt; $cf.Font = $FNorm
  $top = New-Object System.Windows.Forms.FlowLayoutPanel; $top.Dock = 'Top'; $top.Height = 44; $top.Padding = New-Object System.Windows.Forms.Padding(10,8,10,0); $top.BackColor = $Col.Panel
  $bN = New-Btn 'Nueva conversación' $Col.Txt $Col.Border $false; $top.Controls.Add($bN)
  $bI = New-Btn 'Adjuntar imagen...' $Col.Amber $Col.Amber $false; $top.Controls.Add($bI)
  $bB = New-Btn 'Medir velocidad (benchmark)' $Col.Cyan $Col.Cyan $false; $top.Controls.Add($bB)
  $bS = New-Btn 'Detener' $Col.Red $Col.Red $false; $top.Controls.Add($bS)
  $lImg = New-Lbl '' $FSm $Col.Amber; $top.Controls.Add($lImg)
  $rtb = New-Object System.Windows.Forms.RichTextBox; $rtb.Dock = 'Fill'; $rtb.ReadOnly = $true; $rtb.BackColor = $Col.Panel; $rtb.ForeColor = $Col.Txt; $rtb.BorderStyle = 'None'; $rtb.Font = $FNorm
  $bot = New-Object System.Windows.Forms.Panel; $bot.Dock = 'Bottom'; $bot.Height = 86; $bot.Padding = New-Object System.Windows.Forms.Padding(10,8,10,8); $bot.BackColor = $Col.Bg
  $tin = New-Object System.Windows.Forms.TextBox; $tin.Multiline = $true; $tin.Dock = 'Fill'; $tin.BackColor = $Col.Card; $tin.ForeColor = $Col.Txt; $tin.BorderStyle = 'FixedSingle'; $tin.Font = $FNorm; $tin.ScrollBars = 'Vertical'
  $bSend = New-Object System.Windows.Forms.Button; $bSend.Text = 'Enviar'; $bSend.Dock = 'Right'; $bSend.Width = 110; $bSend.FlatStyle = 'Flat'; $bSend.FlatAppearance.BorderSize = 0; $bSend.BackColor = $Col.Acc; $bSend.ForeColor = $Col.White; $bSend.Font = $FBold
  $bot.Controls.Add($tin); $bot.Controls.Add($bSend)
  $stat = New-Object System.Windows.Forms.Label; $stat.Dock = 'Bottom'; $stat.Height = 22; $stat.ForeColor = $Col.Sub; $stat.Font = $FSm; $stat.Padding = New-Object System.Windows.Forms.Padding(10,0,0,0); $stat.Text = 'Enter = enviar  ·  Shift+Enter = nueva línea'
  $cf.Controls.Add($rtb); $cf.Controls.Add($top); $cf.Controls.Add($stat); $cf.Controls.Add($bot)
  $Script:ChatRtb = $rtb; $Script:ChatIn = $tin; $Script:ChatSend = $bSend; $Script:ChatStat = $stat; $Script:ChatLblImg = $lImg
  Rtb-Append ('Modelo: ' + $id + '   ·   API local de Ollama (sin internet)' + [Environment]::NewLine) $Col.Sub
  $bSend.Add_Click({ $t = $Script:ChatIn.Text.Trim(); if ($t) { $Script:ChatIn.Clear(); $Script:ChatBench = $false; Send-Chat $t } })
  $tin.Add_KeyDown({ param($s,$ev) if ($ev.KeyCode -eq 'Return' -and -not $ev.Shift) { $ev.SuppressKeyPress = $true; $Script:ChatSend.PerformClick() } })
  $bN.Add_Click({ if ($Script:ChatBusy) { return }; $Script:ChatHist.Clear(); $Script:ChatRtb.Clear(); Rtb-Append ('Nueva conversación con ' + $Script:ChatModel + [Environment]::NewLine) $Col.Sub })
  $bI.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Imágenes|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif'
    if ($d.ShowDialog() -eq 'OK') { $fi = Get-Item -LiteralPath $d.FileName; if ($fi.Length -gt 20MB) { MsgWarn 'La imagen es demasiado grande (máx. 20 MB).'; return }; $Script:ChatImg = [Convert]::ToBase64String([IO.File]::ReadAllBytes($d.FileName)); $Script:ChatImgName = $fi.Name; $Script:ChatLblImg.Text = ('Imagen: ' + $fi.Name + ' (solo modelos con Visión)') } })
  $bB.Add_Click({ if ($Script:ChatBusy) { return }; $Script:ChatHist.Clear(); $Script:ChatBench = $true; Rtb-Append ([Environment]::NewLine + '--- BENCHMARK ---') $Col.Amber; Send-Chat 'Escribe un texto de unas 200 palabras explicando cómo funciona una radio AM. No uses listas.' })
  $bS.Add_Click({ $Script:ChatF.Stop = $true })
  $Script:ChatTimer = New-Object System.Windows.Forms.Timer; $Script:ChatTimer.Interval = 120
  $Script:ChatTimer.Add_Tick({
    try {
      while ($Script:ChatQ.Count -gt 0) {
        $m = $Script:ChatQ[0]; $Script:ChatQ.RemoveAt(0)
        switch ($m.t) {
          'think' { if (-not $Script:ChatThinking) { $Script:ChatThinking = $true; Rtb-Append ('[pensando] ') $Col.Purple }; Rtb-Append $m.text $Col.Sub }
          'tok' { if ($Script:ChatThinking) { $Script:ChatThinking = $false; Rtb-Append ([Environment]::NewLine) $Col.Txt }; $Script:ChatAcc += $m.text; Rtb-Append $m.text $Col.Txt }
          'err' { Rtb-Append (' [ERROR: ' + $m.text + ']') $Col.Red }
          'end' {
            $Script:ChatStat.Text = ('{0:N1} tok/s  ·  {1} tokens  ·  carga del modelo {2:N1} s' -f $m.tps,$m.n,$m.load)
            if ($Script:ChatBench -and $m.tps -gt 0) {
              $Script:Cfg.Bench[$Script:ChatModel] = [Math]::Round($m.tps,1); Save-Config
              Add-History 'Benchmark' $Script:ChatModel 'OK' 0 0 ('{0:N1} tok/s ({1} tokens)' -f $m.tps,$m.n)
              Write-Log 'INFO' 'BENCHMARK' ('{0}: {1:N1} tok/s' -f $Script:ChatModel,$m.tps)
              Rtb-Append ([Environment]::NewLine + ('Resultado: {0:N1} tokens/segundo (guardado)' -f $m.tps) + [Environment]::NewLine) $Col.Amber
              $Script:FitCache = @{}
            }
          }
          'fin' {
            if ($Script:ChatAcc) { [void]$Script:ChatHist.Add(@{ role='assistant'; content=$Script:ChatAcc }) }
            Rtb-Append ([Environment]::NewLine) $Col.Txt
            $Script:ChatBusy = $false; $Script:ChatSend.Enabled = $true
            try { [void]$Script:ChatPs.EndInvoke($Script:ChatAsync) } catch {}; try { $Script:ChatPs.Runspace.Close(); $Script:ChatPs.Dispose() } catch {}; $Script:ChatPs = $null
          }
        }
      }
    } catch {}
  })
  $Script:ChatTimer.Start()
  $cf.Add_FormClosed({ $Script:ChatF.Stop = $true; try { $Script:ChatTimer.Stop() } catch {}; if ($Script:ChatBench) { $Script:FitCache = @{}; ApplyFilters } })
  [void]$cf.ShowDialog($form)
}

function Update-OllamaStatus {
  $ok = Test-OllamaApi
  if ($ok) { $dotOllama.BackColor = $Col.Green; $v = ''; if ($Script:OllamaVer) { $v = ' v' + $Script:OllamaVer }; $lblOllamaStatus.Text = ('Ollama activo' + $v); $lblOllamaStatus.ForeColor = $Col.Green; $btnSrv.Text = 'Reiniciar Ollama'; if ($Script:OllamaUpd) { $lblOllamaStatus.Text += ('  ·  nueva versión ' + $Script:OllamaLatest + ' disponible'); $lblOllamaStatus.ForeColor = $Col.Amber } }
  elseif ($Script:OllamaExe) { $dotOllama.BackColor = $Col.Amber; $lblOllamaStatus.Text = 'Ollama instalado, servicio detenido'; $lblOllamaStatus.ForeColor = $Col.Amber; $btnSrv.Text = 'Iniciar Ollama' }
  else { $dotOllama.BackColor = $Col.Red; $lblOllamaStatus.Text = 'Ollama no instalado'; $lblOllamaStatus.ForeColor = $Col.Red; $btnSrv.Text = 'Instalar Ollama' }
}

# =====================================================================
#  TEMPORIZADORES Y ARRANQUE
# =====================================================================
$T = New-Object System.Windows.Forms.Timer; $T.Interval = 300
$T.Add_Tick({
  try {
    while ($Script:MsgQ.Count -gt 0) {
      $m = $Script:MsgQ[0]; $Script:MsgQ.RemoveAt(0)
      switch ($m.t) {
        'prog' {
          if ([double]$m.total -gt 0) {
            $fr = [double]$m.cur / [double]$m.total; Set-Bar $fr; $pct = [int][Math]::Floor($fr * 100)
            if ($Script:CurJob -and $pct -ne $Script:LastPct) {
              $Script:LastPct = $pct; $form.Text = ('{0}% · {1} — {2}' -f $pct,$Script:CurJob.label,$AppName)
              if ($Script:CurJob.type -eq 'download' -and $Script:CardMap.ContainsKey($Script:CurJob.id)) { try { $cb = $Script:CardMap[$Script:CurJob.id].Tag.pn.Controls[0]; if ($cb -is [System.Windows.Forms.Button]) { $cb.Text = ('Descargando {0}%' -f $pct) } } catch {} }
            }
          }
          if ($m.detail) { $lblJobDetail.Text = $m.detail } }
        'status' { $lblJobStatus.Text = $m.text; $lblJobStatus.ForeColor = $Col.Cyan }
        'log' { Write-Log $m.lvl $m.cat $m.text }
        'hist' { Add-History $m.accion $m.modelo $m.res $m.bytes 0 $m.det }
        'size' { if ($m.bytes -gt 0) { $Script:VerSizes[$m.id] = [double]$m.bytes; Save-VerSizes; $ce = Get-Entry $m.id; if ($ce) { $ce.gb = [Math]::Round($m.bytes/1GB,2); $ce.verified = $true } } }
        'verifyres' { $Script:VerifyState[$m.id] = $m.status; $Script:VerifyBad[$m.id] = @($m.bad); if ($Script:CurPage -eq 'inst') { Refresh-InstalledLV } }
        'updres' { $Script:UpdState[$m.id] = $m.status; if ($Script:CurPage -eq 'inst') { Refresh-InstalledLV } }
        'checkres' { $Script:CheckState[$m.id] = $m.code; if ($m.code -eq '200' -and [double]$m.bytes -gt 0) { $Script:VerSizes[$m.id] = [double]$m.bytes } }
        'jobdone' { Finish-Job $m.st }
      }
    }
    while ($Script:FetchQ.Count -gt 0) { $fm = $Script:FetchQ[0]; $Script:FetchQ.RemoveAt(0); Handle-FetchMsg $fm }
  } catch { Write-Log 'ERROR' 'APP' ('Error en la interfaz: ' + $_.Exception.Message) }
})
$Script:StatTimer = New-Object System.Windows.Forms.Timer; $Script:StatTimer.Interval = 15000
$Script:StatTimer.Add_Tick({ $Script:StatTimer.Interval = 15000; try { Update-OllamaStatus } catch {} })

foreach ($g in @(@('cat','Todas'),@('cap','Todas'),@('size','Todos'),@('fit','Todos'))) { Set-ChipActive $g[0] $g[1] }

$form.Add_FormClosing({ param($s,$ev)
  if ($Script:CurJob) {
    $extra = ''; if ($Script:Jobs.Count -gt 0) { $extra = (' (y {0} más en cola)' -f $Script:Jobs.Count) }
    if (-not (MsgYes ('Hay una tarea en curso: {0}{1}.{2}{2}Lo transferido se conserva y la descarga CONTINUARÁ AUTOMÁTICAMENTE la próxima vez que abras la app. ¿Cerrar ahora?' -f $Script:CurJob.label,$extra,"`n"))) { $ev.Cancel = $true; return }
    Save-Queue
    $Script:Flags.Cancel = $true; Start-Sleep -Milliseconds 800
    Write-Log 'WARN' 'APP' ('Cerrado con tarea en curso (se reanudará al abrir): ' + $Script:CurJob.label)
  } else { Save-Queue }
  try { $Script:Tray.Visible = $false; $Script:Tray.Dispose() } catch {}
  if ($Script:ImgBusy) { $Script:ImgF.Stop = $true; Start-Sleep -Milliseconds 500 }
  try { $T.Stop(); $Script:StatTimer.Stop(); $Script:ImgTimer.Stop() } catch {}
  try { if ($Script:JobPs) { $Script:JobPs.Stop() } } catch {}
  Write-Log 'INFO' 'APP' 'Aplicación cerrada.'
})

$form.Add_Shown({
  $form.Activate(); [System.Windows.Forms.Cursor]::Current = 'WaitCursor'
  Set-Status 'Detectando equipo...'; $form.Refresh()
  $Script:HwDet = Detect-Hardware
  Build-HwEff
  Refresh-Installed
  Update-OllamaStatus
  Fill-HwPage
  if ($Script:HwDet.Vendor -eq 'NVIDIA') { $cmbVariant.SelectedIndex = 1 } elseif (-not $Script:HwDet.Vendor) { $cmbVariant.SelectedIndex = 2 }
  if ($Script:HwDet.Vram -gt 10) { $chkLowVram.Checked = $false }
  Show-Page 'cat'
  if ($Script:HwDet.NeedVulkan -and -not (Vulkan-On)) {
    $q1 = ('Tu GPU ({0}) NO tiene soporte de ROCm en Windows, así que ahora mismo Ollama NO la usa: todo va por el procesador.{1}{1}La solución es activar Vulkan (OLLAMA_VULKAN=1). ¿Activarlo ahora y reiniciar Ollama?' -f $Script:HwDet.Gpu,"`n")
    if (MsgYes $q1) {
      Set-UserEnv 'OLLAMA_VULKAN' '1'; $chkVK.Checked = $true
      Write-Log 'INFO' 'AJUSTES' ('Vulkan activado para ' + $Script:HwDet.Gpu)
      Build-HwEff; Fill-HwPage
      if ($Script:OllamaExe) { Restart-Ollama }
    } else { Write-Log 'WARN' 'EQUIPO' 'Vulkan no activado: la GPU no se usará en Ollama.' }
  }
  ApplyFilters; Update-HwSummary; Update-QueueLabel; Update-InstallerLabel
  try { $split.SplitterDistance = [int]($split.Height * 0.62) } catch {}
  try { $tl = Join-Path $LogDir ('ollama-manager_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')); if (Test-Path -LiteralPath $tl) { $logBox.Text = ((Get-Content -LiteralPath $tl -Encoding UTF8 -Tail 300) -join "`r`n") + "`r`n" } } catch {}
  Write-Log 'INFO' 'APP' ('{0} v{1} iniciado. Modelos: {2}. {3}' -f $AppName,$AppVer,$Script:Models,$Script:HwEff.Label)
  $msg = ('Listo. {0} modelos en el catálogo · {1} instalados · {2}' -f $Script:Catalog.Count,$Script:Installed.Count,$Script:HwEff.Label)
  if ($Script:HwDet.Disk -gt 0 -and $Script:HwDet.Disk -lt 15) { $msg += ('  ·  ⚠ solo quedan {0} GB libres en el disco de modelos' -f $Script:HwDet.Disk) }
  Set-Status $msg
  $T.Start(); $Script:StatTimer.Start()
  Resume-Pending
  if ($Script:OllamaExe) { Start-OllamaRelCheck }
})

[void]$form.ShowDialog()
try { $Script:Tray.Visible = $false; $Script:Tray.Dispose() } catch {}
try { $Script:AppMutex.ReleaseMutex(); $Script:AppMutex.Dispose() } catch {}
try { $T.Stop() } catch {}
try { if ($Script:JobPs) { $Script:JobPs.Runspace.Close() } } catch {}
try { if ($Script:ChatPs) { $Script:ChatPs.Runspace.Close() } } catch {}
