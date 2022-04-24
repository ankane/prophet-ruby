require "bundler/gem_tasks"
require "rake/testtask"

task default: :test
Rake::TestTask.new do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false # for daru
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
    system "unzip", "-q", file, "-d", dest
    system "chmod", "+x", "#{dest}/bin/prophet"
  end
end

namespace :vendor do
  task :linux do
    download_file("prophet-linux.zip", "f203dfcb9849aee40a5ab4fa320523843f699ebd62f4b1bd3343f59cb8d6c47a")
    download_file("prophet-linux-arm.zip", "67f8775e6d9e71476f86d6a3b41b4f93bf9d5e5f7c21e157cd791d0e48cec58b")
  end

  task :mac do
    download_file("prophet-mac.zip", "d6b9189b1e9292ad30e8ecf2e03c21222a0888dad4c8d9153e9219d9706b5686")
    download_file("prophet-mac-arm.zip", "d14162da3aa684bc55d88796a94774c3648b17dbe7dc9a88b1cde607d511a5db")
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
