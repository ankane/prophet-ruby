require_relative "test_helper"

class ProphetTest < Minitest::Test
  def setup
    skip if ENV["APPVEYOR"] # Numo bug

    return unless defined?(RubyProf)
    RubyProf.start
  end

  def teardown
    return unless defined?(RubyProf)
    result = RubyProf.stop
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT)
  end

  def test_linear
    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8004.75, m.params["lp__"][0]
      assert_in_delta -0.359494, m.params["k"][0]
      assert_in_delta 0.626234, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_equal ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2).map(&:to_s)

    forecast = m.predict(future)
    assert_equal ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2).map(&:to_s)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2).to_a
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2).to_a
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2).to_a

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_equal ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2).map(&:to_s)

    plot(m, forecast, "linear")
  end

  def test_logistic
    df = load_example
    df["cap"] = 1000

    m = Prophet.new(growth: "logistic")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 7750.6, m.params["lp__"][0]
      assert_in_delta 0.0514968, m.params["k"][0]
      assert_in_delta 94.2344, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    future["cap"] = 1000

    forecast = m.predict(future)
    assert_equal ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2).map(&:to_s)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2).to_a
    assert_elements_in_delta [7.503160, 7.481241], forecast["yhat_lower"].tail(2).to_a
    assert_elements_in_delta [8.992239, 9.017918], forecast["yhat_upper"].tail(2).to_a

    plot(m, forecast, "logistic")
  end

  def test_holidays
    df = load_example

    m = Prophet.new
    m.add_country_holidays("US")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8040.81, m.params["lp__"][0]
      assert_in_delta -0.36428, m.params["k"][0]
      assert_in_delta 0.626888, m.params["m"][0]
    end

    assert m.train_holiday_names

    future = m.make_future_dataframe(periods: 365)
    assert_equal ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2).map(&:to_s)

    forecast = m.predict(future)
    assert_equal ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2).map(&:to_s)
    assert_elements_in_delta [8.093708, 8.111485], forecast["yhat"].tail(2).to_a
    assert_elements_in_delta [7.400929, 7.389584], forecast["yhat_lower"].tail(2).to_a
    assert_elements_in_delta [8.863748, 8.867099], forecast["yhat_upper"].tail(2).to_a

    plot(m, forecast, "holidays")
  end

  def test_mcmc_samples
    df = load_example

    m = Prophet.new(mcmc_samples: 3)
    m.fit(df, seed: 123)
    params = m.params
    assert_elements_in_delta [963.497, 1006.49], m.params["lp__"][0..1].to_a
    assert_elements_in_delta [7.84723, 7.84723], m.params["stepsize__"][0..1].to_a
  end

  def test_custom_seasonality
    df = load_example

    m = Prophet.new(weekly_seasonality: false)
    m.add_seasonality(name: "monthly", period: 30.5, fourier_order: 5)
    m.fit(df, seed: 123)

    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)

    plot(m, forecast, "custom_seasonality")
  end

  def test_multiplicative_seasonality
    df = Daru::DataFrame.from_csv("examples/example_air_passengers.csv")
    m = Prophet.new(seasonality_mode: "multiplicative")
    m.fit(df)
    future = m.make_future_dataframe(periods: 50, freq: "MS")
    forecast = m.predict(future)

    assert_equal ["1965-01-01 00:00:00 UTC", "1965-02-01 00:00:00 UTC"], forecast["ds"].tail(2).map(&:to_s)
    assert_elements_in_delta [606.099342, 580.144827], forecast["yhat"].tail(2).to_a, 1

    plot(m, forecast, "multiplicative_seasonality")
  end

  def test_subdaily
    df = Daru::DataFrame.from_csv("examples/example_yosemite_temps.csv")
    index = df.where(df["y"].eq("NaN")).index
    df["y"][*index] = nil

    m = Prophet.new(changepoint_prior_scale: 0.01)
    m.fit(df, seed: 123)
    # different t_change sampling produces different params

    future = m.make_future_dataframe(periods: 300, freq: "H")
    assert_equal ["2017-07-17 11:00:00 UTC", "2017-07-17 12:00:00 UTC"], future["ds"].tail(2).map(&:to_s)

    forecast = m.predict(future)
    assert_elements_in_delta [7.755761, 7.388094], forecast["yhat"].tail(2).to_a, 1
    assert_elements_in_delta [-8.481951, -8.933871], forecast["yhat_lower"].tail(2).to_a, 3
    assert_elements_in_delta [22.990261, 23.190911], forecast["yhat_upper"].tail(2).to_a, 3

    plot(m, forecast, "subdaily")
  end

  private

  def load_example
    Daru::DataFrame.from_csv("examples/example_wp_log_peyton_manning.csv")
  end

  def plot(m, forecast, name)
    return if ci?

    m.plot(forecast).savefig("/tmp/#{name}.png")
    m.plot_components(forecast).savefig("/tmp/#{name}2.png")
  end

  def mac?
    RbConfig::CONFIG["host_os"] =~ /darwin/i
  end

  def ci?
    ENV["CI"]
  end
end
