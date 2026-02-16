FROM ubuntu:22.04

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git \
    curl gnupg2 lsb-release software-properties-common \
    libeigen3-dev \
    libtbb-dev \
    libopencv-dev \
    freeglut3-dev \
    libglew-dev \
    libglm-dev \
    python3-pip \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Install newer CMake (HDMapping requires >= 4.0.0)
RUN pip3 install cmake==4.0.3

WORKDIR /opt

# Build HDMapping (from local source with Linux fixes)
COPY src/HDMapping /opt/HDMapping
RUN cd HDMapping \
    && rm -rf build && mkdir -p build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release \
    && make -j$(nproc)

# Copy default parameters
COPY default_params.toml /opt/default_params.toml

ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID hdmap && \
    useradd -m -u $UID -g $GID -s /bin/bash hdmap && \
    mkdir -p /opt/output && \
    chown $UID:$GID /opt/output

WORKDIR /opt

CMD ["bash"]
