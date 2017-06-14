#!/bin/sh

##############################################################################################################
# Default settings:
##############################################################################################################

CAMERA=ov9650
use_usbserial=1    # Use a serial-over-USB to communicate with JeVois command-line interface
use_usbsd=1        # Expose the JEVOIS partition of the microSD as a USB drive
use_serialtty=0    # Use a TTY on the hardware serial and do not use it in jevois-daemon
use_usbserialtty=0 # Use a TTY on the serial-over-USB and do not use it in jevois-daemon

if [ -f /boot/nousbserial ]; then use_usbserial=0; echo "JeVois serial-over-USB disabled"; fi
if [ -f /boot/nousbsd ]; then use_usbsd=0; echo "JeVois microSD access over USB disabled"; fi

# Block device we present to the host as a USB drive, or empty to not present it at start:
usbsdfile=""
if [ -f /boot/usbsdauto ]; then usbsdfile="/dev/mmcblk0p3"; echo "JeVois microSD access over USB is AUTO"; fi

# Login prompts over hardware serial or serial-over-USB:
if [ -f /boot/serialtty ]; then use_serialtty=1; echo "Using tty on JeVois hardware serial"; fi
if [ "X${use_usbserial}" != "X1" ]; then use_usbserialtty=0;
elif [ -f /boot/usbserialtty ]; then use_usbserialtty=1; echo "Using tty on JeVois serial-over-USB"; fi

##############################################################################################################
# Fix Python-OpenCV library location if needed and pre-load Python and OpenCV so it is cached for faster startup
##############################################################################################################

if [ ! -f /usr/lib/python3.5/site-packages/cv2.so ]; then
    echo "Fixing OpenCV library location"
    # There is a flaw in the buildroot building of opencv, where the library file name still shows up as compiled for
    # whatever the host architecture was, even though it has been correctly cross-compiled for the JeVois ARM
    # processor. Here we fix that and also move the library to the python site-packages:
    mv /usr/python/3.5/cv2.cpython-35m-x86_64-linux-gnu.so /usr/lib/python3.5/site-packages/cv2.so
    sync
fi

##############################################################################################################
# Load all required kernel modules:
##############################################################################################################

cd /lib/modules/3.4.39

for m in videobuf-core videobuf-dma-contig videodev vfe_os vfe_subdev v4l2-common v4l2-int-device \
		       cci ${CAMERA} vfe_v4l2 ump disp mali ; do
    echo "### insmod ${m}.ko ###"
    insmod ${m}.ko
done

##############################################################################################################
# Install any new packages:
##############################################################################################################

cd /jevois
for f in packages/*.jvpkg; do
    if [ -f "${f}" ]; then
	echo "### Installing package ${f} ###"
	bzcat "${f}" | tar xvf -
	sync
	rm -f "${f}"
	sync
    fi
done

##############################################################################################################
# Find any newly unpacked postinstall scripts, run them, and delete them:
##############################################################################################################

for f in modules/*/*/postinstall; do
    if [ -f "${f}" ]; then
	echo "### Running ${f} ###"
	d=`dirname "${f}"`
	cd "${d}"
	sh postinstall
	sync
	rm -f postinstall
	sync
	cd /jevois
    fi
done

##############################################################################################################
# Build videomappings.cfg, if missing, from any info in the modules:
##############################################################################################################

if [ ! -f /jevois/config/videomappings.cfg ]; then
    cat /jevois/modules/*/*/videomappings.cfg > /jevois/config/videomappings.cfg
fi

##############################################################################################################
# Get a list of all our needed library paths:
##############################################################################################################

LIBPATH="/lib:/usr/lib:/jevois/lib"
for d in /jevois/lib/*; do if [ -d "${d}" ]; then LIBPATH="${LIBPATH}:${d}"; fi; done
export LD_LIBRARY_PATH=${LIBPATH}

##############################################################################################################
# Insert the gadget driver:
##############################################################################################################

echo "### Insert gadget driver ###"
MODES=`/jevois/bin/jevois-module-param`

insmodopts=""
#if [ "X${use_usbsd}" = "X1" -a "X${usbsdfile}" != "X" ]; then insmodopts="${insmodopts} file=${usbsdfile}"; fi
if [ "X${use_usbsd}" = "X1" ]; then insmodopts="${insmodopts} file=${usbsdfile}"; fi

insmod /lib/modules/3.4.39/g_jevoisa33.ko modes=${MODES} use_serial=${use_usbserial} \
       use_storage=${use_usbsd} ${insmodopts}

##############################################################################################################
# Launch jevois-daemon:
##############################################################################################################

echo "### Start jevois daemon ###"
opts=""
if [ "X${use_usbserial}" != "X1" -o "X${use_usbserialtty}" = "X1" ]; then opts="${opts} --usbserialdev="; fi
if [ "X${use_serialtty}" = "X1" ]; then opts="${opts} --serialdev="; fi

# Start the jevois daemon:
if [ "X${use_serialtty}" = "X1" -o "X${use_usbserialtty}" = "X1" ]; then
    /jevois/bin/jevois-daemon ${opts} &
else
    /jevois/bin/jevois-daemon ${opts}
fi

##############################################################################################################
# Launch any ttys:
##############################################################################################################
if [ "X${use_usbserialtty}" = "X1" ]; then
    while [ ! -c /dev/ttyGS0 ]; do sleep 1; done # wait until gadget is operational
    if [ "X${use_serialtty}" = "X1" ]; then
	/sbin/getty -L ttyGS0 115200 vt100 &
    else
	/sbin/getty -L ttyGS0 115200 vt100
    fi
fi

if [ "X${use_serialtty}" = "X1" ]; then
    /sbin/getty -L ttyS0 115200 vt100
fi
