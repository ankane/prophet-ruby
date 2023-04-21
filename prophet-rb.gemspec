require_relative "lib/prophet/version"

Gem::Specification.new do |spec|
  spec.name          = "prophet-rb"
  spec.version       = Prophet::VERSION
  spec.summary       = "Time series forecasting for Ruby"
  spec.homepage      = "https://github.com/ankane/prophet-ruby"
  spec.license       = "MIT"

  spec.author        = "Andrew Kane"
  spec.email         = "andrew@ankane.org"

  spec.files         = Dir["*.{md,txt}", "{data-raw,lib,stan,vendor}/**/*"]
  spec.require_path  = "lib"

  spec.required_ruby_version = ">= 3"

  spec.add_dependency "cmdstan", ">= 0.2"
  spec.add_dependency "numo-narray", ">= 0.9.1.7" # for percentile
  spec.add_dependency "polars-df" # ">= 0.4.1"
end
