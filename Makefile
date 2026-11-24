# Makefile for the wildfire & power outages analysis pipeline.
#
# Pipeline:
#   analysis/0_data/<name>             -> download raw data into data/raw/
#   analysis/1_preprocessing/<name>.R  -> write data/processed/
#
# All scripts use paths relative to the project root, so always run make from
# the project root (that is where this file lives).

R           := Rscript
DATA        := analysis/0_data
PREP        := analysis/1_preprocessing
# Set NO_DOWNLOAD=1 to reuse whatever raw data is already on disk instead of
# (re)downloading it. Handy after editing a download script or when you only
# want to re-run preprocessing:
#
#   make NO_DOWNLOAD=1              # rebuild processed data, never download
#   make outages-with-viirs-image.parquet NO_DOWNLOAD=1
#
# `download` wraps each download recipe: with NO_DOWNLOAD set it skips the
# command and reuses the existing file, erroring only if it is actually missing.
NO_DOWNLOAD ?=
download = $(if $(NO_DOWNLOAD),@test -e $@ && echo "  NO_DOWNLOAD: reusing $@" || { echo "  NO_DOWNLOAD set but $@ is missing" >&2; exit 1; },$1)

PROCESSED := \
	data/processed/viirs-passes.csv \
	outages-with-viirs-image.parquet

QC_REPORT := qc/outages-with-viirs-image-qc.html

.PHONY: all data qc clean clean-processed clean-raw clean-figures help
.DELETE_ON_ERROR:

all: $(PROCESSED) $(QC_REPORT)           ## Build the dataset and render its QC report (default)

qc: $(QC_REPORT)                         ## Render the dataset QC report

data: data/raw/eagle-i/.stamp \
      data/raw/county/.stamp \
      data/raw/viirs-passes/.stamp \
	  data/raw/timezones-now.geojson           ## Download all raw data

# ---------------------------------------------------------------------------
# 0. Download raw data
# ---------------------------------------------------------------------------

# eagle-i.sh pulls many files from figshare via figshare_sync.sh, so we track a
# stamp rather than a single output file.
data/raw/eagle-i/.stamp: $(DATA)/eagle-i.sh $(DATA)/figshare_sync.sh
	$(call download,$(DATA)/eagle-i.sh)
	@touch $@

# counties.R downloads one county shapefile per year (2018-2025), so we track a
# stamp rather than a single output file.
data/raw/county/.stamp: $(DATA)/counties.R
	$(call download,$(R) $(DATA)/counties.R)
	@touch $@


data/raw/timezones-now.geojson: $(DATA)/tz.sh
	$(call download,$(DATA)/tz.sh)
	@touch $@

# The VIIRS downloader writes multiple pages and skips complete year/region sets.
data/raw/viirs-passes/.stamp: $(DATA)/viirs-passes.R
	$(call download,$(R) $<)
	@touch $@

# ---------------------------------------------------------------------------
# 1. Preprocess raw -> processed
# ---------------------------------------------------------------------------

data/processed/viirs-passes.csv: $(PREP)/viirs-passes.R data/raw/viirs-passes/.stamp data/raw/county/.stamp
	@mkdir -p $(@D)
	$(R) $<

data/processed/timezones/.stamp: $(PREP)/timezones.R data/raw/timezones-now.geojson data/raw/county/.stamp
	@mkdir -p $(@D) data/processed
	$(R) $<
	@touch $@

outages-with-viirs-image.parquet: $(PREP)/eagle-i.R data/raw/eagle-i/.stamp data/raw/county/.stamp data/processed/viirs-passes.csv data/processed/timezones/.stamp
	$(R) $<

$(QC_REPORT): qc/outages-with-viirs-image-qc.qmd outages-with-viirs-image.parquet
	quarto render $<

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

clean-processed:                         ## Remove processed outputs
	rm -f $(PROCESSED) $(QC_REPORT) data/processed/tz_lookup_*.csv data/processed/timezones/.stamp data/processed/eagle-i-viirs.parquet

clean-raw:                               ## Remove downloaded raw data
	rm -rf data/raw/eagle-i data/raw/county data/raw/viirs-passes data/raw/timezones-now.geojson data/raw/timezones-now.geojson.zip

clean-figures:                           ## Remove generated figures
	rm -rf figures/by_state figures/by_county figures/time_series

clean: clean-processed clean-raw clean-figures  ## Remove all generated data

help:                                    ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'