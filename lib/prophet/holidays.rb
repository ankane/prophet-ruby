module Prophet
  module Holidays
    def get_holiday_names(country)
      years = (1995..2045).to_a
      holiday_names = make_holidays_df(years, country)["holiday"].uniq
      # TODO raise error in 0.4.0
      logger.warn "Holidays in #{country} are not currently supported"
      holiday_names
    end

    def make_holidays_df(year_list, country)
      holidays_df[(holidays_df["country"] == country) & (holidays_df["year"].in?(year_list))][["ds", "holiday"]]
    end

    # TODO improve performance
    def holidays_df
      @holidays_df ||= begin
        holidays_file = File.expand_path("../../data-raw/generated_holidays.csv", __dir__)
        Rover.read_csv(holidays_file, converters: [:date, :numeric])
      end
    end
  end
end
