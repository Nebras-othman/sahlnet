#!/bin/bash

##############################################################################
# 1. Install Docker & Docker Compose (Ubuntu)
##############################################################################
if ! [ -x "$(command -v docker)" ]; then
  echo "Docker is not installed. Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable docker
  sudo systemctl start docker
else
  echo "Docker already installed."
fi

if ! [ -x "$(command -v docker-compose)" ]; then
  echo "Docker Compose is not installed. Installing Docker Compose..."
  sudo apt-get update
  sudo apt-get install -y docker-compose
else
  echo "Docker Compose already installed."
fi

##############################################################################
# 2. Create Project Directory Structure
##############################################################################
echo "Creating project directory structure..."

PROJECT_ROOT="./isp-project"
FREERADIUS_DIR="$PROJECT_ROOT/freeradius"
FREERADIUS_CONFIG_DIR="$FREERADIUS_DIR/config"
MONITORING_DIR="$PROJECT_ROOT/monitoring"

mkdir -p "$FREERADIUS_CONFIG_DIR"
mkdir -p "$MONITORING_DIR"

echo "Directory structure created at: $PROJECT_ROOT"

##############################################################################
# 3. Generate .env file
##############################################################################
echo "Generating .env file..."
cat <<EOF > $PROJECT_ROOT/.env
# ------------------------------------------------------------------------------
# Global Environment Variables
# ------------------------------------------------------------------------------

# PostgreSQL Database Credentials
POSTGRES_USER=openwisp
POSTGRES_PASSWORD=changeme
POSTGRES_DB=openwisp_db

# RADIUS Secret
RADIUS_SECRET=supersecret

# Optional: CoovaChilli UAM Secret (if using CoovaChilli)
UAM_SECRET=chillisecret

# OpenWISP Admin (superuser) credentials
OPENWISP_SUPERUSER_USERNAME=admin
OPENWISP_SUPERUSER_PASSWORD=admin
OPENWISP_SUPERUSER_EMAIL=admin@example.com

# Additional environment variables can go here
EOF

##############################################################################
# 4. Generate docker-compose.yml
##############################################################################
echo "Generating docker-compose.yml..."
cat <<'EOF' > $PROJECT_ROOT/docker-compose.yml
version: "3.8"

services:
  ###################################################################
  # PostgreSQL
  ###################################################################
  postgres:
    image: postgres:13
    container_name: isp_postgres
    restart: always
    env_file:
      - .env
    environment:
      POSTGRES_USER: "${POSTGRES_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: "${POSTGRES_DB}"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  ###################################################################
  # FreeRADIUS + CoovaChilli (Custom Dockerfile)
  ###################################################################
  freeradius:
    build:
      context: ./freeradius
      args:
        RADIUS_SECRET: "${RADIUS_SECRET}"
    container_name: isp_freeradius
    restart: always
    ports:
      - "1812:1812/udp"  # RADIUS Authentication
      - "1813:1813/udp"  # RADIUS Accounting
    env_file:
      - .env
    depends_on:
      - postgres
    volumes:
      # Mount local FreeRADIUS config
      - ./freeradius/config:/etc/freeradius/3.0

  ###################################################################
  # OpenWISP (Base, NGINX, Websocket, Dashboard, etc.)
  ###################################################################
  # Base container
  openwisp-base:
    image: openwisp/openwisp-base:latest
    container_name: isp_openwisp_base
    restart: always
    env_file:
      - .env
    environment:
      DATABASE_URL: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
      DJANGO_SUPERUSER_USERNAME: "${OPENWISP_SUPERUSER_USERNAME}"
      DJANGO_SUPERUSER_PASSWORD: "${OPENWISP_SUPERUSER_PASSWORD}"
      DJANGO_SUPERUSER_EMAIL: "${OPENWISP_SUPERUSER_EMAIL}"
    depends_on:
      - postgres

  # NGINX container for OpenWISP
  openwisp-nginx:
    image: openwisp/openwisp-nginx:latest
    container_name: isp_openwisp_nginx
    restart: always
    depends_on:
      - openwisp-base
    ports:
      - "80:80"
      - "443:443"
    env_file:
      - .env

  # OpenWISP Websocket
  openwisp-websocket:
    image: openwisp/openwisp-websocket:latest
    container_name: isp_openwisp_websocket
    restart: always
    depends_on:
      - openwisp-base
    env_file:
      - .env
    environment:
      DATABASE_URL: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"

  # OpenWISP Dashboard (optional)
  openwisp-dashboard:
    image: openwisp/openwisp-dashboard:latest
    container_name: isp_openwisp_dashboard
    restart: always
    depends_on:
      - openwisp-base
    env_file:
      - .env
    environment:
      DATABASE_URL: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"

  # OpenWISP API (optional)
  openwisp-api:
    image: openwisp/openwisp-api:latest
    container_name: isp_openwisp_api
    restart: always
    depends_on:
      - openwisp-base
    env_file:
      - .env
    environment:
      DATABASE_URL: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"

  ###################################################################
  # Prometheus
  ###################################################################
  prometheus:
    image: prom/prometheus
    container_name: isp_prometheus
    restart: always
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml

  ###################################################################
  # Grafana
  ###################################################################
  grafana:
    image: grafana/grafana
    container_name: isp_grafana
    restart: always
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin

volumes:
  postgres_data:
EOF

##############################################################################
# 5. Generate minimal FreeRADIUS config files
##############################################################################
echo "Generating FreeRADIUS config files..."

# clients.conf
cat <<EOF > $FREERADIUS_CONFIG_DIR/clients.conf
client localhost {
    ipaddr = 127.0.0.1
    secret = \${env:RADIUS_SECRET}
}

client edge_router {
    ipaddr = 10.0.0.1
    secret = \${env:RADIUS_SECRET}
}

client coova_chilli {
    ipaddr = 10.20.0.1
    secret = \${env:RADIUS_SECRET}
}
EOF

# users
cat <<EOF > $FREERADIUS_CONFIG_DIR/users
# Simple test users
testing Cleartext-Password := "test123"
    Reply-Message := "Hello, Testing!"

user1 Cleartext-Password := "password"
    # Example Mikrotik attribute for rate-limiting
    Mikrotik-Rate-Limit := "8M/4M"

user2 Cleartext-Password := "password2"
    Mikrotik-Rate-Limit := "16M/8M"
EOF

##############################################################################
# 6. Generate Prometheus config
##############################################################################
echo "Generating Prometheus config..."
cat <<EOF > $MONITORING_DIR/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'self'
    static_configs:
      - targets: ['localhost:9090']
EOF

##############################################################################
# 7. Create Dockerfile for FreeRADIUS + CoovaChilli
##############################################################################
echo "Generating Dockerfile for FreeRADIUS (and CoovaChilli)..."
cat <<'EOF' > $FREERADIUS_DIR/Dockerfile
# Base Image
FROM ubuntu:22.04

ARG RADIUS_SECRET
ENV RADIUS_SECRET=$RADIUS_SECRET

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    freeradius freeradius-utils \
    git \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    libgcrypt-dev \
    libjson-c-dev \
    nano \
    net-tools \
    iptables && \
    apt-get clean

# If you want CoovaChilli from source:
RUN git clone https://github.com/coova/coova-chilli.git && \
    cd coova-chilli && \
    autoreconf -i && \
    ./configure --prefix=/usr/local --sysconfdir=/etc --localstatedir=/var && \
    make && \
    make install && \
    ldconfig

WORKDIR /etc/freeradius/3.0

# Copy config from Docker build context
COPY config/ /etc/freeradius/3.0/

# Expose RADIUS ports
EXPOSE 1812/udp 1813/udp

# Default command: run FreeRADIUS in debug mode (-X) for clarity
CMD ["freeradius", "-X"]
EOF

##############################################################################
# 8. Print Summary
##############################################################################
echo ""
echo "====================================================="
echo "Setup script completed! Here's what was done:"
echo "1. Installed Docker & Docker Compose (if missing)."
echo "2. Created project directory structure at $PROJECT_ROOT."
echo "3. Generated a .env file with default credentials."
echo "4. Generated docker-compose.yml with Postgres, FreeRADIUS, OpenWISP, Prometheus & Grafana."
echo "5. Created minimal FreeRADIUS config (clients.conf, users)."
echo "6. Created a basic Prometheus config in monitoring/prometheus.yml."
echo "7. Created a Dockerfile for FreeRADIUS + CoovaChilli in freeradius/."
echo ""
echo "Next Steps:"
echo "-----------------------------------------------"
echo "1) cd $PROJECT_ROOT"
echo "2) docker-compose build freeradius     # build the custom FreeRADIUS + CoovaChilli image"
echo "3) docker-compose up -d               # start all containers"
echo "4) Check logs: docker-compose logs -f"
echo "5) Access OpenWISP at http://<Host_IP> (port 80 mapped)"
echo "   - Username: \$OPENWISP_SUPERUSER_USERNAME"
echo "   - Password: \$OPENWISP_SUPERUSER_PASSWORD"
echo "-----------------------------------------------"
echo "Adjust any config & environment variables as needed!"
echo "====================================================="
echo ""
