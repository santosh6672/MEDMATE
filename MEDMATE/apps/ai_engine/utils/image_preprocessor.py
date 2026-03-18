"""
image_preprocessor.py
─────────────────────
Prepares handwritten prescription images before CRAFT + OCR.

Why this matters:
  CRAFT and PaddleOCR both work harder (and slower) on noisy, skewed, low-contrast
  images. One preprocessing pass shared by ALL models means:
    - CRAFT detects more text regions (especially faint handwriting)
    - PaddleOCR crops are cleaner → higher confidence scores
    - Qwen2-VL sees a sharper image → better medicine name extraction
    - Total: better accuracy, same or less compute time

Steps:
  1. Deskew        — fixes camera tilt (up to ±15° for hand-held photos)
  2. Denoise       — removes paper texture / camera noise
  3. CLAHE         — local contrast boost (critical for faded ink)
  4. Sharpen       — enhances pen stroke edges for CRAFT detection
  5. Resize        — normalises to 1600px long side (CRAFT sweet spot for A4)
"""

import cv2
import numpy as np
import os
import tempfile


def preprocess(image_path: str, target_long_side: int = 1600) -> np.ndarray:
    """
    Load and preprocess a prescription image for OCR.

    Returns:
        Preprocessed BGR numpy array (uint8)
    """
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"Cannot load image: {image_path}")

    image = _deskew(image)
    image = _denoise(image)
    image = _clahe(image)
    image = _sharpen(image)
    image = _resize(image, target_long_side)

    return image


def save_temp(image: np.ndarray) -> str:
    """
    Write numpy BGR image to a named temp file.
    Caller is responsible for deleting it after use.
    Returns the temp file path.
    """
    fd, path = tempfile.mkstemp(suffix=".jpg")
    os.close(fd)
    cv2.imwrite(path, image, [cv2.IMWRITE_JPEG_QUALITY, 95])
    return path


# ── private steps ──────────────────────────────────────────────────────────────

def _deskew(image: np.ndarray, max_angle: float = 15.0) -> np.ndarray:
    """
    Correct camera tilt using minAreaRect on thresholded ink content.
    Skips correction if detected angle > max_angle (likely mis-detection).
    """
    gray  = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray  = cv2.bitwise_not(gray)
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)

    coords = np.column_stack(np.where(thresh > 0))
    if len(coords) < 100:
        return image  # not enough ink to estimate angle

    angle = cv2.minAreaRect(coords)[-1]
    if angle < -45:
        angle = 90 + angle

    if abs(angle) > max_angle:
        return image  # skip — likely a false detection

    h, w = image.shape[:2]
    M = cv2.getRotationMatrix2D((w // 2, h // 2), angle, 1.0)
    return cv2.warpAffine(image, M, (w, h),
                          flags=cv2.INTER_CUBIC,
                          borderMode=cv2.BORDER_REPLICATE)


def _denoise(image: np.ndarray) -> np.ndarray:
    """
    Remove paper texture and camera noise while preserving ink edges.
    Uses bilateral filter (edge-preserving) over Gaussian.
    """
    return cv2.bilateralFilter(image, d=9, sigmaColor=75, sigmaSpace=75)


def _clahe(image: np.ndarray) -> np.ndarray:
    """
    CLAHE on the L-channel of LAB colorspace.
    Boosts local contrast — essential for faded or unevenly lit handwriting.
    clipLimit=3.0 is stronger than default (2.0) to handle very faint ink.
    """
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    l = clahe.apply(l)
    return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)


def _sharpen(image: np.ndarray) -> np.ndarray:
    """
    Unsharp mask — enhances pen stroke edges for better CRAFT detection.
    Helps CRAFT find character regions in cursive/overlapping handwriting.
    """
    blurred = cv2.GaussianBlur(image, (0, 0), sigmaX=3)
    return cv2.addWeighted(image, 1.5, blurred, -0.5, 0)


def _resize(image: np.ndarray, target_long_side: int) -> np.ndarray:
    """
    Resize so the longer dimension = target_long_side, preserving aspect ratio.
    1600px is the sweet spot: enough detail for CRAFT, not too slow to process.
    """
    h, w   = image.shape[:2]
    scale  = target_long_side / max(h, w)
    if abs(scale - 1.0) < 0.02:
        return image  # already close enough
    interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_CUBIC
    return cv2.resize(image, (int(w * scale), int(h * scale)), interpolation=interp)