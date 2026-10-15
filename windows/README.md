# ChaceRecordings para Windows 11

App nativa WPF/.NET, sin Electron ni navegador integrado. Captura WASAPI del sistema, micrófono o ambos; selector de entradas y de salida del sistema; pausa; barras de audio; panel flotante e icono en la bandeja; carpetas y nombres de grabación; MP3 y Deepgram Nova 3 con idiomas español, inglés y multilingüe.

## Instalar

En GitHub abre **Actions → Crear instalador Windows 11** y selecciona la ejecución más reciente terminada correctamente. Descarga el artefacto **ChaceRecordings-Windows11-x64**, descomprime y ejecuta **ChaceRecordings-Windows11-Setup-x64.exe**. El instalador incluye .NET y no necesita Homebrew, FFmpeg ni herramientas de desarrollo.

El instalador es para Windows 11 x64 (Intel/AMD). No está firmado con un certificado comercial; Windows puede mostrar SmartScreen. Comprueba que sea tu compilación del repositorio antes de permitir su ejecución. No se incluye una compilación ARM64 en este instalador.

También hay una versión portátil: extrae **todo** `ChaceRecordings-Windows11-win-x64.zip` en una carpeta y abre `ChaceRecordings.exe`. No copies únicamente el EXE: necesita sus bibliotecas incluidas.

## Usar

1. En Windows, autoriza el micrófono en **Configuración → Privacidad y seguridad → Micrófono → Permitir que las aplicaciones de escritorio accedan al micrófono**.
2. Elige **Sistema y micrófono**, **Solo sistema** o **Solo micrófono**. Selecciona el micrófono y la salida que reproduce el audio (altavoces, auriculares, etc.). El sistema captura esa salida: si cambias de dispositivo, detén la grabación y selecciona el nuevo.
3. Pulsa **Grabar**. Pausa/reanuda o guarda desde la ventana principal, el panel flotante o la bandeja del sistema. Cerrar la ventana durante una grabación la oculta; vuelve a abrirla desde el icono de la bandeja. Guarda antes de salir. No captures conversaciones importantes sin hacer primero una prueba.
4. **Cambiar carpeta** selecciona el destino; **Nombre** cambia el título y **MP3** exporta mezclando ambas entradas. Las grabaciones anteriores siguen en la biblioteca.
5. **Ajustes** permite pegar la clave de Deepgram. Se guarda cifrada con DPAPI para tu usuario y PC, no en el código o instalador. Configúrala por separado en cada equipo.
6. Con la grabación guardada, pulsa **Transcribir**, elige el idioma y confirma el envío. Se utiliza `nova-3` con `language=es`, `en` o `multi`. El audio se envía a Deepgram y consume créditos. No hay reintentos automáticos. El TXT se guarda en la carpeta de la grabación y se abre al terminar.
7. **Abrir TXT** abre la última transcripción existente, incluso después de reiniciar. No hace una petición a Deepgram ni consume créditos. Se habilita cuando encuentra un TXT.

## Grabaciones largas y requisitos

No hay corte de tiempo impuesto por la app. Las pistas se almacenan en **segmentos WAV internos de hasta 256 MiB**, evitando el límite de un WAV individual. La reproducción y exportación los leen de forma continua desde disco. Conserva la carpeta completa de cada grabación, incluido `recording.json` y todos sus segmentos. El espacio en disco, suspensión, dispositivos y fallos del sistema siguen siendo límites prácticos. La app intenta pausar ante suspensión; no puede grabar durante ella. Audio protegido puede no ser capturable.

MP3 usa Media Foundation de Windows. En las ediciones **Windows 11 N** debes instalar **Media Feature Pack** desde las características opcionales de Windows. La transcripción tiene además los límites propios de Deepgram y un plazo de dos horas de envío/procesamiento, no una duración de audio garantizada.

Las carpetas internas de grabación de Windows son distintas de las de Mac. No hay migración automática de CAF a WAV. Los TXT y MP3 exportados sí pueden abrirse en ambos sistemas. La grabación se hace en disco; la forma de onda conserva solo 64 valores por entrada y su temporizador se detiene en pausa/reposo. El efecto Mica usa el compositor de Windows 11, con fondo opaco de respaldo. No se ha medido la RAM real en un PC en esta sesión.

## Compilar tú mismo

Instala el SDK **.NET 10** desde Microsoft y **Inno Setup 6**. Desde PowerShell, en la raíz del proyecto:

```powershell
.\windows\build-windows.ps1
```

Para generar únicamente la versión portátil: `./windows/build-windows.ps1 -SkipInstaller`. Si una política de tu equipo bloquea scripts, puedes usar el instalador generado por GitHub Actions sin modificar esa política.

El workflow de GitHub compila y crea el instalador en Windows. Las pruebas automáticas cubren mezcla de segmentos, persistencia, reapertura de TXT y parámetros/respuesta de Deepgram. La captura de dispositivos, permisos, MP3 con Media Foundation, suspensión y apariencia necesitan pruebas en Windows real. No se ha usado ninguna clave ni gastado créditos durante el desarrollo.
