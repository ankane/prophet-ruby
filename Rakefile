require "bundler/gem_tasks"
require "rake/testtask"

task default: :test
Rake::TestTask.new do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false # for daru
end

directories = %w(x86_64-linux aarch64-linux x86_64-darwin arm64-darwin)

# ensure vendor files exist
task :ensure_vendor do
  directories.each do |dir|
    raise "Missing directory: #{dir}" unless Dir.exist?("vendor/#{dir}")
  end
end

Rake::Task["build"].enhance [:ensure_vendor]

def download_file(target, sha256)
  version = "1.0"

  require "fileutils"
  require "open-uri"
  require "tmpdir"

  file = "prophet-#{version}-#{target}.zip"
  # TODO remove revision on next release
  url = "https://github.com/ankane/ml-builds/releases/download/prophet-#{version}-1/#{file}"
  puts "Downloading #{file}..."
  contents = URI.open(url).read

  computed_sha256 = Digest::SHA256.hexdigest(contents)
  raise "Bad hash: #{computed_sha256}" if computed_sha256 != sha256

  Dir.chdir(Dir.mktmpdir) do
    File.binwrite(file, contents)
    dest = File.expand_path("vendor/#{target}", __dir__)
    FileUtils.rm_r(dest) if Dir.exist?(dest)
    # run apt install unzip on Linux
    system "unzip", "-q", file, "-d", dest, exception: true
    system "chmod", "+x", "#{dest}/bin/prophet", exception: true
  end
end

namespace :vendor do
  task :linux do
    download_file("x86_64-linux", "ab2a6e77078c7d5057b58be0b8ac505e7a6523b241b628900b4594f3e4f52792")
    download_file("aarch64-linux", "b5211439fad89ed6b571c4d4c59c390cba015b8b3585493c6922b62c2cc0d020")
  end

  task :mac do
    download_file("x86_64-darwin", "31268095b70aa7c11c291b26ae43d073111c1f0e14309e024d17688782046a9f")
    download_file("arm64-darwin", "c1ce84c1669b4960da413d45c22b1ee4b757fad36e127a71fe95874c4ea5a490")
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
