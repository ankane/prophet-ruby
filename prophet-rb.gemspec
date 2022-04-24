require_relative "lib/prophet/version"

Gem::Specification.new do |spec|
  spec.name          = "prophet-rb"
  spec.version       = Prophet::VERSION
  spec.summary       = "Time series forecasting for Ruby"
  spec.homepage      = "https://github.com/ankane/prophet-ruby"
  spec.license       = "MIT"

  spec.author        = "Andrew Kane"
  spec.email         = "andrew@ankane.org"

  spec.files         = Dir["*.{md,txt}", "{data-raw,lib,stan}/**/*"]
  spec.require_path  = "lib"

  case spec.platform.to_s
  when "x86_64-linux"
    spec.files.concat(Dir["vendor/prophet-linux/**/*"])
  when "aarch64-linux"
    spec.files.concat(Dir["vendor/prophet-linux-arm/**/*"])
  when "x86_64-darwin"
    spec.files.concat(Dir["vendor/prophet-mac/**/*"])
  when "arm64-darwin"
    spec.files.concat(Dir["vendor/prophet-mac-arm/**/*"])
  else
    spec.files.concat(Dir["vendor/**/*"])
  end

  spec.required_ruby_version = ">= 2.7"

  spec.add_dependency "cmdstan", ">= 0.2"
  spec.add_dependency "numo-narray", ">= 0.9.1.7" # for percentile
  spec.add_dependency "rover-df"
end
