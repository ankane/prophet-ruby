module Prophet
  class StanBackend
    def initialize(logger)
      @model = load_model
      @logger = logger
    end

    def load_model
      model_file = File.expand_path("../../vendor/#{platform}/bin/prophet", __dir__)
      raise Error, "Platform not supported yet" unless File.exist?(model_file)
      CmdStan::Model.new(exe_file: model_file)
    end

    def fit(stan_init, stan_data, **kwargs)
      stan_init, stan_data = prepare_data(stan_init, stan_data)

      if !kwargs[:inits] && kwargs[:init]
        kwargs[:inits] = prepare_data(kwargs.delete(:init), stan_data)[0]
      end

      kwargs[:algorithm] ||= stan_data["T"] < 100 ? "Newton" : "LBFGS"
      iterations = 10000

      args = {
        data: stan_data,
        inits: stan_init,
        iter: iterations
      }
      args.merge!(kwargs)

      stan_fit = nil
      begin
        stan_fit = @model.optimize(**args)
      rescue => e
        if kwargs[:algorithm] != "Newton"
          @logger.warn "Optimization terminated abnormally. Falling back to Newton."
          kwargs[:algorithm] = "Newton"
          stan_fit = @model.optimize(
            data: stan_data,
            inits: stan_init,
            iter: iterations,
            **kwargs
          )
        else
          raise e
        end
      end

      params = stan_to_numo(stan_fit.column_names, Numo::NArray.asarray(stan_fit.optimized_params.values))
      params.each_key do |par|
        params[par] = params[par].reshape(1, *params[par].shape)
      end
      params
    end

    def sampling(stan_init, stan_data, samples, **kwargs)
      stan_init, stan_data = prepare_data(stan_init, stan_data)

      if !kwargs[:inits] && kwargs[:init]
        kwargs[:inits] = prepare_data(kwargs.delete(:init), stan_data)[0]
      end

      kwargs[:chains] ||= 4
      kwargs[:warmup_iters] ||= samples / 2

      stan_fit = @model.sample(
        data: stan_data,
        inits: stan_init,
        sampling_iters: samples,
        **kwargs
      )
      res = Numo::NArray.asarray(stan_fit.sample)
      samples, c, columns = res.shape
      res = res.reshape(samples * c, columns)
      params = stan_to_numo(stan_fit.column_names, res)

      params.each_key do |par|
        s = params[par].shape

        if s[1] == 1
          params[par] = params[par].reshape(s[0])
        end

        if ["delta", "beta"].include?(par) && s.size < 2
          params[par] = params[par].reshape(-1, 1)
        end
      end

      params
    end

    private

    def stan_to_numo(column_names, data)
      output = {}

      prev = nil

      start = 0
      finish = 0

      two_dims = data.shape.size > 1

      column_names.each do |cname|
        parsed = cname.split(".")

        curr = parsed[0]
        prev = curr if prev.nil?

        if curr != prev
          raise Error, "Found repeated column name" if output[prev]
          if two_dims
            output[prev] = Numo::NArray.asarray(data[true, start...finish])
          else
            output[prev] = Numo::NArray.asarray(data[start...finish])
          end
          prev = curr
          start = finish
          finish += 1
        else
          finish += 1
        end
      end

      raise Error, "Found repeated column name" if output[prev]
      if two_dims
        output[prev] = Numo::NArray.asarray(data[true, start...finish])
      else
        output[prev] = Numo::NArray.asarray(data[start...finish])
      end

      output
    end

    def prepare_data(stan_init, stan_data)
      stan_data["y"] = stan_data["y"].to_a
      stan_data["t"] = stan_data["t"].to_a
      stan_data["cap"] = stan_data["cap"].to_a
      stan_data["t_change"] = stan_data["t_change"].to_a
      stan_data["s_a"] = stan_data["s_a"].to_a
      stan_data["s_m"] = stan_data["s_m"].to_a
      stan_data["X"] = stan_data["X"].respond_to?(:to_numo) ? stan_data["X"].to_numo.to_a : stan_data["X"].to_a
      stan_init["delta"] = stan_init["delta"].to_a
      stan_init["beta"] = stan_init["beta"].to_a
      [stan_init, stan_data]
    end

    def platform
      if Gem.win_platform?
        "windows"
      elsif RbConfig::CONFIG["host_os"] =~ /darwin/i
        if RbConfig::CONFIG["host_cpu"] =~ /arm|aarch64/i
          "arm64-darwin"
        else
          "x86_64-darwin"
        end
      else
        if RbConfig::CONFIG["host_cpu"] =~ /arm|aarch64/i
          "aarch64-linux"
        else
          "x86_64-linux"
        end
      end
    end
  end
end
