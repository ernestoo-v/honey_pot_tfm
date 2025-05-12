#!/usr/bin/env bash
# Script para generar la estructura y ficheros de un honeypot de media interacción
# con Cowrie (SSH), Proftpd (FTP), un servicio web Apache+PHP y herramientas de observabilidad.

set -e

# Base directory
dir="honeypot"

# Crear estructura de carpetas
mkdir -p $dir/{grafana/data,grafana/provisioning/datasources,config}
echo "Creando directorios necesarios..."

# Asignar permisos adecuados para Grafana
sudo chown -R 472:472 $dir/grafana/data
echo "Asignando permisos a grafana/data..."

# Instalar Docker y Docker Compose
echo "Instalando Docker y Docker Compose..."
apt-get update
apt-get install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

# Generar docker-compose.yml
echo "Generando docker-compose.yml..."
cat > $dir/docker-compose.yml << 'EOF'
version: "3.8"

services:
  grafana:
    image: grafana/grafana-oss:latest
    container_name: honeypot_grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    networks:
      dmz:
        ipv4_address: 172.18.0.13
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning

  mi_loki:
    image: grafana/loki:2.9.0
    container_name: mi_loki
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./config/loki-config.yaml:/etc/loki/local-config.yaml
    ports:
      - "3100:3100"
    networks:
      dmz:
        ipv4_address: 172.18.0.14

networks:
  dmz:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16
          gateway: 172.18.0.1
EOF

# Configuración de Loki
echo "Generando configuración para Loki..."
cat > $dir/config/loki-config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

query_scheduler:
  max_outstanding_requests_per_tenant: 4096
frontend:
  max_outstanding_per_tenant: 4096

common:
  instance_addr: 127.0.0.1
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

analytics:
  reporting_enabled: false
EOF

# Configuración de provisioning para Grafana
echo "Generando configuración de provisioning para Grafana..."
cat > $dir/grafana/provisioning/datasources/datasource.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://mi_loki:3100
    jsonData:
      maxLines: 1000
EOF


echo "Estructura y ficheros generados en ./$dir"
