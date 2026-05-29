from fastapi import APIRouter, HTTPException

from app.database import call_db


router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])


@router.get("/plans")
def get_subscription_plans():
    try:
        result_sets = call_db(
            """
            SELECT
                PlanId,
                PlanName,
                Price,
                DurationDays,
                Description,
                IsActive
            FROM dbo.SubscriptionPlan
            WHERE IsActive = 1
            ORDER BY Price ASC;
            """
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error))