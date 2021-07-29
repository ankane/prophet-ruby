require_relative "test_helper"

class AnomaliesTest < Minitest::Test
  def test_dates
    series = {}
    date = Date.parse("2018-04-01")
    28.times do
      series[date] = rand(100)
      date += 1
    end
    series[date - 8] = 999

    assert_equal [date - 8], Prophet.anomalies(series)
  end

  def test_times
    series = {}
    date = Date.parse("2018-04-01")
    28.times do
      series[date.to_time] = rand(100)
      date += 1
    end
    series[(date - 8).to_time] = 999

    assert_equal [(date - 8).to_time], Prophet.anomalies(series)
  end
end
