#!/bin/bash
# Runs HDMapping's lidar odometry on a ROS 1 bag and stores the HDMapping
# session, following the manual procedure in README.md without the GUI:
#
#   1. Convert the bag to HDMapping (Mandeye) format with mandeye_to_bag's
#      rosbag_to_mandeye (image mandeye-ws_noetic, built from
#      https://github.com/MapsHD/mandeye_to_bag with --target ros1).
#      Skipped when the input is a folder already in HDMapping format.
#   2. Run lidar_odometry_step_1 in its command-line mode and save the session
#      to <output_dir>/output_hdmapping-HDMapping_LIO.
#
# Usage:
#   ./docker_session_run-hdmapping-lio.sh <input.bag | hdmapping_dir> <output_dir>
#
#   input.bag     : ROS 1 bag — converted to HDMapping format first
#   hdmapping_dir : folder already in HDMapping (Mandeye) format (*.laz +
#                   imu *.csv, e.g. the output of mandeye_to_bag's
#                   ros1-to-hdmapping) — used directly, no conversion
#
# Environment variables:
#   PARAMS_FILE       - lidar odometry parameters (*.toml); default: HDMapping's
#                       default parameters (lidar_odometry_step_1 --dump-default-params)
#   POINTCLOUD_TOPIC  - Livox point cloud topic in the bag (default: /livox/lidar)
#   IMU_TOPIC         - IMU topic in the bag (default: /livox/imu)

set -e

IMAGE_NAME='hdmapping-lio_standalone'
CONVERT_IMAGE='mandeye-ws_noetic'
OUTPUT_NAME='output_hdmapping-HDMapping_LIO'
CONVERTED_NAME='converted_to_hdmapping'

POINTCLOUD_TOPIC="${POINTCLOUD_TOPIC:-/livox/lidar}"
IMU_TOPIC="${IMU_TOPIC:-/livox/imu}"
PARAMS_FILE="${PARAMS_FILE:-}"

usage() {
  echo "Usage: $0 <input.bag | hdmapping_dir> <output_dir>"
  echo
  echo "  input.bag     : ROS 1 bag — converted to HDMapping format first"
  echo "  hdmapping_dir : folder already in HDMapping (Mandeye) format — no conversion"
  echo
  echo "  PARAMS_FILE       - lidar odometry parameters (*.toml), default: HDMapping defaults"
  echo "  POINTCLOUD_TOPIC  - Livox point cloud topic (default: /livox/lidar)"
  echo "  IMU_TOPIC         - IMU topic (default: /livox/imu)"
  exit 1
}

[[ "$1" == "-h" || "$1" == "--help" || $# -ne 2 ]] && usage

DATASET_HOST_PATH=$(realpath "$1")
OUTPUT_HOST_DIR=$(realpath -m "$2")

# A folder is data already in HDMapping (Mandeye) format; a file is a ROS 1 bag.
if [[ -d "$DATASET_HOST_PATH" ]]; then
  INPUT_IS_DIR=1
  if ! compgen -G "$DATASET_HOST_PATH/*.laz" > /dev/null || ! compgen -G "$DATASET_HOST_PATH/*.csv" > /dev/null; then
    echo "Error: $DATASET_HOST_PATH is not in HDMapping (Mandeye) format"
    echo "       (expected point clouds *.laz and IMU *.csv, e.g. pointcloud_0000.laz, imu_0000.csv)"
    exit 1
  fi
elif [[ -f "$DATASET_HOST_PATH" ]]; then
  INPUT_IS_DIR=0
else
  echo "Error: input does not exist: $DATASET_HOST_PATH"
  exit 1
fi
if [[ -n "$PARAMS_FILE" && ! -f "$PARAMS_FILE" ]]; then
  echo "Error: PARAMS_FILE does not exist: $PARAMS_FILE"
  exit 1
fi
REQUIRED_IMAGES=("$IMAGE_NAME")
[[ "$INPUT_IS_DIR" == "0" ]] && REQUIRED_IMAGES+=("$CONVERT_IMAGE")
for image in "${REQUIRED_IMAGES[@]}"; do
  if ! docker image inspect "$image" > /dev/null 2>&1; then
    echo "Error: docker image '$image' not found."
    [[ "$image" == "$CONVERT_IMAGE" ]] && echo "Build it from https://github.com/MapsHD/mandeye_to_bag: docker build -t $CONVERT_IMAGE --target ros1 ."
    [[ "$image" == "$IMAGE_NAME" ]] && echo "Build it in this repository: docker build -t $IMAGE_NAME ."
    exit 1
  fi
done

mkdir -p "$OUTPUT_HOST_DIR"
DATASET_DIR=$(dirname "$DATASET_HOST_PATH")
DATASET_FILE=$(basename "$DATASET_HOST_PATH")

echo "Input         : $DATASET_HOST_PATH ($([[ $INPUT_IS_DIR == 1 ]] && echo 'HDMapping-format folder, no conversion' || echo 'ROS 1 bag, converted first'))"
echo "Output dir    : $OUTPUT_HOST_DIR/$OUTPUT_NAME"
echo "Parameters    : ${PARAMS_FILE:-HDMapping defaults}"

# ---------- 1. bag -> HDMapping (Mandeye) format ----------
if [[ "$INPUT_IS_DIR" == "1" ]]; then
  echo "=== [1/2] Input is already in HDMapping format, skipping the conversion ==="
  HDMAPPING_INPUT_HOST="$DATASET_HOST_PATH"
  # lidar_odometry_step_1 keeps its chunk cache in <input folder>/cache and
  # never clears it; drop a previous run's cache in a reused folder.
  rm -rf "$HDMAPPING_INPUT_HOST/cache"
else
  echo "=== [1/2] Converting the bag to HDMapping format ==="
  HDMAPPING_INPUT_HOST="$OUTPUT_HOST_DIR/$CONVERTED_NAME"
  rm -rf "$HDMAPPING_INPUT_HOST"
  mkdir -p "$HDMAPPING_INPUT_HOST"
  docker run --rm \
    --user 1000:1000 \
    -v "$DATASET_DIR":/mandeye_ws/dataset:ro \
    -v "$HDMAPPING_INPUT_HOST":/mandeye_ws/output \
    "$CONVERT_IMAGE" \
    /bin/bash -c "
      set -e
      source /opt/ros/noetic/setup.bash
      source /mandeye_ws/devel/setup.bash
      rosrun mandeye_to_rosbag1 rosbag_to_mandeye /mandeye_ws/dataset/$DATASET_FILE /mandeye_ws/output \
        --pointcloud_topic $POINTCLOUD_TOPIC --imu_topic $IMU_TOPIC
    "
fi

# ---------- 2. HDMapping lidar odometry, command-line mode ----------
echo "=== [2/2] Running HDMapping lidar odometry ==="
rm -rf "$OUTPUT_HOST_DIR/$OUTPUT_NAME"
PARAMS_MOUNT=()
PARAMS_IN_CONTAINER=/tmp/lidar_odometry_default_params.toml
if [[ -n "$PARAMS_FILE" ]]; then
  PARAMS_MOUNT=(-v "$(realpath "$PARAMS_FILE")":/params/params.toml:ro)
  PARAMS_IN_CONTAINER=/params/params.toml
fi
# The HDMapping-format input is mounted read-write: lidar_odometry_step_1
# creates its chunk cache in <input folder>/cache.
docker run --rm \
  --user 1000:1000 \
  -v "$HDMAPPING_INPUT_HOST":/input \
  -v "$OUTPUT_HOST_DIR":/output \
  "${PARAMS_MOUNT[@]}" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    set -e
    if [[ ! -f $PARAMS_IN_CONTAINER ]]; then
      lidar_odometry_step_1 --dump-default-params $PARAMS_IN_CONTAINER
    fi
    mkdir -p /output/$OUTPUT_NAME
    lidar_odometry_step_1 /input $PARAMS_IN_CONTAINER /output/$OUTPUT_NAME

    # HDMapping saves its session as session.mjs with session_poses.mrp and
    # session_ini_poses.mri. The benchmark, like every other algorithm's
    # output_hdmapping-* folder, uses session.json with poses.reg and
    # lio_initial_poses.reg. The pose files have the same format, so they are
    # copied, and session.json is session.mjs pointing at the standard names.
    cd /output/$OUTPUT_NAME
    if [[ -f session.json ]]; then
      echo '[session] session.json already written by HDMapping'
    elif [[ -f session.mjs ]]; then
      cp session_poses.mrp poses.reg
      cp session_ini_poses.mri lio_initial_poses.reg
      sed -e 's/session_poses\.mrp/poses.reg/g' -e 's/session_ini_poses\.mri/lio_initial_poses.reg/g' \
        session.mjs > session.json
      echo '[session] session.json, poses.reg, lio_initial_poses.reg written from session.mjs'
    else
      echo 'ERROR: lidar_odometry_step_1 wrote neither session.json nor session.mjs'
      exit 1
    fi
  "

echo "=== DONE === Results in: $OUTPUT_HOST_DIR/$OUTPUT_NAME"
