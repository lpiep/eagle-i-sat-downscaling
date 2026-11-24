#!/usr/bin/env bash
set -euo pipefail

mkdir -p data/raw
wget -O data/raw/timezones-now.geojson.zip https://github.com/evansiroky/timezone-boundary-builder/releases/download/2026f/timezones-now.geojson.zip
unzip data/raw/timezones-now.geojson.zip -d data/raw
mv data/raw/combined-now.json data/raw/timezones-now.geojson
rm data/raw/timezones-now.geojson.zip
