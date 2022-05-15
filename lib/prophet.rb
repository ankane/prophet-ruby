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

  def self.forecast(series, count: 10, country_holidays: nil, cap: nil, verbose: false, **options)
    raise ArgumentError, "Series must have at least 10 data points" if series.size < 10

    # error early on unknown keywords
    m = Prophet.new(**options)

    # check type to determine output format
    # check for before converting to time
    keys = series.keys
    dates = keys.all? { |k| k.is_a?(Date) }
    time_zone = keys.first.time_zone if keys.first.respond_to?(:time_zone)
    utc = keys.first.utc? if keys.first.respond_to?(:utc?)
    times = keys.map(&:to_time)

    day = times.all? { |t| t.hour == 0 && t.min == 0 && t.sec == 0 && t.nsec == 0 }
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
      else
        diff = Rover::Vector.new(times).sort.diff.to_numo[1..-1]
        min_diff = diff.min.to_i

        # could be another common divisor
        # but keep it simple for now
        raise "Unknown frequency" unless (diff % min_diff).eq(0).all?

        "#{min_diff}S"
      end

    # use series, not times, so dates are handled correctly
    df = Rover::DataFrame.new({"ds" => series.keys, "y" => series.values})
    df["cap"] = cap if cap

    m.logger.level = ::Logger::FATAL unless verbose
    m.add_country_holidays(country_holidays) if country_holidays
    m.fit(df)

    future = m.make_future_dataframe(periods: count, include_history: false, freq: freq)
    future["cap"] = cap if cap
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

  # TODO better name for interval_width
  # TODO DRY with forecast method
  def self.anomalies(series, interval_width: 0.99, country_holidays: nil, cap: nil, verbose: false, **options)
    df = Rover::DataFrame.new({"ds" => series.keys, "y" => series.values})
    df["cap"] = cap if cap

    m = Prophet.new(interval_width: interval_width, **options)
    m.logger.level = ::Logger::FATAL unless verbose
    m.add_country_holidays(country_holidays) if country_holidays
    m.fit(df)

    forecast = m.predict(df)
    # filter df["ds"] to ensure dates/times in same format as input
    df["ds"][(df["y"] < forecast["yhat_lower"]) | (df["y"] > forecast["yhat_upper"])].to_a
  end
end
