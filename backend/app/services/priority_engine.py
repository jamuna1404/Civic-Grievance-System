import re
import logging
from datetime import datetime
from typing import Tuple, Dict, Any, Optional

logger = logging.getLogger("priority_engine")

# Base weights for departments as per SRS Section 4.5
DEPT_BASE_WEIGHTS = {
    1: 20,  # Water Supply & Sewerage
    2: 15,  # Solid Waste Management
    3: 10,  # Roads & Public Works
    4: 25,  # Electricity Grid & Power (High default safety weight)
    5: 10   # Streetlight Maintenance
}

# Severity keyword boosts
SEVERITY_KEYWORDS = {
    "danger": 20, "dangerous": 20,
    "accident": 20, "hazard": 20,
    "injury": 20, "injured": 20,
    "elderly": 15, "child": 15, "disabled": 15,
    "spark": 25, "fire": 25, "blast": 25, "shock": 25,
    "flood": 20, "drown": 20, "toxic": 20,
    "immediate": 15, "urgent": 15, "emergency": 15
}

def compute_priority(
    complaint: Any,
    related_complaints_count: int,
    cv_severity_hint: Optional[str],
    department_sla_hours: Optional[int]
) -> Tuple[int, str, Dict[str, Any]]:
    """
    Computes a transparent, explainable priority score (0-100) and label (Module 4.5).
    Satisfies FR-4.1 and FR-4.2. Fully deterministic, no LLM calls.
    """
    # 1. Base Weight
    dept_id = complaint.department_id
    base_weight = DEPT_BASE_WEIGHTS.get(dept_id, 10) # default to 10 if department not resolved yet
    
    # 2. Severity-keyword boost
    text_to_scan = ((complaint.raw_text or "") + " " + (complaint.transcribed_text or "")).lower()
    keyword_score = 0
    matched_kws = []
    
    for kw, score in SEVERITY_KEYWORDS.items():
        # Match using word prefix boundary to capture inflections (e.g. "spark" in "sparking", "flood" in "flooded")
        if re.search(r"\b" + re.escape(kw), text_to_scan):
            keyword_score += score
            matched_kws.append(f"{kw} (+{score})")

            
    # Cap keyword boost at 35 points
    keyword_boost = min(keyword_score, 35)
    
    # 3. CV severity contribution
    cv_boost = 0
    if cv_severity_hint:
        cv_severity_lower = cv_severity_hint.lower()
        if cv_severity_lower == "severe":
            cv_boost = 25
        elif cv_severity_lower == "moderate":
            cv_boost = 10
        elif cv_severity_lower == "minor":
            cv_boost = 0
            
    # 4. Cluster boost (FR-4.2)
    # If there are >= 2 other open complaints nearby of the same department,
    # then total cluster size including the current one is 3+. We apply a +15 boost.
    cluster_boost = 0
    if related_complaints_count >= 2:
        cluster_boost = 15
        
    # 5. SLA time-decay boost
    # If the complaint is open longer than the department SLA, apply decay boost
    sla_boost = 0
    hours_elapsed = 0.0
    is_at_risk = False
    
    if complaint.created_at:
        time_diff = datetime.utcnow() - complaint.created_at.replace(tzinfo=None)
        hours_elapsed = time_diff.total_seconds() / 3600.0
        
        if department_sla_hours and hours_elapsed > department_sla_hours:
            sla_boost = 15
            is_at_risk = True
            
    # 6. Sum into 0-100 score
    raw_sum = base_weight + keyword_boost + cv_boost + cluster_boost + sla_boost
    final_score = max(0, min(100, raw_sum))
    
    # Map to label
    if final_score >= 86:
        label = "Critical"
    elif final_score >= 61:
        label = "High"
    elif final_score >= 31:
        label = "Medium"
    else:
        label = "Low"
        
    # Detailed breakdown dictionary for audit logs
    breakdown = {
        "base_weight": base_weight,
        "keyword_boost": keyword_boost,
        "matched_keywords": matched_kws,
        "cv_boost": cv_boost,
        "cv_severity_hint": cv_severity_hint,
        "cluster_boost": cluster_boost,
        "related_complaints_count": related_complaints_count,
        "sla_breach_boost": sla_boost,
        "hours_elapsed": round(hours_elapsed, 2),
        "sla_hours": department_sla_hours,
        "at_risk": is_at_risk or (complaint.status == "escalated")
    }
    
    return final_score, label, breakdown
