# Aire Audio

Grabador nativo para MacBook Air con macOS 13 Ventura o posterior. Interfaz en español, audio del sistema, micrófono o ambos; controles flotantes y en la barra de menús; pausa/reanudación y exportación local a MP3 de 192 kbps. No graba vídeo ni envía audio a servidores.

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

4. Abre `dist/Aire Audio.dmg` y arrastra **Aire Audio** a **Aplicaciones**.
5. Abre la app. La compilación local lleva firma ad hoc, sin notarización de Apple. Si macOS bloquea su apertura, usa Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente, solo para tu propia compilación.

El script genera una app para la arquitectura del Mac donde lo ejecutes (Apple Silicon o Intel). Para distribuir públicamente hacen falta firma Developer ID, revisión de licencias de FFmpeg/bibliotecas y notarización. `AIRE_SIGN_IDENTITY` permite indicar una identidad de firma, pero el script no realiza notarización.

También hay un workflow de GitHub Actions para compilar en macOS y entregar el DMG de Apple Silicon como artefacto. Se ejecutará al subir los archivos a `main` o manualmente desde Actions → Crear instalador macOS. No se ha ejecutado en esta sesión.

## Grabar

- Selecciona **Sistema**, **Micrófono** o **Sistema + micrófono**, y pulsa **Grabar**.
- Autoriza el micrófono si lo elegiste. Para el sistema, autoriza la grabación de pantalla/audio en Privacidad y seguridad. ScreenCaptureKit necesita ese permiso aunque la app solo guarde audio. Puede ser necesario cerrar y reabrir la app tras autorizarlo.
- Usa **Pausar/Reanudar** y **Detener y guardar** en la ventana principal, el panel flotante o el icono **REC** de la barra de menús. El panel se puede arrastrar.
- Cerrar la ventana no detiene la grabación. La barra de menús permite volver a mostrarla. Salir de la app con una grabación activa requiere detenerla primero.
- Pulsa **Exportar MP3** para elegir nombre y carpeta. En modo combinado se mezclan ambas pistas con normalización; no hay controles de volumen independientes en esta versión.
- La reproducción de una grabación combinada y el MP3 exportado contienen ambas pistas.

Las pistas originales están en `~/Library/Application Support/AireAudio/Grabaciones`. El botón de carpeta las muestra en Finder. Se conservan después de exportar. El contenido protegido por DRM puede impedir la captura. No hay promesa de sincronización de precisión de estudio entre dos dispositivos/relojes independientes.

## Estado de verificación

El entorno de desarrollo utilizado es Linux, sin SDK macOS ni Xcode: **la compilación Swift y la captura en un Mac están pendientes**. No se entrega un DMG ya compilado. Se han comprobado aquí el empaquetador mediante pruebas, la sintaxis del script y el flujo FFmpeg de mezcla/exportación con pistas de prueba. El script de macOS compila Swift, empaqueta las bibliotecas, comprueba la firma y genera un MP3 de prueba antes de crear el DMG.

Para la versión 1.1 se comprobó además la sintaxis de los archivos Swift con un parser. Esto no comprueba los tipos ni sustituye la compilación. El workflow ejecuta `swift test`: pruebas de silencio, picos de frecuencia, amplitud, canales estéreo con fase opuesta y buffers intercalados cortos. Estas pruebas Swift y la captura del micrófono físico requieren macOS y no se ejecutaron localmente en Linux.

Pruebas de aceptación en tu Mac antes de usarlo para una grabación importante:

1. Graba 20 segundos del sistema mientras reproduces un sonido; pausa 5 segundos y reanuda 10. El audio debe durar aproximadamente 30 segundos, sin incluir la pausa.
2. Repite con micrófono y con ambas fuentes. Exporta y reproduce el MP3 combinado para comprobar las dos pistas.
   Elige explícitamente el micrófono integrado, después uno externo si está disponible. Comprueba que cada espectro responde solo a su pista, se vacía al pausar y muestra silencio cuando llegan datos sin sonido. Reduce la ventana y recorre toda la biblioteca con la barra de desplazamiento. Verifica el icono de micrófono en Finder y Dock.
3. Cierra la ventana y pausa/detén desde el panel flotante y desde el menú REC.
4. Reinicia la app y confirma que conserva la biblioteca y exporta de nuevo.
5. Prueba permisos denegados, desconexión del micrófono y suspensión/reanudación. Comprueba que los errores preserven las pistas ya guardadas.
6. Haz una grabación prolongada con suficiente espacio y verifica duración y reproducción. La ausencia de un temporizador de corte no sustituye esta prueba de estabilidad.
