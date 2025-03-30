#!/bin/bash

################################# Variables #################################

## --- USER CONFIGURATION: USB Controller --- ##
USB_HOST_DRIVER="xhci_hcd"       # <--- Usually xhci_hcd, change if different (e.g., ehci_hcd)
## --- End User Configuration --- ##

## Adds current time to var for use in echo for a cleaner log and script ##
DATE=$(date +"%m/%d/%Y %R:%S :")

## Sets dispmgr var as null ##
DISPMGR="null"

################################## Script ###################################

logger "$DATE Beginning of Startup!"


function stop_display_manager_if_running {
    ## Get display manager on systemd based distros ##
    if [[ -x /run/systemd/system ]] && logger "$DATE Distro is using Systemd"; then
        DISPMGR="$(grep 'ExecStart=' /etc/systemd/system/display-manager.service | awk -F'/' '{print $(NF-0)}')"
        logger "$DATE Display Manager = $DISPMGR"

        ## Stop display manager using systemd ##
        if systemctl is-active --quiet "$DISPMGR.service"; then
            grep -qsF "$DISPMGR" "/tmp/vfio-store-display-manager" || echo "$DISPMGR" >/tmp/vfio-store-display-manager
            systemctl stop "$DISPMGR.service"
            systemctl isolate multi-user.target
        fi

        while systemctl is-active --quiet "$DISPMGR.service"; do
            sleep "1"
        done

        return

    fi

}

function kde-clause {

    logger "$DATE Display Manager = display-manager"

    ## Stop display manager using systemd ##
    if systemctl is-active --quiet "display-manager.service"; then
    
        grep -qsF "display-manager" "/tmp/vfio-store-display-manager"  || echo "display-manager" >/tmp/vfio-store-display-manager
        systemctl stop "display-manager.service"
    fi

        while systemctl is-active --quiet "display-manager.service"; do
            sleep 2
        done

    return

}

####################################################################################################################
## Checks to see if your running KDE. If not it will run the function to collect your display manager.            ##
## Have to specify the display manager because kde is weird and uses display-manager even though it returns sddm. ##
####################################################################################################################

if pgrep -l "plasma" | grep "plasmashell"; then
    logger "$DATE Display Manager is KDE, running KDE clause!"
    kde-clause
    else
        logger "$DATE Display Manager is not KDE!"
        stop_display_manager_if_running
fi

## Unbind EFI-Framebuffer ##
if test -e "/tmp/vfio-is-nvidia"; then
    rm -f /tmp/vfio-is-nvidia
    else
        test -e "/tmp/vfio-is-amd"
        rm -f /tmp/vfio-is-amd
fi

sleep "1"

##############################################################################################################################
## Unbind VTconsoles if currently bound (adapted and modernised from https://www.kernel.org/doc/Documentation/fb/fbcon.txt) ##
##############################################################################################################################
logger "$DATE Unbinding Console 0"
echo 0 > /sys/class/vtconsole/vtcon0/bind

# if test -e "/tmp/vfio-bound-consoles"; then
#     rm -f /tmp/vfio-bound-consoles
# fi
# for (( i = 0; i < 16; i++))
# do
#   if test -x /sys/class/vtconsole/vtcon"${i}"; then
#       if [ "$(grep -c "frame buffer" /sys/class/vtconsole/vtcon"${i}"/name)" = 1 ]; then
# 	       echo 0 > /sys/class/vtconsole/vtcon"${i}"/bind
#            logger "$DATE Unbinding Console ${i}"
#            echo "$i" >> /tmp/vfio-bound-consoles
#       fi
#   fi
# done

sleep "1"

if lspci -nn | grep -e VGA | grep -s NVIDIA ; then
    logger "$DATE System has an NVIDIA GPU"
    grep -qsF "true" "/tmp/vfio-is-nvidia" || echo "true" >/tmp/vfio-is-nvidia
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

    ## Unload NVIDIA GPU drivers ##
    modprobe -r nvidia_uvm
    modprobe -r nvidia_drm
    modprobe -r nvidia_modeset
    modprobe -r nvidia
    modprobe -r i2c_nvidia_gpu
    modprobe -r drm_kms_helper
    modprobe -r drm

    logger "$DATE NVIDIA GPU Drivers Unloaded"
fi

# if lspci -nn | grep -e VGA | grep -s AMD ; then
#     logger "$DATE System has an AMD GPU"
#     grep -qsF "true" "/tmp/vfio-is-amd" || echo "true" >/tmp/vfio-is-amd
#     echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

#     ## Unload AMD GPU drivers ##
#     modprobe -r drm_kms_helper
#     modprobe -r amdgpu
#     modprobe -r radeon
#     modprobe -r drm

#     logger "$DATE AMD GPU Drivers Unloaded"
# fi

## Load VFIO-PCI driver ##
modprobe vfio vfio_pci vfio_iommu_type1 || logger "$DATE Failed to load vfio modules"

sleep 1

## --- USB Controller Passthrough --- ##

usb_controller_passthrough() {
    local DATE="$1"
    local USB_CONTROLLER_PCI="$2"
    local USB_HOST_DRIVER="$3"

    logger "$DATE Starting USB Controller Passthrough for $USB_CONTROLLER_PCI"

    # Verify vfio_pci driver is loaded and path exists
    [ -d /sys/bus/pci/drivers/vfio-pci ] || { 
        logger "$DATE ERROR: vfio-pci driver sysfs path not found!"; 
    }

    if [ -L "/sys/bus/pci/devices/$USB_CONTROLLER_PCI/driver" ]; then
        CURRENT_DRIVER=$(basename "$(readlink -f "/sys/bus/pci/devices/$USB_CONTROLLER_PCI/driver")")
        [ "$CURRENT_DRIVER" = "vfio-pci" ] && {
            logger "$DATE INFO: Already bound to vfio-pci."; return 0;
        }
        [ "$CURRENT_DRIVER" = "$USB_HOST_DRIVER" ] && {
            logger "$DATE Unbinding from $USB_HOST_DRIVER";
            echo "$USB_CONTROLLER_PCI" > "/sys/bus/pci/drivers/$USB_HOST_DRIVER/unbind"
            sleep 0.5
        }
    fi
}

usb_device_passthrough() {
    local VENDOR_ID="$2" DEVICE_ID="$3"
    logger "$1 Binding to vfio-pci"
    echo "$VENDOR_ID $DEVICE_ID" > /sys/bus/pci/drivers/vfio-pci/new_id || {
        logger "$DATE ERROR: Failed to bind via new_id."; return 1;
    }
}

usb_controller_passthrough "$DATE" "73:00.0" "$USB_HOST_DRIVER"
usb_controller_passthrough "$DATE" "76:00.4" "$USB_HOST_DRIVER"
# Genesys
usb_device_passthrough "$DATE" "0x05e3" "0x0610"
# Terminus
usb_device_passthrough "$DATE" "0x1a40" "0x0101"
# Focusrite
usb_device_passthrough "$DATE" "0x1235" "0x8214"
# Mouse
usb_device_passthrough "$DATE" "0x30fa" "0x1701"
# Keyboard
usb_device_passthrough "$DATE" "0x046d" "0xc317"

## --- End USB Controller Passthrough --- ##

logger "$DATE End of Startup!"
