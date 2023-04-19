import pandas as pd
from prophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Polars.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

m = Prophet(changepoints=['2014-01-01'])
m.fit(df)
future = m.make_future_dataframe(periods=365)
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
