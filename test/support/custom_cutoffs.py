import pandas as pd
from prophet import Prophet
from prophet.diagnostics import cross_validation, performance_metrics

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

m = Prophet()
m.fit(df, seed=123)

cutoffs = pd.to_datetime(['2013-02-15', '2013-08-15', '2014-02-15'])
df_cv2 = cross_validation(m, cutoffs=cutoffs, horizon='365 days')
print(len(df_cv2))
print(df_cv2.head())
print(df_cv2.tail())
