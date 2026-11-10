# Eagle-I Preproccessing for Satellite Downscaling

## Setup and Run

Cloning this repo and running `make` should rebuild all the data sets and figures (can take a few hours).

### Analysis code

- `analysis/0_data` scripts to download each source data set
- `analysis/1_preprocessing` scripts to turn each data set into a binary daily exposure, then merge
- `analysis/2_figures` scripts to produce figures (not just the main figure for the paper)

### Data

Not on Github. Will be populated when you run `make`. Gets to about 24 GB. 

- `data/raw` produced by `analysis/0_data`
- `data/processed` produced by `analysis/1_preprocessing`
