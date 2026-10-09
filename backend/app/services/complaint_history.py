"""Helpers for complaint_status_history, shared by the officer status-update
and review endpoints."""


def attach_remarks_to_latest(supabase, complaint_id: str, remarks: str | None) -> None:
    """Attach remarks to the history row the status-change trigger just
    logged for this complaint (its most recent entry). No-op if remarks is
    blank."""
    if not remarks or not remarks.strip():
        return
    latest = (
        supabase.table("complaint_status_history")
        .select("history_id")
        .eq("complaint_id", complaint_id)
        .order("changed_at", desc=True)
        .limit(1)
        .execute()
    )
    if latest.data:
        supabase.table("complaint_status_history").update(
            {"remarks": remarks.strip()}
        ).eq("history_id", latest.data[0]["history_id"]).execute()
