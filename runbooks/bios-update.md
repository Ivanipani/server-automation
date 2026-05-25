# BIOS Update

These runbooks assume a MacOS host is used to create the firmware-update utilities.

## Asus ROG STRIX B550-F Gaming (WiFi)

Update the BIOS on the Asus ROG STRIX B550-F Gaming (Wi-Fi) motherboard:

1. Erase + format USB (Disk Utility -> Erase -> MS-DOS (FAT), Master Boot Record
2. Download the latest drivers from [Asus website](https://rog.asus.com/us/motherboards/rog-strix/rog-strix-b550-f-gaming-wi-fi-model/helpdesk_bios/)
3. Copy the .CAP file into the USB, rename to RB550FGW.CAP
4. Insert into PC -> reboot -> Del -> Ez Flash
5. Profit


## HP

### MP9 G2 (older)

1. Erase + format USB on Windows PC
2. Download latest drivers from HP [website](https://support.hp.com/au-en/drivers/closure/hp-mp9-g2-retail-system/8592336)
3. Run the .exe. Copy the extracted files to the USB.
4. Reboot into BIOS menu. Update from USB
