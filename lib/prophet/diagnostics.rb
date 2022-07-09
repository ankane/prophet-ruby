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
      predicts.reduce(Rover::DataFrame.new) { |memo, v| memo.concat(v) }
    end

    def self.single_cutoff_forecast(df, model, cutoff, horizon, predict_columns)
      # Generate new object with copying fitting options
      m = prophet_copy(model, cutoff)
      # Train model
      history_c = df[df["ds"] <= cutoff]
      if history_c.shape[0] < 2
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
      yhat = m.predict(df[index_predicted][columns])
      # Merge yhat(predicts), y(df, original data) and cutoff
      yhat[predict_columns].merge(df[index_predicted][["y"]]).merge(Rover::DataFrame.new({"cutoff" => [cutoff] * yhat.length}))
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
      if (m = /\A(\d+(\.\d+)?) days\z/.match(value))
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
  end
end
