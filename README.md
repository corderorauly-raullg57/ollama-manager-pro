# Ollama Manager Pro

**Gestor profesional de modelos de IA local para Windows**: descarga con reanudación garantizada, compatibilidad según tu hardware, repositorio offline (USB), verificación, actualizaciones, generación y edición de imágenes, y kit de programación. Todo en **un solo archivo `.bat`**, sin instalar nada.

> Pensado para conexiones lentas o inestables: si se va la luz o se cae internet, la descarga continúa donde se quedó. Al volver a abrir la app, retoma sola las tareas pendientes.

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Instalación y primer arranque](#2-instalación-y-primer-arranque)
3. [Pestaña Catálogo: buscar y descargar modelos](#3-pestaña-catálogo)
4. [La cola de descargas: pausar, reanudar, ordenar](#4-la-cola-de-descargas)
5. [Pestaña Imagen: generar y editar imágenes](#5-pestaña-imagen)
6. [Pestaña Instalados: verificar, actualizar, reparar](#6-pestaña-instalados)
7. [Pestaña Offline: exportar e importar (USB)](#7-pestaña-offline)
8. [Pestaña Mi equipo: compatibilidad](#8-pestaña-mi-equipo)
9. [Pestaña Historial y log](#9-pestaña-historial-y-log)
10. [Pestaña Ajustes](#10-pestaña-ajustes)
11. [Programar con IA sin internet (VS Code)](#11-programar-con-ia-sin-internet)
12. [Probar un modelo y medir su velocidad](#12-probar-un-modelo)
13. [Carpetas y archivos de la app](#13-carpetas-y-archivos)
14. [Solución de problemas](#14-solución-de-problemas)
15. [Preguntas frecuentes](#15-preguntas-frecuentes)

---

## 1. Requisitos

| Requisito | Detalle |
|---|---|
| Sistema | Windows 10 (versión 1803 o superior) o Windows 11 |
| Ollama | Recomendado. Si no lo tienes, la app puede descargar el instalador |
| curl.exe | Incluido en Windows 10/11 |
| PowerShell | Incluido en Windows (5.1) |
| Espacio en disco | Según los modelos: de 1 GB a más de 40 GB por modelo |

**GPU:** NVIDIA funciona directamente. **AMD Radeon RX 5000/6000** (por ejemplo RX 6600) e Intel Arc necesitan **Vulkan** activado: la app lo detecta y te ofrece activarlo.

---

## 2. Instalación y primer arranque

1. Copia `Ollama-Manager-Pro.bat` en una carpeta con espacio (por ejemplo `D:\IA\`).
2. Haz **doble clic** en el archivo. Se abre una ventana negra (consola) y luego la aplicación.
   - Si Windows muestra "Windows protegió su PC", pulsa **Más información → Ejecutar de todas formas**.
3. En el primer arranque la app:
   - Detecta tu CPU, RAM, GPU, memoria de vídeo (VRAM) y disco libre.
   - Si tienes una Radeon RX 5000/6000, te pregunta si quieres **activar Vulkan**. Responde **Sí**: sin Vulkan, Ollama no usa tu tarjeta gráfica.
   - Crea la carpeta `OllamaManager-datos\` junto al `.bat`.

> **No cierres la ventana negra**: es el motor de la app. Se cierra sola al cerrar la aplicación.

---

## 3. Pestaña Catálogo

Muestra más de 110 modelos organizados por categoría. Cada tarjeta indica:

- **Modo con tu equipo**: `GPU completa` (máxima velocidad), `GPU + RAM`, `Solo CPU + RAM` o `No cabe en memoria`.
- **Velocidad estimada** en tokens por segundo (tok/s) y memoria necesaria.
- **Capacidades** (Chat, Código, Visión, OCR, Razonamiento, Embeddings…).
- **Para qué sirve** y **en qué destaca**.

### Filtrar y ordenar
En el panel izquierdo: búsqueda, orden ("Mejor para mi equipo" por defecto), categoría, capacidad, tamaño, compatibilidad, "Solo destacados" y "Ocultar instalados".

### Descargar
Pulsa **Descargar** en la tarjeta. Si el modelo no cabe en tu equipo, la app te avisa (puedes descargarlo igual para exportarlo a un PC más potente).

### Buscar modelos que no están en el catálogo
Escribe el nombre en el buscador. Si no aparece:

1. La app muestra **"no está en el catálogo"** y busca automáticamente en **ollama.com** y **Hugging Face**.
2. Resultados posibles:
   - **Existe en ollama.com** → botón **Ver versiones y añadir**: eliges la versión (por ejemplo `:8b`) y la añades o descargas.
   - **Escribiste un ID exacto** (`qwen3:8b`) → la app comprueba si existe y ofrece **Añadir y descargar**.
   - **Solo en Hugging Face** → botón **Elegir versión…**: lista los archivos GGUF con su tamaño y compatibilidad. `Q4_K_M` suele ser el mejor equilibrio.
   - **No existe** → notificación y sugerencias de nombres parecidos.
   - **Sin internet** → aviso con botón **Reintentar**.

También tienes **Buscar en ollama.com…** (explorador completo) y **Descargar por ID…** en el panel izquierdo.

### Verificar catálogo
**Verificar catálogo (tamaños reales)** consulta cada modelo en el registro de Ollama, sustituye los tamaños aproximados (≈) por los reales (✓) y marca los que ya no existen.

---

## 4. La cola de descargas

Todo lo que descargas, exportas o importas pasa por una **cola**. El panel inferior muestra la tarea actual, la barra de progreso, la velocidad y el tiempo restante.

| Botón | Qué hace |
|---|---|
| **Pausar / Reanudar** | Detiene la cola sin perder nada. Reanudar continúa en el mismo punto |
| **Cancelar actual** | Saca la tarea de la cola (lo descargado se conserva en disco) |
| **Ver cola** | Lista las tareas: subir, bajar, poner primero, quitar |
| **Vaciar cola** | Quita las tareas pendientes (la actual sigue) |

### Reanudación garantizada
- **Corte de internet**: la app reintenta cada 15 segundos (configurable) indefinidamente.
- **Corte de luz o cierre de la app**: la cola se guarda en disco. Al volver a abrir la app, **continúa sola** y te avisa con una notificación.
- Cada archivo se verifica con **SHA-256** antes de instalarse: si llega dañado, se descarga de nuevo.

Mientras descarga, la tarjeta del modelo muestra **"Descargando 45 %"** y el título de la ventana muestra el progreso (visible en la barra de tareas).

---

## 5. Pestaña Imagen

Genera y edita imágenes **sin internet** con `stable-diffusion.cpp` (funciona con Vulkan en tarjetas AMD).

### Preparación (una sola vez)
1. **Motor**: pulsa **Instalar / actualizar motor** (elige Vulkan para AMD/Intel, CUDA para NVIDIA).
2. **Modelos** (descarga al menos uno):

| Modelo | Tamaño aprox. | Para qué |
|---|---|---|
| **FLUX.2 Klein 4B** | ~5 GB | Generar **y editar** con instrucciones. El más versátil |
| **Z-Image Turbo** | ~6,6 GB | Generar con la mejor calidad fotográfica |
| Real-ESRGAN x4 | ~20 MB | Ampliar el resultado x4 (opcional) |

Ambos modelos tienen licencia Apache 2.0, que permite el uso comercial.

### Modos de trabajo

| Modo | Cómo usarlo |
|---|---|
| **Generar desde texto** | Describe la imagen: sujeto, lugar, luz, estilo |
| **Editar con instrucciones** | Elige una foto y escribe qué cambiar: *"cambia el fondo por una playa"*, *"pon el texto OFERTA en el cartel"* |
| **Transformar** | Elige una foto y describe el resultado. *Intensidad* baja = más parecido al original |
| **Cambiar solo una zona** | Elige una foto → **Pintar máscara** → pinta la zona → describe qué debe aparecer |

### Consejos
- **Primera prueba en 512x512** con "Modo baja VRAM" marcado; luego sube el tamaño.
- Escribe las descripciones **en inglés** si puedes (los resultados son mejores). Las tildes se quitan automáticamente.
- **Semilla**: con la misma semilla y la misma descripción se obtiene una imagen muy parecida. Útil para hacer variaciones.
- **Usar como entrada**: lleva el resultado a la entrada para seguir editándolo paso a paso.
- Cada imagen se guarda en `OllamaManager-datos\imagen\salidas\` con un `.txt` que registra la descripción y los ajustes.

> Con una GPU de 8 GB (por ejemplo RX 6600), cuenta con **minutos por imagen**, no segundos.

---

## 6. Pestaña Instalados

Lista los modelos de Ollama con tamaño, fecha, integridad, actualización, compatibilidad y velocidad.

| Botón | Qué hace |
|---|---|
| **Verificar (rápido)** | Comprueba que existen todos los archivos con el tamaño correcto |
| **Verificar SHA-256** | Comprueba byte a byte (lento, pero definitivo) |
| **Buscar actualizaciones** | Compara con el registro de Ollama |
| **Actualizar marcados** | Descarga solo lo que cambió |
| **Reparar dañados** | Vuelve a descargar solo los archivos dañados |
| **Probar** | Abre el chat de prueba (también con doble clic) |
| **Exportar marcados** | Copia al repositorio offline |
| **Quitar marcados** | Desinstala y libera espacio |

Si no marcas ningún modelo, la verificación y la búsqueda de actualizaciones se aplican a todos.

---

## 7. Pestaña Offline

### Exportar (crear un USB con tus modelos)
1. **Carpeta destino** → **Examinar…** → elige el USB o disco externo (se crea `OllamaRepo`).
2. Opciones: incluir el instalador de Ollama, incluir esta app, verificar SHA-256.
3. **Exportar marcados** (desde Instalados) o **Exportar TODOS**.
4. **Exportar paquete de IMAGEN** copia el motor y los modelos de imagen.

Los archivos compartidos entre modelos se guardan una sola vez. Si la copia se interrumpe, continúa donde se quedó.

### Importar en otro PC (sin internet)
1. Instala Ollama con **Instalar Ollama desde el repositorio**.
2. Ejecuta el `.bat` incluido en el USB.
3. **Repositorio origen** → elige la carpeta `OllamaRepo` → **Leer repositorio**.
4. **Importar marcados** o **Importar todos los nuevos**.
5. **Importar paquete de IMAGEN** si lo exportaste.

### Importar un archivo GGUF
**Importar archivo GGUF…** convierte un `.gguf` descargado (por ejemplo, de Hugging Face) en un modelo de Ollama. El servicio de Ollama debe estar activo.

---

## 8. Pestaña Mi equipo

- **Equipo detectado**: CPU, RAM, GPU, VRAM, disco y versión de Ollama. Si tu GPU necesita Vulkan, indica si está activado.
- **Perfil para calcular la compatibilidad**: usa el equipo detectado o **datos manuales** para preparar modelos para **otro PC** (por ejemplo, el portátil de un cliente). Incluye perfiles rápidos.
- **Resumen**: cuántos modelos caben en la GPU, cuántos funcionan con GPU + RAM, cuántos solo con CPU y cuántos no caben.
- **Recomendados**: el modelo más capaz que funciona con fluidez en cada categoría, con botón para descargar los marcados.

---

## 9. Pestaña Historial y log

- **Historial**: cada descarga, exportación, importación, verificación, imagen generada o benchmark, con fecha, resultado, tamaño y duración. Se guarda en `historial.csv` (se abre con Excel).
- **Log en vivo**: detalle técnico de todo lo que ocurre. Se guarda un archivo por día en `OllamaManager-datos\logs\`.

---

## 10. Pestaña Ajustes

| Sección | Opciones |
|---|---|
| **Carpetas** | Cambiar la carpeta de modelos (por ejemplo, a otro disco), borrar descargas parciales, limpiar archivos huérfanos |
| **Descargas** | Registro (servidor espejo), segundos entre reintentos, **límite de velocidad**, **proxy**, reanudar al abrir, notificaciones |
| **Optimización de Ollama** | Flash Attention, caché de contexto comprimida, **Vulkan**, no borrar al iniciar, compartir en la red local, longitud de contexto, tiempo en memoria |

Las variables de Ollama se aplican al **reiniciar Ollama** (botón en Ajustes o en la cabecera).

> **Compartir en la red local**: cualquier PC de tu red podrá usar Ollama sin contraseña. Actívalo solo en redes de confianza.

---

## 11. Programar con IA sin internet

1. Catálogo → **Kit de programación (VS Code)…**
2. Descarga los modelos marcados:
   - `qwen3-coder:30b` – chat y agente de código principal.
   - `qwen2.5-coder:7b` – respuestas rápidas en la GPU.
   - `qwen2.5-coder:1.5b` – autocompletado mientras escribes.
   - `nomic-embed-text` – indexa tu proyecto para hacer preguntas sobre el código.
3. Instala **Visual Studio Code** y la extensión **Continue** (una vez con internet, o desde un archivo `.vsix`).
4. Pulsa **Guardar configuración de Continue**. Si ya tenías un `config.yaml`, la app no lo toca: crea `config.ollama-manager.yaml` para que copies su contenido en el tuyo.

---

## 12. Probar un modelo

**Probar** (en la tarjeta o en Instalados) abre un chat:

- Conversación con memoria. **Enter** envía y **Shift+Enter** hace un salto de línea.
- **Adjuntar imagen…** para modelos con Visión.
- **Medir velocidad (benchmark)**: guarda los tokens por segundo reales, que aparecen en el catálogo como "medido".
- Los modelos con razonamiento muestran el texto `[pensando]` antes de la respuesta.

También puedes usar cualquier modelo desde la consola con `ollama run nombre:etiqueta`, o desde otras apps a través de `http://127.0.0.1:11434`.

---

## 13. Carpetas y archivos

```
Tu carpeta\
├── Ollama-Manager-Pro.bat          ← la aplicación
├── descargas-ollama\               ← descargas en curso (se borran al terminar)
└── OllamaManager-datos\
    ├── config.json                 ← tus ajustes
    ├── cola-pendiente.json         ← cola guardada (para reanudar)
    ├── historial.csv               ← historial (Excel)
    ├── catalogo-usuario.json       ← modelos que añadiste tú
    ├── tamanos-verificados.json
    ├── logs\                       ← un log por día
    ├── instalador\                 ← OllamaSetup.exe
    └── imagen\
        ├── motor\                  ← stable-diffusion.cpp
        ├── modelos\                ← Z-Image, FLUX.2 Klein, ESRGAN
        └── salidas\                ← tus imágenes + .txt
```

Los modelos de Ollama se instalan en `%USERPROFILE%\.ollama\models` (o en la carpeta que elijas en Ajustes).

---

## 14. Solución de problemas

| Problema | Solución |
|---|---|
| "Ollama Manager Pro ya está abierto" | Ya hay una ventana abierta (quizá minimizada). Solo se permite una |
| La GPU AMD no acelera | Ajustes → marca **Vulkan** → **Aplicar variables** → **Reiniciar Ollama** |
| "Ollama no está activo" | Pulsa **Iniciar Ollama** en la cabecera y espera unos segundos |
| La descarga no avanza | Revisa la conexión; la app reintenta sola. Si usas proxy, configúralo en Ajustes |
| "Espacio insuficiente" | Libera espacio, cambia la carpeta de modelos o limpia descargas parciales |
| Un modelo responde mal o falla | Instalados → **Verificar SHA-256** → **Reparar dañados** |
| Imagen: error de memoria | Baja el tamaño (512x512) y deja marcado "Modo baja VRAM" |
| Imagen: error de Vulkan | Actualiza el driver de AMD o desmarca "Flash attention" |
| Fallo al bajar de Hugging Face | Descarga el `.gguf` con el navegador → Offline → **Importar archivo GGUF** |
| No encuentro qué pasó | Historial y log → **Abrir carpeta de logs** |

---

## 15. Preguntas frecuentes

**¿Funciona sin internet?**
Sí. Solo necesitas internet para descargar. Probar modelos, generar imágenes, programar e importar desde un USB funcionan sin conexión.

**¿Pierdo lo descargado si se va la luz?**
No. Al reabrir la app continúa desde el último punto guardado (se descartan como mucho unos pocos MB del final, por seguridad).

**¿Los modelos de visión generan imágenes?**
No: los modelos de visión de Ollama *entienden* imágenes (describen, leen texto, analizan). Para *crear* imágenes usa la pestaña **Imagen**.

**¿Puedo usar los modelos comercialmente?**
Depende de la licencia de cada modelo: revísala en ollama.com o en Hugging Face antes de un uso comercial.

**¿La velocidad estimada es exacta?**
No, es una aproximación. Usa **Medir velocidad** para conocer la real en tu equipo.

---

## Licencia

MIT. Consulta el archivo LICENSE. Los modelos descargados tienen sus propias licencias.
