options(scipen = 999)
if (!require("pacman", quietly = TRUE)) {
  install.packages("pacman", repos = "https://cloud.r-project.org")
}
pacman::p_load(tidyverse, here, fs, arrow, sf, lwgeom)

sf_use_s2(FALSE)

raw_dir <- "data/raw/viirs-passes"

county_sf <- map(
  dir_ls('data/raw/county/', glob = '*.geojson') |> sort(),
  read_sf
)
names(county_sf) <- str_extract(names(county_sf), '20\\d{2}')
county_sf <- bind_rows(county_sf, .id = 'census_year')
county_sf <- st_transform(county_sf, 4326)
county_sf <- st_centroid(county_sf, of_largest_polygon = TRUE)

viirs_passes <- list.files(raw_dir, pattern = "_page_[0-9]+\\.geojson$", full.names = TRUE) |> 
  map(read_sf) |> 
  bind_rows() |>
  mutate(
    year = pmin(pmax(year(datetime), 2018), 2025),
    batch = round(row_number()/10000)
  ) |> 
  group_split(year, batch) |> 
  map(\(df) {
    census_year <- first(df$year)
    message('Year: ', census_year, ' N: ', nrow(df))
    df |> st_join(county_sf, left = FALSE) |> 
      filter(year(datetime) == census_year) |> 
      st_drop_geometry() |> 
      select(GEOID, viirs_id = id, viirs_start_datetime = start_datetime, viirs_end_datetime = end_datetime) 
  }) |> 
  bind_rows() |>
  distinct()

write_csv(viirs_passes, "data/processed/viirs-passes.csv")
