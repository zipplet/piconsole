#!/bin/sh
sudo mkdir /opt/piconsole
sudo cp config.ini /opt/piconsole/
sudo cp piconsole /opt/piconsole/
sudo cp start.sh /opt/piconsole/
sudo cp mypoweroff.sh /opt/piconsole/
sudo cp piconsole.service /lib/systemd/system/
sudo chmod +x /opt/piconsole/piconsole
sudo chmod +x /opt/piconsole/start.sh
sudo chmod +x /opt/piconsole/mypoweroff.sh
sudo systemctl daemon-reload
sudo systemctl enable piconsole.service
sudo systemctl start piconsole.service

