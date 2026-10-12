# ChaceRecordings

Grabador nativo para MacBook Air con macOS 13 Ventura o posterior. Interfaz en español, audio del sistema, micrófono o ambos; controles flotantes y en la barra de menús; pausa/reanudación y exportación local a MP3 de 192 kbps. No graba vídeo ni envía audio a servidores.

### Cambios de la versión 1.4: transcripción con Deepgram

1. Pulsa el **engranaje de Ajustes** en la cabecera. Pega únicamente tu API key de Deepgram y pulsa **Guardar**. La clave queda en el Llavero de macOS, no en preferencias, archivos de audio ni Git. Cada Mac necesita su propia configuración. Al recompilar con firma local, el Llavero puede pedir que autorices de nuevo a la app.
2. Termina y guarda la grabación. Pulsa **Transcribir** debajo de ella.
3. Selecciona **Español**, **Inglés** o **Multilingüe**. El modelo siempre es **Nova 3**. Los parámetros enviados son `model=nova-3` y `language=es`, `en` o `multi`.
4. Pulsa **Transcribir** en el selector. Esto envía el audio a `api.deepgram.com` y consume créditos de tu cuenta. La app no transcribe ni envía audio automáticamente al grabar.
5. Cuando termine, se abre un **TXT UTF-8** y se muestra en Finder. Queda **dentro de la carpeta de esa grabación**, junto a sus pistas CAF, con nombre `Transcripcion-idioma-fecha-identificador.txt`. Incluye texto y, cuando Deepgram los devuelve, tiempos y hablantes. Cada intento exitoso crea otro TXT sin sobrescribir resultados previos.

Para la transcripción se crea una copia temporal MP3 mono a 16 kHz/64 kbps; las dos pistas se mezclan cuando la grabación contiene sistema y micrófono. Los originales no se modifican. La subida se hace desde un archivo, sin cargar toda la grabación en RAM, y la copia temporal se elimina al finalizar. La app muestra errores de clave, saldo, límite de solicitudes, archivos demasiado grandes o respuestas sin voz. No reintenta automáticamente solicitudes que puedan consumir créditos. No cierres la app durante el proceso; la salida se bloquea hasta que termine. Si hay un error después de que Deepgram haya recibido el audio, es posible que el servicio haya consumido créditos.

La grabación sigue sin un corte de duración impuesto por la app, pero Deepgram tiene sus propios límites de tamaño, idioma/modelo, disponibilidad y tiempo de procesamiento. La operación de transcripción tiene un plazo de red de hasta dos horas. Requiere Internet, una clave con permisos y saldo válido. Nova 3 multilingüe permite conversaciones con idiomas alternados; no es la opción `detect_language`.

**Validación:** se han comprobado localmente la sintaxis Swift y las pruebas existentes de mezcla/exportación y empaquetado. Las pruebas Swift del workflow comprueban la URL para los tres idiomas, el modelo, la lectura del texto y hablantes, respuestas vacías y errores HTTP. No se ha realizado una petición real a Deepgram ni una prueba del Llavero en esta máquina Linux, y no se han gastado créditos. La documentación oficial de Deepgram no estuvo accesible desde la red de esta sesión. Comprueba la integración en tu Mac con una conversación corta y revisa el consumo en Deepgram antes de enviar grabaciones largas.

### Cambios de la versión 1.3

- Nuevo nombre de app, ejecutable, proyecto Swift y DMG: **ChaceRecordings**. Se conserva `app.aireaudio.recorder` como identificador interno para mantener preferencias y continuidad de permisos. El repositorio sigue siendo `blockchace/Test123`.
- **Cambiar carpeta** permite elegir dónde se guardan las pistas originales y recuerda la elección al reiniciar. Las grabaciones existentes no se mueven: la biblioteca sigue mostrando las carpetas anteriores. Si un disco externo no está disponible o la carpeta no permite escribir, se informa del error; no se cambia el destino en silencio.
- Botón de **lápiz** para poner nombre a una grabación. El nombre queda guardado y se propone al exportar a MP3. Se guarda como metadato en `recording.json`, sin renombrar ni alterar las pistas originales.
- Dos formas de onda con **64 líneas verticales centradas**, una por entrada, que muestran el historial reciente de amplitud a un máximo de **30 actualizaciones por segundo**. Responden al audio realmente guardado; no son un espectro de frecuencias. El historial visual se limita a unos dos segundos y nunca aumenta con la duración de la grabación.
- Ventana con material translúcido nativo de macOS, tarjetas suaves y compatibilidad con modo oscuro y Reducir transparencia. Se elimina la frase “Sin límite” de la interfaz; sigue sin existir un corte de duración.

Para actualizar, cierra y guarda cualquier grabación de la versión anterior. Instala **ChaceRecordings.app** y elimina solo la antigua app **Aire Audio.app** de Aplicaciones para evitar abrir dos versiones con el mismo identificador. No borres sus carpetas de audio. Las pistas antiguas se siguen leyendo desde `~/Library/Application Support/AireAudio/Grabaciones` hasta que elijas otro destino. Si macOS vuelve a pedir permisos después de compilar con firma ad hoc, autoriza la nueva app. El nombre visible nuevo no garantiza continuidad de permisos con una firma nueva.

### Rendimiento y medición de RAM

La ventana utiliza un solo `NSVisualEffectView` detrás del contenido y dos `Canvas` para todas las barras. No usa WebView, imágenes de fondo, sombras animadas ni un temporizador de animación en reposo. El muestreo visual se detiene al pausar o finalizar; el contador y la biblioteca no se actualizan a 30 Hz. Los dos historiales contienen solo 128 valores Float, no todo el audio. Las pistas continúan escribiéndose en disco.

Estas decisiones limitan el trabajo y los buffers del diseño, pero **no se ha medido la RAM real de esta versión en Linux**. El workflow de macOS ejecuta una medición de RSS de la ventana en reposo, con un presupuesto de comprobación de 256 MiB y un artefacto `ChaceRecordings-memory-report`. Es un umbral de detección de regresiones, no una promesa de consumo. RSS del proceso no incluye toda la memoria GPU/WindowServer.

Puedes ejecutar la medición en tu Mac después de compilar, cerrando primero cualquier otra instancia:

```bash
python3 scripts/profile-memory-macos.py
```

El script abre su propia instancia, mide 15 segundos y la cierra; no detiene apps ajenas. El resultado queda en `dist/memory-report.json`. Para verificar el uso real durante la captura, observa **ChaceRecordings** en Monitor de Actividad durante unos minutos en reposo, grabando ambas entradas y en pausa. Comprueba también que la RAM no crezca de forma sostenida con una grabación larga. La captura con permisos, la apariencia final y ese consumo activo necesitan comprobación en tu Mac.

### Cambios de la versión 1.2

Interfaz compacta para usarla junto a otras apps: ventana inicial de 460 × 500 puntos, tamaño mínimo de 400 × 350, márgenes reducidos, espectros más bajos y contador junto a los controles cuando hay espacio. El contenido mantiene desplazamiento vertical y los controles se reordenan si no caben. El botón **Guardar** detiene y guarda; **MP3** exporta una grabación. La captura y las pistas guardadas no cambian. La disposición visual necesita comprobación en macOS.

### Cambios de la versión 1.1

- Selector de micrófono con nombres de dispositivos (integrado, USB, auriculares, etc.), actualización de la lista y recuerdo de la selección. Ahora la captura abre el dispositivo elegido mediante `AVCaptureSession`.
- Desplazamiento vertical de toda la ventana, incluida la biblioteca, sin necesidad de pantalla completa.
- Dos espectros de frecuencia independientes, calculados a partir del audio guardado: **Sistema** y **Micrófono**. Distinguen entrada desactivada, pausa, ausencia de datos, silencio y sonido detectado. Se activan al grabar; no son una prueba de entrada previa a la grabación.
- La reproducción de grabaciones combinadas ahora mezcla ambas pistas; antes solo se escuchaba la del sistema en la app.
- Icono de micrófono en Finder/Dock y en la barra de menús. El instalador genera el recurso `.icns` durante la compilación.

Para actualizar, cierra la versión anterior, genera o descarga el nuevo DMG y reemplaza la app en Aplicaciones. Las grabaciones permanecen en Application Support. Comprueba el permiso del micrófono tras reemplazar la app, ya que macOS puede solicitarlo de nuevo con una firma local nueva. Selecciona **Micrófono** o **Sistema + micrófono** y el dispositivo integrado en el selector; al hablar deben moverse las barras del espectro del micrófono. En modo **Sistema** no se captura el micrófono.

La app **no impone un límite de duración**. Escribe audio PCM en archivos CAF en disco, aptos para archivos grandes. El límite práctico es el almacenamiento disponible. El formato original ocupa aproximadamente 0,35–1,4 GB por hora por pista, según canales y formato del dispositivo; la grabación combinada suma ambas pistas. Un MP3 a 192 kbps ocupa unos 86 MB por hora. Las pausas se excluyen de las pistas. Al dormir el Mac se pausa y al despertar se intenta reanudar; no se puede capturar mientras el Mac está dormido. Los cambios de dispositivo y la suspensión necesitan verificación en un Mac real.

## Crear e instalar en tu Mac

Necesitas las herramientas de desarrollo de Apple y FFmpeg para **construir** el instalador. La app generada incluye el codificador y sus bibliotecas: el usuario final no necesita instalar FFmpeg.

1. Instala las herramientas de Apple: `xcode-select --install`.
2. Con [Homebrew](https://brew.sh) instalado, ejecuta `brew install ffmpeg`.
3. Descarga este proyecto, abre Terminal en su carpeta y ejecuta:

   ```bash
   bash scripts/build-macos.sh
   ```

4. Abre `dist/ChaceRecordings.dmg` y arrastra **ChaceRecordings** a **Aplicaciones**.
5. Abre la app. La compilación local lleva firma ad hoc, sin notarización de Apple. Si macOS bloquea su apertura, usa Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente, solo para tu propia compilación.

El script genera una app para la arquitectura del Mac donde lo ejecutes (Apple Silicon o Intel). Para distribuir públicamente hacen falta firma Developer ID, revisión de licencias de FFmpeg/bibliotecas y notarización. `CHACE_SIGN_IDENTITY` permite indicar una identidad de firma, pero el script no realiza notarización.

También hay un workflow de GitHub Actions para compilar en macOS y entregar el DMG de Apple Silicon como artefacto. Se ejecutará al subir los archivos a `main` o manualmente desde Actions → Crear instalador macOS. No se ha ejecutado en esta sesión.

## Grabar

- Selecciona **Sistema**, **Micrófono** o **Sistema + micrófono**, y pulsa **Grabar**.
- Autoriza el micrófono si lo elegiste. Para el sistema, autoriza la grabación de pantalla/audio en Privacidad y seguridad. ScreenCaptureKit necesita ese permiso aunque la app solo guarde audio. Puede ser necesario cerrar y reabrir la app tras autorizarlo.
- Usa **Pausar/Reanudar** y **Detener y guardar** en la ventana principal, el panel flotante o el icono **REC** de la barra de menús. El panel se puede arrastrar.
- Cerrar la ventana no detiene la grabación. La barra de menús permite volver a mostrarla. Salir de la app con una grabación activa requiere detenerla primero.
- Pulsa **Exportar MP3** para elegir nombre y carpeta. En modo combinado se mezclan ambas pistas con normalización; no hay controles de volumen independientes en esta versión.
- La reproducción de una grabación combinada y el MP3 exportado contienen ambas pistas.

Las pistas originales están en la carpeta elegida. Por compatibilidad, el destino inicial sigue siendo `~/Library/Application Support/AireAudio/Grabaciones`. El botón de carpeta las muestra en Finder. Se conservan después de exportar. El contenido protegido por DRM puede impedir la captura. No hay promesa de sincronización de precisión de estudio entre dos dispositivos/relojes independientes.

## Estado de verificación

El entorno de desarrollo utilizado es Linux, sin SDK macOS ni Xcode: **la compilación Swift y la captura en un Mac están pendientes**. No se entrega un DMG ya compilado. Se han comprobado aquí el empaquetador mediante pruebas, la sintaxis del script y el flujo FFmpeg de mezcla/exportación con pistas de prueba. El script de macOS compila Swift, empaqueta las bibliotecas, comprueba la firma y genera un MP3 de prueba antes de crear el DMG.

Para las versiones recientes se comprobó además la sintaxis de los archivos Swift con un parser. Esto no comprueba los tipos ni sustituye la compilación. El workflow ejecuta `swift test`: pruebas de amplitud de audio, canales estéreo con fase opuesta, buffers intercalados, historial visual acotado y persistencia de nombres. Estas pruebas Swift y la captura del micrófono físico requieren macOS y no se ejecutaron localmente en Linux.

Pruebas de aceptación en tu Mac antes de usarlo para una grabación importante:

1. Graba 20 segundos del sistema mientras reproduces un sonido; pausa 5 segundos y reanuda 10. El audio debe durar aproximadamente 30 segundos, sin incluir la pausa.
2. Cambia el destino a una carpeta de prueba, graba, reinicia y verifica que lo recuerde. Pon un nombre con el lápiz, reinicia y confirma que se conserve y se proponga al exportar. Comprueba que las pistas antiguas sigan visibles y que se informe de una carpeta inaccesible.
3. Repite con micrófono y con ambas fuentes. Exporta y reproduce el MP3 combinado para comprobar las dos pistas.
   Elige explícitamente el micrófono integrado, después uno externo si está disponible. Comprueba que cada espectro responde solo a su pista, se vacía al pausar y muestra silencio cuando llegan datos sin sonido. Reduce la ventana y recorre toda la biblioteca con la barra de desplazamiento. Verifica el icono de micrófono en Finder y Dock, la transparencia en claro/oscuro y la opción Reducir transparencia.
4. Cierra la ventana y pausa/detén desde el panel flotante y desde el menú REC.
5. Reinicia la app y confirma que conserva la biblioteca y exporta de nuevo.
6. Prueba permisos denegados, desconexión del micrófono y suspensión/reanudación. Comprueba que los errores preserven las pistas ya guardadas.
7. Haz una grabación prolongada con suficiente espacio y verifica duración y reproducción. La ausencia de un temporizador de corte no sustituye esta prueba de estabilidad.
