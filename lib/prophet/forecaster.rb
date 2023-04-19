module Prophet
  class Forecaster
    include Holidays
    include Plot

    attr_reader :logger, :params, :train_holiday_names,
      :history, :seasonalities, :specified_changepoints, :fit_kwargs,
      :growth, :changepoints, :n_changepoints, :changepoint_range,
      :holidays, :seasonality_mode, :seasonality_prior_scale,
      :holidays_prior_scale, :changepoint_prior_scale, :mcmc_samples,
      :interval_width, :uncertainty_samples

    attr_accessor :extra_regressors, :seasonalities, :country_holidays

    def initialize(
      growth: "linear",
      changepoints: nil,
      n_changepoints: 25,
      changepoint_range: 0.8,
      yearly_seasonality: "auto",
      weekly_seasonality: "auto",
      daily_seasonality: "auto",
      holidays: nil,
      seasonality_mode: "additive",
      seasonality_prior_scale: 10.0,
      holidays_prior_scale: 10.0,
      changepoint_prior_scale: 0.05,
      mcmc_samples: 0,
      interval_width: 0.80,
      uncertainty_samples: 1000
    )
      @growth = growth

      @changepoints = to_datetime(changepoints)
      if !@changepoints.nil?
        @n_changepoints = @changepoints.size
        @specified_changepoints = true
      else
        @n_changepoints = n_changepoints
        @specified_changepoints = false
      end

      @changepoint_range = changepoint_range
      @yearly_seasonality = yearly_seasonality
      @weekly_seasonality = weekly_seasonality
      @daily_seasonality = daily_seasonality
      @holidays = convert_df(holidays)

      @seasonality_mode = seasonality_mode
      @seasonality_prior_scale = seasonality_prior_scale.to_f
      @changepoint_prior_scale = changepoint_prior_scale.to_f
      @holidays_prior_scale = holidays_prior_scale.to_f

      @mcmc_samples = mcmc_samples
      @interval_width = interval_width
      @uncertainty_samples = uncertainty_samples

      # Set during fitting or by other methods
      @start = nil
      @y_scale = nil
      @logistic_floor = false
      @t_scale = nil
      @changepoints_t = nil
      @seasonalities = {}
      @extra_regressors = {}
      @country_holidays = nil
      @stan_fit = nil
      @params = {}
      @history = nil
      @history_dates = nil
      @train_component_cols = nil
      @component_modes = nil
      @train_holiday_names = nil
      @fit_kwargs = {}
      validate_inputs

      @logger = ::Logger.new($stderr)
      @logger.level = ::Logger::WARN
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[prophet] #{msg}\n"
      end
      @stan_backend = StanBackend.new(@logger)
    end

    def validate_inputs
      if !["linear", "logistic", "flat"].include?(@growth)
        raise ArgumentError, "Parameter \"growth\" should be \"linear\", \"logistic\", or \"flat\"."
      end
      if @changepoint_range < 0 || @changepoint_range > 1
        raise ArgumentError, "Parameter \"changepoint_range\" must be in [0, 1]"
      end
      if @holidays
        if !(@holidays.is_a?(Polars::DataFrame) && @holidays.include?("ds") && @holidays.include?("holiday"))
          raise ArgumentError, "holidays must be a DataFrame with \"ds\" and \"holiday\" columns."
        end
        @holidays["ds"] = to_datetime(@holidays["ds"])
        has_lower = @holidays.include?("lower_window")
        has_upper = @holidays.include?("upper_window")
        if has_lower ^ has_upper # xor
          raise ArgumentError, "Holidays must have both lower_window and upper_window, or neither"
        end
        if has_lower
          if @holidays["lower_window"].max > 0
            raise ArgumentError, "Holiday lower_window should be <= 0"
          end
          if @holidays["upper_window"].min < 0
            raise ArgumentError, "Holiday upper_window should be >= 0"
          end
        end
        @holidays["holiday"].uniq.each do |h|
          validate_column_name(h, check_holidays: false)
        end
      end

      if !["additive", "multiplicative"].include?(@seasonality_mode)
        raise ArgumentError, "seasonality_mode must be \"additive\" or \"multiplicative\""
      end
    end

    def validate_column_name(name, check_holidays: true, check_seasonalities: true, check_regressors: true)
      if name.include?("_delim_")
        raise ArgumentError, "Name cannot contain \"_delim_\""
      end
      reserved_names = [
        "trend", "additive_terms", "daily", "weekly", "yearly",
        "holidays", "zeros", "extra_regressors_additive", "yhat",
        "extra_regressors_multiplicative", "multiplicative_terms",
      ]
      rn_l = reserved_names.map { |n| "#{n}_lower" }
      rn_u = reserved_names.map { |n| "#{n}_upper" }
      reserved_names.concat(rn_l)
      reserved_names.concat(rn_u)
      reserved_names.concat(["ds", "y", "cap", "floor", "y_scaled", "cap_scaled"])
      if reserved_names.include?(name)
        raise ArgumentError, "Name #{name.inspect} is reserved."
      end
      if check_holidays && @holidays && @holidays["holiday"].uniq.include?(name)
        raise ArgumentError, "Name #{name.inspect} already used for a holiday."
      end
      if check_holidays && @country_holidays && get_holiday_names(@country_holidays).include?(name)
        raise ArgumentError, "Name #{name.inspect} is a holiday name in #{@country_holidays.inspect}."
      end
      if check_seasonalities && @seasonalities[name]
        raise ArgumentError, "Name #{name.inspect} already used for a seasonality."
      end
      if check_regressors && @extra_regressors[name]
        raise ArgumentError, "Name #{name.inspect} already used for an added regressor."
      end
    end

    def setup_dataframe(df, initialize_scales: false)
      if df.include?("y")
        df["y"] = df["y"].map(&:to_f)
        raise ArgumentError, "Found infinity in column y." unless df["y"].all?(&:finite?)
      end
      # TODO support integers

      df["ds"] = to_datetime(df["ds"])

      raise ArgumentError, "Found NaN in column ds." if df["ds"].any?(&:nil?)

      @extra_regressors.each_key do |name|
        if !df.include?(name)
          raise ArgumentError, "Regressor #{name.inspect} missing from dataframe"
        end
        df[name] = df[name].map(&:to_f)
        if df[name].any?(&:nil?)
          raise ArgumentError, "Found NaN in column #{name.inspect}"
        end
      end
      @seasonalities.each_value do |props|
        condition_name = props[:condition_name]
        if condition_name
          if !df.include?(condition_name)
            raise ArgumentError, "Condition #{condition_name.inspect} missing from dataframe"
          end
          if df.where(!df[condition_name].in([true, false])).any?
            raise ArgumentError, "Found non-boolean in column #{condition_name.inspect}"
          end
        end
      end

      df = df.sort("ds")

      initialize_scales(initialize_scales, df)

      if @logistic_floor
        unless df.include?("floor")
          raise ArgumentError, "Expected column \"floor\"."
        end
      else
        df["floor"] = 0
      end

      if @growth == "logistic"
        unless df.include?("cap")
          raise ArgumentError, "Capacities must be supplied for logistic growth in column \"cap\""
        end
        if (df["cap"] <= df["floor"]).any?
          raise ArgumentError, "cap must be greater than floor (which defaults to 0)."
        end
        df["cap_scaled"] = (df["cap"] - df["floor"]) / @y_scale.to_f
      end

      df["t"] = (df["ds"] - @start) / @t_scale.to_f / 1e9
      if df.include?("y")
        df["y_scaled"] = (df["y"] - df["floor"]) / @y_scale.to_f
      end

      @extra_regressors.each do |name, props|
        df[name] = (df[name] - props[:mu]) / props[:std].to_f
      end

      df
    end

    def initialize_scales(initialize_scales, df)
      return unless initialize_scales

      if @growth == "logistic" && df.include?("floor")
        @logistic_floor = true
        floor = df["floor"]
      else
        floor = 0.0
      end
      @y_scale = (df["y"] - floor).abs.max
      @y_scale = 1 if @y_scale == 0
      @start = df["ds"].min
      @t_scale = df["ds"].max - @start
    end

    def set_changepoints
      if @changepoints
        if @changepoints.size > 0
          too_low = @changepoints.min < @history["ds"].min
          too_high = @changepoints.max > @history["ds"].max
          if too_low || too_high
            raise ArgumentError, "Changepoints must fall within training data."
          end
        end
      else
        hist_size = (@history.shape[0] * @changepoint_range).floor

        if @n_changepoints + 1 > hist_size
          @n_changepoints = hist_size - 1
          logger.info "n_changepoints greater than number of observations. Using #{@n_changepoints}"
        end

        if @n_changepoints > 0
          step = (hist_size - 1) / @n_changepoints.to_f
          cp_indexes = (@n_changepoints + 1).times.map { |i| (i * step).round }
          @changepoints = Polars::Series.new(@history["ds"].to_a.values_at(*cp_indexes))[1..-1]
        else
          @changepoints = []
        end
      end

      if @changepoints.size > 0
        @changepoints_t = (@changepoints.map(&:to_i).sort.to_numo.cast_to(Numo::DFloat) - @start.to_i) / @t_scale.to_f
      else
        @changepoints_t = Numo::NArray.asarray([0])
      end
    end

    def fourier_series(dates, period, series_order)
      t = dates.map(&:to_i).to_numo / (3600 * 24.0)

      # no need for column_stack
      series_order.times.flat_map do |i|
        [Numo::DFloat::Math.method(:sin), Numo::DFloat::Math.method(:cos)].map do |fun|
          fun.call(2.0 * (i + 1) * Math::PI * t / period)
        end
      end
    end

    def make_seasonality_features(dates, period, series_order, prefix)
      features = fourier_series(dates, period, series_order)
      Polars::DataFrame.new(features.map.with_index { |v, i| ["#{prefix}_delim_#{i + 1}", v] }.to_h)
    end

    def construct_holiday_dataframe(dates)
      all_holidays = Polars::DataFrame.new
      if @holidays
        all_holidays = @holidays.dup
      end
      if @country_holidays
        year_list = dates.map(&:year)
        country_holidays_df = make_holidays_df(year_list, @country_holidays)
        all_holidays = all_holidays.vstack(country_holidays_df)
      end
      # Drop future holidays not previously seen in training data
      if @train_holiday_names
        # Remove holiday names didn't show up in fit
        all_holidays = all_holidays[Polars.col("holiday").is_in(@train_holiday_names)]

        # Add holiday names in fit but not in predict with ds as NA
        holidays_to_add = Polars::DataFrame.new({
          "holiday" => @train_holiday_names.filter(@train_holiday_names.is_in(all_holidays["holiday"])._not)
        })
        all_holidays = all_holidays.vstack(holidays_to_add)
      end

      all_holidays
    end

    def make_holiday_features(dates, holidays)
      expanded_holidays = Hash.new { |hash, key| hash[key] = Numo::DFloat.zeros(dates.size) }
      prior_scales = {}
      # Makes an index so we can perform `get_loc` below.
      # Strip to just dates.
      row_index = dates.map(&:to_date)

      holidays.iter_rows(named: true) do |row|
        dt = row["ds"]
        lw = nil
        uw = nil
        begin
          lw = row["lower_window"].to_i
          uw = row["upper_window"].to_i
        rescue IndexError
          lw = 0
          uw = 0
        end
        ps = @holidays_prior_scale
        if prior_scales[row["holiday"]] && prior_scales[row["holiday"]] != ps
          raise ArgumentError, "Holiday #{row["holiday"].inspect} does not have consistent prior scale specification."
        end
        raise ArgumentError, "Prior scale must be > 0" if ps <= 0
        prior_scales[row["holiday"]] = ps

        lw.upto(uw).each do |offset|
          occurrence = dt ? dt + offset : nil
          loc = occurrence ? row_index.to_a.index(occurrence) : nil
          key = "#{row["holiday"]}_delim_#{offset >= 0 ? "+" : "-"}#{offset.abs}"
          if loc
            expanded_holidays[key][loc] = 1.0
          else
            expanded_holidays[key]  # Access key to generate value
          end
        end
      end
      holiday_features = Polars::DataFrame.new(expanded_holidays)
      # Make sure column order is consistent
      holiday_features = holiday_features[holiday_features.columns.sort]
      prior_scale_list = holiday_features.columns.map { |h| prior_scales[h.split("_delim_")[0]] }
      holiday_names = prior_scales.keys
      # Store holiday names used in fit
      if @train_holiday_names.nil?
        @train_holiday_names = Polars::Series.new(holiday_names)
      end
      [holiday_features, prior_scale_list, holiday_names]
    end

    def add_regressor(name, prior_scale: nil, standardize: "auto", mode: nil)
      raise Error, "Regressors must be added prior to model fitting." if @history
      validate_column_name(name, check_regressors: false)
      prior_scale ||= @holidays_prior_scale.to_f
      mode ||= @seasonality_mode
      raise ArgumentError, "Prior scale must be > 0" if prior_scale <= 0
      if !["additive", "multiplicative"].include?(mode)
        raise ArgumentError, "mode must be \"additive\" or \"multiplicative\""
      end
      @extra_regressors[name] = {
        prior_scale: prior_scale,
        standardize: standardize,
        mu: 0.0,
        std: 1.0,
        mode: mode
      }
      self
    end

    def add_seasonality(name:, period:, fourier_order:, prior_scale: nil, mode: nil, condition_name: nil)
      raise Error, "Seasonality must be added prior to model fitting." if @history

      if !["daily", "weekly", "yearly"].include?(name)
        # Allow overwriting built-in seasonalities
        validate_column_name(name, check_seasonalities: false)
      end
      if prior_scale.nil?
        ps = @seasonality_prior_scale
      else
        ps = prior_scale.to_f
      end
      raise ArgumentError, "Prior scale must be > 0" if ps <= 0
      raise ArgumentError, "Fourier Order must be > 0" if fourier_order <= 0
      mode ||= @seasonality_mode
      if !["additive", "multiplicative"].include?(mode)
        raise ArgumentError, "mode must be \"additive\" or \"multiplicative\""
      end
      validate_column_name(condition_name) if condition_name
      @seasonalities[name] = {
        period: period,
        fourier_order: fourier_order,
        prior_scale: ps,
        mode: mode,
        condition_name: condition_name
      }
      self
    end

    def add_country_holidays(country_name)
      raise Error, "Country holidays must be added prior to model fitting." if @history

      # Fix for previously documented keyword argument
      if country_name.is_a?(Hash) && country_name[:country_name]
        country_name = country_name[:country_name]
      end

      # Validate names.
      get_holiday_names(country_name).each do |name|
        # Allow merging with existing holidays
        validate_column_name(name, check_holidays: false)
      end
      # Set the holidays.
      if @country_holidays
        logger.warn "Changing country holidays from #{@country_holidays.inspect} to #{country_name.inspect}."
      end
      @country_holidays = country_name
      self
    end

    def make_all_seasonality_features(df)
      seasonal_features = []
      prior_scales = []
      modes = {"additive" => [], "multiplicative" => []}

      # Seasonality features
      @seasonalities.each do |name, props|
        features = make_seasonality_features(
          df["ds"],
          props[:period],
          props[:fourier_order],
          name
        )
        if props[:condition_name]
          features[!df.where(props[:condition_name])] = 0
        end
        seasonal_features << features
        prior_scales.concat([props[:prior_scale]] * features.shape[1])
        modes[props[:mode]] << name
      end

      # Holiday features
      holidays = construct_holiday_dataframe(df["ds"])
      if holidays.size > 0
        features, holiday_priors, holiday_names = make_holiday_features(df["ds"], holidays)
        seasonal_features << features
        prior_scales.concat(holiday_priors)
        modes[@seasonality_mode].concat(holiday_names)
      end

      # Additional regressors
      @extra_regressors.each do |name, props|
        seasonal_features << Polars::DataFrame.new({name => df[name]})
        prior_scales << props[:prior_scale]
        modes[props[:mode]] << name
      end

      # Dummy to prevent empty X
      if seasonal_features.size == 0
        seasonal_features << Polars::DataFrame.new({"zeros" => [0] * df.shape[0]})
        prior_scales << 1.0
      end

      seasonal_features = df_concat_axis_one(seasonal_features)

      component_cols, modes = regressor_column_matrix(seasonal_features, modes)

      [seasonal_features, prior_scales, component_cols, modes]
    end

    def regressor_column_matrix(seasonal_features, modes)
      components = Polars::DataFrame.new({
        "col" => seasonal_features.shape[1].times.to_a,
        "component" => seasonal_features.columns.map { |x| x.split("_delim_")[0] }
      })

      # Add total for holidays
      if @train_holiday_names
        components = add_group_component(components, "holidays", @train_holiday_names.uniq)
      end
      # Add totals additive and multiplicative components, and regressors
      ["additive", "multiplicative"].each do |mode|
        components = add_group_component(components, "#{mode}_terms", modes[mode])
        regressors_by_mode = @extra_regressors.select { |r, props| props[:mode] == mode }
          .map { |r, props| r }
        components = add_group_component(components, "extra_regressors_#{mode}", regressors_by_mode)

        # Add combination components to modes
        modes[mode] << "#{mode}_terms"
        modes[mode] << "extra_regressors_#{mode}"
      end
      # After all of the additive/multiplicative groups have been added,
      modes[@seasonality_mode] << "holidays"
      # Convert to a binary matrix
      component_cols =
        components.pivot(
          values: "component",
          index: "col",
          columns: "component",
          aggregate_fn: "count",
          sort_columns: "col"
        ).fill_null(0)

      # Add columns for additive and multiplicative terms, if missing
      ["additive_terms", "multiplicative_terms"].each do |name|
        component_cols[name] = 0 unless component_cols.include?(name)
      end

      # TODO validation

      [component_cols, modes]
    end

    def add_group_component(components, name, group)
      new_comp = components[Polars.col("component").is_in(group)]
      group_cols = new_comp["col"].uniq
      if group_cols.size > 0
        new_comp = Polars::DataFrame.new({"col" => group_cols}).with_column(Polars.lit(name).alias("component"))
        components = components.vstack(new_comp)
      end
      components
    end

    def parse_seasonality_args(name, arg, auto_disable, default_order)
      case arg
      when "auto"
        fourier_order = 0
        if @seasonalities.include?(name)
          logger.info "Found custom seasonality named #{name.inspect}, disabling built-in #{name.inspect}seasonality."
        elsif auto_disable
          logger.info "Disabling #{name} seasonality. Run prophet with #{name}_seasonality: true to override this."
        else
          fourier_order = default_order
        end
      when true
        fourier_order = default_order
      when false
        fourier_order = 0
      else
        fourier_order = arg.to_i
      end
      fourier_order
    end

    def set_auto_seasonalities
      first = @history["ds"].min
      last = @history["ds"].max
      dt = @history["ds"].diff
      min_dt = dt.cast(Polars::Int64).min / 1e9

      days = 86400

      # Yearly seasonality
      yearly_disable = last - first < 370 * days
      fourier_order = parse_seasonality_args("yearly", @yearly_seasonality, yearly_disable, 10)
      if fourier_order > 0
        @seasonalities["yearly"] = {
          period: 365.25,
          fourier_order: fourier_order,
          prior_scale: @seasonality_prior_scale,
          mode: @seasonality_mode,
          condition_name: nil
        }
      end

      # Weekly seasonality
      weekly_disable = last - first < 14 * days || min_dt >= 7 * days
      fourier_order = parse_seasonality_args("weekly", @weekly_seasonality, weekly_disable, 3)
      if fourier_order > 0
        @seasonalities["weekly"] = {
          period: 7,
          fourier_order: fourier_order,
          prior_scale: @seasonality_prior_scale,
          mode: @seasonality_mode,
          condition_name: nil
        }
      end

      # Daily seasonality
      daily_disable = last - first < 2 * days || min_dt >= 1 * days
      fourier_order = parse_seasonality_args("daily", @daily_seasonality, daily_disable, 4)
      if fourier_order > 0
        @seasonalities["daily"] = {
          period: 1,
          fourier_order: fourier_order,
          prior_scale: @seasonality_prior_scale,
          mode: @seasonality_mode,
          condition_name: nil
        }
      end
    end

    def linear_growth_init(df)
      i0 = 0
      i1 = df.size - 1
      t = df["t"][i1] - df["t"][i0]
      k = (df["y_scaled"][i1] - df["y_scaled"][i0]) / t
      m = df["y_scaled"][i0] - k * df["t"][i0]
      [k, m]
    end

    def logistic_growth_init(df)
      i0 = 0
      i1 = df.size - 1
      t = df["t"][i1] - df["t"][i0]

      # Force valid values, in case y > cap or y < 0
      c0 = df["cap_scaled"][i0]
      c1 = df["cap_scaled"][i1]
      y0 = [0.01 * c0, [0.99 * c0, df["y_scaled"][i0]].min].max
      y1 = [0.01 * c1, [0.99 * c1, df["y_scaled"][i1]].min].max

      r0 = c0 / y0
      r1 = c1 / y1

      if (r0 - r1).abs <= 0.01
        r0 = 1.05 * r0
      end

      l0 = Math.log(r0 - 1)
      l1 = Math.log(r1 - 1)

      # Initialize the offset
      m = l0 * t / (l0 - l1)
      # And the rate
      k = (l0 - l1) / t
      [k, m]
    end

    def flat_growth_init(df)
      k = 0
      m = df["y_scaled"].mean
      [k, m]
    end

    def fit(df, **kwargs)
      raise Error, "Prophet object can only be fit once" if @history

      df = convert_df(df)
      raise ArgumentError, "Must be a data frame" unless df.is_a?(Polars::DataFrame)

      unless df.include?("ds") && df.include?("y")
        raise ArgumentError, "Data frame must have ds and y columns"
      end

      history = df.drop_nulls(subset: ["y"])
      raise Error, "Data has less than 2 non-nil rows" if history.size < 2

      @history_dates = to_datetime(df["ds"]).sort
      history = setup_dataframe(history, initialize_scales: true)
      @history = history
      set_auto_seasonalities
      seasonal_features, prior_scales, component_cols, modes = make_all_seasonality_features(history)
      @train_component_cols = component_cols
      @component_modes = modes
      @fit_kwargs = kwargs.dup # TODO deep dup?

      set_changepoints

      trend_indicator = {"linear" => 0, "logistic" => 1, "flat" => 2}

      dat = {
        "T" => history.shape[0],
        "K" => seasonal_features.shape[1],
        "S" => @changepoints_t.size,
        "y" => history["y_scaled"],
        "t" => history["t"],
        "t_change" => @changepoints_t,
        "X" => seasonal_features,
        "sigmas" => prior_scales,
        "tau" => @changepoint_prior_scale,
        "trend_indicator" => trend_indicator[@growth],
        "s_a" => component_cols["additive_terms"],
        "s_m" => component_cols["multiplicative_terms"]
      }

      if @growth == "linear"
        dat["cap"] = Numo::DFloat.zeros(@history.shape[0])
        kinit = linear_growth_init(history)
      elsif @growth == "flat"
        dat["cap"] = Numo::DFloat.zeros(@history.shape[0])
        kinit = flat_growth_init(history)
      else
        dat["cap"] = history["cap_scaled"]
        kinit = logistic_growth_init(history)
      end

      stan_init = {
        "k" => kinit[0],
        "m" => kinit[1],
        "delta" => Numo::DFloat.zeros(@changepoints_t.size),
        "beta" => Numo::DFloat.zeros(seasonal_features.shape[1]),
        "sigma_obs" => 1
      }

      if history["y"].min == history["y"].max && (@growth == "linear" || @growth == "flat")
        # Nothing to fit.
        @params = stan_init
        @params["sigma_obs"] = 1e-9
        @params.each do |par, _|
          @params[par] = Numo::NArray.asarray([@params[par]])
        end
      elsif @mcmc_samples > 0
        @params = @stan_backend.sampling(stan_init, dat, @mcmc_samples, **kwargs)
      else
        @params = @stan_backend.fit(stan_init, dat, **kwargs)
      end

      # If no changepoints were requested, replace delta with 0s
      if @changepoints.size == 0
        # Fold delta into the base rate k
        # Numo doesn't support -1 with reshape
        negative_one = @params["delta"].shape.inject(&:*)
        @params["k"] = @params["k"] + @params["delta"].reshape(negative_one)
        @params["delta"] = Numo::DFloat.zeros(@params["delta"].shape).reshape(negative_one, 1)
      end

      self
    end

    def predict(df = nil)
      raise Error, "Model has not been fit." unless @history

      if df.nil?
        df = @history.dup
      else
        raise ArgumentError, "Dataframe has no rows." if df.shape[0] == 0
        df = setup_dataframe(df.dup)
      end

      df["trend"] = predict_trend(df)
      seasonal_components = predict_seasonal_components(df)
      if @uncertainty_samples
        intervals = predict_uncertainty(df)
      else
        intervals = nil
      end

      # Drop columns except ds, cap, floor, and trend
      cols = ["ds", "trend"]
      cols << "cap" if df.include?("cap")
      cols << "floor" if @logistic_floor
      # Add in forecast components
      df2 = df_concat_axis_one([df[cols], intervals, seasonal_components])
      df2["yhat"] = df2["trend"] * (df2["multiplicative_terms"] + 1) + df2["additive_terms"]
      df2
    end

    def piecewise_linear(t, deltas, k, m, changepoint_ts)
      # Intercept changes
      gammas = -changepoint_ts * deltas
      # Get cumulative slope and intercept at each t
      k_t = t.new_ones * k
      m_t = t.new_ones * m
      changepoint_ts.each_with_index do |t_s, s|
        indx = t >= t_s
        k_t[indx] += deltas[s]
        m_t[indx] += gammas[s]
      end
      k_t * t + m_t
    end

    def piecewise_logistic(t, cap, deltas, k, m, changepoint_ts)
      k_1d = Numo::NArray.asarray(k)
      k_1d = k_1d.reshape(1) if k_1d.ndim < 1
      k_cum = k_1d.concatenate(deltas.cumsum + k)
      gammas = Numo::DFloat.zeros(changepoint_ts.size)
      changepoint_ts.each_with_index do |t_s, i|
        gammas[i] = (t_s - m - gammas.sum) * (1 - k_cum[i] / k_cum[i + 1])
      end
      # Get cumulative rate and offset at each t
      k_t = t.new_ones * k
      m_t = t.new_ones * m
      changepoint_ts.each_with_index do |t_s, s|
        indx = t >= t_s
        k_t[indx] += deltas[s]
        m_t[indx] += gammas[s]
      end
      cap.to_numo / (1 + Numo::NMath.exp(-k_t * (t - m_t)))
    end

    def flat_trend(t, m)
      m_t = m * t.new_ones
      m_t
    end

    def predict_trend(df)
      k = @params["k"].mean(nan: true)
      m = @params["m"].mean(nan: true)
      deltas = @params["delta"].mean(axis: 0, nan: true)

      t = Numo::NArray.asarray(df["t"].to_a)
      if @growth == "linear"
        trend = piecewise_linear(t, deltas, k, m, @changepoints_t)
      elsif @growth == "logistic"
        cap = df["cap_scaled"]
        trend = piecewise_logistic(t, cap, deltas, k, m, @changepoints_t)
      elsif @growth == "flat"
        trend = flat_trend(t, m)
      end

      trend * @y_scale + Numo::NArray.asarray(df["floor"].to_a)
    end

    def predict_seasonal_components(df)
      seasonal_features, _, component_cols, _ = make_all_seasonality_features(df)
      if @uncertainty_samples
        lower_p = 100 * (1.0 - @interval_width) / 2
        upper_p = 100 * (1.0 + @interval_width) / 2
      end

      x = seasonal_features.to_numo
      data = {}
      component_cols.columns.each do |component|
        beta_c =  @params["beta"] * component_cols[component].to_numo

        comp = x.dot(beta_c.transpose)
        if @component_modes["additive"].include?(component)
          comp *= @y_scale
        end
        data[component] = comp.mean(axis: 1, nan: true)
        if @uncertainty_samples
          data["#{component}_lower"] = comp.percentile(lower_p, axis: 1)
          data["#{component}_upper"] = comp.percentile(upper_p, axis: 1)
        end
      end
      Polars::DataFrame.new(data)
    end

    def sample_posterior_predictive(df)
      n_iterations = @params["k"].shape[0]
      samp_per_iter = [1, (@uncertainty_samples / n_iterations.to_f).ceil].max

      # Generate seasonality features once so we can re-use them.
      seasonal_features, _, component_cols, _ = make_all_seasonality_features(df)

      # convert to Numo for performance
      seasonal_features = seasonal_features.to_numo
      additive_terms = component_cols["additive_terms"].to_numo
      multiplicative_terms = component_cols["multiplicative_terms"].to_numo

      sim_values = {"yhat" => [], "trend" => []}
      n_iterations.times do |i|
        samp_per_iter.times do
          sim = sample_model(
            df,
            seasonal_features,
            i,
            additive_terms,
            multiplicative_terms
          )
          sim_values.each_key do |key|
            sim_values[key] << sim[key]
          end
        end
      end
      sim_values.each do |k, v|
        sim_values[k] = Numo::NArray.column_stack(v)
      end
      sim_values
    end

    def predictive_samples(df)
      df = setup_dataframe(df.dup)
      sim_values = sample_posterior_predictive(df)
      sim_values
    end

    def predict_uncertainty(df)
      sim_values = sample_posterior_predictive(df)

      lower_p = 100 * (1.0 - @interval_width) / 2
      upper_p = 100 * (1.0 + @interval_width) / 2

      series = {}
      ["yhat", "trend"].each do |key|
        series["#{key}_lower"] = sim_values[key].percentile(lower_p, axis: 1)
        series["#{key}_upper"] = sim_values[key].percentile(upper_p, axis: 1)
      end

      Polars::DataFrame.new(series)
    end

    def sample_model(df, seasonal_features, iteration, s_a, s_m)
      trend = sample_predictive_trend(df, iteration)

      beta = @params["beta"][iteration, true]
      xb_a = seasonal_features.dot(beta * s_a) * @y_scale
      xb_m = seasonal_features.dot(beta * s_m)

      sigma = @params["sigma_obs"][iteration]
      noise = Numo::DFloat.new(*df.shape[0]).rand_norm(0, sigma) * @y_scale

      # skip data frame for performance
      {
        "yhat" => trend * (1 + xb_m) + xb_a + noise,
        "trend" => trend
      }
    end

    def sample_predictive_trend(df, iteration)
      k = @params["k"][iteration]
      m = @params["m"][iteration]
      deltas = @params["delta"][iteration, true]

      t = Numo::NArray.asarray(df["t"].to_a)
      upper_t = t.max

      # New changepoints from a Poisson process with rate S on [1, T]
      if upper_t > 1
        s = @changepoints_t.size
        n_changes = poisson(s * (upper_t - 1))
      else
        n_changes = 0
      end
      if n_changes > 0
        changepoint_ts_new = 1 + Numo::DFloat.new(n_changes).rand * (upper_t - 1)
        changepoint_ts_new.sort
      else
        changepoint_ts_new = []
      end

      # Get the empirical scale of the deltas, plus epsilon to avoid NaNs.
      lambda_ = deltas.abs.mean + 1e-8

      # Sample deltas
      deltas_new = laplace(0, lambda_, n_changes)

      # Prepend the times and deltas from the history
      changepoint_ts = @changepoints_t.concatenate(changepoint_ts_new)
      deltas = deltas.concatenate(deltas_new)

      if @growth == "linear"
        trend = piecewise_linear(t, deltas, k, m, changepoint_ts)
      elsif @growth == "logistic"
        cap = df["cap_scaled"]
        trend = piecewise_logistic(t, cap, deltas, k, m, changepoint_ts)
      elsif @growth == "flat"
        trend = flat_trend(t, m)
      end

      trend * @y_scale + Numo::NArray.asarray(df["floor"].to_a)
    end

    def make_future_dataframe(periods:, freq: "D", include_history: true)
      raise Error, "Model has not been fit" unless @history_dates
      last_date = @history_dates.max
      # TODO add more freq
      # https://pandas.pydata.org/pandas-docs/stable/user_guide/timeseries.html#timeseries-offset-aliases
      case freq
      when /\A\d+S\z/
        secs = freq.to_i
        dates = (periods + 1).times.map { |i| last_date + i * secs }
      when "H"
        hour = 3600
        dates = (periods + 1).times.map { |i| last_date + i * hour }
      when "D"
        # days have constant length with UTC (no DST or leap seconds)
        day = 24 * 3600
        dates = (periods + 1).times.map { |i| last_date + i * day }
      when "W"
        week = 7 * 24 * 3600
        dates = (periods + 1).times.map { |i| last_date + i * week }
      when "MS"
        dates = [last_date]
        # TODO reset day from last date, but keep time
        periods.times do
          dates << dates.last.to_datetime.next_month.to_time.utc
        end
      when "QS"
        dates = [last_date]
        # TODO reset day and month from last date, but keep time
        periods.times do
          dates << dates.last.to_datetime.next_month.next_month.next_month.to_time.utc
        end
      when "YS"
        dates = [last_date]
        # TODO reset day and month from last date, but keep time
        periods.times do
          dates << dates.last.to_datetime.next_year.to_time.utc
        end
      else
        raise ArgumentError, "Unknown freq: #{freq}"
      end
      dates.select! { |d| d > last_date }
      dates = dates.last(periods)
      dates = @history_dates.to_numo.concatenate(Numo::NArray.cast(dates)) if include_history
      Polars::DataFrame.new({"ds" => dates})
    end

    def to_json
      require "json"

      JSON.generate(as_json)
    end

    private

    def convert_df(df)
      if defined?(Daru::DataFrame) && df.is_a?(Daru::DataFrame)
        Polars::DataFrame.new(df.to_h.transform_values(&:to_a))
      elsif defined?(Rover::DataFrame) && df.is_a?(Rover::DataFrame)
        Polars::DataFrame.new(df.to_h)
      else
        df
      end
    end

    # Time is preferred over DateTime in Ruby docs
    # use UTC to be consistent with Python
    # and so days have equal length (no DST)
    def to_datetime(vec)
      return if vec.nil?
      vec =
        vec.map do |v|
          case v
          when Time
            v.utc
          when Date
            v.to_datetime.to_time.utc
          else
            DateTime.parse(v.to_s).to_time.utc
          end
        end
      Polars::Series.new(vec)
    end

    # okay to do in-place
    def df_concat_axis_one(dfs)
      Polars.concat(dfs, how: "horizontal")
    end

    # https://en.wikipedia.org/wiki/Poisson_distribution#Generating_Poisson-distributed_random_variables
    def poisson(lam)
      l = Math.exp(-lam)
      k = 0
      p = 1
      while p > l
        k += 1
        p *= rand
      end
      k - 1
    end

    # https://en.wikipedia.org/wiki/Laplace_distribution#Generating_values_from_the_Laplace_distribution
    def laplace(loc, scale, size)
      u = Numo::DFloat.new(size).rand(-0.5, 0.5)
      loc - scale * u.sign * Numo::NMath.log(1 - 2 * u.abs)
    end

    SIMPLE_ATTRIBUTES = [
      "growth", "n_changepoints", "specified_changepoints", "changepoint_range",
      "yearly_seasonality", "weekly_seasonality", "daily_seasonality",
      "seasonality_mode", "seasonality_prior_scale", "changepoint_prior_scale",
      "holidays_prior_scale", "mcmc_samples", "interval_width", "uncertainty_samples",
      "y_scale", "logistic_floor", "country_holidays", "component_modes"
    ]

    PD_SERIES = ["changepoints", "history_dates", "train_holiday_names"]

    PD_TIMESTAMP = ["start"]

    PD_TIMEDELTA = ["t_scale"]

    PD_DATAFRAME = ["holidays", "history", "train_component_cols"]

    NP_ARRAY = ["changepoints_t"]

    ORDEREDDICT = ["seasonalities", "extra_regressors"]

    def as_json
      if @history.nil?
        raise Error, "This can only be used to serialize models that have already been fit."
      end

      model_dict =
        SIMPLE_ATTRIBUTES.to_h do |attribute|
          [attribute, instance_variable_get("@#{attribute}")]
        end

      # Handle attributes of non-core types
      PD_SERIES.each do |attribute|
        if instance_variable_get("@#{attribute}").nil?
          model_dict[attribute] = nil
        else
          v = instance_variable_get("@#{attribute}")
          d = {
            "name" => "ds",
            "index" => v.size.times.to_a,
            "data" => v.to_a.map { |v| v.iso8601(3).chomp("Z") }
          }
          model_dict[attribute] = JSON.generate(d)
        end
      end
      PD_TIMESTAMP.each do |attribute|
        model_dict[attribute] = instance_variable_get("@#{attribute}").to_f
      end
      PD_TIMEDELTA.each do |attribute|
        model_dict[attribute] = instance_variable_get("@#{attribute}").to_f
      end
      PD_DATAFRAME.each do |attribute|
        if instance_variable_get("@#{attribute}").nil?
          model_dict[attribute] = nil
        else
          # use same format as Pandas
          v = instance_variable_get("@#{attribute}")

          v = v.dup
          v.drop_in_place("col") if v.include?("col")

          fields =
            v.get_columns.map do |v|
              type =
                if v.datelike?
                  "datetime"
                elsif v.numeric? && !v.float?
                  "integer"
                else
                  "number"
                end
              {"name" => v.name, "type" => type}
            end

          v["ds"] = v["ds"].map { |v| v.iso8601(3).chomp("Z") } if v.include?("ds")

          d = {
            "schema" => {
              "fields" => fields,
              "pandas_version" => "1.4.0"
            },
            "data" => v.to_a
          }
          model_dict[attribute] = JSON.generate(d)
        end
      end
      NP_ARRAY.each do |attribute|
        model_dict[attribute] = instance_variable_get("@#{attribute}").to_a
      end
      ORDEREDDICT.each do |attribute|
        model_dict[attribute] = [
          instance_variable_get("@#{attribute}").keys,
          instance_variable_get("@#{attribute}").transform_keys(&:to_s)
        ]
      end
      # Other attributes with special handling
      # fit_kwargs -> Transform any numpy types before serializing.
      # They do not need to be transformed back on deserializing.
      # TODO deep copy
      fit_kwargs = @fit_kwargs.to_h { |k, v| [k.to_s, v.dup] }
      if fit_kwargs.key?("init")
        fit_kwargs["init"].each do |k, v|
          if v.is_a?(Numo::NArray)
            fit_kwargs["init"][k] = v.to_a
          # elsif v.is_a?(Float)
          #   fit_kwargs["init"][k] = v.to_f
          end
        end
      end
      model_dict["fit_kwargs"] = fit_kwargs

      # Params (Dict[str, np.ndarray])
      model_dict["params"] = params.transform_values(&:to_a)
      # Attributes that are skipped: stan_fit, stan_backend
      model_dict["__prophet_version"] = "1.1.2"
      model_dict
    end

    def self.from_json(model_json)
      require "json"

      model_dict = JSON.parse(model_json)

      # We will overwrite all attributes set in init anyway
      model = Prophet.new
      # Simple types
      SIMPLE_ATTRIBUTES.each do |attribute|
        model.instance_variable_set("@#{attribute}", model_dict.fetch(attribute))
      end
      PD_SERIES.each do |attribute|
        if model_dict[attribute].nil?
          model.instance_variable_set("@#{attribute}", nil)
        else
          d = JSON.parse(model_dict.fetch(attribute))
          s = Polars::Series.new(d["data"])
          if d["name"] == "ds"
            s = s.map { |v| DateTime.parse(v).to_time.utc }
          end
          model.instance_variable_set("@#{attribute}", s)
        end
      end
      PD_TIMESTAMP.each do |attribute|
        model.instance_variable_set("@#{attribute}", Time.at(model_dict.fetch(attribute)))
      end
      PD_TIMEDELTA.each do |attribute|
        model.instance_variable_set("@#{attribute}", model_dict.fetch(attribute).to_f)
      end
      PD_DATAFRAME.each do |attribute|
        if model_dict[attribute].nil?
          model.instance_variable_set("@#{attribute}", nil)
        else
          d = JSON.parse(model_dict.fetch(attribute))
          df = Polars::DataFrame.new(d["data"])
          df["ds"] = df["ds"].map { |v| DateTime.parse(v).to_time.utc } if df.include?("ds")
          if attribute == "train_component_cols"
            # Special handling because of named index column
            # df.columns.name = 'component'
            # df.index.name = 'col'
          end
          model.instance_variable_set("@#{attribute}", df)
        end
      end
      NP_ARRAY.each do |attribute|
        model.instance_variable_set("@#{attribute}", Numo::NArray.cast(model_dict.fetch(attribute)))
      end
      ORDEREDDICT.each do |attribute|
        key_list, unordered_dict = model_dict.fetch(attribute)
        od = {}
        key_list.each do |key|
          od[key] = unordered_dict[key].transform_keys(&:to_sym)
        end
        model.instance_variable_set("@#{attribute}", od)
      end
      # Other attributes with special handling
      # fit_kwargs
      model.instance_variable_set(:@fit_kwargs, model_dict["fit_kwargs"].transform_keys(&:to_sym))
      # Params (Dict[str, np.ndarray])
      model.instance_variable_set(:@params, model_dict["params"].transform_values { |v| Numo::NArray.cast(v) })
      # Skipped attributes
      # model.stan_backend = nil
      model.instance_variable_set(:@stan_fit, nil)
      model
    end
  end
end
