module Prophet
  module Diagnostics
    def self.generate_cutoffs(df, horizon, initial, period)
      # Last cutoff is 'latest date in data - horizon' date
      cutoff = df["ds"].max - horizon
      if cutoff < df["ds"].min
        raise Error, "Less data than horizon."
      end
      result = [cutoff]
      while result[-1] >= df["ds"].min + initial
        cutoff -= period
        # If data does not exist in data range (cutoff, cutoff + horizon]
        if !(((df["ds"] > cutoff) & (df["ds"] <= cutoff + horizon)).any?)
          # Next cutoff point is 'last date before cutoff in data - horizon'
          if cutoff > df["ds"].min
            closest_date = df[df["ds"] <= cutoff].max["ds"]
            cutoff = closest_date - horizon
          end
          # else no data left, leave cutoff as is, it will be dropped.
        end
        result << cutoff
      end
      result = result[0...-1]
      if result.length == 0
        raise Error, "Less data than horizon after initial window. Make horizon or initial shorter."
      end
      # logger.info("Making #{result.length} forecasts with cutoffs between #{result[-1]} and #{result[0]}")
      result.reverse
    end

    def self.cross_validation(model, horizon:, period: nil, initial: nil, cutoffs: nil)
      if model.history.nil?
        raise Error, "Model has not been fit. Fitting the model provides contextual parameters for cross validation."
      end

      df = model.history.dup
      horizon = timedelta(horizon)

      predict_columns = ["ds", "yhat"]
      if model.uncertainty_samples
        predict_columns.concat(["yhat_lower", "yhat_upper"])
      end

      # Identify largest seasonality period
      period_max = 0.0
      model.seasonalities.each do |_, s|
        period_max = [period_max, s[:period]].max
      end
      seasonality_dt = timedelta("#{period_max} days")

      if cutoffs.nil?
        # Set period
        period = period.nil? ? 0.5 * horizon : timedelta(period)

        # Set initial
        initial = initial.nil? ? [3 * horizon, seasonality_dt].max : timedelta(initial)

        # Compute Cutoffs
        cutoffs = generate_cutoffs(df, horizon, initial, period)
      else
        # add validation of the cutoff to make sure that the min cutoff is strictly greater than the min date in the history
        if cutoffs.min <= df["ds"].min
          raise Error, "Minimum cutoff value is not strictly greater than min date in history"
        end
        # max value of cutoffs is <= (end date minus horizon)
        end_date_minus_horizon = df["ds"].max - horizon
        if cutoffs.max > end_date_minus_horizon
          raise Error, "Maximum cutoff value is greater than end date minus horizon, no value for cross-validation remaining"
        end
        initial = cutoffs[0] - df["ds"].min
      end

      # Check if the initial window
      # (that is, the amount of time between the start of the history and the first cutoff)
      # is less than the maximum seasonality period
      if initial < seasonality_dt
        msg = "Seasonality has period of #{period_max} days "
        msg += "which is larger than initial window. "
        msg += "Consider increasing initial."
        # logger.warn(msg)
      end

      predicts = cutoffs.map { |cutoff| single_cutoff_forecast(df, model, cutoff, horizon, predict_columns) }

      # Combine all predicted DataFrame into one DataFrame
      Polars.concat(predicts)
    end

    def self.single_cutoff_forecast(df, model, cutoff, horizon, predict_columns)
      # Generate new object with copying fitting options
      m = prophet_copy(model, cutoff)
      # Train model
      history_c = df.filter(df["ds"] <= cutoff)
      if history_c.height < 2
        raise Error, "Less than two datapoints before cutoff. Increase initial window."
      end
      m.fit(history_c, **model.fit_kwargs)
      # Calculate yhat
      index_predicted = (df["ds"] > cutoff) & (df["ds"] <= cutoff + horizon)
      # Get the columns for the future dataframe
      columns = ["ds"]
      if m.growth == "logistic"
        columns << "cap"
        if m.logistic_floor
          columns << "floor"
        end
      end
      columns.concat(m.extra_regressors.keys)
      columns.concat(m.seasonalities.map { |_, props| props[:condition_name] }.compact)
      yhat = m.predict(df.filter(index_predicted)[columns])
      # Merge yhat(predicts), y(df, original data) and cutoff
      yhat[predict_columns].hstack(df.filter(index_predicted)[["y"]]).hstack(Polars::DataFrame.new({"cutoff" => [cutoff] * yhat.length}))
    end

    def self.prophet_copy(m, cutoff = nil)
      if m.history.nil?
        raise Error, "This is for copying a fitted Prophet object."
      end

      if m.specified_changepoints
        changepoints = m.changepoints
        if !cutoff.nil?
          # Filter change points '< cutoff'
          last_history_date = m.history["ds"][m.history["ds"] <= cutoff].max
          changepoints = changepoints[changepoints < last_history_date]
        end
      else
        changepoints = nil
      end

      # Auto seasonalities are set to False because they are already set in
      # m.seasonalities.
      m2 = m.class.new(
        growth: m.growth,
        n_changepoints: m.n_changepoints,
        changepoint_range: m.changepoint_range,
        changepoints: changepoints,
        yearly_seasonality: false,
        weekly_seasonality: false,
        daily_seasonality: false,
        holidays: m.holidays,
        seasonality_mode: m.seasonality_mode,
        seasonality_prior_scale: m.seasonality_prior_scale,
        changepoint_prior_scale: m.changepoint_prior_scale,
        holidays_prior_scale: m.holidays_prior_scale,
        mcmc_samples: m.mcmc_samples,
        interval_width: m.interval_width,
        uncertainty_samples: m.uncertainty_samples
      )
      m2.extra_regressors = deepcopy(m.extra_regressors)
      m2.seasonalities = deepcopy(m.seasonalities)
      m2.country_holidays = deepcopy(m.country_holidays)
      m2
    end

    def self.timedelta(value)
      if value.is_a?(Numeric)
        # ActiveSupport::Duration is a numeric
        value
      elsif (m = /\A(\d+(\.\d+)?) days\z/.match(value))
        m[1].to_f * 86400
      else
        raise Error, "Unknown time delta"
      end
    end

    def self.deepcopy(value)
      if value.is_a?(Hash)
        value.to_h { |k, v| [deepcopy(k), deepcopy(v)] }
      elsif value.is_a?(Array)
        value.map { |v| deepcopy(v) }
      else
        value.dup
      end
    end

    def self.performance_metrics(df, metrics: nil, rolling_window: 0.1, monthly: false)
      valid_metrics = ["mse", "rmse", "mae", "mape", "mdape", "smape", "coverage"]
      if metrics.nil?
        metrics = valid_metrics
      end
      if (!df.include?("yhat_lower") || !df.include?("yhat_upper")) && metrics.include?("coverage")
        metrics.drop_in_place("coverage")
      end
      if metrics.uniq.length != metrics.length
        raise ArgumentError, "Input metrics must be a list of unique values"
      end
      if !Set.new(metrics).subset?(Set.new(valid_metrics))
        raise ArgumentError, "Valid values for metrics are: #{valid_metrics}"
      end
      df_m = df.dup
      if monthly
        raise Error, "Not implemented yet"
        # df_m["horizon"] = df_m["ds"].dt.to_period("M").astype(int) - df_m["cutoff"].dt.to_period("M").astype(int)
      else
        df_m["horizon"] = df_m["ds"] - df_m["cutoff"]
      end
      df_m = df_m.sort("horizon")
      if metrics.include?("mape") && df_m["y"].abs.min < 1e-8
        # logger.info("Skipping MAPE because y close to 0")
        metrics.drop_in_place("mape")
      end
      if metrics.length == 0
        return nil
      end
      w = (rolling_window * df_m.shape[0]).to_i
      if w >= 0
        w = [w, 1].max
        w = [w, df_m.shape[0]].min
      end
      # Compute all metrics
      dfs = {}
      metrics.each do |metric|
        dfs[metric] = send(metric, df_m, w)
      end
      res = dfs[metrics[0]]
      metrics.each do |metric|
        res_m = dfs[metric]
        res[metric] = res_m[metric]
      end
      res
    end

    def self.rolling_mean_by_h(x, h, w, name)
      # Aggregate over h
      df = Polars::DataFrame.new({"x" => x, "h" => h})
      df2 = df.groupby("h").agg([Polars.sum("x"), Polars.count]).sort("h")
      xs = df2["x"]
      ns = df2["count"]
      hs = df2["h"]

      trailing_i = df2.length - 1
      x_sum = 0
      n_sum = 0
      # We don't know output size but it is bounded by len(df2)
      res_x = [nil] * df2.length

      # Start from the right and work backwards
      (df2.length - 1).downto(0) do |i|
        x_sum += xs[i]
        n_sum += ns[i]
        while n_sum >= w
          # Include points from the previous horizon. All of them if still
          # less than w, otherwise weight the mean by the difference
          excess_n = n_sum - w
          excess_x = excess_n * xs[i] / ns[i]
          res_x[trailing_i] = (x_sum - excess_x) / w
          x_sum -= xs[trailing_i]
          n_sum -= ns[trailing_i]
          trailing_i -= 1
        end
      end

      res_h = hs[(trailing_i + 1)..-1]
      res_x = res_x[(trailing_i + 1)..-1]

      Polars::DataFrame.new({"horizon" => res_h, name => res_x})
    end

    def self.rolling_median_by_h(x, h, w, name)
      # TODO remove
      h = h.cast(Polars::Int64)

      # Aggregate over h
      df = Polars::DataFrame.new({"x" => x, "h" => h})
      grouped = df.groupby("h")
      df2 = grouped.count.sort("h")
      hs = df2["h"]

      res_h = []
      res_x = []
      # Start from the right and work backwards
      i = hs.length - 1
      while i >= 0
        h_i = hs[i]
        xs = df.filter(df["h"] == h_i)["x"].to_a

        next_idx_to_add = (h == h_i).to_numo.cast_to(Numo::UInt8).argmax - 1
        while xs.length < w && next_idx_to_add >= 0
          # Include points from the previous horizon. All of them if still
          # less than w, otherwise just enough to get to w.
          xs << x[next_idx_to_add]
          next_idx_to_add -= 1
        end
        if xs.length < w
          # Ran out of points before getting enough.
          break
        end
        res_h << hs[i]
        res_x << Polars::Series.new(xs).median
        i -= 1
      end
      res_h.reverse!
      res_x.reverse!
      r = Polars::DataFrame.new({"horizon" => res_h, name => res_x})
      # TODO remove
      r["horizon"] = r["horizon"].cast(Polars::Duration)
      r
    end

    def self.mse(df, w)
      se = (df["y"] - df["yhat"]) ** 2
      if w < 0
        return Polars::DataFrame.new({"horizon" => df["horizon"], "mse" => se})
      end
      rolling_mean_by_h(se, df["horizon"], w, "mse")
    end

    def self.rmse(df, w)
      res = mse(df, w)
      res["rmse"] = res["mse"].sqrt
      res.drop_in_place("mse")
      res
    end

    def self.mae(df, w)
      ae = (df["y"] - df["yhat"]).abs
      if w < 0
        return Polars::DataFrame.new({"horizon" => df["horizon"], "mae" => ae})
      end
      rolling_mean_by_h(ae, df["horizon"], w, "mae")
    end

    def self.mape(df, w)
      ape = ((df["y"] - df["yhat"]) / df["y"]).abs
      if w < 0
        return Polars::DataFrame.new({"horizon" => df["horizon"], "mape" => ape})
      end
      rolling_mean_by_h(ape, df["horizon"], w, "mape")
    end

    def self.mdape(df, w)
      ape = ((df["y"] - df["yhat"]) / df["y"]).abs
      if w < 0
        return Polars::DataFrame.new({"horizon" => df["horizon"], "mdape" => ape})
      end
      rolling_median_by_h(ape, df["horizon"], w, "mdape")
    end

    def self.smape(df, w)
      sape = (df["y"] - df["yhat"]).abs / ((df["y"].abs + df["yhat"].abs) / 2)
      if w < 0
        return Polars::DataFrame.new({"horizon" => df["horizon"], "smape" => sape})
      end
      rolling_mean_by_h(sape, df["horizon"], w, "smape")
    end

    def self.coverage(df, w)
      is_covered = (df["y"] >= df["yhat_lower"]) & (df["y"] <= df["yhat_upper"])
      if w < 0
        return Polars::DataFrame.new({"horizon" => df["horizon"], "coverage" => is_covered})
      end
      rolling_mean_by_h(is_covered.cast(Polars::Float64), df["horizon"], w, "coverage")
    end
  end
end
