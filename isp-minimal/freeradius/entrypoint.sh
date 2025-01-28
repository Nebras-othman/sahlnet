#!/bin/bash

# Substitute environment variables in configuration files
envsubst < /etc/freeradius/3.0/mods-available/sql > /etc/freeradius/3.0/mods-available/sql
envsubst < /etc/freeradius/3.0/sites-available/default > /etc/freeradius/3.0/sites-available/default

# Enable the sql module
ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/

# Start FreeRADIUS in the foreground with debugging enabled
freeradius -X
