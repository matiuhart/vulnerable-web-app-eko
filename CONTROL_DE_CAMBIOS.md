# Reporte de Control de Cambios, Optimización y Seguridad

Este documento detalla cada una de las modificaciones realizadas sobre la base de código original para la aplicación web vulnerable. Cada cambio está justificado bajo estándares de la industria, buenas prácticas de construcción de imágenes Docker y mitigación de riesgos de seguridad.

---

## 1. Archivo: `Dockerfile` (Modificado)

Se rediseñó por completo el `Dockerfile` para migrar de una configuración insegura y obsoleta a una óptima y segura.

### Tabla Comparativa de Cambios

| Línea Original | Línea Nueva | Acción | Justificación Técnica y de Seguridad |
| :--- | :--- | :--- | :--- |
| `1: FROM node:8` | `1: FROM node:18-slim` | **Modificación** | **Seguridad y Reducción de Superficie de Ataque:** Node 8 llegó al fin de su vida útil (EOL) en 2019 y contiene cientos de vulnerabilidades conocidas (CVEs). Se migró a `node:18-slim` (Active LTS). La variante `-slim` reduce radicalmente el tamaño de la imagen al eliminar herramientas innecesarias en producción (compiladores, paquetes extra de Debian), disminuyendo así las posibilidades de explotación (superficie de ataque). |
| *No existía* | `3-5: ENV NODE_ENV=production`<br>`ENV PORT=8080` | **Adición** | **Optimización y Configuración Estándar:** Establecer `NODE_ENV=production` desactiva dependencias y logs innecesarios de desarrollo en Express y Node.js, aumentando el rendimiento de la aplicación y ocultando trazas detalladas de errores que podrían revelar detalles de la infraestructura a atacantes. |
| *No existía* | `7-8: WORKDIR /usr/src/app` | **Adición** | **Orden y Aislamiento:** Establece un directorio de trabajo seguro dentro del contenedor para evitar que los archivos de la app se mezclen con el sistema de archivos raíz (`/`), lo cual es una mala práctica de organización y seguridad. |
| `4: COPY . .`<br>`5: ADD server.js package*.json ./` | `10-11: COPY package*.json npm-shrinkwrap.json* ./` | **Modificación / Reordenamiento** | **Aprovechamiento de la Caché de Capas (Docker Cache Layering):** Copiar únicamente los manifiestos de dependencias primero permite que Docker cachee la capa del `npm install`. Si los archivos del código fuente cambian, pero no las dependencias, Docker salta el proceso de instalación de dependencias, reduciendo el tiempo de build de minutos a segundos. |
| `6: RUN npm install` | `13-14: RUN npm install --omit=dev && npm cache clean --force` | **Modificación** | **Eficiencia y Seguridad de la Imagen:**<br>1. `--omit=dev` (reemplazo moderno del deprecado `--only=production`) previene la instalación de dependencias de desarrollo (`devDependencies`), reduciendo el tamaño y potenciales fallos en producción.<br>2. `npm cache clean --force` elimina archivos temporales de instalación que se quedarían ocupando espacio inútil dentro del contenedor. |
| *No existía* | `16-17: COPY --chown=node:node . .` | **Adición** | **Principio de Menor Privilegio (Manejo de Permisos):** Copia el código fuente restante de la aplicación asignándole de forma explícita la propiedad al usuario no-raíz `node:node`, evitando que los archivos pertenezcan al usuario `root`. |
| *No existía* | `19-20: USER node` | **Adición** | **Seguridad contra Aislamiento de Contenedores (Container Breakout):** Por defecto, Docker ejecuta los contenedores como usuario `root`. Si un atacante compromete la aplicación mediante RCE (Remote Code Execution), obtendría privilegios de administrador en el contenedor y, potencialmente, en el host. Declarar `USER node` ejecuta la aplicación con un usuario sin privilegios. |
| `8: EXPOSE 8080` | `22-23: EXPOSE 8080` | **Mantenido** | **Documentación de Puerto:** Documenta que el contenedor escucha en el puerto 8080. |
| `12: CMD node server.js` | `25-26: CMD ["node", "server.js"]` | **Modificación** | **Propagación Correcta de Señales del Sistema (Exec Form vs Shell Form):** Al usar la sintaxis de array (exec form), Node.js se ejecuta directamente como proceso con **PID 1** en el contenedor. Esto le permite escuchar y procesar correctamente señales del Kernel como `SIGTERM` o `SIGINT` (útil para un apagado limpio cuando Docker detiene el contenedor). Si se usa la forma shell anterior, el comando corre bajo `/bin/sh -c`, perdiendo la recepción de señales de detención y forzando a Docker a matar el contenedor bruscamente tras un timeout. |

---

## 2. Archivo: `package.json` (Modificado)

Se adaptó para garantizar la compatibilidad con Node.js LTS moderno sin alterar la lógica de la aplicación vulnerable necesaria para el examen práctico.

### Tabla Comparativa de Cambios

| Línea Original | Línea Nueva | Acción | Justificación Técnica y de Seguridad |
| :--- | :--- | :--- | :--- |
| *Fin del archivo* | `15-17: "overrides": { "graceful-fs": "^4.2.11" }` | **Adición** | **Corrección de Compatibilidad Heredada (Legacy):** La librería de plantillas `express-handlebars` v2.0.1 depende de dependencias antiguas de `graceful-fs` (v3.x) que utilizan el paquete `natives`. Este paquete accede a las variables internas de Node.js que fueron eliminadas en versiones superiores a Node 10, provocando el error crítico: `ReferenceError: primordials is not defined`. La propiedad `"overrides"` de NPM obliga a todas las dependencias internas a usar la versión segura y moderna `graceful-fs@4.2.11`, resolviendo el problema sin tener que degradar la versión del motor de Node.js de la imagen. |

---

## 3. Archivo: `.dockerignore` (Creado)

### Justificación Técnica y de Seguridad
Evita el envío accidental de archivos locales al demonio de Docker durante la fase de construcción de la imagen (`docker build`).
* **Seguridad:** Previene la copia accidental de llaves privadas, variables de entorno locales (`.env`), secretos o historial de git (`.git`) que puedan ser accedidos si alguien inspecciona las capas de la imagen.
* **Eficiencia:** Previene subir la carpeta `node_modules` del host, la cual puede contener librerías compiladas para otras arquitecturas de procesador que romperían el funcionamiento del contenedor o ralentizarían el tiempo de build.

### Contenido del archivo
```
node_modules
npm-debug.log
.git
.github
Dockerfile
docker-compose.yml
.dockerignore
README.MD
```

---

## 4. Archivo: `docker-compose.yml` (Modificado)

### Justificación Técnica y de Seguridad
Facilita la orquestación, portabilidad y despliegue estandarizado del entorno de desarrollo local.
* **Portabilidad:** Se reemplazó `build: .` por `image: ghcr.io/matiuhart/vulnerable-web-app-eko:latest` para que la pila local o de Portainer descargue la imagen compilada directamente de los repositorios de paquetes de GitHub. Esto elimina la necesidad de tener los archivos fuente en el entorno de ejecución de Portainer, aumentando la portabilidad y limpieza del despliegue.
* **Estabilidad y Disponibilidad:** Configura la directiva `restart: unless-stopped` que garantiza que el servicio web se reinicie de forma automática si sufre un crash, mejorando la resiliencia de la app localmente.

### Contenido del archivo
```yaml
version: '3.8'

services:
  web:
    image: ghcr.io/matiuhart/vulnerable-web-app-eko:latest
    container_name: vulnerable-app
    ports:
      - "8080:8080"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
```

---

## 5. Archivo: `.github/workflows/deploy-portainer.yml` (Modificado)

Este archivo define el pipeline de Integración y Despliegue Continuo (CI/CD) para construir de forma segura la imagen Docker de la aplicación, publicarla en el Registro de Contenedores de GitHub (GHCR), actualizar dinámicamente el tag de la imagen dentro de `docker-compose.yml`, subir ese cambio a Git omitiendo bucles infinitos, y disparar el webhook de Portainer.

### Tabla Comparativa/Desglose de Líneas

| Rango de Líneas | Elemento/Código | Acción | Justificación Técnica y de Seguridad |
| :--- | :--- | :--- | :--- |
| `1-5` | `name: ... on: push: branches: - master` | **Adición** | **Control de Disparador (Trigger):** Configura la ejecución automática del pipeline ante cualquier subida (`push`) exclusivamente a la rama principal (`master`), garantizando que solo código validado en la rama principal sea desplegado en el entorno local/producción de Portainer. |
| `7-9` | `permissions: contents: write packages: write` | **Modificación** | **Elevación de Permisos del Pipeline:** Otorga privilegios de escritura (`write`) sobre el contenido del repositorio (`contents`) para permitir al pipeline autocommitar la actualización del tag en el `docker-compose.yml`. También se mantienen permisos de escritura en `packages` para publicar la imagen en GHCR. |
| `11-13` | `env: REGISTRY: ghcr.io PORTAINER_WEBHOOK_URL: ...` | **Modificación** | **Seguridad y Parametrización:** Centraliza la dirección del registro de contenedores de GitHub y mapea la URL del webhook de Portainer utilizando la variable de secreto `secrets.PORTAINER_WEBHOOK_URL`. Esto previene la filtración o exposición pública del endpoint webhook de administración de Portainer, siguiendo las directrices de seguridad de OWASP sobre el manejo de secretos en código fuente. |
| `15-18` | `jobs: build-and-deploy: runs-on: ubuntu-latest` | **Adición** | **Entorno Aislado de Construcción:** Ejecuta el proceso de construcción de imágenes Docker en una máquina virtual oficial de GitHub con Ubuntu limpio para prevenir contaminación cruzada de código o datos en builds anteriores. |
| `20-21` | `- name: Checkout Code uses: actions/checkout@v4` | **Adición** | **Descarga del Proyecto:** Obtiene el código fuente del repositorio y lo coloca dentro del directorio de trabajo de la máquina virtual del Action. |
| `23-26` | `- name: Set up Docker image name run: ...` | **Adición** | **Normalización del Nombre de Imagen:** Convierte el nombre de usuario y repositorio a letras minúsculas (`tr '[:upper:]' '[:lower:]'`). Esto es indispensable porque el Registro de Contenedores de GitHub (GHCR) rechaza de forma estricta nombres de imágenes que contengan mayúsculas. |
| `28-34` | `- name: Log in to GHCR uses: docker/login-action@v3 ...` | **Adición** | **Autenticación en el Registro de Paquetes:** Inicia sesión automáticamente en `ghcr.io` utilizando el token de sesión efímero de la ejecución (`secrets.GITHUB_TOKEN`) y el actor del trigger de la build, eliminando credenciales estáticas en texto plano. |
| `36-43` | `- name: Build and Push Docker Image uses: docker/build-push-action@v5 ...` | **Adición** | **Empaquetado Seguro e Inmutable:** Construye la imagen Docker del aplicativo utilizando el `Dockerfile` seguro que diseñamos, y la sube al repositorio de paquetes. Genera dos etiquetas: la versión inmutable basada en el hash del commit (`github.sha`) para trazabilidad e historial de despliegues, y la versión `:latest` para actualizaciones automáticas. |
| `45-47` | `- name: Update image tag in docker-compose.yml run: sed -i ...` | **Adición** | **Actualización Automática de Manifiesto:** Reemplaza la línea del tag de la imagen en `docker-compose.yml` para apuntar a la versión exacta recién compilada (`github.sha`). Esto asegura la reproducibilidad y trazabilidad absoluta de lo que se despliega en Portainer. |
| `49-56` | `- name: Commit and push changes run: git commit -m "... [skip ci]" ...` | **Adición** | **Prevención de Bucle Infinito en CI/CD (Skip CI):** Commita y empuja el cambio de `docker-compose.yml` de vuelta a GitHub. Al incluir la etiqueta **`[skip ci]`** en el mensaje de confirmación, le indicamos a GitHub Actions que **no dispare nuevamente este pipeline**, rompiendo el bucle recursivo infinito de autodespliegue. |
| `58-64` | `- name: Trigger Portainer Webhook run: curl -X POST ...` | **Adición** | **Despliegue a Través de Túnel Seguro (Cloudflare Access):** Ejecuta una petición HTTP POST al webhook de Portainer. Se adjuntan los encabezados de autenticación `CF-Access-Client-Id` y `CF-Access-Client-Secret` obtenidos de los secretos de GitHub para atravesar el túnel protegido de Cloudflare Access. Esto garantiza que nadie fuera del pipeline pueda acceder al endpoint de tu Portainer privado en Internet. |
