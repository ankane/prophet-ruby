require "cmdstan"
require "fileutils"
require "tmpdir"

platform = Gem.win_platform? ? "win" : "unix"
stan_file = File.expand_path("../../stan/#{platform}/prophet.stan", __dir__)

# copy to avoid temp file in repo
temp_file = "#{Dir.tmpdir}/prophet.stan"
FileUtils.cp(stan_file, temp_file)

# compile
sm = CmdStan::Model.new(stan_file: temp_file)

# save
target_dir = File.expand_path("../../stan_model", __dir__)
FileUtils.mkdir_p(target_dir)
FileUtils.cp(sm.exe_file, "#{target_dir}/prophet_model.bin")
