#!/bin/bash
# 1. Solicitar el Hostname de forma interactiva (funciona usando curl | bash)
echo "================================================================="
echo "   CONFIGURACIÓN DE ZABBIX PROXY & INSTALACIÓN DE DOCKER         "
echo "================================================================="
read -p "Ingrese el HOSTNAME para este Zabbix Proxy (ej. dls4168): " ZBX_HOSTNAME </dev/tty
if [ -z "$ZBX_HOSTNAME" ]; then
    echo "Error: El HOSTNAME no puede estar vacío."
    exit 1
fi
echo ""
echo "Iniciando instalación automatizada para el host: $ZBX_HOSTNAME..."
echo "-----------------------------------------------------------------"
# 2. Remover paquetes conflictivos de Docker
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove $pkg -y || true
done
# 3. Actualizar e instalar pre-requisitos
sudo apt-get update
sudo apt install snmp -y
sudo apt-get install ca-certificates curl -y
# 4. Configurar llaves y repositorio oficial de Debian
sudo mkdir -p /etc/apt/keyrings
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
ls -l /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# 5. Instalar Docker
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
# 6. Instalar Docker Compose (Standalone)
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
sudo sh -c "curl -L https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose"
sudo chmod +x /usr/local/bin/docker-compose
docker-compose -v
# 7. Habilitar Docker para que inicie automáticamente tras reanudar
sudo systemctl enable --now docker containerd
# 8. Desplegar el contenedor de Zabbix Proxy con la variable asignada
sudo docker run --name zabbix-proxy-sqlite3 \
  -e ZBX_HOSTNAME="$ZBX_HOSTNAME" \
  -e ZBX_SERVER_HOST=192.168.10.66 \
  --restart=always --init -d \
  zabbix/zabbix-proxy-sqlite3:alpine-7.0.10
echo "-----------------------------------------------------------------"
echo "¡Proceso terminado con éxito!"
echo "Equipo configurado con el Hostname: $ZBX_HOSTNAME"
echo "================================================================="
