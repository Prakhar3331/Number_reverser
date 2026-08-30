from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_positive_number():
    res = client.post("/api/v1/reverse", json={"number": 12345})
    assert res.status_code == 200
    assert res.json()["reversed_number"] == 54321
    assert res.json()["reversed_string"] == "54321"
    assert res.json()["is_negative"] is False


def test_negative_number():
    res = client.post("/api/v1/reverse", json={"number": -123})
    assert res.status_code == 200
    assert res.json()["reversed_number"] == -321
    assert res.json()["reversed_string"] == "-321"
    assert res.json()["is_negative"] is True


def test_trailing_zeros():
    res = client.post("/api/v1/reverse", json={"number": 1200})
    assert res.status_code == 200
    assert res.json()["reversed_number"] == 21
    assert res.json()["reversed_string"] == "0021"
    assert res.json()["dropped_leading_zeros"] == 2


def test_leading_zeros_string():
    res = client.post("/api/v1/reverse", json={"number": "007"})
    assert res.status_code == 200
    assert res.json()["reversed_number"] == 700
    assert res.json()["reversed_string"] == "700"


def test_zero_value():
    res = client.post("/api/v1/reverse", json={"number": 0})
    assert res.status_code == 200
    assert res.json()["reversed_number"] == 0


def test_get_endpoint():
    res = client.get("/api/v1/reverse?number=98700")
    assert res.status_code == 200
    assert res.json()["reversed_number"] == 789
    assert res.json()["reversed_string"] == "00789"


def test_non_numeric_rejection():
    res = client.post("/api/v1/reverse", json={"number": "abc"})
    assert res.status_code == 422


def test_decimal_rejection():
    res = client.post("/api/v1/reverse", json={"number": "12.34"})
    assert res.status_code == 422


def test_empty_string_rejection():
    res = client.post("/api/v1/reverse", json={"number": ""})
    assert res.status_code == 422


def test_integer_overflow_rejection():
    # 1999999999999999999 reversed exceeds 2^63 - 1
    res = client.post("/api/v1/reverse", json={"number": 1999999999999999999})
    assert res.status_code == 400


def test_health_probes():
    res_liveness = client.get("/healthz")
    assert res_liveness.status_code == 200
    assert res_liveness.json()["status"] == "healthy"

    res_readiness = client.get("/ready")
    assert res_readiness.status_code == 200
    assert res_readiness.json()["status"] == "healthy"


def test_metrics_endpoint():
    res = client.get("/metrics")
    assert res.status_code == 200
    assert "http_requests_total" in res.text


def test_root_endpoint():
    res = client.get("/")
    assert res.status_code == 200
    assert res.json()["status"] == "online"
