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
