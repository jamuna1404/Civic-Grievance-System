import os
import av
import logging
from faster_whisper import WhisperModel

logger = logging.getLogger("asr_module")

# Initialize WhisperModel lazily to save startup memory/time
_model = None

def get_whisper_model() -> WhisperModel:
    global _model
    if _model is None:
        logger.info("Initializing faster-whisper 'base' model on CPU...")
        # Use base model, running on CPU with int8 quantization for speed and low RAM usage
        _model = WhisperModel("base", device="cpu", compute_type="int8")
    return _model

def get_audio_duration(audio_path: str) -> float:
    """
    Get audio duration in seconds using PyAV (av package).
    """
    with av.open(audio_path) as container:
        # container.duration is in microseconds
        if container.duration is not None:
            return container.duration / 1000000.0
        # If container duration is not available, calculate from streams
        audio_stream = next((s for s in container.streams if s.type == 'audio'), None)
        if audio_stream and audio_stream.duration and audio_stream.time_base:
            return float(audio_stream.duration * audio_stream.time_base)
    return 0.0

def transcribe(audio_path: str) -> dict:
    """
    Transcribe audio file using faster-whisper.
    Enforces format, size, and duration validation checks (SRS Section 4.1 steps).
    """
    # 1. Validate size
    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"Audio file not found: {audio_path}")
        
    size_bytes = os.path.getsize(audio_path)
    max_size_mb = 10
    if size_bytes > max_size_mb * 1024 * 1024:
        raise ValueError(f"Audio file exceeds maximum size limit of {max_size_mb}MB (found {size_bytes / (1024 * 1024):.2f}MB)")

    # Validate file format/extension
    allowed_extensions = {".wav", ".mp3", ".m4a", ".ogg", ".aac", ".flac", ".3gp", ".webm"}
    _, ext = os.path.splitext(audio_path.lower())
    if ext not in allowed_extensions:
        raise ValueError(f"Unsupported audio format: '{ext}'. Allowed: {list(allowed_extensions)}")

    # 2. Validate duration
    try:
        duration = get_audio_duration(audio_path)
    except Exception as e:
        raise ValueError(f"Failed to read audio metadata: {str(e)}")

    max_duration_sec = 60.0
    if duration > max_duration_sec:
        raise ValueError(f"Audio file exceeds maximum duration of {max_duration_sec} seconds (found {duration:.2f}s)")

    # 3. Run Whisper transcription
    try:
        model = get_whisper_model()
        # transcribe Tamil/English complaints without auto-translating (task-specific setting)
        segments, info = model.transcribe(audio_path, beam_size=5)
        
        # segments is a generator; evaluate it to string list
        segment_texts = []
        for segment in segments:
            segment_texts.append(segment.text)
            
        full_text = " ".join(segment_texts).strip()
        
        # 4. Capture language and confidence (no auto-translation)
        detected_language = info.language
        language_probability = info.language_probability
        
        return {
            "text": full_text,
            "detected_language": detected_language,
            "confidence": language_probability,
            "duration": duration
        }
    except Exception as e:
        logger.error(f"Whisper transcription failed: {str(e)}")
        raise RuntimeError(f"Whisper transcription service error: {str(e)}")
