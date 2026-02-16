#!/bin/bash

IMAGE_NAME='hdmapping-lio'

DATASET_CONTAINER_PATH='/opt/dataset'
OUTPUT_CONTAINER_PATH='/opt/output'

usage() {
  echo "Usage:"
  echo "  $0 <input_dir> <output_dir>"
  echo
  echo "Input: HDMapping format directory (containing *.laz and imu_*.csv)"
  echo
  echo "If no arguments are provided, a GUI file selector will be used."
  exit 1
}

echo "=== HDMapping-LIO pipeline ==="

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

if [[ $# -eq 2 ]]; then
  DATASET_HOST_PATH="$1"
  OUTPUT_HOST="$2"
elif [[ $# -eq 0 ]]; then
  command -v zenity >/dev/null || {
    echo "Error: zenity is not available"
    exit 1
  }
  DATASET_HOST_PATH=$(zenity --file-selection --directory --title="Select input directory")
  OUTPUT_HOST=$(zenity --file-selection --directory --title="Select output directory")
else
  usage
fi

if [[ -z "$DATASET_HOST_PATH" || -z "$OUTPUT_HOST" ]]; then
  echo "Error: no file or directory selected"
  exit 1
fi

if [[ ! -d "$DATASET_HOST_PATH" ]]; then
  echo "Error: input directory does not exist: $DATASET_HOST_PATH"
  exit 1
fi

mkdir -p "$OUTPUT_HOST"

DATASET_HOST_PATH=$(realpath "$DATASET_HOST_PATH")
OUTPUT_HOST=$(realpath "$OUTPUT_HOST")

echo "Input dir     : $DATASET_HOST_PATH"
echo "Output dir    : $OUTPUT_HOST"

xhost +local:docker >/dev/null

docker run -it --rm \
  --network host \
  -e DISPLAY=$DISPLAY \
  -e ROS_HOME=/tmp/.ros \
  -u 1000:1000 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$DATASET_HOST_PATH":"$DATASET_CONTAINER_PATH":ro \
  -v "$OUTPUT_HOST":"$OUTPUT_CONTAINER_PATH" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    set -e

    echo '=== Running HDMapping LIO ==='
    rm -rf ${OUTPUT_CONTAINER_PATH}/output_hdmapping-hdmapping-lio
    mkdir -p ${OUTPUT_CONTAINER_PATH}/output_hdmapping-hdmapping-lio

    /opt/HDMapping/build/bin/lidar_odometry_step_1 \
      $DATASET_CONTAINER_PATH \
      /opt/default_params.toml \
      ${OUTPUT_CONTAINER_PATH}/output_hdmapping-hdmapping-lio

    echo ''
    echo '=== Output files ==='
    ls -la ${OUTPUT_CONTAINER_PATH}/output_hdmapping-hdmapping-lio/
  "

echo "=== DONE ==="
