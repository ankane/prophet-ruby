require_relative "test_helper"

class SaveLoadTest < Minitest::Test
  def test_save_load
    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    m = Prophet.from_json(m.to_json)
    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)
  end

  def test_load_in_python
    skip #unless ENV["TEST_PYTHON"]

    df = load_example

    m = Prophet.new
    m.fit(df, seed: 123)

    File.write("/tmp/model.json", m.to_json)

    system "python3", "test/support/load.py", exception: true
  end

  def test_load_from_python
    skip unless ENV["TEST_PYTHON"]

    system "python3", "test/support/save.py", exception: true

    m = Prophet.from_json(File.read("/tmp/model.json"))
    future = m.make_future_dataframe(periods: 365)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], future["ds"].tail(2)

    forecast = m.predict(future)
    assert_times ["2017-01-18 00:00:00 UTC", "2017-01-19 00:00:00 UTC"], forecast["ds"].tail(2)
    assert_elements_in_delta [8.243210, 8.261121], forecast["yhat"].tail(2)
    assert_elements_in_delta [7.498851, 7.552077], forecast["yhat_lower"].tail(2)
    assert_elements_in_delta [9.000535, 9.030622], forecast["yhat_upper"].tail(2)
  end

  def test_to_json_not_fit
    m = Prophet.new
    error = assert_raises(Prophet::Error) do
      m.to_json
    end
    assert_equal "This can only be used to serialize models that have already been fit.", error.message
  end
end
