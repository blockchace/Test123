# Aire Audio

Grabador nativo para MacBook Air con macOS 13 Ventura o posterior. Interfaz en español, audio del sistema, micrófono o ambos; controles flotantes y en la barra de menús; pausa/reanudación y exportación local a MP3 de 192 kbps. No graba vídeo ni envía audio a servidores.

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
- La reproducción de una grabación combinada escucha la pista del sistema; el MP3 exportado contiene ambas pistas.

Las pistas originales están en `~/Library/Application Support/AireAudio/Grabaciones`. El botón de carpeta las muestra en Finder. Se conservan después de exportar. El contenido protegido por DRM puede impedir la captura. No hay promesa de sincronización de precisión de estudio entre dos dispositivos/relojes independientes.

## Estado de verificación

El entorno de desarrollo utilizado es Linux, sin SDK macOS ni Xcode: **la compilación Swift y la captura en un Mac están pendientes**. No se entrega un DMG ya compilado. Se han comprobado aquí el empaquetador mediante pruebas, la sintaxis del script y el flujo FFmpeg de mezcla/exportación con pistas de prueba. El script de macOS compila Swift, empaqueta las bibliotecas, comprueba la firma y genera un MP3 de prueba antes de crear el DMG.

Pruebas de aceptación en tu Mac antes de usarlo para una grabación importante:

1. Graba 20 segundos del sistema mientras reproduces un sonido; pausa 5 segundos y reanuda 10. El audio debe durar aproximadamente 30 segundos, sin incluir la pausa.
2. Repite con micrófono y con ambas fuentes. Exporta y reproduce el MP3 combinado para comprobar las dos pistas.
3. Cierra la ventana y pausa/detén desde el panel flotante y desde el menú REC.
4. Reinicia la app y confirma que conserva la biblioteca y exporta de nuevo.
5. Prueba permisos denegados, desconexión del micrófono y suspensión/reanudación. Comprueba que los errores preserven las pistas ya guardadas.
6. Haz una grabación prolongada con suficiente espacio y verifica duración y reproducción. La ausencia de un temporizador de corte no sustituye esta prueba de estabilidad.
