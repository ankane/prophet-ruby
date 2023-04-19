import pandas as pd
from prophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Polars.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

def nfl_sunday(ds):
    date = pd.to_datetime(ds)
    if date.weekday() == 6 and (date.month > 8 or date.month < 2):
        return 1
    else:
        return 0
df['nfl_sunday'] = df['ds'].apply(nfl_sunday)

m = Prophet()
m.add_regressor('nfl_sunday')
m.fit(df)

future = m.make_future_dataframe(periods=365)
future['nfl_sunday'] = future['ds'].apply(nfl_sunday)

forecast = m.predict(future)

m.plot(forecast).savefig('/tmp/py_regressors.png')
m.plot_components(forecast).savefig('/tmp/py_regressors2.png')
