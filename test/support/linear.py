import pandas as pd
from prophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Polars.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

m = Prophet()
m.fit(df, seed=123)
future = m.make_future_dataframe(periods=365)
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
m.plot(forecast).savefig('/tmp/py_linear.png')
m.plot_components(forecast).savefig('/tmp/py_linear2.png')
