import pandas as pd
from fbprophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_air_passengers.csv', float_precision='high')

m = Prophet(seasonality_mode='multiplicative')
m.fit(df, seed=123)
future = m.make_future_dataframe(50, freq='MS')
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
m.plot(forecast).savefig('/tmp/py_multiplicative_seasonality.png')
m.plot_components(forecast).savefig('/tmp/py_multiplicative_seasonality2.png')
