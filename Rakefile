require "bundler/gem_tasks"
require "rake/testtask"

task default: :test
Rake::TestTask.new do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false # for daru
end

# ensure vendor files exist
task :ensure_vendor do
  vendor_config.fetch("platforms").each_key do |k|
    raise "Missing directory: #{k}" unless Dir.exist?("vendor/#{k}")
  end
end

Rake::Task["build"].enhance [:ensure_vendor]

def download_platform(platform)
  require "fileutils"
  require "open-uri"
  require "tmpdir"

  config = vendor_config.fetch("platforms").fetch(platform)
  url = config.fetch("url")
  sha256 = config.fetch("sha256")

  puts "Downloading #{url}..."
  contents = URI.parse(url).read

  computed_sha256 = Digest::SHA256.hexdigest(contents)
  raise "Bad hash: #{computed_sha256}" if computed_sha256 != sha256

  file = Tempfile.new(binmode: true)
  file.write(contents)

  vendor = File.expand_path("vendor", __dir__)
  FileUtils.mkdir_p(vendor)

  dest = File.join(vendor, platform)
  FileUtils.rm_r(dest) if Dir.exist?(dest)

  # run apt install unzip on Linux
  system "unzip", "-q", file.path, "-d", dest, exception: true
  system "chmod", "+x", "#{dest}/bin/prophet", exception: true
end

def vendor_config
  @vendor_config ||= begin
    require "yaml"
    YAML.safe_load(File.read("vendor.yml"))
  end
end

namespace :vendor do
  task :all do
    vendor_config.fetch("platforms").each_key do |k|
      download_platform(k)
    end
  end

  task :platform do
    if Gem.win_platform?
      download_platform("x64-mingw")
    elsif RbConfig::CONFIG["host_os"].match?(/darwin/i)
      if RbConfig::CONFIG["host_cpu"].match?(/arm|aarch64/i)
        download_platform("arm64-darwin")
      else
        download_platform("x86_64-darwin")
      end
    else
      if RbConfig::CONFIG["host_cpu"].match?(/arm|aarch64/i)
        download_platform("aarch64-linux")
      else
        download_platform("x86_64-linux")
      end
    end
  end
end
