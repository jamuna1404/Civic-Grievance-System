"""Officer notification delivery.

Real push/SMS delivery isn't wired up yet for this milestone: notify_officer
is a **dummy implementation** that just logs, mirroring the dummy-OTP
approach in app/routers/auth.py. Replace the body with a real push
notification call once a delivery provider is chosen.
"""


def notify_officer(officer_id: str, complaint_id: str) -> None:
    """Notify an officer that a complaint has been assigned to them."""
    print(f"[notify_officer] officer={officer_id} complaint={complaint_id}")
