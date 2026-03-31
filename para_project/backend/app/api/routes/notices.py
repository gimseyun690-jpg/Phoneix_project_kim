from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.notice import Notice
from app.schemas.notice import NoticeDetailResponse, NoticeListItemResponse

router = APIRouter(prefix="/notices", tags=["공지"])


@router.get("", response_model=list[NoticeListItemResponse])
def list_notices(db: Session = Depends(get_db)) -> list[NoticeListItemResponse]:
    notices = (
        db.execute(select(Notice).order_by(Notice.is_pinned.desc(), Notice.published_at.desc()))
        .scalars()
        .all()
    )
    return [NoticeListItemResponse.model_validate(notice) for notice in notices]


@router.get("/{notice_id}", response_model=NoticeDetailResponse)
def read_notice(notice_id: int, db: Session = Depends(get_db)) -> NoticeDetailResponse:
    notice = db.get(Notice, notice_id)
    if notice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="공지를 찾을 수 없습니다.")
    return NoticeDetailResponse.model_validate(notice)
