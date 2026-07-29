#!/bin/bash
# Detener el script ante cualquier error inesperado
set -e
echo "================================================================="
echo "   CONFIGURACIÓN DE ZABBIX PROXY & INSTALACIÓN DE DOCKER         "
echo "================================================================="
# 1. Preguntar HOSTNAME
read -p "1. Ingrese el HOSTNAME para este Zabbix Proxy (ej. dls4168): " ZBX_HOSTNAME </dev/tty
if [ -z "$ZBX_HOSTNAME" ]; then
    echo "Error: El HOSTNAME no puede estar vacío."
    exit 1
fi
# 2. Preguntar por Deshabilitar Wi-Fi
read -p "2. ¿Desea deshabilitar el Wi-Fi permanentemente (incluso tras reiniciar)? [s/N]: " ASK_WIFI </dev/tty
# 3. Preguntar por IP Estática
read -p "3. ¿Desea configurar la IP fija cableada a 192.168.31.2/24? [s/N]: " ASK_IP </dev/tty
echo ""
echo "================================================================="
echo "   INICIANDO INSTALACIÓN (Sin intervención requerida)            "
echo "================================================================="
# 4. Remover paquetes conflictivos de Docker
echo "[1/7] Removiendo paquetes antiguos de Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove $pkg -y || true
done
# 5. Actualizar e instalar pre-requisitos
echo "[2/7] Instalando dependencias (snmp, curl, certificados)..."
sudo apt-get update
sudo apt install snmp -y
sudo apt-get install ca-certificates curl -y
# 6. Configurar llaves y repositorio oficial de Debian
echo "[3/7] Configurando repositorio oficial de Docker..."
sudo mkdir -p /etc/apt/keyrings
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# 7. Instalar Docker
echo "[4/7] Instalando motor de Docker..."
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
# 8. Instalar Docker Compose (Standalone)
echo "[5/7] Instalando Docker Compose (Standalone)..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
sudo sh -c "curl -L https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose"
sudo chmod +x /usr/local/bin/docker-compose
# 9. Habilitar y arrancar Docker
echo "[6/7] Iniciando y habilitando servicios de Docker..."
sudo systemctl enable --now docker containerd
# 10. Desplegar Zabbix Proxy
echo "[7/7] Levantando el contenedor de Zabbix Proxy..."
sudo docker rm -f zabbix-proxy-sqlite3 || true
sudo docker run --name zabbix-proxy-sqlite3 \
  -e ZBX_HOSTNAME="$ZBX_HOSTNAME" \
  -e ZBX_SERVER_HOST=192.168.10.66 \
  --restart=always --init -d \
  zabbix/zabbix-proxy-sqlite3:ubuntu-7.0.10
# =================================================================
#   CONFIGURACIONES OPCIONALES (Respuestas previas del usuario)
# =================================================================
# Aplicar deshabilitación de Wi-Fi
if [[ "$ASK_WIFI" =~ ^[sS]$ ]]; then
    echo ""
    echo "[+] Deshabilitando Wi-Fi de forma permanente..."
    
    # Bloqueo por software inmediato
    if command -v nmcli >/dev/null 2>&1; then
        sudo nmcli radio wifi off || true
    fi
    sudo rfkill block wifi || true
    # Bloqueo persistente por hardware en la Raspberry Pi (config.txt)
    CONFIG_PATH="/boot/firmware/config.txt"
    if [ ! -f "$CONFIG_PATH" ]; then
        CONFIG_PATH="/boot/config.txt"
    fi
    if [ -f "$CONFIG_PATH" ]; then
        if grep -q "dtoverlay=disable-wifi" "$CONFIG_PATH"; then
            echo "   [!] Wi-Fi ya estaba configurado como deshabilitado en $CONFIG_PATH."
        else
            echo "dtoverlay=disable-wifi" | sudo tee -a "$CONFIG_PATH" > /dev/null
            echo "   [✓] Se agregó 'dtoverlay=disable-wifi' a $CONFIG_PATH."
        fi
    fi
fi
# Aplicar IP Estática
if [[ "$ASK_IP" =~ ^[sS]$ ]]; then
    echo ""
    echo "[+] Configurando IP fija a 192.168.31.2/24..."
    
    # Caso A: Si usa NetworkManager (Raspberry Pi OS 12 Bookworm)
    if command -v nmcli >/dev/null 2>&1; then
        # Buscar interfaz cableada activa
        CONN_NAME=$(nmcli -t -f NAME,TYPE connection show --active | grep -E ':802-3-ethernet|:ethernet' | cut -d: -f1 | head -n 1 || true)
        if [ -z "$CONN_NAME" ]; then
            CONN_NAME=$(nmcli -t -f NAME,TYPE connection show | grep -E ':802-3-ethernet|:ethernet' | cut -d: -f1 | head -n 1 || true)
        fi
        
        if [ -n "$CONN_NAME" ]; then
            sudo nmcli connection modify "$CONN_NAME" \
                ipv4.addresses 192.168.31.2/24 \
                ipv4.gateway 192.168.31.1 \
                ipv4.dns "192.168.10.15 192.168.10.16" \
                ipv4.method manual
            echo "   [✓] Conexión '$CONN_NAME' actualizada exitosamente."
            # Reiniciar conexión en segundo plano para evitar colgar el script si se corre vía SSH
            sudo nmcli connection up "$CONN_NAME" >/dev/null 2>&1 &
        else
            echo "   [!] No se detectó ninguna conexión Ethernet en NetworkManager."
        fi
    # Caso B: Si usa dhcpcd antiguo (Raspberry Pi OS 11 o anterior)
    elif [ -f /etc/dhcpcd.conf ]; then
        # Respaldar original
        [ ! -f /etc/dhcpcd.conf.bak ] && sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak
        
        # Limpiar configuración previa de eth0
        sudo sed -i '/interface eth0/,/static domain_name_servers/d' /etc/dhcpcd.conf
        
        # Escribir la nueva configuración
        sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF
interface eth0
static ip_address=192.168.31.2/24
static routers=192.168.31.1
static domain_name_servers=192.168.10.15 192.168.10.16
EOF
        echo "   [✓] Configuración agregada a /etc/dhcpcd.conf."
        sudo systemctl restart dhcpcd >/dev/null 2>&1 &
    else
        echo "   [!] No se detectó ningún gestor de red compatible (NetworkManager/dhcpcd)."
    fi
fi
# =================================================================
#   VALIDACIÓN FINAL DEL ESTADO
# =================================================================
echo ""
echo "================================================================="
echo "   VALIDACIÓN DE SERVICIOS                                       "
echo "================================================================="
# Validar Docker Service
if systemctl is-active --quiet docker; then
    echo "   [✓] Servicio Docker:   CORRIENDO"
else
    echo "   [X] Servicio Docker:   DETENIDO o FALLIDO"
fi
# Validar Contenedor Zabbix
CONTAINER_STATUS=$(sudo docker inspect -f '{{.State.Status}}' zabbix-proxy-sqlite3 2>/dev/null || echo "no_encontrado")
if [ "$CONTAINER_STATUS" = "running" ]; then
    echo "   [✓] Proceso Zabbix:    CORRIENDO (Contenedor activo)"
else
    echo "   [X] Proceso Zabbix:    DETENIDO (Estado: $CONTAINER_STATUS)"
fi
echo "================================================================="
