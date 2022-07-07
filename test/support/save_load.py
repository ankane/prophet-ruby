import pandas as pd
from prophet import Prophet
from prophet.serialize import model_to_json, model_from_json

# float_precision='high' required for pd.read_csv to match precision of Rover.read_csv
df = pd.read_csv('examples/example_wp_log_peyton_manning.csv', float_precision='high')

m = Prophet()
m.fit(df, seed=123)

with open('/tmp/model.json', 'w') as fout:
    fout.write(model_to_json(m))

with open('/tmp/model.json', 'r') as fin:
    m = model_from_json(fin.read())  # Load model

future = m.make_future_dataframe(periods=365)
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
