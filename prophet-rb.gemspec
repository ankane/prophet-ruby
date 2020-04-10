require_relative "lib/prophet/version"

Gem::Specification.new do |spec|
  spec.name          = "prophet-rb"
  spec.version       = Prophet::VERSION
  spec.summary       = "Time series forecasting for Ruby"
  spec.homepage      = "https://github.com/ankane/prophet"
  spec.license       = "MIT"

  spec.author        = "Andrew Kane"
  spec.email         = "andrew@chartkick.com"

  spec.files         = Dir["*.{md,txt}", "{data-raw,ext,lib,stan}/**/*"]
  spec.require_path  = "lib"
  spec.extensions    = ["ext/prophet/extconf.rb"]

  spec.required_ruby_version = ">= 2.4"

  spec.add_dependency "cmdstan", ">= 0.1.2"
  spec.add_dependency "daru"
  spec.add_dependency "numo-narray"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", ">= 5"
  spec.add_development_dependency "matplotlib"
  spec.add_development_dependency "ruby-prof"
end
