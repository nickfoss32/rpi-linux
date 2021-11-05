#!/bin/bash

## Environment variables ##
REPO_ROOT=`git rev-parse --show-toplevel`
MACHINE="raspberrypi4"
IMAGE="rpilinux-image"

################################################################################
# Help                                                                         #
################################################################################
Help()
{
   echo "Script for generating an embedded linux image for the Rapsberry Pi 4 using the Yocto Project."
   echo
   echo "Syntax: ./build.sh [-b|-d|-s|-o|-e|-p|-l|-c|-h]"
   echo "Options:"
   echo "-b|--build-dir                   Specifies separate directory to perform the build."
   echo "-d|--download-dir <DL_DIR>       Specifies directory where pre-downloaded sources reside."
   echo "-s|--sstate-cache <SSTATE_DIR>   Provide path to existing SSTATE cache."
   echo "-o|--offline-build               Configures BitBake to not fetch sources from the internet."
   echo "-e|--extended                    Configures BitBake to build extended (debug) image with analysis tools."
   echo "-p|--populate-sdk                Configures BitBake to generate SDK for the target."
   echo "-l|--list-pkgs                   Lists linux packages to be included in the image. Logs to packages.txt. Does not build."
   echo "-c|--config-only                 Configure BitBake to only generate a build configuration and exit."
   echo "-h|--help                        Prints this usage."
   echo
}


################################################################################
# FetchDependencies                                                            #
################################################################################
FetchDependencies()
{
   ## Update a dummy git repo with the manifest data ##
   mkdir -p manifests
   cd manifests
   git init
   cp $REPO_ROOT/default.xml .
   git add default.xml
   git commit -m "Updating manifest"
   cd ..
   MANIFEST_DIR="`pwd`/manifests"

   ## Configure repo w/ our manifest data ##
   repo init -u $MANIFEST_DIR -b master -m default.xml

   ## fetch our dependencies ##
   repo sync
}


################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

## Parse command line arguments ##
POSITIONAL=()
while [[ $# -gt 0 ]]; do
   key="$1"

   case $key in
      -b|--build-dir)
         BUILD_AREA="$2"
         shift # past argument
         shift # past value
         ;;
      -d|--download-dir)
         DOWNLOAD_DIR="$2"
         shift # past argument
         shift # past value
         ;;
      -s|--sstate-cache)
         SSTATE_CACHE="$2"
         shift # past argument
         shift # past value
         ;;
      -o|--offline-build)
         OFFLINE_BUILD=1
         shift # past argument
         ;;
      -e|--extended)
         EXTENDED_BLD=1
         shift # past argument
         ;;
      -p|--populate-sdk)
         POPULATE_SDK=1
         shift # past argument
         ;;
      -l|--list-pkgs)
         LIST_PKGS=1
         shift # past argument
         ;;
      -c|--config-only)
         CONFIG_ONLY=1
         shift # past argument
         ;;
      -h|--help)
         Help
         shift # past argument
         exit
         ;;
      *)    # unknown option
         shift # past argument
         ;;
   esac
done

## If specified, move into separate area to do the build ##
if [ -v BUILD_AREA ]; then
   cd $BUILD_AREA
fi

## Fetch all of our dependencies ##
FetchDependencies

## Clean up old build config files if they exist ##
if [ -f build/conf/local.conf ]; then
   rm build/conf/local.conf
fi

## Initialize bitbake environment ##
source ./poky/oe-init-build-env

## Configure layers necessary for build ##
bitbake-layers add-layer \
   ../meta-openembedded/meta-oe \
   ../meta-openembedded/meta-multimedia \
   ../meta-openembedded/meta-networking \
   ../meta-openembedded/meta-python \
   ../meta-raspberrypi \
   $REPO_ROOT/meta-rpilinux

## Set machine to build for ##
sed -i "s|^MACHINE ??= .*$|MACHINE = \"${MACHINE}\"|g" conf/local.conf

## If user SSTATE_CACHE was specified, update local.conf with its path ##
if [ -v SSTATE_CACHE ]; then
   sed -i "s|^#SSTATE_DIR ?= .*$|SSTATE_DIR = \"${SSTATE_CACHE}\"|g" conf/local.conf
fi

if [ -v OFFLINE_BUILD ]; then
   printf"\nBB_NO_NETWORK = \"1\"" >> conf/local.conf
else
   # for online builds, check connectivity via google instead of the default www.example.com
   printf "\nCONNECTIVITY_CHECK_URIS = \"https://www.google.com\"" >> conf/local.conf
fi

## If user DL_DIR was specified, update local.conf with its path ##
if [ -v DOWNLOAD_DIR ]; then
   sed -i "s|^#DL_DIR ?= .*$|DL_DIR = \"${DOWNLOAD_DIR}\"|g" conf/local.conf
fi

## Use RPM for package management ##
sed -i "s|^PACKAGE_CLASSES ?= .*$|PACKAGE_CLASSES = \"package_rpm\"|g" conf/local.conf

## Configure cross-compile host machine ##
sed -i "s|^#SDKMACHINE ?= .*$|SDKMACHINE = \"x86_64\"|g" conf/local.conf

## Specify kernel source ##
#printf "\nPREFERRED_PROVIDER_virtual/kernel = \"linux-yocto-rt\"\n" >> conf/local.conf

## Instruct BitBake to produce a fitImage ##
# printf "\nKERNEL_CLASSES = \"kernel-fitimage\"" >> conf/local.conf
# printf "\nKERNEL_IMAGETYPE = \"fitImage\"" >> conf/local.conf
# printf "\nKERNEL_IMAGETYPE_UBOOT = \"fitImage\"" >> conf/local.conf
# printf "\nKERNEL_FITCONFIG = \"conf@bcm2711-rpi-4-b.dtb\"" >> conf/local.conf
# printf "\nKERNEL_BOOTCMD = \"bootm\"\n" >> conf/local.conf

## Specify what packages are included in the image ##
CORE_PACKAGES="nfs-utils"
DEBUG_PACKAGES="lshw tcpdump"
PACKAGES=$CORE_PACKAGES

## Add debug packages if a debug build was specified
if [ -v EXTENDED_BLD ]; then
   PACKAGES="$PACKAGES $DEBUG_PACKAGES"
fi

## Instruct BitBake to add additional packages ##
printf "\nIMAGE_INSTALL_append += \" $PACKAGES\"\n" >> conf/local.conf

## Enable UART on the raspberry pi ##
printf "\nENABLE_UART = \"1\"\n" >> conf/local.conf

## Boot with u-boot ##
# printf "\nRPI_USE_U_BOOT = \"1\"\n" >> conf/local.conf

# ## Use systemd as init manager ##
# printf "\nDISTRO_FEATURES_append = \" systemd\"" >> conf/local.conf
# printf "\nVIRTUAL-RUNTIME_init_manager = \"systemd\"" >> conf/local.conf
# printf "\nDISTRO_FEATURES_BACKFILL_CONSIDERED = \"sysvinit\"" >> conf/local.conf
# printf "\nVIRTUAL-RUNTIME_initscripts = \"\"\n" >> conf/local.conf

## Fetch packages to be included in the image and log to packages.txt ##
if [[ -v LIST_PKGS ]]; then
   bitbake -g $IMAGE && cat pn-buildlist | grep -ve "native" | sort | uniq > packages.txt
fi

if [[ ! -v CONFIG_ONLY ]]; then
   ## Generate SDK if requested ##
   if [[ -v POPULATE_SDK ]]; then
      bitbake $IMAGE -c populate_sdk

   ## Build the embedded linux distribution ##
   else
      bitbake $IMAGE
   fi
fi

