#!/bin/bash

# Definir variables
dir="/honeypot"

# Crear directorios
echo "Creando directorios..."
mkdir -p $dir/loki
mkdir -p $dir/grafana

# Instalar Docker y Docker Compose
echo "Instalando Docker y Docker Compose..."
apt-get update
apt-get install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

# Configurar Loki
echo "Generando configuración para Loki..."
cat > $dir/loki/docker-compose.yml << 'EOF'
version: '3.8'
services:
  loki:
    image: grafana/loki:2.9.0
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml
EOF

cat > $dir/loki/loki-config.yaml << 'EOF'
auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
schema_config:
  configs:
  - from: 2020-10-24
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 24h
storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    cache_ttl: 24h
EOF

# Configurar Grafana
echo "Generando configuración para Grafana..."
cat > $dir/grafana/docker-compose.yml << 'EOF'
version: '3.8'
services:
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - ./grafana-data:/var/lib/grafana
EOF

# Generar docker-compose.yml principal
echo "Generando docker-compose.yml principal..."
cat > $dir/docker-compose.yml << 'EOF'
version: '3.8'
services:
  loki:
    image: grafana/loki:2.9.0
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./loki/loki-config.yaml:/etc/loki/local-config.yaml

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/grafana-data:/var/lib/grafana
EOF

echo "Configuración de VPS2 completada. Ahora levanta los servicios con: cd $dir && docker-compose up -d"
echo "Accede a Grafana en http://<IP_VPS2>:3000, usuario: admin, contraseña: admin"