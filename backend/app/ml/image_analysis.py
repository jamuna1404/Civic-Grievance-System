import logging
from PIL import Image
from transformers import pipeline

logger = logging.getLogger("image_analysis")

# Lazy load pipeline
_classifier = None

def get_image_classifier():
    global _classifier
    if _classifier is None:
        logger.info("Initializing zero-shot CLIP image classifier (openai/clip-vit-base-patch32) on CPU...")
        # Load CLIP model on CPU
        _classifier = pipeline(
            "zero-shot-image-classification",
            model="openai/clip-vit-base-patch32",
            device=-1 # forces CPU execution
        )
    return _classifier

# Map of candidate labels to descriptive prompt templates to improve zero-shot CLIP classification
CIVIC_LABEL_PROMPTS = {
    "pothole": "a road pothole, crack in street pavement, or hole in the road",
    "garbage pile": "a pile of garbage, overflowing trash bin, litter, or street waste",
    "broken streetlight": "a broken or dark streetlight lamp post on the street",
    "pipe leak": "a spraying water pipe leak, water pipe burst, or water line leak",
    "overflowing drain": "sewage water overflowing from a drain, gutter, or manhole onto the street",
    "fallen tree": "a fallen tree, broken tree trunk, or large branch blocking the street",
    "damaged electricity pole": "a damaged electricity power pole, hanging snapped wires, or transformer spark",
    "irrelevant/unclear image": "a pink graphic with yellow lines, a document screenshot, clean geometric stripes, white blank background, or generic text"
}


CIVIC_LABELS = list(CIVIC_LABEL_PROMPTS.keys())


# Tunable severity lookup table mapping: label -> list of (threshold, severity) sorted desc by threshold
SEVERITY_LOOKUP = {
    "pothole": [
        (0.70, "severe"),
        (0.40, "moderate"),
        (0.00, "minor")
    ],
    "garbage pile": [
        (0.75, "severe"),
        (0.35, "moderate"),
        (0.00, "minor")
    ],
    "broken streetlight": [
        (0.60, "severe"),
        (0.30, "moderate"),
        (0.00, "minor")
    ],
    "pipe leak": [
        (0.70, "severe"),
        (0.40, "moderate"),
        (0.00, "minor")
    ],
    "overflowing drain": [
        (0.75, "severe"),
        (0.40, "moderate"),
        (0.00, "minor")
    ],
    "fallen tree": [
        (0.70, "severe"),
        (0.40, "moderate"),
        (0.00, "minor")
    ],
    "damaged electricity pole": [
        (0.60, "severe"),
        (0.00, "moderate")  # default to moderate otherwise
    ],
    "irrelevant/unclear image": [
        (0.00, "minor")
    ]
}

def resolve_severity(label: str, confidence: float) -> str:
    """
    Map label + confidence to severity_hint via the tunable lookup table.
    """
    rules = SEVERITY_LOOKUP.get(label, [(0.00, "minor")])
    for threshold, severity in rules:
        if confidence >= threshold:
            return severity
    return "minor"

def analyze_image(image_path: str) -> dict:
    """
    Run zero-shot CLIP classification on an image file.
    Validates/flags irrelevant or unclear images, maps to severity_hint.
    """
    logger.info(f"Analyzing image: {image_path}")
    try:
        # Load and verify image opens correctly
        with Image.open(image_path) as img:
            img.verify()
        
        # Load image again for processing (verify closes the file pointer/corrupts verification)
        img = Image.open(image_path)
        
        classifier = get_image_classifier()
        # Execute zero-shot classification using prompt templates
        candidate_prompts = list(CIVIC_LABEL_PROMPTS.values())
        results = classifier(img, candidate_labels=candidate_prompts)
        
        if not results:
            raise RuntimeError("Classifier returned empty results")
            
        # Top result is sorted at index 0
        top_match = results[0]
        matched_prompt = top_match["label"]
        confidence = float(top_match["score"])
        
        # Map matched prompt back to key
        prompt_to_label = {v: k for k, v in CIVIC_LABEL_PROMPTS.items()}
        label = prompt_to_label[matched_prompt]
        
        # Resolve severity hint
        severity = resolve_severity(label, confidence)
        
        logger.info(f"Image match: '{label}' with confidence {confidence:.2f} -> Severity: {severity}")
        
        return {
            "label": label,
            "confidence": confidence,
            "severity_hint": severity
        }

        
    except Exception as e:
        logger.error(f"Failed to analyze image {image_path}: {str(e)}")
        # Raise standard exception to let the caller log it on timeline
        raise RuntimeError(f"Computer Vision classification error: {str(e)}")
