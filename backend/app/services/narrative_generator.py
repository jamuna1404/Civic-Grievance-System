import logging
import httpx
from sqlalchemy.future import select
from app.models.all_models import Complaint, Department, Jurisdiction, ComplaintEvent

logger = logging.getLogger("narrative_generator")

OLLAMA_URL = "http://localhost:11434/api/generate"

async def generate_narrative_summary(db, complaint: Complaint) -> str:
    """
    Gathers finalized structured facts and calls local Ollama LLM to generate an explainable summary.
    Enforces a strict deterministic guardrail checking for hallucinated facts, falling back to a template (FR-4.9).
    """
    # 1. Gather structured facts
    complaint_id = str(complaint.id)
    status = complaint.status
    subcategory = complaint.subcategory or "General Civic Issue"
    priority_label = complaint.priority_label or "Medium"
    
    # Relationships
    dept_name = "Unassigned"
    if complaint.department_id:
        stmt_dept = select(Department).where(Department.id == complaint.department_id)
        res_dept = await db.execute(stmt_dept)
        dept = res_dept.scalar_one_or_none()
        if dept:
            dept_name = dept.name
            
    ward_name = "Unknown Ward"
    zone_name = "Unknown Zone"
    office_name = "Department Office"
    if complaint.jurisdiction_id:
        stmt_juris = select(Jurisdiction).where(Jurisdiction.id == complaint.jurisdiction_id)
        res_juris = await db.execute(stmt_juris)
        juris = res_juris.scalar_one_or_none()
        if juris:
            ward_name = juris.ward
            zone_name = juris.zone
            office_name = juris.office_name

    # Fetch events timeline
    stmt_events = select(ComplaintEvent).where(ComplaintEvent.complaint_id == complaint.id).order_by(ComplaintEvent.created_at.asc())
    res_events = await db.execute(stmt_events)
    events = res_events.scalars().all()
    timeline_actions = [e.action for e in events]
    timeline_str = " -> ".join(timeline_actions) if timeline_actions else "No actions logged yet."

    # Construct clean template fallback sentence
    fallback = (
        f"Complaint {complaint_id} regarding {subcategory} is currently {status} with {priority_label} priority. "
        f"It is routed to the {office_name} ({ward_name}, {zone_name}) under the {dept_name} department."
    )

    # 2. Build prompt for Ollama LLM
    prompt = (
        f"Generate a short, clear, 1-2 sentence paragraph summarizing the following structured facts of a civic complaint. "
        f"Use ONLY the facts below. Do NOT introduce any outside facts, dates, times, names, or assumptions. "
        f"Do NOT mention any other departments, wards, or statuses. "
        f"\n\nFacts:\n"
        f"- Complaint ID: {complaint_id}\n"
        f"- Department: {dept_name}\n"
        f"- Subcategory: {subcategory}\n"
        f"- Status: {status}\n"
        f"- Ward: {ward_name}\n"
        f"- Zone: {zone_name}\n"
        f"- Office: {office_name}\n"
        f"- Priority: {priority_label}\n"
        f"- Actions timeline: {timeline_str}\n\n"
        f"Summary:"
    )

    # 3. Call Ollama llama3 model
    llm_response = ""
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.post(OLLAMA_URL, json={
                "model": "llama3",
                "prompt": prompt,
                "stream": False
            })
            if resp.status_code == 200:
                llm_response = resp.json().get("response", "").strip()
                logger.info(f"Ollama generation response: {llm_response}")
    except Exception as e:
        logger.warning(f"Ollama call failed: {e}. Falling back to deterministic template.")

    if not llm_response:
        return fallback

    # 4. Guardrails Validation: prevent hallucinated departments, wards, or statuses
    # Get all potential names to check for mismatch
    all_depts_stmt = select(Department)
    all_depts_res = await db.execute(all_depts_stmt)
    all_depts = all_depts_res.scalars().all()
    disallowed_depts = [d.name for d in all_depts if d.name.lower() != dept_name.lower()]

    all_juris_stmt = select(Jurisdiction)
    all_juris_res = await db.execute(all_juris_stmt)
    all_juris = all_juris_res.scalars().all()
    disallowed_wards = [j.ward for j in all_juris if j.ward.lower() != ward_name.lower()]
    
    all_statuses = ["registered", "assigned", "in_progress", "resolved", "closed", "escalated"]
    disallowed_statuses = [s for s in all_statuses if s.lower() != status.lower()]

    # Case-insensitive checks
    response_lower = llm_response.lower()
    violated = False

    # Check for disallowed departments
    for d in disallowed_depts:
        if d.lower() in response_lower:
            logger.warning(f"Guardrail violation: LLM generated department '{d}' which does not match complaint's '{dept_name}'")
            violated = True
            break

    # Check for disallowed wards
    for w in disallowed_wards:
        if w.lower() in response_lower:
            logger.warning(f"Guardrail violation: LLM generated ward '{w}' which does not match complaint's '{ward_name}'")
            violated = True
            break

    # Check for disallowed statuses
    for s in disallowed_statuses:
        if s.lower() in response_lower:
            logger.warning(f"Guardrail violation: LLM generated status '{s}' which does not match complaint's '{status}'")
            violated = True
            break

    if violated:
        logger.info("Discarding LLM response due to guardrail violation. Returning fallback template.")
        return fallback

    return llm_response
