from enum import Enum


class PilotLevel(str, Enum):
    beginner = "beginner"
    intermediate = "intermediate"
    advanced = "advanced"


class FlightStatus(str, Enum):
    good = "good"
    caution = "caution"
    bad = "bad"
