# HDMapping_LIO to HDMapping simplified instruction

## Step 1 (prepare data)
Download the dataset `reg-1.bag` by clicking [link](https://cloud.cylab.be/public.php/dav/files/7PgyjbM2CBcakN5/reg-1.bag) (it is part of [Bunker DVI Dataset](https://charleshamesse.github.io/bunker-dvi-dataset)).

File `reg-1.bag` is an input for further calculations (HDMapping_LIO reads the raw Livox data, no conversion to `reg-1.bag-pc.bag` is needed).
It should be located in `~/hdmapping-benchmark/data`.

## Step 2 (prepare mandeye_to_bag converter)
HDMapping_LIO works on data in the HDMapping (Mandeye) format. The run script converts the bag with the [mandeye_to_bag](https://github.com/MapsHD/mandeye_to_bag) converter, so build its docker image first:
```shell
mkdir -p ~/hdmapping-benchmark
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/mandeye_to_bag.git --recursive
cd mandeye_to_bag
docker build -t mandeye-ws_noetic --target ros1 .
```

## Step 3 (prepare docker)
```shell
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/benchmark-HDMapping_LIO-to-HDMapping.git
cd benchmark-HDMapping_LIO-to-HDMapping
git checkout Bunker-DVI-Dataset-reg-1
docker build -t hdmapping-lio_standalone .
```

## Step 4 (run docker, file `reg-1.bag` should be in `~/hdmapping-benchmark/data`)
```shell
cd ~/hdmapping-benchmark/benchmark-HDMapping_LIO-to-HDMapping
chmod +x docker_session_run-hdmapping-lio.sh
cd ~/hdmapping-benchmark/data
~/hdmapping-benchmark/benchmark-HDMapping_LIO-to-HDMapping/docker_session_run-hdmapping-lio.sh reg-1.bag .
```

The script first converts `reg-1.bag` with mandeye_to_bag into `~/hdmapping-benchmark/data/converted_to_hdmapping`, then runs HDMapping's lidar odometry (`lidar_odometry_step_1`) in its command-line mode with HDMapping's default parameters.

If the data is already in HDMapping (Mandeye) format, e.g. `converted_to_hdmapping` from a previous run, pass that folder instead of the bag and the conversion is skipped:
```shell
cd ~/hdmapping-benchmark/data
~/hdmapping-benchmark/benchmark-HDMapping_LIO-to-HDMapping/docker_session_run-hdmapping-lio.sh converted_to_hdmapping .
```

To use your own parameters instead of the defaults, pass a TOML file (`lidar_odometry_step_1 --dump-default-params my_params.toml` writes the defaults as a starting point):
```shell
PARAMS_FILE=my_params.toml ~/hdmapping-benchmark/benchmark-HDMapping_LIO-to-HDMapping/docker_session_run-hdmapping-lio.sh reg-1.bag .
```

The same lidar odometry can also be run interactively in the HDMapping GUI, see this [movie](https://youtu.be/9AUvPTLUcos).

## Step 5 (Open and visualize data)
Expected data should appear in `~/hdmapping-benchmark/data/output_hdmapping-HDMapping_LIO`.
Use tool [multi_view_tls_registration_step_2](https://github.com/MapsHD/HDMapping) to open `session.json` from `~/hdmapping-benchmark/data/output_hdmapping-HDMapping_LIO`.

You should see the following data in folder `~/hdmapping-benchmark/data/output_hdmapping-HDMapping_LIO`:

lio_initial_poses.reg

poses.reg

scan_lio_*.laz

session.json

trajectory_lio_*.csv

## Contact email
januszbedkowski@gmail.com
