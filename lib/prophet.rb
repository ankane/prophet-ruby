# dependencies
require "cmdstan"
require "rover"
require "numo/narray"

# stdlib
require "logger"
require "set"

# modules
require "prophet/holidays"
require "prophet/plot"
require "prophet/forecaster"
require "prophet/stan_backend"
require "prophet/version"

module Prophet
  class Error < StandardError; end

  def self.new(**kwargs)
    Forecaster.new(**kwargs)
  end

  def self.forecast(series, count: 10)
    raise ArgumentError, "Series must have at least 10 data points" if series.size < 10

    keys = series.keys
    bad_key = keys.find { |k| !k.is_a?(Date) }
    raise ArgumentError, "Expected Date, got #{bad_key.class.name}" if bad_key

    week = keys.map { |k| k.wday }.uniq.size == 1
    month = keys.all? { |k| k.day == 1 }
    quarter = month && keys.all? { |k| k.month % 3 == 1 }
    year = quarter && keys.all? { |k| k.month == 1 }

    freq =
      if year
        "YS"
      elsif quarter
        "QS"
      elsif month
        "MS"
      elsif week
        "W"
      else
        "D"
      end

    df = Rover::DataFrame.new({"ds" => series.keys, "y" => series.values})

    m = Prophet.new
    m.logger.level = ::Logger::FATAL # no logging
    m.fit(df)

    future = m.make_future_dataframe(periods: count, include_history: false, freq: freq)
    forecast = m.predict(future)
    forecast[["ds", "yhat"]].to_a.map { |v| [v["ds"].to_date, v["yhat"]] }.to_h
  end
end
