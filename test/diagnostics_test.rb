require_relative "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_cross_validation
    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    df_cv = Prophet::Diagnostics.cross_validation(m, initial: "730 days", period: "180 days", horizon: "365 days")
    assert_equal 3988, df_cv.size
    assert_times ["2010-02-15 00:00:00 UTC"], df_cv["cutoff"].first
    assert_times ["2015-01-20 00:00:00 UTC"], df_cv["cutoff"].last

    df_p = Prophet::Diagnostics.performance_metrics(df_cv, metrics: ["mse"])
    assert_equal 329, df_p.size
    assert_equal 37, df_p["horizon"][0] / 86400
    assert_equal 365, df_p["horizon"][-1] / 86400
    # TODO fix
    # assert_in_delta 0.494752, df_p["mse"][0]
    # assert_in_delta 1.188329, df_p["mse"][-1]
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
end
