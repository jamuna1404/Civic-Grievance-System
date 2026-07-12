import os
import json
import re
import logging
import numpy as np
from typing import List, Tuple, Dict, Optional
from sentence_transformers import SentenceTransformer

logger = logging.getLogger("nlp_classifier")

# Check if FAISS is available
try:
    import faiss
    HAS_FAISS = True
    logger.info("FAISS is available in the environment.")
except ImportError:
    HAS_FAISS = False
    logger.warning("FAISS not found in the environment. CosineSimilarityClassifier will use NumPy fallback.")

# Model is initialized lazily
_model = None

def get_sentence_model() -> SentenceTransformer:
    global _model
    if _model is None:
        logger.info("Initializing SentenceTransformer Model (all-MiniLM-L6-v2)...")
        # Load lightweight MiniLM sentence transformer model
        _model = SentenceTransformer("all-MiniLM-L6-v2")
    return _model


# Load Tamil-English civic-term lookup table
LOOKUP_FILE = os.path.join(os.path.dirname(__file__), "civic_lookup.json")
_civic_lookup = None

def get_civic_lookup() -> Dict[str, str]:
    global _civic_lookup
    if _civic_lookup is None:
        if os.path.exists(LOOKUP_FILE):
            try:
                with open(LOOKUP_FILE, "r", encoding="utf-8") as f:
                    _civic_lookup = json.load(f)
                logger.info(f"Loaded {len(_civic_lookup)} terms from civic_lookup.json")
            except Exception as e:
                logger.error(f"Failed to parse civic_lookup.json: {str(e)}")
                _civic_lookup = {}
        else:
            logger.warning(f"civic_lookup.json not found at {LOOKUP_FILE}. Using empty mapping.")
            _civic_lookup = {}
    return _civic_lookup


def normalize_text(text: str) -> str:
    """
    Step 1: Normalize text (lowercase, strip noise, map Tamil-English civic terms).
    """
    if not text:
        return ""
        
    # Lowercase and clean punctuation
    text_lower = text.lower().strip()
    words = re.findall(r"\b\w+\b", text_lower)
    
    lookup = get_civic_lookup()
    normalized_words = []
    
    for word in words:
        # Check Tamil-English code-switched dictionary mapping
        if word in lookup:
            normalized_words.append(lookup[word])
        else:
            normalized_words.append(word)
            
    return " ".join(normalized_words)


class CosineSimilarityClassifier:
    """
    K-Nearest Neighbor classifier using Cosine Similarity.
    Features a dual-mode implementation: uses faiss if available,
    otherwise falls back to a pure numpy implementation.
    """
    def __init__(self, reference_phrases: Dict[str, List[str]], dimension: int = 384):
        self.reference_phrases = reference_phrases  # e.g. {"Roads": ["pothole on the street", ...]}
        self.dimension = dimension
        
        # Flatten reference dictionary into labels and phrases list
        self.labels = []
        self.phrases = []
        for label, phrases in reference_phrases.items():
            for p in phrases:
                self.labels.append(label)
                self.phrases.append(p)
                
        # Generate embeddings for references
        model = get_sentence_model()
        self.embeddings = model.encode(self.phrases, convert_to_numpy=True)
        # Normalize embeddings for cosine similarity
        norms = np.linalg.norm(self.embeddings, axis=1, keepdims=True)
        self.normalized_embeddings = self.embeddings / (norms + 1e-10)

        # Setup FAISS if possible
        self.use_faiss = False
        if HAS_FAISS:
            try:
                # Cosine similarity index in FAISS is IndexFlatIP (Inner Product) on normalized vectors
                self.index = faiss.IndexFlatIP(self.dimension)
                # Convert to float32 for faiss compatibility
                self.index.add(self.normalized_embeddings.astype('float32'))
                self.use_faiss = True
                logger.info("FAISS Index constructed successfully.")
            except Exception as e:
                logger.warning(f"Failed to build FAISS index: {str(e)}. Falling back to pure numpy.")
                
        if not self.use_faiss:
            logger.info("Using pure numpy matrix multiplication for nearest-neighbor search.")

    def search(self, query_vector: np.ndarray, k: int = 1) -> List[Tuple[str, float]]:
        """
        Find top K matching reference phrases and return list of (label, similarity_score).
        """
        # Normalize query vector for cosine similarity
        norm = np.linalg.norm(query_vector)
        query_normalized = query_vector / (norm + 1e-10)
        
        if self.use_faiss:
            # Query FAISS index
            query_reshaped = query_normalized.reshape(1, -1).astype('float32')
            similarities, indices = self.index.search(query_reshaped, k)
            
            results = []
            for sim, idx in zip(similarities[0], indices[0]):
                if idx != -1:
                    results.append((self.labels[idx], float(sim)))
            return results
        else:
            # Pure NumPy implementation (dot product of normalized query with all normalized embeddings)
            similarities = np.dot(self.normalized_embeddings, query_normalized)
            
            # Find top K indices
            top_k_indices = np.argsort(similarities)[::-1][:k]
            
            results = []
            for idx in top_k_indices:
                results.append((self.labels[idx], float(similarities[idx])))
            return results


# Initialize Classifier instances dynamically
_department_classifier = None
_subcategory_classifiers = {}  # {department_name: Classifier}

def get_department_classifier() -> CosineSimilarityClassifier:
    global _department_classifier
    if _department_classifier is None:
        # Curated reference phrases per department (not generated at runtime, SRS 4.2 step 3)
        reference_phrases = {
            "Water Supply & Sewerage": [
                "sewerage leak on street water contamination and foul smell",
                "drainage overflowing water supply pipeline burst leakage",
                "no drinking water dirty water low pressure in tap pipelines",
                "sewage mixing in drinking water pipe leak block in drain"
            ],
            "Solid Waste Management": [
                "garbage pile rubbish litter on road corner dump bin overflowing",
                "waste not collected plastic garbage dumping municipal waste",
                "uncleaned trash bins toxic smell from solid waste rotting dump",
                "garbage lorry not coming waste collection missed roadside litter"
            ],
            "Roads & Public Works": [
                "large pothole road damaged street pothole accident hazard pavement",
                "broken pavement road crack mud road repair concrete damage potholes",
                "potholes causing traffic road resurfacing public work division",
                "open trench roadside trench road work abandoned pits"
            ],
            "Electricity Grid & Power": [
                "electricity cable hanging down transformer spark black out wire cut",
                "power cut low voltage short circuit wire cut electricity pole damaged",
                "high voltage power line issue transformer blast electrical hazard sparks",
                "frequent power shutdown grid failure wire sparking on trees",
                "electricity outage power cut no current blackout transformer fault"
            ],

            "Streetlight Maintenance": [
                "streetlight not working dark road street lamp flickering",
                "broken bulb in streetlight bulb replacement street pole light off",
                "lights off in night danger on street street illumination missing",
                "dark alleyway street lamp off line fault pole damage"
            ]
        }
        _department_classifier = CosineSimilarityClassifier(reference_phrases)
    return _department_classifier

def get_subcategory_classifier(department_name: str) -> CosineSimilarityClassifier:
    global _subcategory_classifiers
    if department_name not in _subcategory_classifiers:
        # Predefined subcategory references per department (SRS 4.2 step 5)
        subcat_references = {
            "Water Supply & Sewerage": {
                "Water Pipeline Leak": ["pipe leakage", "water pipeline burst", "water spraying out", "main line leak"],
                "Drainage Overflow": ["sewer overflowing", "drain blockage", "sewage on road", "gutter blocked"],
                "Contaminated Supply": ["dirty water", "smelly water tap", "sewage mixing", "color in drinking water"]
            },
            "Solid Waste Management": {
                "Overflowing Garbage Bin": ["bin full", "rubbish dump overflowing", "garbage spilled", "waste container full"],
                "Door-to-Door Collection Fail": ["garbage collector did not come", "waste collection missed", "no collection today"],
                "Illegal Waste Dumping": ["plastics dumping on empty plot", "garbage thrown on roadside", "unauthorized dump"]
            },
            "Roads & Public Works": {
                "Pothole Repair": ["road pothole", "pavement holes", "deep potholes", "cracks on road"],
                "Road Cavity / Sinkhole": ["road collapsed", "large sinkhole", "hollow road surface"],
                "Damaged Footpath": ["broken pavements", "footpath blocks missing", "sidewalk damage"]
            },
            "Electricity Grid & Power": {
                "Hanging / Broken Cable": ["overhead wire snapped", "dangling cable", "sparking electrical line"],
                "Power Outage / Low Voltage": ["no electricity power cut", "frequent blackout", "voltage fluctuation"],
                "Damaged Transformer": ["transformer burst", "transformer sparks", "fuse blown in grid"]
            },
            "Streetlight Maintenance": {
                "Bulb Replacement": ["light bulb broken", "street lamp fused", "replace led light"],
                "No Street Illumination": ["all lights off", "complete darkness road", "automatic switch failed"],
                "Flickering Light": ["lamp blinking", "flickering streetlight", "disturbing flash"]
            }
        }
        
        phrases = subcat_references.get(department_name, {})
        if phrases:
            _subcategory_classifiers[department_name] = CosineSimilarityClassifier(phrases)
            
    return _subcategory_classifiers.get(department_name)


# Main pipeline classifier interface
async def classify_complaint_text(text: str, departments_dict: Dict[int, str]) -> dict:
    """
    Classify a complaint text into a department and subcategory (Module 4.2).
    Includes Tamil-English term lookup normalization and a cosine similarity search threshold.
    """
    # Step 1: Normalize text
    normalized_text = normalize_text(text)
    
    # Step 2: Generate sentence embedding
    model = get_sentence_model()
    query_vector = model.encode(normalized_text, convert_to_numpy=True)
    
    # Step 3: Compare against department references (FAISS index or numpy fallback)
    dept_classifier = get_department_classifier()
    matches = dept_classifier.search(query_vector, k=1)
    
    if not matches:
        return {
            "department_id": None,
            "subcategory": None,
            "confidence": 0.0,
            "status": "needs_review"
        }
        
    matched_dept_name, confidence = matches[0]
    
    # Map matched department name back to integer ID
    dept_id = None
    for d_id, name in departments_dict.items():
        if name == matched_dept_name:
            dept_id = d_id
            break

    # Step 5: If confidence >= 0.55, classify subcategory
    # Step 6: If confidence < 0.55 (FR-2.3), flag for admin triage queue instead of guessing
    # Quote FR-2.2:
    # "FR-2.2: System shall classify each complaint into a department and subcategory with a confidence score."
    # Quote FR-2.3:
    # "FR-2.3: System shall route low-confidence classifications to an admin review queue instead of guessing."
    if confidence >= 0.55:
        sub_classifier = get_subcategory_classifier(matched_dept_name)
        subcategory = "Other"
        if sub_classifier:
            sub_matches = sub_classifier.search(query_vector, k=1)
            if sub_matches:
                subcategory = sub_matches[0][0]
                
        return {
            "department_id": dept_id,
            "subcategory": subcategory,
            "confidence": float(confidence),
            "status": "registered" # proceed normally
        }
    else:
        logger.info(f"Low confidence classification ({confidence:.2f} < 0.55). Routing to admin review.")
        return {
            "department_id": None,
            "subcategory": None,
            "confidence": float(confidence),
            "status": "needs_review"
        }
