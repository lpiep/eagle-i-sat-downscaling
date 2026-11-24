options(scipen = 999)
if (!require("pacman", quietly = TRUE)) {
  install.packages("pacman", repos = "https://cloud.r-project.org")
}
pacman::p_load(tidyverse, here, fs, arrow, sf)


tz_current <- read_sf(here('data/raw/timezones-now.geojson'))

map(
  dir_ls(here('data/raw/county/'), glob = '*.geojson'),
  \(county_file){
    st_join(
      st_transform(suppressWarnings(st_centroid(read_sf(county_file), of_largest_polygon = TRUE)), crs = st_crs(tz_current)),
      tz_current,
      join = st_nearest_feature
    ) %>%
      st_drop_geometry() %>%
      select(
        fips_code = GEOID, tzid
      )
  }
) %>%
  walk2(
    ., 
    names(.),
    \(dat, f){
      write_csv(
        dat, 
        here(file.path('data/processed/', paste0('tz_lookup_', str_extract(f, '\\d{4}'), '.csv')))
      )
    }
  )

