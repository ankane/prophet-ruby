## 0.6.0 (2025-04-03)

- Updated holidays
- Dropped support for Ruby < 3.2

## 0.5.3 (2024-12-29)

- Fixed warning with Ruby 3.4

## 0.5.2 (2024-10-26)

- Fixed warning with `plot` method

## 0.5.1 (2024-05-06)

- Added `scaling` option
- Fixed issue with yearly seasonality being enabled without enough data
- Fixed issue with internal columns in `predict` output (`col`, `col_lower`, and `col_upper`)

## 0.5.0 (2023-09-05)

- Added support for Polars
- Updated holidays
- Changed warning to error for unsupported country holidays
- Disabled logging by default
- Fixed error with `add_regressor` and holidays
- Dropped support for Ruby < 3

## 0.4.2 (2022-07-12)

- Fixed warning with `add_country_holidays` method

## 0.4.1 (2022-07-10)

- Added support for cross validation and performance metrics
- Added support for updating fitted models
- Added support for saturating minimum forecasts

## 0.4.0 (2022-07-07)

- Added support for saving and loading models
- Updated holidays

## 0.3.2 (2022-05-15)

- Added advanced API options to `forecast` and `anomalies` methods

## 0.3.1 (2022-04-28)

- Improved error message for missing columns

## 0.3.0 (2022-04-24)

- Switched to precompiled models
- Dropped support for Ruby < 2.7

## 0.2.5 (2021-07-28)

- Added `anomalies` method

## 0.2.4 (2021-04-02)

- Added support for flat growth

## 0.2.3 (2020-10-14)

- Added support for times to `forecast` method

## 0.2.2 (2020-07-26)

- Fixed error with constant series
- Fixed error with no changepoints

## 0.2.1 (2020-07-15)

- Added `forecast` method

## 0.2.0 (2020-05-13)

- Switched from Daru to Rover

## 0.1.1 (2020-04-10)

- Added `add_changepoints_to_plot`
- Fixed error with `changepoints` option
- Fixed error with `mcmc_samples` option
- Fixed error with additional regressors

## 0.1.0 (2020-04-09)

- First release
