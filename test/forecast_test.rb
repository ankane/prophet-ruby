require_relative "test_helper"

class ForecastTest < Minitest::Test
  def test_daily
    series = {}
    date = Date.parse("2018-04-01")
    38.times do
      series[date] = date.wday
      date += 1
    end

    expected = series.to_a.last(10).to_h
    predicted = Prophet.forecast(series.first(28).to_h)
    assert_equal expected.keys, predicted.keys
    assert_elements_in_delta expected.values, predicted.values
  end

  def test_weekly
    series = {}
    date = Date.parse("2018-04-01")
    62.times do |i|
      series[date] = i % 2
      date += 7
    end

    expected = series.to_a.last(10).to_h
    predicted = Prophet.forecast(series.first(52).to_h)
    assert_equal expected.keys, predicted.keys
  end

  def test_monthly
    # TODO
  end

  def test_hourly
    # TODO
  end

  def test_count
    series = {}
    date = Date.parse("2018-04-01")
    31.times do
      series[date] = date.wday
      date += 1
    end

    expected = series.to_a.last(3).to_h
    predicted = Prophet.forecast(series.first(28).to_h, count: 3)
    assert_equal expected.keys, predicted.keys
    assert_elements_in_delta expected.values, predicted.values
  end

  def test_few_data_points
    error = assert_raises(ArgumentError) do
      Prophet.forecast({})
    end
    assert_equal "Series must have at least 10 data points", error.message
  end
end
