require "bundler/gem_tasks"
require "rake/testtask"

task default: :test
Rake::TestTask.new do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false # for daru
end

directories = %w(prophet-linux prophet-linux-arm prophet-mac prophet-mac-arm)

# ensure vendor files exist
task :ensure_vendor do
  directories.each do |dir|
    raise "Missing directory: #{dir}" unless Dir.exist?("vendor/#{dir}")
  end
end

Rake::Task["build"].enhance [:ensure_vendor]

platforms = ["x86_64-linux", "aarch64-linux", "x86_64-darwin", "arm64-darwin"]

task :build_platform do
  require "fileutils"

  platforms.each do |platform|
    sh "gem", "build", "--platform", platform
  end

  FileUtils.mkdir_p("pkg")
  Dir["*.gem"].each do |file|
    FileUtils.move(file, "pkg")
  end
end

task :release_platform do
  require_relative "lib/prophet/version"

  Dir["pkg/prophet-rb-#{Prophet::VERSION}-*.gem"].each do |file|
    sh "gem", "push", file
  end
end

def download_file(file, sha256)
  require "fileutils"
  require "open-uri"
  require "tmpdir"

  url = "https://github.com/ankane/ml-builds/releases/download/prophet-1.0/#{file}"
  puts "Downloading #{file}..."
  contents = URI.open(url).read

  computed_sha256 = Digest::SHA256.hexdigest(contents)
  raise "Bad hash: #{computed_sha256}" if computed_sha256 != sha256

  Dir.chdir(Dir.mktmpdir) do
    File.binwrite(file, contents)
    dest = File.expand_path("vendor/#{file[0..-5]}", __dir__)
    FileUtils.rm_r(dest) if Dir.exist?(dest)
    # run apt install unzip on Linux
    system "unzip", "-q", file, "-d", dest, exception: true
    system "chmod", "+x", "#{dest}/bin/prophet", exception: true
  end
end

namespace :vendor do
  task :linux do
    download_file("prophet-linux.zip", "38cd783382dd3464500a9579b21d9974b892124e3305816573a647700df9d7a8")
    download_file("prophet-linux-arm.zip", "ab94b20e344d205efe3154362192640e51855fcc03014c9287330c563cf5ab97")
  end

  task :mac do
    download_file("prophet-mac.zip", "09ec8791a54c9b1f4275107831ad3f4fb9f77e69f7a185ec903fdb0f8b844920")
    download_file("prophet-mac-arm.zip", "0b1039c7e557053a900217430d39d09df2769105e397b71ec985daec361249cd")
  end

  task :windows do
  end

  task all: [:linux, :mac, :windows]

  task :platform do
    if Gem.win_platform?
      Rake::Task["vendor:windows"].invoke
    elsif RbConfig::CONFIG["host_os"] =~ /darwin/i
      Rake::Task["vendor:mac"].invoke
    else
      Rake::Task["vendor:linux"].invoke
    end
  end
end
