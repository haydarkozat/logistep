"""
LogiStep API Gateway
--------------------
Mobil uygulamadan (Flutter) gelen teslimat verisini karsilayan FastAPI kopru
katmanidir. Gelen veriyi dogrular ve SAP middleware katmanina iletir.

Calistirma:
    uvicorn api_gateway:app --host 0.0.0.0 --port 8000
"""
import logging
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from sap_middleware import SAPDeliveryManager

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("logistep.gateway")

app = FastAPI(title="LogiStep API Gateway", version="1.0.0")

# Mobil istemcinin erisebilmesi icin CORS (gelistirme amacli genis tutuldu)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class DeliveryPayload(BaseModel):
    """Flutter tarafindaki payload ile birebir eslesir."""

    delivery_id: str = Field(..., examples=["80012345"])
    driver_id: str = Field(..., examples=["DRV_HANS_01"])
    status_code: str = Field(..., examples=["DELIVERED"])
    gps_location: Optional[str] = Field(default=None, examples=["48.6606, 8.9366"])


# SAP yoneticisini uygulama omru boyunca tek sefer olustur
sap_manager = SAPDeliveryManager()


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "LogiStep API Gateway"}


@app.post("/api/v1/delivery/sync")
def sync_delivery(payload: DeliveryPayload):
    logger.info(
        "Teslimat alindi: %s (surucu: %s)", payload.delivery_id, payload.driver_id
    )
    result = sap_manager.update_delivery(payload.delivery_id, payload.status_code)

    if not result.get("success"):
        raise HTTPException(
            status_code=502,
            detail=result.get("message", "SAP islemi basarisiz"),
        )

    return {
        "message": result.get("message", "Lieferung erfolgreich verarbeitet"),
        "delivery_id": payload.delivery_id,
        "sap_status": result.get("status"),
    }
