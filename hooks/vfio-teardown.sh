#!/bin/bash

# Define the current date/time for logging
DATE=$(date +"%m/%d/%Y %R:%S :")

# Log the start of the script
logger "$DATE Beginning of Teardown!"

# Log VFIO unloads
logger "$DATE Unloading VFIO drivers..."
modprobe -r vfio_pci
modprobe -r vfio_iommu_type1
modprobe -r vfio

if grep -q "true" "/tmp/vfio-is-nvidia"; then
    # Log if we are using NVIDIA drivers
    logger "$DATE Loading NVIDIA GPU Drivers"
    modprobe drm
    modprobe drm_kms_helper
    modprobe i2c_nvidia_gpu
    modprobe nvidia
    modprobe nvidia_modeset
    modprobe nvidia_drm
    modprobe nvidia_uvm
    logger "$DATE NVIDIA GPU Drivers Loaded"
fi

if grep -q "true" "/tmp/vfio-is-amd"; then
    # Log if we are using AMD drivers
    logger "$DATE Loading AMD GPU Drivers"
    modprobe drm
    modprobe amdgpu
    modprobe radeon
    modprobe drm_kms_helper
    logger "$DATE AMD GPU Drivers Loaded"
fi

# Restart Display Manager and log each step
input="/tmp/vfio-store-display-manager"
while read -r DISPMGR; do
    logger "$DATE Trying to start display manager: $DISPMGR"
    if command -v systemctl; then
        logger "$DATE Starting $DISPMGR service"
        systemctl start "$DISPMGR.service"
    else
        if command -v sv; then
            logger "$DATE Starting $DISPMGR with sv"
            sv start "$DISPMGR"
        fi
    fi
done < "$input"

# Rebind VT consoles and log each console that is rebinding
consoleNumber=0
logger "$DATE Rebinding console $consoleNumber"
echo 1 > /sys/class/vtconsole/vtcon"${consoleNumber}"/bind
# input="/tmp/vfio-bound-consoles"
# while read -r consoleNumber; do
#     if test -x /sys/class/vtconsole/vtcon"${consoleNumber}"; then
#         if [ "$(grep -c "frame buffer" "/sys/class/vtconsole/vtcon${consoleNumber}/name")" = 1 ]; then
#             logger "$DATE Rebinding console $consoleNumber"
#             echo 1 > /sys/class/vtconsole/vtcon"${consoleNumber}"/bind
#         fi
#     fi
# done < "$input"

# Final log entry
logger "$DATE End of Teardown!"
