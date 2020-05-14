module Prophet
  module Holidays
    def get_holiday_names(country)
      years = (1995..2045).to_a
      make_holidays_df(years, country)["holiday"].uniq
    end

    def make_holidays_df(year_list, country)
      holidays_df[(holidays_df["country"] == country) & (holidays_df["year"].in?(year_list))][["ds", "holiday"]]
    end

    # TODO marshal on installation
    def holidays_df
      @holidays_df ||= begin
        holidays = {"ds" => [], "holiday" => [], "country" => [], "year" => []}
        holidays_file = File.expand_path("../../data-raw/generated_holidays.csv", __dir__)
        CSV.foreach(holidays_file, headers: true, converters: [:date, :numeric]) do |row|
          holidays["ds"] << row["ds"]
          holidays["holiday"] << row["holiday"]
          holidays["country"] << row["country"]
          holidays["year"] << row["year"]
        end
        Rover::DataFrame.new(holidays)
      end
    end
  end
end
