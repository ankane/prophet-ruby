from prophet.serialize import model_from_json

with open('/tmp/model.json', 'r') as fin:
    m = model_from_json(fin.read())  # Load model

future = m.make_future_dataframe(periods=365)
forecast = m.predict(future)
print(forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].tail())
