#!/bin/bash
#!/bin/bash

echo "Mapping USB Bus Numbers to PCI Controllers:"
echo "-------------------------------------------"

# Iterate through all PCI device directories
for pcidevdir in /sys/bus/pci/devices/*; do
    # Read the PCI device class code
    pci_class=$(cat "$pcidevdir/class")

    # Check if it's a USB Host Controller (class code 0x0c03xx)
    # 0x0c0300 = UHCI, 0x0c0310 = OHCI, 0x0c0320 = EHCI, 0x0c0330 = xHCI
    if [[ "$pci_class" == 0x0c0300 || "$pci_class" == 0x0c0310 || "$pci_class" == 0x0c0320 || "$pci_class" == 0x0c0330 ]]; then
        pci_addr=$(basename "$pcidevdir")
        pci_info=$(lspci -nns "$pci_addr") # Get vendor/device info, address

        # Find the USB root hub directory (usbX) associated with this PCI device
        # There might be multiple if a controller handles different speeds/ports separately
        found_bus=0
        for usbdir in "$pcidevdir"/usb*; do
            # Check if it's a directory and contains the busnum file
            if [ -d "$usbdir" ] && [ -f "$usbdir/busnum" ]; then
                busnum=$(cat "$usbdir/busnum")
                printf "USB Bus %03d -> PCI Device: %s\n" "$busnum" "$pci_info"
                # Optional: Show devices on this bus for easy correlation
                echo "  Devices currently on Bus $busnum:"
                lsusb -s "${busnum}:"* | sed 's/^/    /' # Indent lsusb output
                echo "" # Add spacing
                found_bus=1
            fi
        done
         # If you uncomment the below, it warns if a USB controller is found but has no active bus (e.g., disabled in BIOS)
         # if [ $found_bus -eq 0 ]; then
         #   echo "Info: Found USB Controller $pci_info but no associated active USB bus directory found."
         #   echo "" # Add spacing
         # fi
    fi
done

echo "-------------------------------------------"
echo "Mapping complete."
echo "Compare the 'USB Bus XXX' number here with the 'Bus XXX' from 'lsusb -t'."

# Bus 1 73:00:0
# Bus 5 76:00:4