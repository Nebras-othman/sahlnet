FROM freeradius/freeradius-server:latest

# Install gettext to provide envsubst
RUN apt-get update && apt-get install -y gettext-base && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY mods-available/sql /etc/freeradius/3.0/mods-available/sql
COPY sites-available/default /etc/freeradius/3.0/sites-available/default
COPY entrypoint.sh /entrypoint.sh

# Set execute permission on entrypoint
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
