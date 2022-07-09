import pandas as pd
from prophet import Prophet
from prophet.diagnostics import cross_validation, performance_metrics

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

m = Prophet()
m.fit(df, seed=123)

df_cv = cross_validation(m, initial='730 days', period='180 days', horizon='365 days')
print(len(df_cv))
print(df_cv.head())
print(df_cv.tail())

cutoffs = pd.to_datetime(['2013-02-15', '2013-08-15', '2014-02-15'])
df_cv2 = cross_validation(m, cutoffs=cutoffs, horizon='365 days')
print(len(df_cv2))
print(df_cv2.head())
print(df_cv2.tail())

# df_p = performance_metrics(df_cv)
# print(df_p.head())
