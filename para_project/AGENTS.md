# AGENTS.md

## Project intent
This repository is a paragliding MVP app for club operations and flight decision support.
Focus on a runnable MVP, not production perfection.

## Priorities
1. Make it run end-to-end
2. Keep code simple and understandable
3. Preserve clean folder structure
4. Document exact setup steps
5. Use Korean UI labels where reasonable

## Technical preferences
- Frontend: Flutter
- Backend: FastAPI
- DB: PostgreSQL
- ORM: SQLModel or SQLAlchemy
- Alembic for migrations
- Seed data required

## Domain rules
- Flight recommendation is rule-based, not LLM-based
- Assessment must return score, status, reasons, summary_text
- Skill levels: beginner, intermediate, advanced
- Status values: good, caution, bad

## UI expectations
- Clean card-based layout
- Avoid overly flashy design
- Keep navigation simple
- Korean labels preferred for end-user screens

## Coding rules
- Prefer small, clear files
- Avoid unnecessary abstractions
- Add comments only where logic is non-obvious
- If something is unfinished, leave a precise TODO

## Completion checklist
Before finishing:
- backend runs
- frontend runs
- seed data exists
- README has exact commands
- .env.example exists
- docs/overview.md exists