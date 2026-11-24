library(httr2)

raw_dir <- "data/raw/viirs-passes"
page_size <- 2000L

dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

# CMR bounds: west,south,east,north. Alaska is split at the date line.
regions <- c(
  contiguous_us = "-125,24,-66,50",
  alaska_west = "-180,50,-129,72",
  alaska_east = "170,50,180,72",
  hawaii = "-180,18,-154,30",
  puerto_rico = "-68.5,17.5,-65,19.5"
)

for (year in 2018:2024) {
  temporal <- sprintf("%d-01-01T00:00:00Z,%d-01-01T00:00:00Z", year, year + 1L)
  for (region in names(regions)) {
    base <- request("https://cmr.earthdata.nasa.gov/search/granules.stac") |>
      req_url_query(
        collection_concept_id = "C2105087643-LAADS",
        bounding_box = regions[[region]],
        temporal = temporal,
        page_size = page_size
      ) |>
      req_retry(max_tries = 3)

    response <- base |> req_url_query(page_num = 1L) |> req_perform()
    result <- resp_body_json(response, simplifyVector = FALSE)
    matched <- as.numeric(result$numberMatched)
    if (is.na(matched) || matched > 1000000) {
      stop("STAC result count is missing or exceeds its 1-million-result limit: ", region, " ", year)
    }

    expected_pages <- ceiling(matched / page_size)
    existing_files <- list.files(
      raw_dir,
      pattern = sprintf("^%s_%d_page_[0-9]{5}\\.geojson$", region, year),
      full.names = TRUE
    )
    existing_pages <- as.integer(sub(
      "^.*_page_([0-9]{5})\\.geojson$",
      "\\1",
      basename(existing_files)
    ))
    if (length(existing_pages) == expected_pages &&
      setequal(existing_pages, seq_len(expected_pages))) {
      message("Already complete: ", region, " ", year)
      next
    }

    page <- 1L
    received <- 0L
    repeat {
      if (page > 1L) {
        response <- base |> req_url_query(page_num = page) |> req_perform()
      }
      result <- resp_body_json(response, simplifyVector = FALSE)
      n <- length(result$features)
      matched <- as.numeric(result$numberMatched)
      if (is.na(matched) || matched > 1000000) {
        stop("STAC result count is missing or exceeds its 1-million-result limit: ", region, " ", year)
      }
      if (n == 0L) {
        if (received < matched) stop("Search ended early: ", region, " ", year)
        break
      }

      path <- file.path(raw_dir, sprintf("%s_%d_page_%05d.geojson", region, year, page))
      writeBin(resp_body_raw(response), path)
      message("Saved ", path, " (", n, " granules)")
      received <- received + n
      if (received >= matched) break
      page <- page + 1L
    }
  }
}
