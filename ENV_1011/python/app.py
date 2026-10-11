"""Simple Flask app that rolls a dice."""

import logging
from random import randint

from flask import Flask, request

# ─── ここからOpenTelemetryの設定を追加 ───
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.system_metrics import SystemMetricsInstrumentor

app = Flask(__name__)

# メトリクス（計測データ）を送信する設定
reader = PeriodicExportingMetricReader(OTLPMetricExporter(endpoint="http://localhost:4317"))
provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(provider)

# 自動計測の有効化
FlaskInstrumentor().instrument_app(app)

SystemMetricsInstrumentor().instrument()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route("/error")
def cause_error():
    return str(1 / 0)  # アクセスすると必ず500エラーになるルート


@app.route("/rolldice")
def roll_dice():
    """Rolls a dice and returns the result."""
    player = request.args.get("player", default=None, type=str)
    result = str(roll())
    if player:
        logger.warning("%s is rolling the dice: %s", player, result)
    else:
        logger.warning("Anonymous player is rolling the dice: %s", result)
    return result


def roll():
    """Rolls a dice and returns the result."""
    return randint(1, 6)

# 🔥 【重要】ここから下の起動処理を追加しました！
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

