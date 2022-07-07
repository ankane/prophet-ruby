import pandas as pd
from prophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_yosemite_temps.csv', float_precision='high')

m = Prophet(changepoint_prior_scale=0.01)
m.fit(df, seed=123)
future = m.make_future_dataframe(periods=300, freq='H')
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
m.plot(forecast).savefig('/tmp/py_subdaily.png')
m.plot_components(forecast).savefig('/tmp/py_subdaily2.png')
