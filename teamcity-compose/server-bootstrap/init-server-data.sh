#!/bin/sh
set -eu

data_dir=/data/teamcity_server/datadir
config_dir="$data_dir/config"

mkdir -p "$config_dir/projects/_Root"
chown -R 1000:1000 "$data_dir"
