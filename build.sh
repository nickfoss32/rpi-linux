#!/bin/bash

## Parse command line arguments ##
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -s|--sstate-cache)
      SSTATE_CACHE="$2"
      shift # past argument
      shift # past value
      ;;
    *)    # unknown option
      shift # past argument
      ;;
  esac
done

## Initialize bitbake environment ##
source ./poky/oe-init-build-env

## If user SSTATE_CACHE was specified, update local.conf with its path ##
if [ -v SSTATE_CACHE ]; then
   sed -i "s|#SSTATE_DIR|SSTATE_DIR|g; s|${TOPDIR}/sstate-cache|${SSTATE_CACHE}|g" conf/local.conf
   sed -i 's|${TOPDIR}||g' conf/local.conf
fi

## Configure layers necessary for build ##
bitbake-layers add-layer \
   ../meta-openembedded/meta-oe \
   ../meta-openembedded/meta-multimedia \
   ../meta-openembedded/meta-networking \
   ../meta-openembedded/meta-python \
   ../meta-raspberrypi \
   ../meta-rpilinux

## Execute bitbake ##
MACHINE=raspberrypi2 ENABLE_UART=1 bitbake rpilinux-image
