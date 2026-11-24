# Match Eagle-I outage records to overlapping VIIRS passes during local
# nighttime hours and summarize outages over the preceding eight hours.
#
# `total_customers` comes only from raw Eagle-I files and remains missing
# when the raw data has no value. `est_total_customers` is a separate county
# estimate allocated from state coverage totals using ACS household shares;
# 2022 state totals are carried forward for 2023–2024 estimates only.
# Connecticut uses 2021 ACS county estimates for 2022–2024 to retain its old
# county boundaries. U.S. Virgin Islands records (FIPS prefix 78) are excluded.
#

options(scipen = 999)
if (!require("pacman", quietly = TRUE)) {
  install.packages("pacman", repos = "https://cloud.r-project.org")
}
pacman::p_load(tidyverse, here, lubridate, data.table, fs, arrow, tidycensus)

if(Sys.getenv('CENSUS_API_KEY') == '') stop("Install a Census API Key with tidycensus (https://walker-data.com/tidycensus/reference/census_api_key.html).")

dir_create(here('data/processed'))

annual_cov <- fread(here('data/raw/eagle-i/coverage_history.csv')) %>%
  transmute(
    year = lubridate::year(mdy(year)),
    state,
    total_customers
  ) %>%
  left_join(
     tidycensus::fips_codes %>%
      transmute(
        state_fips = state_code,
        state
      ) %>%
      distinct(),
      by = c('state')
    )

# Extend coverage totals for estimates only; raw Eagle-I totals remain unchanged.
annual_cov_carried <- annual_cov %>%
  select(state, state_fips) %>%
  distinct() %>%
  tidyr::crossing(year = 2023:2024) %>%
  bind_rows(annual_cov) %>%
  arrange(state_fips, year) %>%
  group_by(state_fips) %>%
  fill(total_customers, .direction = 'down') %>%
  ungroup()

viirs_passes <- read_csv('data/processed/viirs-passes.csv')

eaglei_annual_files <- dir_ls(here('data/raw/eagle-i'), glob = '*eaglei_outages*csv')
eaglei_annual_files <- eaglei_annual_files[which(between(as.numeric(str_extract(eaglei_annual_files, '[0-9]{4}')), 2018, 2024))]
ct_county_households_2021 <- suppressMessages(
  get_acs(
    geography = 'county',
    state = 'CT',
    variables = 'B11001_001',
    year = 2021
  )
) %>%
  transmute(
    fips_code = GEOID,
    state_fips = substr(GEOID, 1, 2),
    estimate,
    moe
  )

eaglei <- map(
  eaglei_annual_files,
  function(eaglei_annual_file){
    message(eaglei_annual_file)
    eaglei_year <- as.numeric(str_extract(eaglei_annual_file, '[0-9]{4}'))
    acs_county_households <- suppressMessages(
      get_acs(
        geography = 'county',
        variables = 'B11001_001',
        year = pmin(2024, eaglei_year) # use 2024 ACS estimate since 2025 not yet available
      )
    ) %>%
      transmute(
        fips_code = GEOID,
        state_fips = substr(fips_code, 1, 2),
        estimate_year = eaglei_year,
        estimate,
        moe
      )

    if (eaglei_year >= 2022) {
      # Use the last ACS vintage with Connecticut's former county geographies.
      acs_county_households <- acs_county_households %>%
        filter(state_fips != '09') %>%
        bind_rows(
          ct_county_households_2021 %>%
            mutate(estimate_year = eaglei_year)
        )
    }

    county_households <- acs_county_households %>%
      rename(year = estimate_year) %>%
      left_join(
        annual_cov_carried %>%
          transmute(
            state_fips,
            year,
            carried_total_customers = total_customers
          ),
        by = c('state_fips', 'year')
      ) %>%
      group_by(state_fips) %>%
      mutate(
        pct_state_households = estimate / sum(estimate),
        est_total_customers = round(carried_total_customers * pct_state_households)
      ) %>%
      ungroup() %>%
      select(fips_code, est_total_customers)

    eaglei <- read_csv(eaglei_annual_file, show_col_types = FALSE) %>%
      mutate(fips_code = str_pad(fips_code, width = 5, pad = '0')) %>%
      left_join(county_households,  join_by(fips_code))

    if('sum' %in% names(eaglei)) eaglei <- rename(eaglei, customers_out = sum) # fix inconsistent naming

    if(!('total_customers' %in% names(eaglei))) eaglei$total_customers <- NA_real_

    tz_lookup <- read_csv(paste0('data/processed/tz_lookup_', str_extract(eaglei_annual_file, '[0-9]{4}'), '.csv'), show_col_types = FALSE)

    # Determine the local hour for each outage record.
    eaglei <- eaglei %>%
      filter(
        !is.na(fips_code),
        !str_starts(fips_code, '78'),
        !is.na(run_start_time),
        !is.na(customers_out)
      ) %>%
      left_join(tz_lookup, by = 'fips_code') %>%
      group_by(tzid) %>%
      group_split() %>%
      map(
        \(.x) .x %>%
        mutate(
          local_hour = hour(with_tz(run_start_time, first(tzid))),
          fips_code = str_pad(fips_code, 5, pad = '0')
        )
      ) %>%
      bind_rows()

    ## match to satellite passes
    outages_with_images <- eaglei %>%
      mutate(run_end_time = run_start_time + (15*60)) %>%
      left_join(
        viirs_passes,
        join_by(
          x$fips_code == y$GEOID,
          x$run_start_time <= y$viirs_end_datetime,
          x$run_end_time >= y$viirs_start_datetime,
        )
      ) %>%
      mutate(nighttime_image = (local_hour %in% c(0:2)) & !is.na(viirs_id)) # or look up sunrise/sunset?

    nighttime_passes <- left_join(
      outages_with_images %>%
        filter(nighttime_image) %>%
        transmute(
          fips_code,
          viirs_id,
          run_start_time,
          run_start_time_8hr_prior = run_start_time - hours(8),
          viirs_start_datetime,
          viirs_end_datetime,
          tzid
        ),
      outages_with_images,
      by = join_by(
        fips_code,
        viirs_start_datetime,
        viirs_end_datetime,
        tzid,
        between(y$run_start_time, x$run_start_time_8hr_prior, x$run_start_time)
      ),
      suffix = c('', '_prior')
    ) %>%
      group_by(fips_code, run_start_time, viirs_id, viirs_start_datetime, viirs_end_datetime, tzid) %>%
      arrange(desc(run_start_time_prior)) %>%
      summarize(
        total_customers = first(total_customers),
        est_total_customers = first(est_total_customers),
        customers_out = first(customers_out),
        customers_out_8hr_prior = sum(customers_out)/(4*8) # div by 8 hrs of 15m intervals (missing => 0)
      )
  }
) %>%
  bind_rows()

eaglei <- eaglei %>%
  rename(
    eaglei_outage_time_utc = run_start_time,
    viirs_pass_start_time_utc = viirs_start_datetime,
    viirs_pass_end_time_utc = viirs_end_datetime,
  )

write_parquet(eaglei, here('outages-with-viirs-image.parquet'))
