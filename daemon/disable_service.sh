#!/bin/sh
echo "Stopping piconsole service..."
sudo systemctl stop piconsole.service
echo "Disabling piconsole service..."
sudo systemctl disable piconsole.service
echo "Done. If you want to completely remove piconsole, please remove /opt/piconsole"
