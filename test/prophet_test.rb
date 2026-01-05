require_relative "test_helper"

class ProphetTest < Minitest::Test
  def setup
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
      assert_in_delta 8004.75, m.params["lp__"][0], 1
      assert_in_delta -0.359494, m.params["k"][0], 0.01
      assert_in_delta 0.626234, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)

    plot(m, forecast, "linear")
  end

  def test_logistic
    df = Rover.read_csv("examples/example_wp_log_R.csv")
    df["cap"] = 8.5

    m = Prophet.new(growth: "logistic")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 9019.8, m.params["lp__"][0], 1
      assert_in_delta 2.07112, m.params["k"][0], 0.1
      assert_in_delta -0.361439, m.params["m"][0], 0.01
    end

    future = m.make_future_dataframe(periods: 365)
    future["cap"] = 8.5

    forecast = m.predict(future)
    assert_times ["2016-12-29 00:00:00 UTC", "2016-12-30 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [7.796425, 7.714560], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.503935, 7.398324], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [8.099635, 7.997564], forecast["yhat_upper"].tail(2)

    plot(m, forecast, "logistic")
  end

  def test_logistic_floor
    df = Rover.read_csv("examples/example_wp_log_R.csv")
    df["y"] = 10 - df["y"]
    df["cap"] = 6
    df["floor"] = 1.5

    m = Prophet.new(growth: "logistic")
    m.fit(df, seed: 123)

    future = m.make_future_dataframe(periods: 1826)
    future["cap"] = 6
    future["floor"] = 1.5
    forecast = m.predict(future)

    plot(m, forecast, "logistic_floor")
  end

  def test_flat
    df = load_example

    m = Prophet.new(growth: "flat")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 7494.87, m.params["lp__"][0], 1
      assert_in_delta 0, m.params["k"][0], 0.01
      assert_in_delta 0.63273591, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [9.086030, 9.103180], forecast["yhat"].tail(2)
    assert_elements_in_delta [8.285740, 8.416043], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.859524, 9.877022], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)

    plot(m, forecast, "flat")
  end

  def test_changepoints
    df = load_example

    m = Prophet.new(changepoints: ["2014-01-01"])
    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)

    plot(m, forecast, "changepoints")
  end

  def test_holidays
    df = load_example

    playoffs = Rover::DataFrame.new({
      "holiday" => "playoff",
      "ds" => [
        "2008-01-13", "2009-01-03", "2010-01-16",
        "2010-01-24", "2010-02-07", "2011-01-08",
        "2013-01-12", "2014-01-12", "2014-01-19",
        "2014-02-02", "2015-01-11", "2016-01-17",
        "2016-01-24", "2016-02-07"
      ],
      "lower_window" => 0,
      "upper_window" => 1
    })
    superbowls = Rover::DataFrame.new({
      "holiday" => "superbowl",
      "ds" => ["2010-02-07", "2014-02-02", "2016-02-07"],
      "lower_window" => 0,
      "upper_window" => 1
    })
    holidays = playoffs.concat(superbowls)

    m = Prophet.new(holidays: holidays)
    m.fit(df)
  end

  def test_country_holidays
    df = load_example

    m = Prophet.new
    m.add_country_holidays("US")
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8040.81, m.params["lp__"][0], 1
      assert_in_delta -0.36428, m.params["k"][0], 0.02
      assert_in_delta 0.626888, m.params["m"][0]
    end

    assert m.train_holiday_names

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.093708, 8.111485], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.400929, 7.389584], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [8.863748, 8.867099], forecast["yhat_upper"].tail(2)

    plot(m, forecast, "country_holidays")
  end

  def test_country_holidays_unsupported
    m = Prophet.new
    error = assert_raises(ArgumentError) do
      m.add_country_holidays("USA")
    end
    assert_equal "Holidays in USA are not currently supported", error.message
  end

  def test_mcmc_samples
    df = load_example

    m = Prophet.new(mcmc_samples: 3)
    m.fit(df, seed: 123)

    assert_elements_in_delta [963.497, 1006.49], m.params["lp__"][0..1].to_a
    assert_elements_in_delta [7.84723, 7.84723], m.params["stepsize__"][0..1].to_a

    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)

    plot(m, forecast, "mcmc_samples")
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

  def test_regressors
    df = load_example

    nfl_sunday = lambda do |ds|
      date = Date.parse(ds.to_s)
      date.wday == 0 && (date.month > 8 || date.month < 2) ? 1 : 0
    end

    df["nfl_sunday"] = df["ds"].map(&nfl_sunday)

    m = Prophet.new
    m.add_regressor("nfl_sunday")
    m.fit(df, seed: 123)

    future = m.make_future_dataframe(periods: 365)
    future["nfl_sunday"] = future["ds"].map(&nfl_sunday)

    forecast = m.predict(future)

    plot(m, forecast, "regressors")
  end

  def test_multiplicative_seasonality
    df = Rover.read_csv("examples/example_air_passengers.csv")
    m = Prophet.new(seasonality_mode: "multiplicative")
    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 50, freq: "MS")
    forecast = m.predict(future)

    assert_times ["1965-01-01 00:00:00 UTC", "1965-02-01 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [606.099342, 580.144827], forecast["yhat"].tail(2), 3

    plot(m, forecast, "multiplicative_seasonality")
  end

  def test_override_seasonality_mode
    df = Rover.read_csv("examples/example_air_passengers.csv")

    m = Prophet.new(seasonality_mode: "multiplicative")
    m.add_seasonality(name: "quarterly", period: 91.25, fourier_order: 8, mode: "additive")
    # m.add_regressor("regressor", mode: "additive")

    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 50, freq: "MS")
    forecast = m.predict(future)

    plot(m, forecast, "override_seasonality_mode")
  end

  def test_subdaily
    df = Rover.read_csv("examples/example_yosemite_temps.csv")
    df["y"][df["y"] == "NaN"] = nil

    m = Prophet.new(changepoint_prior_scale: 0.01)
    m.fit(df, seed: 123)
    # different t_change sampling produces different params

    future = m.make_future_dataframe(periods: 300, freq: "H")
    assert_times ["2017-07-17 11:00:00 UTC", "2017-07-17 12:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_elements_in_delta [7.755761, 7.388094], forecast["yhat"].tail(2), 2
    assert_elements_in_delta [-8.481951, -8.933871], forecast["yhat_lower"].tail(2), 5
    assert_elements_in_delta [22.990261, 23.190911], forecast["yhat_upper"].tail(2), 5

    plot(m, forecast, "subdaily")
  end

  def test_no_changepoints
    df = load_example

    m = Prophet.new(changepoints: [])
    m.fit(df, seed: 123)
    future = m.make_future_dataframe(periods: 365)
    forecast = m.predict(future)
  end

  def test_daru
    df = Daru::DataFrame.from_csv("examples/example_wp_log_peyton_manning.csv")

    m = Prophet.new
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8004.75, m.params["lp__"][0], 1
      assert_in_delta -0.359494, m.params["k"][0], 0.01
      assert_in_delta 0.626234, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)
  end

  def test_polars
    skip if RUBY_VERSION.to_i >= 4

    df = Polars.read_csv("examples/example_wp_log_peyton_manning.csv")

    m = Prophet.new
    m.fit(df, seed: 123)

    if mac?
      assert_in_delta 8004.75, m.params["lp__"][0], 1
      assert_in_delta -0.359494, m.params["k"][0], 0.01
      assert_in_delta 0.626234, m.params["m"][0]
    end

    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)

    future = m.make_future_dataframe(periods: 365, include_history: false)
    assert_times ["2016-01-21 00:00:00 UTC", "2016-01-22 00:00:00 UTC"], future["ds"].head(2)
  end

  def test_infinity
    df = load_example
    df["y"][0] = Float::INFINITY
    m = Prophet.new
    error = assert_raises(ArgumentError) do
      m.fit(df)
    end
    assert_equal "Found infinity in column y.", error.message
  end

  def test_missing_columns
    df = load_example
    df.delete("y")
    m = Prophet.new
    error = assert_raises(ArgumentError) do
      m.fit(df)
    end
    assert_equal "Data frame must have ds and y columns", error.message
  end

  def test_updating_fitted_model
    df = load_example
    df1 = df[df["ds"] <= "2016-01-19"] # All data except the last day
    m1 = Prophet.new.fit(df1) # A model fit to all data except the last day

    m2 = Prophet.new.fit(df) # Adding the last day, fitting from scratch
    m2 = Prophet.new.fit(df, init: stan_init(m1)) # Adding the last day, warm-starting from m1
  end

  def test_outliers
    df = Rover.read_csv("examples/example_wp_log_R_outliers1.csv")
    df["y"][(df["ds"] > "2010-01-01") & (df["ds"] < "2011-01-01")] = Float::NAN
    m = Prophet.new.fit(df)
    future = m.make_future_dataframe(periods: 1096)
    forecast = m.predict(future)

    plot(m, forecast, "outliers")
  end

  def test_holidays_and_regressor
    m = Prophet.new
    m.add_country_holidays("GB")
    m.add_regressor("precipitation_intensity")
  end

  def test_add_regressor_reserved
    m = Prophet.new
    error = assert_raises(ArgumentError) do
      m.add_regressor("trend")
    end
    assert_equal "Name \"trend\" is reserved.", error.message
  end

  def test_add_regressor_holidays
    holidays =  Rover::DataFrame.new({
      "holiday" => "playoff",
      "ds" => ["2008-01-13"]
    })
    m = Prophet.new(holidays: holidays)
    error = assert_raises(ArgumentError) do
      m.add_regressor("playoff")
    end
    assert_equal "Name \"playoff\" already used for a holiday.", error.message
  end

  def test_add_regressor_country_holidays
    m = Prophet.new
    m.add_country_holidays("GB")
    error = assert_raises(ArgumentError) do
      m.add_regressor("New Year's Day")
    end
    assert_equal "Name \"New Year's Day\" is a holiday name in \"GB\".", error.message
  end

  def test_add_regressor_seasonality
    m = Prophet.new
    m.add_seasonality(name: "monthly", period: 30.5, fourier_order: 5)
    error = assert_raises(ArgumentError) do
      m.add_regressor("monthly")
    end
    assert_equal "Name \"monthly\" already used for a seasonality.", error.message
  end

  def test_add_seasonality_regressor
    m = Prophet.new
    m.add_regressor("monthly")
    error = assert_raises(ArgumentError) do
      m.add_seasonality(name: "monthly", period: 30.5, fourier_order: 5)
    end
    assert_equal "Name \"monthly\" already used for an added regressor.", error.message
  end

  def test_scaling
    df = load_example
    m = Prophet.new(scaling: "minmax")
    m.fit(df, seed: 123)
  end

  private

  def stan_init(m)
    res = {}
    ["k", "m", "sigma_obs"].each do |pname|
      res[pname] = m.params[pname][0, true][0]
    end
    ["delta", "beta"].each do |pname|
      res[pname] = m.params[pname][0, true]
    end
    res
  end

  def plot(m, forecast, name)
    return unless test_python?

    fig = m.plot(forecast)
    fig.savefig("/tmp/#{name}.png")
    m.add_changepoints_to_plot(fig.gca, forecast)
    fig.savefig("/tmp/#{name}2.png")
    Matplotlib::Pyplot.close(fig)

    fig2 = m.plot_components(forecast)
    fig2.savefig("/tmp/#{name}3.png")
    Matplotlib::Pyplot.close(fig2)
  end

  def mac?
    RbConfig::CONFIG["host_os"] =~ /darwin/i
  end
end
