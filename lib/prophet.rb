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

  # TODO detect more intervals, like N minutes
  def self.forecast(series, count: 10)
    raise ArgumentError, "Series must have at least 10 data points" if series.size < 10

    # check type to determine output format
    # check for before converting to time
    keys = series.keys
    dates = keys.all? { |k| k.is_a?(Date) }
    time_zone = keys.first.time_zone if keys.first.respond_to?(:time_zone)
    utc = keys.first.utc? if keys.first.respond_to?(:utc?)
    times = keys.map(&:to_time)

    minute = times.all? { |t| t.sec == 0 && t.nsec == 0 }
    hour = minute && times.all? { |t| t.min == 0 }
    day = hour && times.all? { |t| t.hour == 0 }
    week = day && times.map { |k| k.wday }.uniq.size == 1
    month = day && times.all? { |k| k.day == 1 }
    quarter = month && times.all? { |k| k.month % 3 == 1 }
    year = quarter && times.all? { |k| k.month == 1 }

    freq =
      if year
        "YS"
      elsif quarter
        "QS"
      elsif month
        "MS"
      elsif week
        "W"
      elsif day
        "D"
      elsif hour
        "H"
      else
        raise ArgumentError, "Unknown frequency"
      end

    df = Rover::DataFrame.new({"ds" => series.keys, "y" => series.values})

    m = Prophet.new
    m.logger.level = ::Logger::FATAL # no logging
    m.fit(df)

    future = m.make_future_dataframe(periods: count, include_history: false, freq: freq)
    forecast = m.predict(future)
    result = forecast[["ds", "yhat"]].to_a

    # use the same format as input
    if dates
      result.each { |v| v["ds"] = v["ds"].to_date }
    elsif time_zone
      result.each { |v| v["ds"] = v["ds"].in_time_zone(time_zone) }
    elsif utc
      result.each { |v| v["ds"] = v["ds"].utc }
    else
      result.each { |v| v["ds"] = v["ds"].localtime }
    end
    result.map { |v| [v["ds"], v["yhat"]] }.to_h
  end
end
