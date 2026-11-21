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
#   PRESET            - apply one of the GUI's parameter presets on top (Presets menu):
#                       3 = "Velocity < 30 km/h, largest open spaces, fast motion"
#                       (cars, e.g. KITTI). Default: none.
#   SKIP_FIRST_FILE   - true/false: [filter_points] skip_first_file. HDMapping drops the
#                       first chunk by default (on Mandeye data the device standing
#                       still); set false for data moving from the first scan.
#                       Default: unset, HDMapping's own default.
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
PRESET="${PRESET:-}"
SKIP_FIRST_FILE="${SKIP_FIRST_FILE:-}"

usage() {
  echo "Usage: $0 <input.bag | hdmapping_dir> <output_dir>"
  echo
  echo "  input.bag     : ROS 1 bag — converted to HDMapping format first"
  echo "  hdmapping_dir : folder already in HDMapping (Mandeye) format — no conversion"
  echo
  echo "  PARAMS_FILE       - lidar odometry parameters (*.toml), default: HDMapping defaults"
  echo "  PRESET            - GUI parameter preset applied on top: 3 (< 30 km/h, open spaces), default: none"
  echo "  SKIP_FIRST_FILE   - true/false, drop the first chunk (default: HDMapping's default)"
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
echo "Parameters    : ${PARAMS_FILE:-HDMapping defaults}${PRESET:+, preset $PRESET}${SKIP_FIRST_FILE:+, skip_first_file = $SKIP_FIRST_FILE}"

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
if [[ -n "$PARAMS_FILE" || -n "$PRESET" || -n "$SKIP_FIRST_FILE" ]]; then
  # Parameters are prepared here and mounted read-only: PARAMS_FILE (or HDMapping's
  # defaults), then PRESET, then SKIP_FIRST_FILE. PARAMS_FILE itself is not changed.
  PARAMS_TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$PARAMS_TMP_DIR"' EXIT
  PARAMS_HOST="$PARAMS_TMP_DIR/params.toml"
  if [[ -n "$PARAMS_FILE" ]]; then
    cp "$PARAMS_FILE" "$PARAMS_HOST"
  else
    docker run --rm --user "$(id -u):$(id -g)" -v "$PARAMS_TMP_DIR":/params "$IMAGE_NAME" \
      lidar_odometry_step_1 --dump-default-params /params/params.toml >/dev/null
  fi
  # set_param <section> <key> <value>: sets key in [section], adding it if missing.
  set_param() {
    awk -v sec="[$1]" -v key="$2" -v val="$3" '
      function emit() { if (in_sec && !done) { print key " = " val; done = 1 } }
      /^\[/ { emit(); in_sec = ($0 == sec); seen = seen || in_sec }
      in_sec && $0 ~ "^" key " *=" { print key " = " val; done = 1; next }
      { print }
      END { emit(); if (!seen) { print ""; print sec; print key " = " val } }
    ' "$PARAMS_HOST" > "$PARAMS_HOST.new" && mv "$PARAMS_HOST.new" "$PARAMS_HOST"
  }
  case "$PRESET" in
    "") ;;
    3)
      # Presets > "3 Velocity < 30 km/h, largest open spaces, fast motion" (lidar_odometry_gui.cpp)
      set_param filter_points decimation 0.03
      for axis in X Y Z; do
        set_param in_out_params_indoor "resolution_$axis" 0.3
        set_param in_out_params_outdoor "resolution_$axis" 0.5
      done
      set_param filter_points filter_threshold_xy_inner 1.0
      set_param filter_points filter_threshold_xy_outer 70.0
      set_param filter_points threshould_output_filter 3.0
      set_param robust_lidar_odometry use_robust_and_accurate_lidar_odometry false
      set_param robust_lidar_odometry distance_bucket 0.2
      set_param robust_lidar_odometry polar_angle_deg 10.0
      set_param robust_lidar_odometry azimutal_angle_deg 10.0
      set_param robust_lidar_odometry robust_and_accurate_lidar_odometry_iterations 20
      set_param lidar_odometry_control max_distance_lidar 70.0
      set_param lidar_odometry_control nr_iter 500
      set_param lidar_odometry_control sliding_window_trajectory_length_threshold 200
      set_param performance real_time_threshold_seconds 10
      ;;
    *) echo "Error: unknown PRESET '$PRESET' (known: 3)"; exit 1 ;;
  esac
  case "$SKIP_FIRST_FILE" in
    "") ;;
    true|false) set_param filter_points skip_first_file "$SKIP_FIRST_FILE" ;;
    *) echo "Error: SKIP_FIRST_FILE must be true or false, not '$SKIP_FIRST_FILE'"; exit 1 ;;
  esac
  PARAMS_MOUNT=(-v "$PARAMS_HOST":/params/params.toml:ro)
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
    # lio_initial_poses.reg and nothing else: a second session file makes the
    # later steps ambiguous. The pose files have the same format, so they are
    # renamed, and session.json is session.mjs pointing at the standard names.
    cd /output/$OUTPUT_NAME
    if [[ -f session.json ]]; then
      echo '[session] session.json already written by HDMapping'
    elif [[ -f session.mjs ]]; then
      mv session_poses.mrp poses.reg
      mv session_ini_poses.mri lio_initial_poses.reg
      sed -e 's/session_poses\.mrp/poses.reg/g' -e 's/session_ini_poses\.mri/lio_initial_poses.reg/g' \
        session.mjs > session.json
      rm session.mjs
      echo '[session] session.mjs, session_poses.mrp, session_ini_poses.mri replaced by session.json, poses.reg, lio_initial_poses.reg'
    else
      echo 'ERROR: lidar_odometry_step_1 wrote neither session.json nor session.mjs'
      exit 1
    fi
  "

echo "=== DONE === Results in: $OUTPUT_HOST_DIR/$OUTPUT_NAME"
