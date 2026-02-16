# benchmark-HDMapping_LIO-to-HDMapping

## Step 1 (download mobile mapping LiDAR data that includes LiVOX MID360)
Download the dataset `reg-1.bag` by clicking [link](https://cloud.cylab.be/public.php/dav/files/7PgyjbM2CBcakN5/reg-1.bag) (it is part of [Bunker DVI Dataset](https://charleshamesse.github.io/bunker-dvi-dataset))

Create 'output_hdmapping' folder and copy downloaded data with following commands:

```shell
mkdir -p ~/hdmapping-benchmark/data/output_hdmapping
cd ~/hdmapping-benchmark/data/output_hdmapping
cp <download_folder>/reg-1.bag .
```

## Step 3 (prepare code)
```shell
mkdir -p ~/hdmapping-benchmark
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/mandeye_to_bag.git --recursive
```

## Step 4 (build docker)
```shell
cd ~/hdmapping-benchmark/mandeye_to_bag
docker build -t mandeye-ws_noetic --target ros1 .
```

## Step 5 (run docker)
```shell
mkdir -p ~/hdmapping-benchmark/data/output_hdmapping/converted_to_hdmapping
cd ~/hdmapping-benchmark/mandeye_to_bag
chmod +x mandeye-convert.sh
./mandeye-convert.sh ~/hdmapping-benchmark/data/output_hdmapping/reg-1.bag ~/hdmapping-benchmark/data/output_hdmapping/converted_to_hdmapping ros1-to-hdmapping
```

## Step 6 (run HDMapping-LIO)
```shell
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/benchmark-HDMapping_LIO-to-HDMapping --recursive
cd benchmark-HDMapping_LIO-to-HDMapping
git checkout Bunker-DVI-Dataset-reg-1
docker build -t hdmapping-lio .
chmod +x docker_session_run-ros2-hdmapping-lio.sh
cd ~/hdmapping-benchmark/data/output_hdmapping
~/hdmapping-benchmark/benchmark-HDMapping_LIO-to-HDMapping/docker_session_run-ros2-hdmapping-lio.sh converted_to_hdmapping .
```

Expected data should appear in ~/hdmapping-benchmark/data/output_hdmapping/output_hdmapping-hdmapping-lio.

If you want to use HDMapping-LIO GUI, follow procedure in this [[movie]](https://youtu.be/9AUvPTLUcos).

## Contact email
januszbedkowski@gmail.com
