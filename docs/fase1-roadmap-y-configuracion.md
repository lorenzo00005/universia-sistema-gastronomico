# Fase 1 — Infraestructura y configuración base de Odoo 17 (Universia)

Estado: entregada el 14/11/2026, a la espera de tu confirmación para pasar a la Fase 2.
Cubre las semanas 1 a 4 del roadmap (carriles A y C) y el diseño de datos de auditoría (carril B).
Marcas: ⚠ = verificar en tu instalación; los nombres de ajustes de Odoo pueden variar levemente en 17.0.

---

## 0. Cómo encaja en el sistema

Esta fase deja listo el **servidor local**, la **base de producción** y el **POS Restaurant operando con mesas, catálogo, impresión por sector y empleados**. Todo lo demás (stock completo, ARCA, auditoría, eWallet en producción, reservas, delivery) se monta encima.

- **Datos:** base `universia_prod` nueva y limpia, con backup diario verificado.
- **Procesos:** convención de nombres y tres procedimientos iniciales (SOP).
- **Usuarios:** roles definidos y PIN por empleado.
- **Hardware:** impresoras de comanda en red, tablets de mozos por Wi-Fi.
- **Seguridad:** Odoo solo en la LAN, administración de bases cerrada, secretos fuera del código.
- **Escalabilidad:** misma estructura sirve para sumar un segundo POS sin rehacer nada.

## 1. Decisiones vigentes y supuestos

**Se reutiliza de la documentación existente (30/09)**

| Elemento | Estado |
|---|---|
| Odoo 17 en Docker (`odoo:17.0` + `postgres:15.8`) | Se mantiene |
| Middleware NFC (`pyscard`, `pyserial`, SendInput, `.exe`), tarea programada `UniversiaNFC` | Se mantiene |
| `BARCODE_PREFIX=042` + UID en el contacto | Se mantiene |
| eWallet con bono 25 % (`loyalty.rule` id=2, 1.25), saldo sin vencimiento | Se recrea en producción en la semana 3 |
| `scripts/backup.ps1` y `restore.ps1` de staging | Se conservan para staging. Producción usa `backup_prod.ps1` |

**Supuestos por defecto** (no respondiste las preguntas de la Fase 0; si alguno es distinto, se ajusta):

| Tema | Supuesto |
|---|---|
| Edición | Odoo **Community** 17.0 |
| Hosting | Servidor **local** (PC dedicada con Windows 11 + Docker Desktop) y copia externa de backups |
| Mesas | **12** de ejemplo: 8 en Salón (T1–T8) y 4 en Terraza (T9–T12), editables |
| Mozos y cajas | 4 mozos, 1 caja |
| Impresoras | 1 de cocina y 1 de barra, **Epson con ePOS en red** |
| Condición fiscal | Sin definir: **los impuestos se configuran en la semana 5-6 junto con ARCA**; hasta entonces se prueba con precios finales |
| Reservas, delivery, PedidosYa | Sin cambios: semanas 9 a 12 |
| Staging | Se conserva como base de pruebas y NFC |

## 2. Estructura de carpetas (servidor)

```
C:\universia-prod\
├── docker-compose.yml
├── .env                  (copia de .env.example, con claves reales)
├── config\odoo.conf
├── addons\               (módulos propios, desde la Fase 2)
└── scripts\backup_prod.ps1
```

## 3. Infraestructura

Requisitos: Windows 11, Docker Desktop con WSL2 y reinicio automático activado.

### 3.1 `C:\universia-prod\docker-compose.yml`

```yaml
name: universia-prod

services:
  db:
    image: postgres:15.8
    restart: unless-stopped
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 10
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  odoo:
    image: odoo:17.0
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "${ODOO_BIND_IP}:8069:8069"
    environment:
      HOST: db
      USER: ${POSTGRES_USER}
      PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - odoo-data:/var/lib/odoo
      - ./config/odoo.conf:/etc/odoo/odoo.conf:ro
      - ./addons:/mnt/extra-addons
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

volumes:
  pgdata:
  odoo-data:
```

### 3.2 `C:\universia-prod\.env` (crear a partir de este modelo)

```ini
# Copiar a ".env" y completar. No subir ".env" a ningún repositorio.
# Odoo se niega a arrancar si el usuario de base de datos es "postgres": usar "odoo".
POSTGRES_USER=odoo
POSTGRES_PASSWORD=CAMBIAR_POR_UNA_CLAVE_LARGA
# IP de la LAN del servidor para limitar el acceso a esa interfaz (ej. 192.168.1.50). 0.0.0.0 = todas.
ODOO_BIND_IP=0.0.0.0
ODOO_DB_NAME=universia_prod
# Backups (usados por scripts\backup_prod.ps1)
BACKUP_DIR=D:\backups\universia
BACKUP_KEEP_DAYS=14
# Carpeta de copia externa (unidad de red, carpeta sincronizada con la nube). Dejar vacío para omitir.
BACKUP_COPY_DIR=
```

### 3.3 `C:\universia-prod\config\odoo.conf`

```ini
[options]
; Reemplazar por el hash generado con el comando del documento (Fase 1, sección 3.4).
admin_passwd = REEMPLAZAR_POR_HASH_PBKDF2
dbfilter = ^universia_prod$
; Poner en True SOLO mientras se crea la base (sección 4.1) y volver a False.
list_db = True
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
; workers = 0 (modo hilos): el websocket del POS funciona en el puerto 8069, sin proxy.
workers = 0
max_cron_threads = 1
limit_time_cpu = 120
limit_time_real = 240
log_level = info
proxy_mode = False
```

### 3.4 Clave maestra de Odoo (hash)

Desde `C:\universia-prod` en PowerShell:

```powershell
docker compose run --rm --no-deps --entrypoint python3 odoo -c "from passlib.hash import pbkdf2_sha512; import getpass; print(pbkdf2_sha512.hash(getpass.getpass('Clave maestra: ')))"
```

Pegar el resultado completo como valor de `admin_passwd` en `odoo.conf`. Guardar la clave en tu gestor de contraseñas.

### 3.5 Arranque y red

```powershell
cd C:\universia-prod
docker compose up -d
docker compose ps
```

Regla de firewall, solo para la red privada local (PowerShell como administrador):

```powershell
New-NetFirewallRule -DisplayName "Universia Odoo 8069 (LAN)" -Direction Inbound -Protocol TCP -LocalPort 8069 -RemoteAddress LocalSubnet -Action Allow -Profile Private
```

Además: reservar una **IP fija** para el servidor en el router, desactivar la suspensión del equipo y **no abrir ni redirigir el puerto 8069 a internet**. PostgreSQL no se publica fuera de Docker.

⚠ Docker Desktop necesita una sesión de usuario iniciada. Si el servidor se reinicia solo, la sesión debe iniciar automáticamente. Si esto se vuelve un problema, la alternativa es un mini-PC Linux con el mismo `docker-compose.yml`.

### 3.6 Backup diario

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Backup de la base universia_prod (PostgreSQL + filestore) con rotación y copia externa opcional.
.NOTES
    Ruta : <proyecto>\scripts\backup_prod.ps1
    Uso  : powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup_prod.ps1
    Config: lee <proyecto>\.env (ODOO_DB_NAME, POSTGRES_USER, BACKUP_DIR, BACKUP_KEEP_DAYS, BACKUP_COPY_DIR).
    Salida: <BACKUP_DIR>\universia_prod_AAAAMMDD_HHMMSS.zip (db.dump + filestore) y <BACKUP_DIR>\backup.log
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $ProjectDir '.env'

function Read-DotEnv {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "No existe el archivo .env: $Path" }
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $map[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
        }
    }
    return $map
}

$cfg = Read-DotEnv -Path $EnvFile
foreach ($key in 'ODOO_DB_NAME', 'POSTGRES_USER', 'BACKUP_DIR') {
    if (-not $cfg.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($cfg[$key])) {
        throw "Falta la variable $key en .env"
    }
}

$DbName = $cfg['ODOO_DB_NAME']
$PgUser = $cfg['POSTGRES_USER']
$BackupDir = $cfg['BACKUP_DIR']
$KeepDays = 14
if ($cfg.ContainsKey('BACKUP_KEEP_DAYS') -and $cfg['BACKUP_KEEP_DAYS'] -match '^\d+$') {
    $KeepDays = [int]$cfg['BACKUP_KEEP_DAYS']
}
$CopyDir = ''
if ($cfg.ContainsKey('BACKUP_COPY_DIR')) { $CopyDir = $cfg['BACKUP_COPY_DIR'] }

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$LogFile = Join-Path $BackupDir 'backup.log'

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Docker {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & docker @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        throw ("docker {0} falló (código {1}): {2}" -f ($Arguments -join ' '), $code, (($output | Out-String).Trim()))
    }
}

function Remove-OldBackups {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][int]$Days
    )
    $limit = (Get-Date).AddDays(-$Days)
    Get-ChildItem -LiteralPath $Folder -Filter 'universia_prod_*.zip' -File |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Log "Rotación: eliminado $($_.Name)"
        }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$work = Join-Path $BackupDir "universia_prod_$stamp"
$zip = "$work.zip"
$exitCode = 0

Push-Location $ProjectDir
try {
    Write-Log "Inicio de backup de '$DbName'"
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    # 1) Dump de PostgreSQL dentro del contenedor, verificación y copia al host
    Invoke-Docker -Arguments @('compose', 'exec', '-T', 'db', 'pg_dump', '-U', $PgUser, '-Fc', '-f', '/tmp/db.dump', $DbName)
    Invoke-Docker -Arguments @('compose', 'exec', '-T', 'db', 'pg_restore', '-l', '/tmp/db.dump')
    Invoke-Docker -Arguments @('compose', 'cp', 'db:/tmp/db.dump', (Join-Path $work 'db.dump'))
    Invoke-Docker -Arguments @('compose', 'exec', '-T', 'db', 'rm', '-f', '/tmp/db.dump')
    Write-Log 'Dump de base de datos verificado y copiado'

    # 2) Filestore (adjuntos). Si todavía no existe, se avisa pero no se aborta.
    try {
        Invoke-Docker -Arguments @('compose', 'cp', "odoo:/var/lib/odoo/filestore/$DbName", (Join-Path $work 'filestore'))
        Write-Log 'Filestore copiado'
    }
    catch {
        Write-Log "No se pudo copiar el filestore: $($_.Exception.Message)" 'WARN'
    }

    # 3) Compresión
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -CompressionLevel Optimal -Force
    Remove-Item -LiteralPath $work -Recurse -Force
    $sizeMb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
    Write-Log "Backup creado: $zip ($sizeMb MB)"

    # 4) Copia externa opcional
    if (-not [string]::IsNullOrWhiteSpace($CopyDir)) {
        New-Item -ItemType Directory -Force -Path $CopyDir | Out-Null
        Copy-Item -LiteralPath $zip -Destination $CopyDir -Force
        Write-Log "Copia externa en: $CopyDir"
        Remove-OldBackups -Folder $CopyDir -Days $KeepDays
    }

    # 5) Rotación local
    Remove-OldBackups -Folder $BackupDir -Days $KeepDays
    Write-Log 'Backup finalizado correctamente'
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode = 1
}
finally {
    Pop-Location
}

exit $exitCode
```

Programación (PowerShell como administrador):

```powershell
schtasks /Create /TN "Universia-Backup" /SC DAILY /ST 04:30 /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\universia-prod\scripts\backup_prod.ps1" /RL HIGHEST
```

⚠ `Compress-Archive` en PowerShell 5.1 falla con archivos de más de 2 GB. Para una cafetería no debería ocurrir en el primer año. Si pasa, se cambia por 7-Zip.

**Prueba obligatoria:** restaurar un backup en staging con `restore.ps1` antes de la semana 7.

## 4. Creación de la base y apps

### 4.1 Crear la base

1. Con `list_db = True` en `odoo.conf`, abrir `http://IP-DEL-SERVIDOR:8069`.
2. Crear base: nombre `universia_prod`, **demo desactivado**, idioma Español (AR), país **Argentina**, y el correo y la clave del administrador.
3. Volver a `odoo.conf`, poner `list_db = False` y ejecutar `docker compose restart odoo`.

### 4.2 Empresa

Ajustes → Empresas: nombre, CUIT, dirección, moneda ARS y zona horaria `America/Argentina/Buenos_Aires` (en Ajustes del usuario y en la empresa).

### 4.3 Apps a instalar (en este orden)

Inventario, Compras, Fabricación (solo para listas de materiales; no se usarán órdenes de producción), Empleados, **Punto de venta**, CRM, Marketing por correo.

⚠ Al instalar Punto de venta se instala Facturación (`account`). Con el país en Argentina, Odoo debería cargar la localización `l10n_ar` automáticamente. Verificarlo en Ajustes → Contabilidad → Localización fiscal.

## 5. Configuración del POS Restaurant

Punto de venta → Configuración → Punto de venta → crear **"Universia – Salón"**. Luego Configuración → Ajustes, eligiendo ese punto de venta.

| Ajuste | Valor |
|---|---|
| Es un bar/restaurante | Activado (instala `pos_restaurant`) |
| Facturación parcial de cuenta ("Dividir cuenta") | Activado |
| Impresión de precuenta | Activado |
| Propinas | Activado, con producto "Propina" sin impuesto |
| Múltiples empleados por sesión | Activado (instala `pos_hr`) |
| Control de precios y descuentos | Restringir a gerentes |
| Impresora de pedidos | Activado (ver sección 8) |
| Impresora Epson de recibos | IP de la impresora de caja |

**Métodos de pago iniciales:** Efectivo, Tarjeta (manual, sin terminal integrada), Transferencia. Mercado Pago QR y eWallet se agregan después.

**Plano de mesas:** crear los pisos "Salón" y "Terraza" y arrastrar las 12 mesas en el modo de edición del POS. Numeración fija T1 a T12, con el número **físicamente visible** en cada mesa.

⚠ Odoo 17 no trae "cursos" (entrada, principal, postre). En la Fase 1 se envía a cocina por tandas con el botón de pedido. Un control propio de cursos queda para la Fase 2.

## 6. Catálogo y convención de nombres

**Categorías de POS** (cada una responde a un sector de impresión):

| Sector | Categorías |
|---|---|
| Cocina | Platos, Sándwiches |
| Barra | Café, Bebidas, Licuados, Pastelería |

**Códigos internos:** `CAF-001` (café), `COC-001` (cocina), `BEB-001` (bebidas), `PAS-001` (pastelería), `INS-001` (insumos).
**Nombre del producto:** `Nombre – Tamaño` (ej. "Latte – Grande"). Sin abreviaturas ni mayúsculas sostenidas.

**Reglas de carga**
- Producto vendible: marcado "Puede ser vendido" y "Disponible en PdV", con categoría de POS.
- Insumo: marcado "Puede ser comprado", **no** "Disponible en PdV", con unidad de medida de stock y de compra (crear mL si no existe).
- Receta: lista de materiales tipo **Kit** sobre el producto vendible (consumo automático al vender).
- Valoración de stock: **costo promedio**, manual hasta definir el plan contable con el contador.

⚠ Por defecto, Odoo genera los movimientos de stock del POS **al cerrar la sesión**. Eso es correcto para esta etapa.

## 7. Empleados, roles y permisos

Empleados → crear a cada persona y asignar un **PIN** en la pestaña de ajustes de RR. HH. Cada mozo entra al POS con su PIN, no con usuario compartido.

| Rol | Acceso en Odoo |
|---|---|
| Mozo | Punto de venta: usuario (empleado básico) |
| Cajero | Punto de venta: usuario (empleado básico), con apertura y cierre de caja |
| Encargado | Empleado avanzado en el POS: autoriza precios, descuentos y anulaciones |
| Dueño | Administrador de Punto de venta e Inventario |

| Acción | Mozo | Cajero | Encargado | Dueño | Control en Fase 1 |
|---|---|---|---|---|---|
| Tomar y enviar pedido | ✅ | ✅ | ✅ | ✅ | Nativo |
| Dividir y transferir mesa | ✅ | ✅ | ✅ | ✅ | Nativo |
| Aplicar descuento o cambiar precio | ❌ | ❌ | ✅ | ✅ | Nativo (PIN de gerente) |
| Cobrar y cerrar caja | ❌ | ✅ | ✅ | ✅ | Nativo |
| Anular ítem **ya enviado a cocina** | ❌ | ❌ | ✅ | ✅ | **Propio (Fase 2)**: hoy no hay aprobación ni registro |
| Ajustar stock | ❌ | ❌ | ✅ | ✅ | Parcial; registro propio en Fase 2 |

## 8. Impresión por sector

Ajustes del POS → Impresora de pedidos → agregar dos impresoras:

| Nombre | Tipo | IP | Categorías impresas |
|---|---|---|---|
| Cocina | Impresora Epson | IP fija de la impresora | Platos, Sándwiches |
| Barra | Impresora Epson | IP fija de la impresora | Café, Bebidas, Licuados, Pastelería |

Requisitos previos:
- Activar **ePOS-Print** desde la página web de cada impresora.
- Mantener Odoo en **HTTP dentro de la LAN**. Si el POS se sirve por HTTPS, el navegador bloquea la impresión a impresoras sin certificado.
- IP fija o reserva DHCP para cada impresora.

⚠ Las impresoras que no sean Epson necesitarían un IoT Box (Enterprise). Para Community, la alternativa es un servicio propio de impresión ESC/POS, que se evalúa en la Fase 2 una vez que sepamos las marcas.

## 9. Procedimientos operativos iniciales (SOP)

**SOP-01 — Apertura del local (encargado)**
1. Encender el servidor y verificar que Odoo responde en la tablet de caja.
2. Controlar que las impresoras de cocina y barra impriman una prueba.
3. Contar el fondo de caja y anotar el monto en el sistema.
4. Abrir la sesión del POS con el PIN propio.
5. Revisar el stock mínimo de los insumos críticos.

**SOP-02 — Pedido y servicio (mozo)**
1. Entrar con el PIN propio. No compartir PIN.
2. Abrir la mesa por su número y cargar el pedido con las notas del cliente.
3. Enviar a cocina antes de salir de la mesa.
4. Para anular algo ya enviado, pedir al encargado: nunca borrar sin autorización.
5. Pedir la precuenta desde el sistema; no calcular a mano.

**SOP-03 — Cierre de caja (cajero)**
1. Verificar que no queden mesas abiertas.
2. Contar el efectivo por denominación y compararlo con el esperado.
3. Anotar el motivo de cualquier diferencia.
4. Cerrar la sesión y esperar la confirmación del sistema.
5. El encargado revisa el reporte de cierre y lo firma.

Pendientes: SOP-04 Recepción de mercadería, SOP-05 Recarga eWallet y tarjeta perdida, SOP-06 Inventario semanal (se redactan con las fases correspondientes).

## 10. Pruebas de aceptación

| # | Prueba | Resultado esperado |
|---|---|---|
| 1 | Abrir mesa, cargar pedido y enviar | Comanda impresa en el sector correcto |
| 2 | Pedido con ítems de cocina y barra | Dos comandas distintas |
| 3 | Dividir cuenta con pago mixto (efectivo y tarjeta) | Cuenta cerrada, ambos pagos registrados |
| 4 | Unir dos mesas y transferir un pedido | Un único pedido, sin ítems duplicados |
| 5 | Dos mozos con la misma mesa en simultáneo | Sin pérdida de datos, el cambio llega a ambos |
| 6 | Descuento como mozo | Pide PIN de gerente |
| 7 | Cerrar caja con diferencia | Diferencia visible en el cierre |
| 8 | Cortar el Wi-Fi de una tablet y reconectar | Sesión se recupera sin perder el pedido |
| 9 | Vender producto con receta y cerrar sesión | Insumos descontados del stock |
| 10 | Restaurar el backup en staging | Base funcional con datos íntegros |

## 11. Diseño de datos de auditoría antirrobo (módulo `universia_audit`, Fase 2)

**Modelo `universia.audit.event`** (inmutable: sin edición ni borrado, ni siquiera para administradores)

| Campo | Contenido |
|---|---|
| `event_type` | Anulación post-comanda, descuento, precuenta cancelada, mesa reabierta, reimpresión, ajuste de stock, movimiento de saldo, diferencia de caja |
| `pos_config_id`, `session_id`, `order_id` | Contexto de la venta |
| `employee_id` | Quién ejecuta |
| `approver_id` | Quién autoriza, si corresponde |
| `amount`, `currency_id` | Monto involucrado |
| `reason_code`, `reason_text` | Motivo (obligatorio en los eventos críticos) |
| `payload_before`, `payload_after` | Estado antes y después (JSON) |
| `device_info` | Dispositivo y dirección IP |
| `hash_prev`, `hash` | Cadena de hashes: detecta alteraciones directas en la base |

**Modelo `universia.audit.rule`**

| Campo | Contenido |
|---|---|
| `event_type` | Evento al que aplica |
| `role` | Rol afectado |
| `threshold_amount` | Monto desde el que exige aprobación o alerta |
| `require_approval` | Bloqueante (sí/no) |
| `notify_channel` | Aviso por n8n / WhatsApp al dueño |

La retención del log (⚠ sugerida: 24 meses) y los datos personales de empleados que contiene deben alinearse con la Ley 25.326.

## 12. Riesgos y pendientes

- Los datos del cliente (mesas, impresoras, condición fiscal) están asumidos. Cada uno que cambie mueve un ajuste de esta fase.
- Impresoras no Epson requieren una solución adicional.
- Docker Desktop depende de una sesión de usuario iniciada.
- El lector PN532 y las pruebas pendientes del 30/09 siguen sin validación; no bloquean esta fase.
- Los impuestos quedan sin configurar hasta definir la condición fiscal.

## 13. Qué sigue (Fase 2)

Roadmap semanas 3 a 5: recreación del eWallet en producción, recetas y compras, aprobación de anulaciones tras cocina (primer módulo propio), arqueo de caja con motivo de diferencia y servicio ARCA en homologación.
