require_relative "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_cross_validation
    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    df_cv = Prophet::Diagnostics.cross_validation(m, initial: "730 days", period: "180 days", horizon: "365 days")
    assert_equal 3988, df_cv.size
    assert_times ["2010-02-16 00:00:00 UTC", "2010-02-17 00:00:00 UTC"], df_cv["ds"].head(2)
    assert_times ["2016-01-19 00:00:00 UTC", "2016-01-20 00:00:00 UTC"], df_cv["ds"].tail(2)
    assert_elements_in_delta [8.959074, 8.725548], df_cv["yhat"].head(2), 0.001
    assert_elements_in_delta [9.068809, 8.905042], df_cv["yhat"].tail(2), 0.001
    assert_elements_in_delta [8.242493, 8.008033], df_cv["y"].head(2), 0.001
    assert_elements_in_delta [9.125871, 8.891374], df_cv["y"].tail(2), 0.001
    assert_times ["2010-02-15 00:00:00 UTC", "2010-02-15 00:00:00 UTC"], df_cv["cutoff"].head(2)
    assert_times ["2015-01-20 00:00:00 UTC", "2015-01-20 00:00:00 UTC"], df_cv["cutoff"].tail(2)

    df_p = Prophet::Diagnostics.performance_metrics(df_cv, metrics: ["mse", "rmse"])
    assert_equal 329, df_p.size
    assert_equal [37, 38], (df_p["horizon"].head(2) / 86400.0).to_a
    assert_equal [364, 365], (df_p["horizon"].tail(2) / 86400.0).to_a
    # TODO fix
    # assert_elements_in_delta [0.494752, 0.500521], df_p["mse"].head(2), 0.001
    # assert_elements_in_delta [1.175513, 1.188329], df_p["mse"].tail(2), 0.001
    # assert_elements_in_delta [0.703386, 0.707475], df_p["rmse"].head(2), 0.001
    # assert_elements_in_delta [1.084211, 1.090105], df_p["rmse"].tail(2), 0.001
  end

  def test_cross_validation_cutoffs
    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    cutoffs = ["2013-02-15", "2013-08-15", "2014-02-15"].map { |v| Time.parse("#{v} 00:00:00 UTC") }
    df_cv2 = Prophet::Diagnostics.cross_validation(m, cutoffs: cutoffs, horizon: "365 days")
    assert_equal 1090, df_cv2.size
    assert_times ["2013-02-15 00:00:00 UTC"], df_cv2["cutoff"].first
    assert_times ["2014-02-15 00:00:00 UTC"], df_cv2["cutoff"].last
  end

  def test_performance_metrics_invalid
    error = assert_raises(ArgumentError) do
      Prophet::Diagnostics.performance_metrics(Rover::DataFrame.new, metrics: ["invalid"])
    end
    assert_match "Valid values for metrics are: ", error.message
  end

  def test_performance_metrics_non_unique
    error = assert_raises(ArgumentError) do
      Prophet::Diagnostics.performance_metrics(Rover::DataFrame.new, metrics: ["mse", "mse"])
    end
    assert_equal "Input metrics must be a list of unique values", error.message
  end
end
