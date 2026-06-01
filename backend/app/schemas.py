from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field


PaymentMethod = Literal["Card", "OnlineWallet", "Bonus", "Balance"]


class RegisterUserRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=4, max_length=100)
    date_of_birth: Optional[date] = None


class LoginUserRequest(BaseModel):
    login: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)


class TopUpBalanceRequest(BaseModel):
    amount: float = Field(..., gt=0)
    payment_method: Literal["Card", "OnlineWallet", "Bonus"] = "Card"


class PurchaseBookRequest(BaseModel):
    user_id: int
    payment_method: Literal["Balance"] = "Balance"
    promo_code: Optional[str] = Field(None, max_length=50)


class CreateSubscriptionRequest(BaseModel):
    plan_id: int
    payment_method: Literal["Balance"] = "Balance"


class AddReviewRequest(BaseModel):
    user_id: int
    rating: int = Field(..., ge=1, le=5)
    review_text: Optional[str] = Field(None, max_length=1000)


class UpdateReadingProgressRequest(BaseModel):
    user_id: int
    current_page: int = Field(..., ge=1)


class AdminCreateBookRequest(BaseModel):
    publisher_id: int
    author_ids: list[int] = Field(..., min_length=1)
    genre_ids: list[int] = Field(..., min_length=1)

    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    publication_year: Optional[int] = Field(None, ge=1450, le=2100)
    age_limit: int = Field(0, ge=0)
    page_count: int = Field(..., gt=0)
    price: float = Field(..., ge=0)

    is_free: bool = False
    is_premium: bool = False
    is_available_by_subscription: bool = True
    cover_image_url: Optional[str] = None

    content_text: str = Field(..., min_length=1)
    content_format: Literal["TEXT", "HTML", "EPUB", "PDF"] = "TEXT"


class AdminCreatePublisherRequest(BaseModel):
    publisher_name: str = Field(..., min_length=1, max_length=255)


class AdminCreateAuthorRequest(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)


class AdminCreateGenreRequest(BaseModel):
    genre_name: str = Field(..., min_length=1, max_length=100)
