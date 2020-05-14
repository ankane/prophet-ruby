import pandas as pd
from fbprophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

m = Prophet(weekly_seasonality=False)
m.add_seasonality(name='monthly', period=30.5, fourier_order=5)
m.fit(df, seed=123)
future = m.make_future_dataframe(periods=365)
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
m.plot(forecast).savefig('/tmp/py_custom_seasonality.png')
m.plot_components(forecast).savefig('/tmp/py_custom_seasonality2.png')
