# Setup — Guía de instalación y desarrollo

Esta guía explica cómo instalar las dependencias necesarias y levantar el proyecto en tu máquina, ya sea en modo web (sin compilar Rust) o como aplicación de escritorio nativa con Tauri.

---

## Requisitos

Antes de clonar el repo instalá las herramientas del sistema según tu plataforma.

### macOS

Necesitás las herramientas de compilación de Xcode, Rust y Node.js.

```bash
# Xcode Command Line Tools — compilador C/C++ que usa Rust internamente
xcode-select --install

# Rust — lenguaje en el que está escrito el core de Tauri
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Hacé el PATH de Rust permanente para nuevas terminales
echo 'source $HOME/.cargo/env' >> ~/.zshrc

# Node.js — para correr el frontend y los scripts del proyecto
# Descargar de https://nodejs.org/ o con Homebrew:
brew install node
```

### Windows

Los comandos de instalación usan **PowerShell**. Abrilo desde el menú inicio o con `Win + X → Windows PowerShell`.

1. **Visual Studio Build Tools** — compilador de C++ que necesita Rust para generar el binario nativo.
   Descargalo de [visualstudio.microsoft.com/visual-cpp-build-tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) y marcá la opción _Desktop development with C++_ durante la instalación.

2. **Rust** — en PowerShell:
   ```powershell
   winget install --id Rustlang.Rustup
   ```
   Cerrá y volvé a abrir la terminal para que `cargo` y `rustc` queden disponibles en el PATH.

3. **Node.js** — para el frontend y los scripts del proyecto. En PowerShell:
   ```powershell
   winget install --id OpenJS.NodeJS.LTS
   ```
   Reiniciá la terminal luego de instalar.

4. **Git** — para clonar el repositorio. En PowerShell:
   ```powershell
   winget install --id Git.Git
   ```

> WebView2 ya viene incluido en Windows 10 (v1803+) y Windows 11, no hace falta instalarlo por separado.

#### ¿winget no funciona?

`winget` requiere **Windows 10 v1809 o superior** y viene incluido con el _App Installer_ de la Microsoft Store. Si el comando no se reconoce, seguí estos pasos desde **PowerShell como administrador**:

1. Intentá registrar el paquete ya instalado:
   ```powershell
   Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
   ```
2. Si eso falla, instalalo manualmente:
   - Andá a [aka.ms/getwinget](https://aka.ms/getwinget) y descargá el archivo `.msixbundle`.
   - En PowerShell (como administrador), desde la carpeta donde lo descargaste:
     ```powershell
     Add-AppxPackage .\Microsoft.DesktopAppInstaller_*.msixbundle
     ```
3. Cerrá y volvé a abrir PowerShell. Verificá que quedó instalado:
   ```powershell
   winget --version
   ```

> **Nota:** usá siempre **PowerShell** (no cmd) para los comandos de `winget`. En Windows 11 viene preinstalado y no requiere ningún paso adicional.

### Linux (Ubuntu/Debian)

Instalá las dependencias del sistema, Rust y Node.js via nvm.

```bash
# Librerías del sistema necesarias para compilar Tauri
sudo apt update
sudo apt install -y \
  build-essential curl wget file \
  libgtk-3-dev libwebkit2gtk-4.1-dev \
  libayatana-appindicator3-dev librsvg2-dev \
  libssl-dev patchelf

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Hacé el PATH de Rust permanente para nuevas terminales
echo 'source $HOME/.cargo/env' >> ~/.bashrc

# Node.js via nvm (gestor de versiones, recomendado en Linux)
# El instalador de nvm agrega las líneas necesarias a ~/.bashrc automáticamente
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
source ~/.bashrc
nvm install 20
```

---

## Instalar y correr

Con los requisitos listos, cloná el repo e instalá las dependencias del proyecto.

```bash
# 1. Clonar el repositorio
git clone https://github.com/dotdeivid/srvfiles.git
cd srvfiles

# 2. Instalar dependencias de raíz, backend y frontend de una sola vez
npm run install:all
```

### Modo web — sin Rust, sin Tauri

Levanta el backend en el puerto 3001 y el frontend en el 5173 con hot reload. No requiere tener Rust instalado.

```bash
npm run dev
```

Abrí `http://localhost:5173` en el navegador.

### Modo app de escritorio — con Tauri

Compila la app nativa y la corre con hot reload en el frontend.

```bash
# Primera vez (o cuando cambia el backend): compilar el sidecar de Node
npm run build:sidecar

# Iniciar la app nativa con hot reload en el frontend
npm run tauri:dev
```

---

## Build

### Preview (frontend compilado, servido por el backend)

Útil para probar la versión de producción sin empaquetar.

```bash
cd frontend && npm run build
cd ../backend && npm start
# → http://localhost:3001
```

### Instalador nativo (distribución)

Genera el instalador listo para distribuir según el sistema operativo.

```bash
npm run tauri:build
# → src-tauri/target/release/bundle/
#   macOS:   .dmg
#   Windows: .msi / .exe
#   Linux:   .deb / .AppImage
```
