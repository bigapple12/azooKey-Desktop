#\!/bin/bash
pkill -9 azooKeyMac
sleep 1
sudo rm -rf "/Library/Input Methods/azooKeyMac.app"
sudo cp -R build/DerivedData/Build/Products/Debug/azooKeyMac.app "/Library/Input Methods/azooKeyMac.app"
echo "Done."
