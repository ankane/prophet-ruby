import pandas as pd
from prophet import Prophet

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_wp_log_R_outliers1.csv', float_precision='high')

m = Prophet()
m.fit(df, seed=123)
future = m.make_future_dataframe(periods=1096)
forecast = m.predict(future)

df.loc[(df['ds'] > '2010-01-01') & (df['ds'] < '2011-01-01'), 'y'] = None
model = Prophet().fit(df)
model.predict(future)
