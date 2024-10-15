module Prophet
  module Plot
    def plot(fcst, ax: nil, uncertainty: true, plot_cap: true, xlabel: "ds", ylabel: "y", figsize: [10, 6])
      if ax.nil?
        fig = plt.figure(facecolor: "w", figsize: figsize)
        ax = fig.add_subplot(111)
      else
        fig = ax.get_figure
      end
      fcst_t = to_pydatetime(fcst["ds"])
      ax.plot(to_pydatetime(@history["ds"]), @history["y"].to_a, "k.")
      ax.plot(fcst_t, fcst["yhat"].to_a, ls: "-", c: "#0072B2")
      if fcst.include?("cap") && plot_cap
        ax.plot(fcst_t, fcst["cap"].to_a, ls: "--", c: "k")
      end
      if @logistic_floor && fcst.include?("floor") && plot_cap
        ax.plot(fcst_t, fcst["floor"].to_a, ls: "--", c: "k")
      end
      if uncertainty && @uncertainty_samples
        ax.fill_between(fcst_t, fcst["yhat_lower"].to_a, fcst["yhat_upper"].to_a, color: "#0072B2", alpha: 0.2)
      end
      # Specify formatting to workaround matplotlib issue #12925
      locator = dates.AutoDateLocator.new(interval_multiples: false)
      formatter = dates.AutoDateFormatter.new(locator)
      ax.xaxis.set_major_locator(locator)
      ax.xaxis.set_major_formatter(formatter)
      ax.grid(true, which: "major", c: "gray", ls: "-", lw: 1, alpha: 0.2)
      ax.set_xlabel(xlabel)
      ax.set_ylabel(ylabel)
      fig.tight_layout
      fig
    end

    def plot_components(fcst, uncertainty: true, plot_cap: true, weekly_start: 0, yearly_start: 0, figsize: nil)
      components = ["trend"]
      if @train_holiday_names && fcst.include?("holidays")
        components << "holidays"
      end
      # Plot weekly seasonality, if present
      if @seasonalities["weekly"] && fcst.include?("weekly")
        components << "weekly"
      end
      # Yearly if present
      if @seasonalities["yearly"] && fcst.include?("yearly")
        components << "yearly"
      end
      # Other seasonalities
      components.concat(@seasonalities.keys.select { |name| fcst.include?(name) && !["weekly", "yearly"].include?(name) }.sort)
      regressors = {"additive" => false, "multiplicative" => false}
      @extra_regressors.each do |name, props|
        regressors[props[:mode]] = true
      end
      ["additive", "multiplicative"].each do |mode|
        if regressors[mode] && fcst.include?("extra_regressors_#{mode}")
          components << "extra_regressors_#{mode}"
        end
      end
      npanel = components.size

      figsize = figsize || [9, 3 * npanel]
      fig, axes = plt.subplots(npanel, 1, facecolor: "w", figsize: figsize)

      if npanel == 1
        axes = [axes]
      end

      multiplicative_axes = []

      axes.tolist.zip(components) do |ax, plot_name|
        if plot_name == "trend"
          plot_forecast_component(fcst, "trend", ax: ax, uncertainty: uncertainty, plot_cap: plot_cap)
        elsif @seasonalities[plot_name]
          if plot_name == "weekly" || @seasonalities[plot_name][:period] == 7
            plot_weekly(name: plot_name, ax: ax, uncertainty: uncertainty, weekly_start: weekly_start)
          elsif plot_name == "yearly" || @seasonalities[plot_name][:period] == 365.25
            plot_yearly(name: plot_name, ax: ax, uncertainty: uncertainty, yearly_start: yearly_start)
          else
            plot_seasonality(name: plot_name, ax: ax, uncertainty: uncertainty)
          end
        elsif ["holidays", "extra_regressors_additive", "extra_regressors_multiplicative"].include?(plot_name)
          plot_forecast_component(fcst, plot_name, ax: ax, uncertainty: uncertainty, plot_cap: false)
        end
        if @component_modes["multiplicative"].include?(plot_name)
          multiplicative_axes << ax
        end
      end

      fig.tight_layout
      # Reset multiplicative axes labels after tight_layout adjustment
      multiplicative_axes.each do |ax|
        ax = set_y_as_percent(ax)
      end
      fig
    end

    # in Python, this is a separate method
    def add_changepoints_to_plot(ax, fcst, threshold: 0.01, cp_color: "r", cp_linestyle: "--", trend: true)
      artists = []
      if trend
        artists << ax.plot(to_pydatetime(fcst["ds"]), fcst["trend"].to_a, c: cp_color)
      end
      signif_changepoints =
        if @changepoints.size > 0
          (@params["delta"].mean(axis: 0, nan: true).abs >= threshold).mask(@changepoints.to_numo)
        else
          []
        end
      to_pydatetime(signif_changepoints).each do |cp|
        artists << ax.axvline(x: cp, c: cp_color, ls: cp_linestyle)
      end
      artists
    end

    def self.plot_cross_validation_metric(df_cv, metric:, rolling_window: 0.1, ax: nil, figsize: [10, 6], color: "b", point_color: "gray")
      if ax.nil?
        fig = plt.figure(facecolor: "w", figsize: figsize)
        ax = fig.add_subplot(111)
      else
        fig = ax.get_figure
      end
      # Get the metric at the level of individual predictions, and with the rolling window.
      df_none = Diagnostics.performance_metrics(df_cv, metrics: [metric], rolling_window: -1)
      df_h = Diagnostics.performance_metrics(df_cv, metrics: [metric], rolling_window: rolling_window)

      # Some work because matplotlib does not handle timedelta
      # Target ~10 ticks.
      tick_w = df_none["horizon"].max * 1e9 / 10.0
      # Find the largest time resolution that has <1 unit per bin.
      dts = ["D", "h", "m", "s", "ms", "us", "ns"]
      dt_names = ["days", "hours", "minutes", "seconds", "milliseconds", "microseconds", "nanoseconds"]
      dt_conversions = [
        24 * 60 * 60 * 10 ** 9,
        60 * 60 * 10 ** 9,
        60 * 10 ** 9,
        10 ** 9,
        10 ** 6,
        10 ** 3,
        1.0
      ]
      # TODO update
      i = 0
      # dts.each_with_index do |dt, i|
      #   if np.timedelta64(1, dt) < np.timedelta64(tick_w, "ns")
      #     break
      #   end
      # end

      x_plt = df_none["horizon"] * 1e9 / dt_conversions[i].to_f
      x_plt_h = df_h["horizon"] * 1e9 / dt_conversions[i].to_f

      ax.plot(x_plt.to_a, df_none[metric].to_a, ".", alpha: 0.1, c: point_color)
      ax.plot(x_plt_h.to_a, df_h[metric].to_a, "-", c: color)
      ax.grid(true)

      ax.set_xlabel("Horizon (#{dt_names[i]})")
      ax.set_ylabel(metric)
      fig
    end

    def self.plt
      begin
        require "matplotlib/pyplot"
      rescue LoadError
        raise Error, "Install the matplotlib gem for plots"
      end
      Matplotlib::Pyplot
    end

    private

    def plot_forecast_component(fcst, name, ax: nil, uncertainty: true, plot_cap: false, figsize: [10, 6])
      artists = []
      if !ax
        fig = plt.figure(facecolor: "w", figsize: figsize)
        ax = fig.add_subplot(111)
      end
      fcst_t = to_pydatetime(fcst["ds"])
      artists += ax.plot(fcst_t, fcst[name].to_a, ls: "-", c: "#0072B2")
      if fcst.include?("cap") && plot_cap
        artists += ax.plot(fcst_t, fcst["cap"].to_a, ls: "--", c: "k")
      end
      if @logistic_floor && fcst.include?("floor") && plot_cap
        ax.plot(fcst_t, fcst["floor"].to_a, ls: "--", c: "k")
      end
      if uncertainty && @uncertainty_samples
        artists += [ax.fill_between(fcst_t, fcst["#{name}_lower"].to_a, fcst["#{name}_upper"].to_a, color: "#0072B2", alpha: 0.2)]
      end
      # Specify formatting to workaround matplotlib issue #12925
      locator = dates.AutoDateLocator.new(interval_multiples: false)
      formatter = dates.AutoDateFormatter.new(locator)
      ax.xaxis.set_major_locator(locator)
      ax.xaxis.set_major_formatter(formatter)
      ax.grid(true, which: "major", c: "gray", ls: "-", lw: 1, alpha: 0.2)
      ax.set_xlabel("ds")
      ax.set_ylabel(name)
      if @component_modes["multiplicative"].include?(name)
        ax = set_y_as_percent(ax)
      end
      artists
    end

    def seasonality_plot_df(ds)
      df_dict = {"ds" => ds, "cap" => 1.0, "floor" => 0.0}
      @extra_regressors.each_key do |name|
        df_dict[name] = 0.0
      end
      # Activate all conditional seasonality columns
      @seasonalities.values.each do |props|
        if props[:condition_name]
          df_dict[props[:condition_name]] = true
        end
      end
      df = Rover::DataFrame.new(df_dict)
      df = setup_dataframe(df)
      df
    end

    def plot_weekly(ax: nil, uncertainty: true, weekly_start: 0, figsize: [10, 6], name: "weekly")
      artists = []
      if !ax
        fig = plt.figure(facecolor: "w", figsize: figsize)
        ax = fig.add_subplot(111)
      end
      # Compute weekly seasonality for a Sun-Sat sequence of dates.
      start = Date.parse("2017-01-01")
      days = 7.times.map { |i| start + i + weekly_start }
      df_w = seasonality_plot_df(days)
      seas = predict_seasonal_components(df_w)
      days = days.map { |v| v.strftime("%A") }
      artists += ax.plot(days.size.times.to_a, seas[name].to_a, ls: "-", c: "#0072B2")
      if uncertainty && @uncertainty_samples
        artists += [ax.fill_between(days.size.times.to_a, seas["#{name}_lower"].to_a, seas["#{name}_upper"].to_a, color: "#0072B2", alpha: 0.2)]
      end
      ax.grid(true, which: "major", c: "gray", ls: "-", lw: 1, alpha: 0.2)
      ax.set_xticks(days.size.times.to_a)
      ax.set_xticklabels(days)
      ax.set_xlabel("Day of week")
      ax.set_ylabel(name)
      if @seasonalities[name]["mode"] == "multiplicative"
        ax = set_y_as_percent(ax)
      end
      artists
    end

    def plot_yearly(ax: nil, uncertainty: true, yearly_start: 0, figsize: [10, 6], name: "yearly")
      artists = []
      if !ax
        fig = plt.figure(facecolor: "w", figsize: figsize)
        ax = fig.add_subplot(111)
      end
      # Compute yearly seasonality for a Jan 1 - Dec 31 sequence of dates.
      start = Date.parse("2017-01-01")
      days = 365.times.map { |i| start + i + yearly_start }
      df_y = seasonality_plot_df(days)
      seas = predict_seasonal_components(df_y)
      artists += ax.plot(to_pydatetime(df_y["ds"]), seas[name].to_a, ls: "-", c: "#0072B2")
      if uncertainty && @uncertainty_samples
        artists += [ax.fill_between(to_pydatetime(df_y["ds"]), seas["#{name}_lower"].to_a, seas["#{name}_upper"].to_a, color: "#0072B2", alpha: 0.2)]
      end
      ax.grid(true, which: "major", c: "gray", ls: "-", lw: 1, alpha: 0.2)
      months = dates.MonthLocator.new((1..12).to_a, bymonthday: 1, interval: 2)
      ax.xaxis.set_major_formatter(ticker.FuncFormatter.new(lambda { |x, pos = nil| dates.num2date(x).strftime("%B %-e") }))
      ax.xaxis.set_major_locator(months)
      ax.set_xlabel("Day of year")
      ax.set_ylabel(name)
      if @seasonalities[name][:mode] == "multiplicative"
        ax = set_y_as_percent(ax)
      end
      artists
    end

    def plot_seasonality(name:, ax: nil, uncertainty: true, figsize: [10, 6])
      artists = []
      if !ax
        fig = plt.figure(facecolor: "w", figsize: figsize)
        ax = fig.add_subplot(111)
      end
      # Compute seasonality from Jan 1 through a single period.
      start = Time.utc(2017)
      period = @seasonalities[name][:period]
      finish = start + period * 86400
      plot_points = 200
      start = start.to_i
      finish = finish.to_i
      step = (finish - start) / (plot_points - 1).to_f
      days = plot_points.times.map { |i| Time.at(start + i * step).utc }
      df_y = seasonality_plot_df(days)
      seas = predict_seasonal_components(df_y)
      artists += ax.plot(to_pydatetime(df_y["ds"]), seas[name].to_a, ls: "-", c: "#0072B2")
      if uncertainty && @uncertainty_samples
        artists += [ax.fill_between(to_pydatetime(df_y["ds"]), seas["#{name}_lower"].to_a, seas["#{name}_upper"].to_a, color: "#0072B2", alpha: 0.2)]
      end
      ax.grid(true, which: "major", c: "gray", ls: "-", lw: 1, alpha: 0.2)
      step = (finish - start) / (7 - 1).to_f
      xticks = to_pydatetime(7.times.map { |i| Time.at(start + i * step).utc })
      ax.set_xticks(xticks)
      if period <= 2
        fmt_str = "%T"
      elsif period < 14
        fmt_str = "%m/%d %R"
      else
        fmt_str = "%m/%d"
      end
      ax.xaxis.set_major_formatter(ticker.FuncFormatter.new(lambda { |x, pos = nil| dates.num2date(x).strftime(fmt_str) }))
      ax.set_xlabel("ds")
      ax.set_ylabel(name)
      if @seasonalities[name][:mode] == "multiplicative"
        ax = set_y_as_percent(ax)
      end
      artists
    end

    def set_y_as_percent(ax)
      yticks = 100 * ax.get_yticks
      yticklabels = yticks.tolist.map { |y| "%.4g%%" % y }
      ax.set_yticks(ax.get_yticks.tolist)
      ax.set_yticklabels(yticklabels)
      ax
    end

    def plt
      Plot.plt
    end

    def dates
      PyCall.import_module("matplotlib.dates")
    end

    def ticker
      PyCall.import_module("matplotlib.ticker")
    end

    def to_pydatetime(v)
      datetime = PyCall.import_module("datetime")
      v.map { |v| datetime.datetime.utcfromtimestamp(v.to_i) }.to_a
    end
  end
end
