# Eagle-I Outages with VIIRS Passes

## Setup and run

Run `make` from the repository root to download the inputs, build
`outages-with-viirs-image.parquet` in the repository root, and render the QC
report to `qc/outages-with-viirs-image-qc.html`. The downloads and
preprocessing can take several hours and require a Census API key configured
for `tidycensus` as `CENSUS_API_KEY`.

If the raw inputs are already present and should not be downloaded again, run:

```sh
make NO_DOWNLOAD=1
```

The pipeline downloads Eagle-I outage data, county boundaries, time-zone
boundaries, and VIIRS granule metadata. It builds VIIRS-to-county and
county-to-time-zone lookup tables before producing the final Parquet file.
Raw and intermediate files are stored under `data/` and are not the final
dataset.

The figure scripts in `analysis/2_figures` are from the previous pipeline.
They read `merged.parquet`, which this repository does not generate, and are
not run by `make`.

## Data sources

- **VIIRS passes:** NASA's
  [Common Metadata Repository (CMR) STAC API](https://cmr.earthdata.nasa.gov/search/granules.stac),
  querying the [VNP02MOD VIIRS/NPP Moderate Resolution 6-Min L1B Swath, 750 m,
  Version 2](https://doi.org/10.5067/VIIRS/VNP02MOD.002) collection. The
  downloader saves STAC granule metadata pages, not satellite image pixels.
  The current downloader queries 2018–2024.
- **Eagle-I outages:** [The Environment for Analysis of Geo-Located Energy Information's Recorded Electricity Outages, 2014–2025](https://doi.org/10.6084/m9.figshare.24237376.v4).
- **County household estimates:** The U.S. Census Bureau's
  [American Community Survey](https://www.census.gov/programs-surveys/acs/data.html),
  variable `B11001_001`, accessed with `tidycensus`. For Connecticut from
  2022 onward, 2021 ACS county estimates are reused to retain the former
  county geography.
- **State customer coverage:** Eagle-I's `coverage_history.csv` provides
  state totals for 2018–2022. For `est_total_customers` only, 2022 state totals
  are carried forward to calculate 2023–2024 county estimates. This carry-forward
  does not fill `total_customers`, which contains only values from the raw
  Eagle-I files.
- **County boundaries:** U.S. Census county boundaries downloaded through
  `tigris`.
- **Time zones:** [Timezone Boundary Builder](https://github.com/evansiroky/timezone-boundary-builder).

## Final dataset: `outages-with-viirs-image.parquet`

Each row represents a 15 minute Eagle-I outage record associated with a matching VIIRS
image over a county centroid during the hours of midnight through 2:45AM local time.
The final dataset excludes U.S. Virgin Islands records (FIPS prefix `78`).

| Column | Type | Description |
| --- | --- | --- |
| `fips_code` | string | Five-character county FIPS code. |
| `eaglei_outage_time_utc` | timestamp (UTC) | Start time of the 15 minute Eagle-I outage interval. |
| `viirs_id` | string | Identifier of the matching VIIRS CMR granule. |
| `viirs_pass_start_time_utc` | timestamp (UTC) | Start of the VIIRS granule time range. |
| `viirs_pass_end_time_utc` | timestamp (UTC) | End of the VIIRS granule time range. |
| `tzid` | string | IANA time zone identifier for time zone of county centroid. |
| `total_customers` | numeric | Value from the raw Eagle-I file only. It is missing when the raw file does not provide a value; coverage estimates are not substituted. |
| `est_total_customers` | numeric | Estimated county customers, allocated from state coverage totals using each county's share of ACS households; 2022 state totals are carried forward to estimate 2023–2024. |
| `customers_out` | numeric | Customers reported out in the Eagle-I outage interval. |
| `customers_out_8hr_prior` | numeric | Average customers out over the preceding eight hours, with unreported intervals assumed to be zero. |
