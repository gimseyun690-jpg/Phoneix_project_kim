from datetime import date, datetime

from pydantic import BaseModel

from app.models.training_log import TrainingLog


class TrainingLogCreateRequest(BaseModel):
    user_id: int
    site_id: int
    training_date: date
    training_type: str
    participated: bool
    flight_success: bool
    difficulty: str
    memo: str


class TrainingLogResponse(BaseModel):
    id: int
    user_id: int
    site_id: int
    site_name: str
    training_date: date
    training_type: str
    participated: bool
    flight_success: bool
    difficulty: str
    memo: str
    created_at: datetime

    @classmethod
    def from_model(cls, log: TrainingLog) -> "TrainingLogResponse":
        return cls(
            id=log.id,
            user_id=log.user_id,
            site_id=log.site_id,
            site_name=log.site.name if log.site else "",
            training_date=log.training_date,
            training_type=log.training_type,
            participated=log.participated,
            flight_success=log.flight_success,
            difficulty=log.difficulty,
            memo=log.memo,
            created_at=log.created_at,
        )
