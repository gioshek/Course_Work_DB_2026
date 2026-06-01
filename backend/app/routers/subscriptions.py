from fastapi import APIRouter, HTTPException

from app.database import call_db


router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])


@router.get("/plans")
def get_subscription_plans():
    try:
        result_sets = call_db("EXEC dbo.usp_GetSubscriptionPlans")
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error))
