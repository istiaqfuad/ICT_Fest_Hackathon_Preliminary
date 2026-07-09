"""Pydantic request/response models."""

from pydantic import BaseModel, Field, field_validator
from datetime import datetime


class RegisterRequest(BaseModel):
    org_name: str
    username: str
    password: str


class LoginRequest(BaseModel):
    org_name: str
    username: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class RoomCreateRequest(BaseModel):
    name: str
    capacity: int = Field(ge=1)
    hourly_rate_cents: int = Field(ge=0)


class BookingCreateRequest(BaseModel):
    room_id: int
    start_time: str
    end_time: str

    @field_validator("start_time", "end_time")
    @classmethod
    def validate_datetime_format(cls, v: str) -> str:
        try:
            datetime.fromisoformat(v)
        except ValueError:
            raise ValueError(
                "must be a valid ISO-8601 datetime, e.g. 2026-07-10T14:00:00"
            )
        return v
