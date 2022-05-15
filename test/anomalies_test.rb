require_relative "test_helper"

class AnomaliesTest < Minitest::Test
  def test_dates
    series = generate_series
    date = series.keys.last
    series[date - 8] = 999

    assert_equal [date - 8], Prophet.anomalies(series)
  end

  def test_times
    series = generate_series.transform_keys(&:to_time)
    date = series.keys.last
    series[(date - 8).to_time] = 999

    assert_equal [(date - 8).to_time], Prophet.anomalies(series)
  end

  # TODO improve test
  def test_country_holidays
    Prophet.anomalies(generate_series, country_holidays: "US")
  end

  # TODO raise error in 0.4.0
  def test_country_holidays_unsupported
    assert_output(nil, /Holidays in USA are not currently supported/) do
      Prophet.anomalies(generate_series, country_holidays: "USA", verbose: true)
    end
  end

  # TODO improve test
  def test_cap
    Prophet.anomalies(generate_series, growth: "logistic", cap: 8.5)
  end

  def test_unknown_keyword
    error = assert_raises(ArgumentError) do
      Prophet.anomalies(generate_series, a: true)
    end
    assert_equal "unknown keyword: :a", error.message
  end

  private

  def generate_series
    series = {}
    date = Date.parse("2018-04-01")
    28.times do
      series[date] = rand(100)
      date += 1
    end
    series
  end
end
