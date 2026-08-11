# MadMixGame — Proyecto de Ingeniería Inversa

*[Read this in English](README.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*
 
Resumen
-------
MadMixGame es un proyecto de ingeniería inversa cuyo objetivo es estudiar, documentar y reconstruir el comportamiento y los recursos de un juego clásico para la plataforma MSX. El proyecto agrupa análisis técnico, extracción de datos (gráficos, audio, niveles), reconstrucción del código y experimentos para permitir ejecutar, modificar y estudiar el juego en entornos modernos.

Objetivos
---------
- Analizar el binario/distribución original para entender su arquitectura y recursos.
- Recuperar y documentar gráficos, sonido y niveles.
- Reimplementar partes del juego o crear herramientas que permitan editar y experimentar con sus datos.
- Proporcionar documentación clara para que otros investigadores y entusiastas continúen el trabajo.

Alcance
-------
Este repositorio se centra en el trabajo técnico: desensamblado, extracción de recursos, herramientas de conversión y documentación técnica. No incluye ni redistribuye binarios comerciales del juego original ni materiales con copyright sin la debida autorización. Los aportes deben ceñirse a prácticas legales y éticas.

Estructura del repositorio
--------------------------
- src/: Documentación y código fuente relacionado con el análisis y las herramientas (ver [src/README.md](C:/Users/User/Documents/Programacion/MSX/proyectos/madmixgame/src/README.md)).
- assets/ (si existe): recursos extraídos (gráficos, audio, mapas), normalmente en formato convertido.
- tools/: utilidades y scripts usados para extracción, conversión y análisis.
- docs/: notas de ingeniería inversa, diagramas y referencias.

Cómo empezar
------------
1. Leer la documentación principal en [src/README.md](C:/Users/User/Documents/Programacion/MSX/proyectos/madmixgame/src/README.md) para conocer detalles específicos del análisis realizado.
2. Revisar la carpeta tools/ para ver scripts y utilidades disponibles.
3. Ejecutar (si aplica) scripts de extracción en un entorno controlado. Usar máquinas virtuales o entornos aislados para manipular binarios.

Dependencias y entorno
----------------------
Las herramientas usadas pueden incluir ensambladores/desensambladores, utilidades de conversión de imágenes/sonido y entornos de desarrollo (Python, Node.js, Make, etc.). Consulte los ficheros dentro de src/ y tools/ para instrucciones concretas sobre instalación de dependencias y versiones recomendadas.

Contribuir
---------
- Antes de enviar cambios, abrir un issue para describir la propuesta de trabajo o la mejora.
- Crear ramas con descripciones claras y enviar pull requests con pruebas y documentación de los cambios.
- Mantener un historial de cambios y documentar nuevas dependencias o pasos de construcción.

Aspectos legales y éticos
-------------------------
La ingeniería inversa puede estar sujeta a restricciones legales según la jurisdicción y el origen del material analizado. Este proyecto promueve:
- No redistribuir software propietario o activos con copyright sin permiso.
- Compartir solo resultados, herramientas y documentación que no infrinjan derechos de terceros.
- Documentar claramente el origen de los datos y cualquier uso de material protegido.

Recursos y referencias
----------------------
- Documentación interna: [src/README.md](C:/Users/User/Documents/Programacion/MSX/proyectos/madmixgame/src/README.md)
- Herramientas típicas: desensambladores Z80, editores hexadecimales, utilidades de conversión de tiles, trackers de audio retro.

Contacto
--------
Para preguntas o propuestas de colaboración, abrir un issue en este repositorio o enviar un mensaje a los mantenedores indicados en la documentación interna.

Notas finales
-------------
Este README es un resumen introductorio. Revisar los documentos en src/ para información técnica detallada y pasos reproducibles.
