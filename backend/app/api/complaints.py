import os
import tempfile
import requests
import logging
import uuid
from typing import List, Optional, Any, Dict
from fastapi import APIRouter, Depends, UploadFile, File, Form, BackgroundTasks, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func

from app.core.database import get_db, SessionLocal
from app.core.security import get_current_user
from app.core.supabase import supabase_client
from app.models.all_models import User, Complaint, ComplaintEvent, Department
from app.schemas.all_schemas import ComplaintRead
from app.ml.asr import transcribe
from app.services.nlp_classifier import classify_complaint_text
from app.ml.image_analysis import analyze_image
from app.services.gis_resolver import resolve_gis_jurisdiction





router = APIRouter()
logger = logging.getLogger("complaints_api")

async def process_complaint_pipeline(complaint_id: uuid.UUID):
    """
    Async background task executing the AI processing pipeline for a submitted complaint.
    Under Prompt 4, it executes Speech-to-Text translation (Module 4.1).
    """
    logger.info(f"Kicking off processing pipeline for complaint {complaint_id}")
    
    async with SessionLocal() as db:
        # Retrieve the complaint record
        stmt = select(Complaint).where(Complaint.id == complaint_id)
        result = await db.execute(stmt)
        complaint = result.scalar_one_or_none()
        
        if not complaint:
            logger.error(f"Complaint {complaint_id} not found in database.")
            return

        # 1. Speech-to-Text Transcription Module (Module 4.1)
        if complaint.audio_url:
            logger.info(f"Audio file found for complaint {complaint_id}. Downloading for transcription...")
            temp_path = None
            try:
                # Download audio from public Supabase Storage URL
                response = requests.get(complaint.audio_url, timeout=30)
                if response.status_code != 200:
                    raise RuntimeError(f"Failed to download audio file: Status code {response.status_code}")
                
                # Deduce file extension
                ext = complaint.audio_url.split(".")[-1].split("?")[0]
                if not ext or len(ext) > 4:
                    ext = "wav"
                
                # Write to temp file
                with tempfile.NamedTemporaryFile(delete=False, suffix=f".{ext}") as temp_file:
                    temp_file.write(response.content)
                    temp_path = temp_file.name

                logger.info(f"Running faster-whisper transcription on {temp_path}...")
                
                # Run transcription (SRS step 2, 3)
                transcription_result = transcribe(temp_path)
                
                # Update complaint record (SRS step 4)
                complaint.transcribed_text = transcription_result["text"]
                complaint.detected_language = transcription_result["detected_language"]
                
                # Log audit event (SRS step 5)
                # Quote FR-2.1:
                # "FR-2.1: System shall transcribe voice complaints, detecting spoken language."
                audit_event = ComplaintEvent(
                    complaint_id=complaint_id,
                    actor_id=complaint.citizen_id,
                    action="audio_transcribed",
                    note=(
                        f"Voice complaint transcribed. Spoken Language: "
                        f"{transcription_result['detected_language'].upper()} "
                        f"(Confidence: {transcription_result['confidence']:.2f}). "
                        f"Transcript: '{transcription_result['text']}'"
                    )
                )
                db.add(audit_event)
                await db.commit()
                logger.info(f"Transcription saved for complaint {complaint_id}")

            except Exception as e:
                logger.error(f"Error during audio transcription of complaint {complaint_id}: {str(e)}")
                # Append error to timeline for visibility
                error_event = ComplaintEvent(
                    complaint_id=complaint_id,
                    actor_id=complaint.citizen_id,
                    action="transcription_failed",
                    note=f"System failed to transcribe audio: {str(e)}"
                )
                db.add(error_event)
                await db.commit()
            finally:
                # Clean up temp file
                if temp_path and os.path.exists(temp_path):
                    try:
                        os.remove(temp_path)
                        logger.info(f"Cleaned up temporary audio file: {temp_path}")
                    except Exception as clean_err:
                        logger.error(f"Failed to delete temp file {temp_path}: {str(clean_err)}")
        else:
            logger.info(f"No audio file present for complaint {complaint_id}. Skipping STT step.")

        # 2. NLP Department Classification Module (Module 4.2)
        # Prefer raw_text, fall back to transcribed_text
        text_to_classify = complaint.raw_text or complaint.transcribed_text
        if text_to_classify:
            logger.info(f"Running NLP classification on text: '{text_to_classify[:100]}...'")
            try:
                # Retrieve existing departments list from DB
                depts_stmt = select(Department)
                depts_result = await db.execute(depts_stmt)
                depts = depts_result.scalars().all()
                departments_dict = {d.id: d.name for d in depts}
                
                # Execute classification (returns department_id, subcategory, confidence, status)
                nlp_res = await classify_complaint_text(text_to_classify, departments_dict)
                
                complaint.department_id = nlp_res["department_id"]
                complaint.subcategory = nlp_res["subcategory"]
                complaint.nlp_confidence = nlp_res["confidence"]
                complaint.status = nlp_res["status"]
                
                # Log audit event
                # Quote FR-2.2:
                # "FR-2.2: System shall classify each complaint into a department and subcategory with a confidence score."
                # Quote FR-2.3:
                # "FR-2.3: System shall route low-confidence classifications to an admin review queue instead of guessing."
                dept_resolved_name = departments_dict.get(nlp_res["department_id"]) if nlp_res["department_id"] else "None"
                
                audit_note = (
                    f"NLP classification completed. "
                    f"Resolved Department: {dept_resolved_name}, "
                    f"Subcategory: {nlp_res['subcategory']}, "
                    f"Confidence: {nlp_res['confidence']:.2f}, "
                    f"Routing Status: {nlp_res['status']}"
                )
                
                classification_event = ComplaintEvent(
                    complaint_id=complaint_id,
                    actor_id=complaint.citizen_id,
                    action="nlp_classified",
                    note=audit_note
                )
                db.add(classification_event)
                await db.commit()
                logger.info(f"NLP classification saved for complaint {complaint_id}: {nlp_res['status']}")
                
            except Exception as e:
                logger.error(f"Error during NLP classification of complaint {complaint_id}: {str(e)}")
                # Append error to timeline
                error_event = ComplaintEvent(
                    complaint_id=complaint_id,
                    actor_id=complaint.citizen_id,
                    action="classification_failed",
                    note=f"System failed to classify complaint: {str(e)}"
                )
                db.add(error_event)
                await db.commit()
        else:
            logger.warning(f"No text (raw or transcribed) available for complaint {complaint_id}. Skipping NLP classification.")

        # 3. Computer Vision Image Analysis Module (Module 4.3)
        if complaint.image_url:
            logger.info(f"Image found for complaint {complaint_id}. Downloading for CV analysis...")
            temp_img_path = None
            try:
                # Download image from public Supabase Storage URL
                response = requests.get(complaint.image_url, timeout=30)
                if response.status_code != 200:
                    raise RuntimeError(f"Failed to download image file: Status code {response.status_code}")
                
                # Deduce file extension
                ext = complaint.image_url.split(".")[-1].split("?")[0]
                if not ext or len(ext) > 4:
                    ext = "jpg"
                    
                # Write to temp file
                with tempfile.NamedTemporaryFile(delete=False, suffix=f".{ext}") as temp_file:
                    temp_file.write(response.content)
                    temp_img_path = temp_file.name

                logger.info(f"Running zero-shot CLIP analysis on {temp_img_path}...")
                
                # Execute CV analysis
                cv_res = analyze_image(temp_img_path)
                
                # Persist CV outputs
                complaint.cv_label = cv_res["label"]
                complaint.cv_confidence = cv_res["confidence"]
                complaint.cv_severity = cv_res["severity_hint"]
                
                # Log audit event
                # "FR-2.4: System shall analyze submitted images for issue type and severity cues."
                cv_event = ComplaintEvent(
                    complaint_id=complaint_id,
                    actor_id=complaint.citizen_id,
                    action="image_analyzed",
                    note=(
                        f"Image analysis completed. Matched Label: '{cv_res['label']}' "
                        f"(Confidence: {cv_res['confidence']:.2f}). "
                        f"Resolved Severity Hint: {cv_res['severity_hint'].upper()}"
                    )
                )
                db.add(cv_event)
                
                # Retrieve existing departments list from DB for cross-checking
                depts_stmt = select(Department)
                depts_result = await db.execute(depts_stmt)
                depts = depts_result.scalars().all()
                departments_dict = {d.id: d.name for d in depts}
                
                # Cross-check CV label against NLP department result (FR-2.5)
                # Map CV label to department names
                CV_LABEL_TO_DEPT = {
                    "pothole": "Roads & Public Works",
                    "garbage pile": "Solid Waste Management",
                    "broken streetlight": "Streetlight Maintenance",
                    "pipe leak": "Water Supply & Sewerage",
                    "overflowing drain": "Water Supply & Sewerage",
                    "fallen tree": "Roads & Public Works",
                    "damaged electricity pole": "Electricity Grid & Power"
                }
                
                nlp_dept_name = departments_dict.get(complaint.department_id) if complaint.department_id else None
                cv_label_key = cv_res["label"]
                
                if cv_label_key in CV_LABEL_TO_DEPT and nlp_dept_name:
                    expected_dept_name = CV_LABEL_TO_DEPT[cv_label_key]
                    if expected_dept_name != nlp_dept_name:
                        # Conflict detected!
                        logger.warning(
                            f"Classification conflict for complaint {complaint_id}: "
                            f"NLP matched '{nlp_dept_name}', CV matched '{expected_dept_name}'."
                        )
                        complaint.cv_conflict = True
                        
                        # Log conflict event (FR-2.5)
                        # Quote FR-2.5:
                        # "FR-2.5: System shall flag disagreement between text-based and image-based classification for admin visibility."
                        conflict_event = ComplaintEvent(
                            complaint_id=complaint_id,
                            actor_id=complaint.citizen_id,
                            action="classification_conflict",
                            note=(
                                f"Disagreement detected between text classification ({nlp_dept_name}) "
                                f"and image classification ({expected_dept_name}). "
                                f"Flagged for manual admin verification."
                            )
                        )
                        db.add(conflict_event)
                
                await db.commit()
                logger.info(f"CV analysis completed successfully for complaint {complaint_id}")

            except Exception as e:
                logger.error(f"Error during CV analysis of complaint {complaint_id}: {str(e)}")
                # Append error to timeline
                error_event = ComplaintEvent(
                    complaint_id=complaint_id,
                    actor_id=complaint.citizen_id,
                    action="cv_analysis_failed",
                    note=f"System failed to analyze complaint image: {str(e)}"
                )
                db.add(error_event)
                await db.commit()
            finally:
                # Clean up temp file
                if temp_img_path and os.path.exists(temp_img_path):
                    try:
                        os.remove(temp_img_path)
                        logger.info(f"Cleaned up temporary image file: {temp_img_path}")
                    except Exception as clean_err:
                        logger.error(f"Failed to delete temp file {temp_img_path}: {str(clean_err)}")
        else:
            logger.info(f"No image present for complaint {complaint_id}. Skipping CV analysis.")

        # 4. GIS Location Intelligence Module (Module 4.4)
        logger.info(f"Running GIS Resolution for complaint {complaint_id}...")
        try:
            # Query the PostGIS Point coordinates directly using ST_X and ST_Y
            stmt_coords = select(func.ST_X(Complaint.location), func.ST_Y(Complaint.location)).where(Complaint.id == complaint_id)
            coords_res = await db.execute(stmt_coords)
            coords_row = coords_res.first()
            
            lng_val, lat_val = None, None
            if coords_row and coords_row[0] is not None:
                lng_val, lat_val = coords_row[0], coords_row[1]
                
            # Execute GIS resolution (Polygon contains, address geocoding, centroid fallbacks)
            gis_res = await resolve_gis_jurisdiction(
                db=db,
                lat=lat_val,
                lng=lng_val,
                address_text=complaint.address_text,
                department_id=complaint.department_id
            )
            
            complaint.jurisdiction_id = gis_res["jurisdiction_id"]
            complaint.gis_resolution_method = gis_res["gis_resolution_method"]
            complaint.jurisdiction_uncertain = gis_res["jurisdiction_uncertain"]
            
            # If geocoding resolved coordinates, save them back to PostGIS point
            if gis_res["resolved_lat"] is not None and gis_res["resolved_lng"] is not None and (lat_val is None or lng_val is None):
                complaint.location = func.ST_SetSRID(func.ST_MakePoint(gis_res["resolved_lng"], gis_res["resolved_lat"]), 4326)
                
            # If location resolved to a jurisdiction, look up office details for the timeline note
            office_desc = "None (Manual Assignment Needed)"
            if gis_res["jurisdiction_id"]:
                stmt_juris = select(Jurisdiction).where(Jurisdiction.id == gis_res["jurisdiction_id"])
                juris_res = await db.execute(stmt_juris)
                matched_j = juris_res.scalar_one_or_none()
                if matched_j:
                    office_desc = f"{matched_j.office_name} ({matched_j.ward}, {matched_j.zone})"
            
            # "FR-3.3: if no polygon contains the point, fall back to nearest jurisdiction centroid... and flag 'jurisdiction_uncertain'"
            if gis_res["jurisdiction_uncertain"]:
                complaint.status = "needs_review"
                
            # Log timeline event
            # Quote FR-3.1:
            # "FR-3.1: System shall resolve a complaint's zone, ward, and responsible office from its location."
            # Quote FR-3.3:
            # "FR-3.3: System shall flag complaints whose location cannot be confidently resolved for manual assignment."
            gis_note = (
                f"GIS resolution complete. Assigned Office: {office_desc}. "
                f"Method: {gis_res['gis_resolution_method']}. "
                f"Uncertainty Flag: {gis_res['jurisdiction_uncertain']}"
            )
            
            gis_event = ComplaintEvent(
                complaint_id=complaint_id,
                actor_id=complaint.citizen_id,
                action="gis_resolved",
                note=gis_note
            )
            db.add(gis_event)
            await db.commit()
            logger.info(f"GIS Resolution saved for complaint {complaint_id}")
            
        except Exception as e:
            logger.error(f"Error during GIS Resolution of complaint {complaint_id}: {str(e)}")
            error_event = ComplaintEvent(
                complaint_id=complaint_id,
                actor_id=complaint.citizen_id,
                action="gis_failed",
                note=f"System failed to resolve GIS jurisdiction: {str(e)}"
            )
            db.add(error_event)
            await db.commit()






@router.post("", status_code=status.HTTP_201_CREATED)

async def create_complaint(
    background_tasks: BackgroundTasks,
    text: Optional[str] = Form(None),
    location_lat: Optional[float] = Form(None),
    location_lng: Optional[float] = Form(None),
    address_text: Optional[str] = Form(None),
    image: Optional[UploadFile] = File(None),
    audio: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Intake a new complaint with multi-modal inputs (FR-1.1 - FR-1.4).
    Uploads media files directly to Supabase storage.
    """
    # Quote FR-1.2:
    # "FR-1.2: System shall require at least one of text/image/audio per complaint."
    if not text and not image and not audio:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Complaint must contain at least one modality: text, image, or audio."
        )

    # Quote FR-1.3:
    # "FR-1.3: System shall accept location as GPS coordinates or free-text address."
    has_coords = (location_lat is not None) and (location_lng is not None)
    has_address = address_text is not None and len(address_text.strip()) > 0
    if not has_coords and not has_address:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Complaint must contain location details (either lat/lng coordinates or address text)."
        )

    complaint_id = uuid.uuid4()
    image_url = None
    audio_url = None

    # Upload files directly to Supabase Storage bucket
    if image:
        try:
            file_bytes = await image.read()
            file_ext = image.filename.split(".")[-1] if image.filename else "jpg"
            storage_path = f"complaint-media/{complaint_id}/image.{file_ext}"
            
            # Execute upload
            supabase_client.storage.from_("complaint-media").upload(
                path=storage_path,
                file=file_bytes,
                file_options={"content-type": image.content_type or "image/jpeg"}
            )
            image_url = supabase_client.storage.from_("complaint-media").get_public_url(storage_path)
        except Exception as e:
            logger.error(f"Failed to upload image file to Supabase: {str(e)}")
            # We fail-safe or let it proceed depending on requirements. Let's raise error.
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to process and store image upload: {str(e)}"
            )

    if audio:
        try:
            file_bytes = await audio.read()
            file_ext = audio.filename.split(".")[-1] if audio.filename else "wav"
            storage_path = f"complaint-media/{complaint_id}/audio.{file_ext}"
            
            supabase_client.storage.from_("complaint-media").upload(
                path=storage_path,
                file=file_bytes,
                file_options={"content-type": audio.content_type or "audio/wav"}
            )
            audio_url = supabase_client.storage.from_("complaint-media").get_public_url(storage_path)
        except Exception as e:
            logger.error(f"Failed to upload audio file to Supabase: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to process and store audio upload: {str(e)}"
            )

    # Set up PostGIS point geometry if coordinates are available
    location_geom = None
    if has_coords:
        location_geom = func.ST_SetSRID(func.ST_MakePoint(location_lng, location_lat), 4326)

    # Create model instance
    complaint = Complaint(
        id=complaint_id,
        citizen_id=current_user.id,
        raw_text=text,
        image_url=image_url,
        audio_url=audio_url,
        status="registered",
        location=location_geom,
        address_text=address_text,
    )

    db.add(complaint)

    # Add initial event to audit timeline
    initial_event = ComplaintEvent(
        complaint_id=complaint_id,
        actor_id=current_user.id,
        action="registered",
        note="Grievance submitted successfully by citizen."
    )
    db.add(initial_event)

    await db.commit()

    # Quote FR-1.4:
    # "FR-1.4: System shall return a complaint ID immediately without blocking on AI processing."
    # Queue the background pipeline processing
    background_tasks.add_task(process_complaint_pipeline, complaint_id)

    return {
        "status": "registered",
        "complaint_id": str(complaint_id),
        "message": "Complaint registered successfully."
    }


@router.get("", response_model=List[ComplaintRead])
async def list_complaints(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    List complaints. Scoped by RLS and client-side roles.
    """
    # For citizens: only return their own complaints
    if current_user.role == "citizen":
        stmt = select(
            Complaint,
            func.ST_X(Complaint.location).label("location_lng"),
            func.ST_Y(Complaint.location).label("location_lat")
        ).where(Complaint.citizen_id == current_user.id)
    else:
        # For staff (officers/supervisors): only return complaints in their jurisdiction
        # Wait, if they don't have a jurisdiction assigned, they can't view any.
        if not current_user.jurisdiction_id:
            return []
        stmt = select(
            Complaint,
            func.ST_X(Complaint.location).label("location_lng"),
            func.ST_Y(Complaint.location).label("location_lat")
        ).where(Complaint.jurisdiction_id == current_user.jurisdiction_id)

    result = await db.execute(stmt)
    complaints_list = []
    for row in result:
        comp, lng, lat = row
        # Map values back to schema format
        comp_dict = {c.name: getattr(comp, c.name) for c in comp.__table__.columns}
        comp_dict["location_lng"] = lng
        comp_dict["location_lat"] = lat
        complaints_list.append(ComplaintRead.model_validate(comp_dict))

    return complaints_list


@router.get("/{complaint_id}", response_model=ComplaintRead)
async def get_complaint(
    complaint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Retrieve specific complaint details by ID.
    """
    stmt = select(
        Complaint,
        func.ST_X(Complaint.location).label("location_lng"),
        func.ST_Y(Complaint.location).label("location_lat")
    ).where(Complaint.id == complaint_id)

    result = await db.execute(stmt)
    row = result.first()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Complaint not found."
        )

    comp, lng, lat = row

    # Enforce role-based access checks (aligns with database RLS rules)
    if current_user.role == "citizen" and comp.citizen_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to view this complaint."
        )
    elif current_user.role in ["officer", "supervisor"] and comp.jurisdiction_id != current_user.jurisdiction_id:
        # Note: If complaint is newly registered and not assigned a jurisdiction yet,
        # but the request is from a staff member, we might block or allow depending on triage status.
        # Let's allow access for now if the user is an admin or is handling triage.
        if comp.jurisdiction_id is not None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This complaint belongs to another jurisdiction."
            )

    comp_dict = {c.name: getattr(comp, c.name) for c in comp.__table__.columns}
    comp_dict["location_lng"] = lng
    comp_dict["location_lat"] = lat

    return ComplaintRead.model_validate(comp_dict)


@router.get("/{complaint_id}/timeline")
async def get_complaint_timeline(
    complaint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Retrieve full audit timeline for a specific complaint.
    """
    # Verify complaint visibility first
    stmt = select(Complaint).where(Complaint.id == complaint_id)
    result = await db.execute(stmt)
    comp = result.scalar_one_or_none()
    if not comp:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Complaint not found."
        )

    if current_user.role == "citizen" and comp.citizen_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied."
        )

    # Fetch events
    events_stmt = select(ComplaintEvent).where(ComplaintEvent.complaint_id == complaint_id).order_by(ComplaintEvent.created_at.asc())
    events_result = await db.execute(events_stmt)
    events = events_result.scalars().all()

    return [
        {
            "id": str(e.id),
            "action": e.action,
            "note": e.note,
            "created_at": e.created_at.isoformat()
        }
        for e in events
    ]
