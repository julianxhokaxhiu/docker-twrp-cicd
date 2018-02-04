#!/bin/bash
#
# Build script
#
###########################################################

DOCKER_LOG=/var/log/docker.log
DEBUG_LOG=/dev/null
if [ "$DEBUG" = true ]; then
  DEBUG_LOG=$DOCKER_LOG
fi

if ! [ -z "$DEVICE_LIST" ]; then

  # cd to working directory
  cd $SRC_DIR

  # If the source directory is empty
  if ! [ "$(ls -A $SRC_DIR)" ]; then
    # Initialize repository
    echo ">> [$(date)] Initializing repository" >> $DOCKER_LOG
    yes | repo init -u git://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git -b $BRANCH_NAME 2>&1 >&$DEBUG_LOG
  fi

  # Copy local manifests to the appropriate folder in order take them into consideration
  echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '$SRC_DIR/.repo/local_manifests/'" >> $DOCKER_LOG
  mkdir -p $SRC_DIR/.repo/local_manifests
  cp $LMANIFEST_DIR/*.xml $SRC_DIR/.repo/local_manifests/ >&$DEBUG_LOG

  # Go to "vendor/cm" and reset it's current git status ( remove previous changes ) only if the directory exists
  if [ -d "vendor/cm" ]; then
    cd vendor/cm
    git reset --hard 2>&1 >&$DEBUG_LOG
    cd $SRC_DIR
  fi

  # Sync the source code
  echo ">> [$(date)] Syncing repository" >> $DOCKER_LOG
  repo sync -f 2>&1 >&$DEBUG_LOG

  # If requested, clean the OUT dir in order to avoid clutter
  if [ "$CLEAN_OUTDIR" = true ]; then
    echo ">> [$(date)] Cleaning '$IMG_DIR'" >> $DOCKER_LOG
    cd $IMG_DIR
    rm * 2>&1 >&$DEBUG_LOG
    cd $SRC_DIR
  fi

  # Prepare the environment
  echo ">> [$(date)] Preparing build environment" >> $DOCKER_LOG
  source build/envsetup.sh 2>&1 >&$DEBUG_LOG

  # Fetch TWRP version
  TWRP_VERSION=`sed -n 's/#define TW_MAIN_VERSION_STR[ ]*"//p' $SRC_DIR/bootable/recovery/variables.h | sed "s/\"//g"`

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    if ! [ -z "$codename" ]; then
      # Start the build
      echo ">> [$(date)] Starting build for $codename" >> $DOCKER_LOG
      lunch omni_$codename-eng 2>&1 >&$DEBUG_LOG
      if mka recoveryimage 2>&1 >&$DEBUG_LOG; then
        # Move produced IMG files to the main OUT directory
        echo ">> [$(date)] Moving build artifacts for $codename to '$IMG_DIR/twrp-$TWRP_VERSION-0-$codename.img'" >> $DOCKER_LOG
        cd $SRC_DIR
        find out/target/product/$codename -name 'recovery.img' -exec cp {} $IMG_DIR/twrp-$TWRP_VERSION-0-$codename.img \; >&$DEBUG_LOG
      else
        echo ">> [$(date)] Failed build for $codename" >> $DOCKER_LOG
      fi
      # Clean everything, in order to start fresh on next build
      if [ "$CLEAN_AFTER_BUILD" = true ]; then
        echo ">> [$(date)] Cleaning build for $codename" >> $DOCKER_LOG
        mka clean 2>&1 >&$DEBUG_LOG
      fi
      echo ">> [$(date)] Finishing build for $codename" >> $DOCKER_LOG
    fi
  done

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi
