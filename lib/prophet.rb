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

    times = series.keys
    dates = times.all? { |k| k.is_a?(Date) }
    times = times.map(&:to_time) unless dates

    freq =
      if dates
        if times.all? { |k| k.day == 1 }
          if times.all? { |k| k.month == 1 }
            "YS"
          elsif times.all? { |k| k.month % 3 == 1 }
            "QS"
          else
            "MS"
          end
        elsif times.map { |k| k.wday }.uniq.size == 1
          "W"
        else
          "D"
        end
      else
        # TODO support times
        raise ArgumentError, "Unknown frequency"
      end

    df = Rover::DataFrame.new({"ds" => series.keys, "y" => series.values})

    m = Prophet.new
    m.logger.level = ::Logger::FATAL # no logging
    m.fit(df)

    future = m.make_future_dataframe(periods: count, include_history: false, freq: freq)
    forecast = m.predict(future)
    result = forecast[["ds", "yhat"]].to_a
    if dates
      result.each { |v| v["ds"] = v["ds"].to_date }
    else
      # TODO set time zone
    end
    result.map { |v| [v["ds"], v["yhat"]]  }.to_h
  end
end
