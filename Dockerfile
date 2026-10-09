# HDMapping lidar odometry (lidar_odometry_step_1) for the benchmark.
#
# The app has a GUI, but the benchmark uses its command-line mode, which runs
# the full odometry and saves the HDMapping session without opening a window:
#   lidar_odometry_step_1 <input_folder> <parameter_file.toml> <output_folder>
#   lidar_odometry_step_1 --dump-default-params <file.toml>
#
# Build recipe follows the orchestration's HDMapping build (conversion_tum_step4),
# with every package HDMapping's own Linux CI installs (.github/workflows/cmake-linux.yml),
# plus liblz4-dev and libzstd-dev: HDMapping's bundled mcap (MCAP exporter, since
# commit 640402a) refuses to configure without them on Linux, and unlike GitHub's
# CI runners a plain ubuntu:24.04 image does not ship them.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    cmake \
    git \
    wget \
    pkg-config \
    libeigen3-dev \
    libtbb-dev \
    liblaszip-dev \
    libproj-dev \
    proj-bin \
    libopencv-dev \
    libopencv-contrib-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    mesa-common-dev \
    xorg-dev \
    libx11-dev \
    libxi-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxxf86vm-dev \
    libglx-dev \
    libopengl-dev \
    libgl-dev \
    libglut-dev \
    libegl1-mesa-dev \
    libxext-dev \
    liblz4-dev \
    libzstd-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.sh && \
    chmod +x cmake-4.0.0-linux-x86_64.sh && \
    ./cmake-4.0.0-linux-x86_64.sh --prefix=/usr/local --skip-license && \
    rm cmake-4.0.0-linux-x86_64.sh

# HDMapping version to benchmark: a branch, tag or commit.
ARG HDMAPPING_REF=main

WORKDIR /workspace
RUN git clone --recursive https://github.com/MapsHD/HDMapping.git && \
    cd HDMapping && \
    git checkout "$HDMAPPING_REF" && \
    git submodule update --init --recursive

WORKDIR /workspace/HDMapping
# The binary's output folder depends on the build configuration, so it is
# located with find and linked onto PATH. Running --help fails the build if
# the binary cannot start (e.g. a missing shared library).
RUN mkdir -p build && cd build && \
    cmake .. && \
    cmake --build . --target lidar_odometry_step_1 -j$(nproc) && \
    BIN="$(find /workspace/HDMapping/build -type f -name lidar_odometry_step_1 -perm -u+x | head -1)" && \
    test -n "$BIN" && \
    ln -s "$BIN" /usr/local/bin/lidar_odometry_step_1 && \
    lidar_odometry_step_1 --help > /dev/null

CMD ["bash"]
