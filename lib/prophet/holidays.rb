module Prophet
  module Holidays
    def get_holiday_names(country)
      years = (1995..2045).to_a
      holiday_names = make_holidays_df(years, country)["holiday"].uniq
      if holiday_names.size == 0
        raise ArgumentError, "Holidays in #{country} are not currently supported"
      end
      holiday_names
    end

    def make_holidays_df(year_list, country)
      holidays_df
        .filter((Polars.col("country") == country) & (Polars.col("year").in?(year_list)))
        .select(["ds", "holiday"])
        .collect
    end

    def holidays_df
      @holidays_df ||= begin
        holidays_file = File.expand_path("../../data-raw/generated_holidays.csv", __dir__)
        Polars.scan_csv(holidays_file, dtypes: {"ds" => Polars::Date})
      end
    end
  end
end
