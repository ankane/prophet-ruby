require "bundler/setup"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
require "csv"
require "daru"
# require "ruby-prof"

$VERBOSE = nil # for Daru and PyCall deprecation warnings

class Minitest::Test
  def assert_elements_in_delta(expected, actual, delta = 0.2)
    assert_equal expected.size, actual.size
    expected.zip(actual) do |exp, act|
      assert_in_delta exp, act, delta
    end
  end

  def assert_times(exp, act)
    assert_equal exp, act.map(&:to_s).to_a
  end
end
