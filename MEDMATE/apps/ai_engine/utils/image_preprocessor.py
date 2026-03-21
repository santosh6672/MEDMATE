"""
utils/image_preprocessor.py
─────────────────────────────
Prepares prescription images before OCR.

Steps:
  1. Upscale  — images below 1000px on their longest edge are scaled up
  2. Deskew   — corrects tilts in the range 0.5°–45° (full range, not capped at 10°)
  3. Denoise  — removes paper grain / camera noise
  4. CLAHE    — local contrast boost for faded or low-contrast ink
  5. Sharpen  — unsharp-mask to crisp pen-stroke edges

Returns an RGB PIL Image ready for PaddleOCR-VL and Qwen2-VL.

Fixes vs original:
  - Removed unused `numpy` import
  - Deskew upper-bound raised from 10° → 45° (was silently skipping moderate tilts)
  - Deskew: normalised angle is now always in [-45, 45] before the abs() check,
    so the guard fires consistently for both negative and positive corrections
  - h, w from shape[:2] were never used after upscale — removed
  - logging instead of print()
"""

import logging

import cv2
from PIL import Image

logger = logging.getLogger(__name__)

# ── Tunable constants ─────────────────────────────────────────────────────────
MIN_DIMENSION     = 1000   # px — upscale threshold
DESKEW_MIN_ANGLE  = 0.5    # degrees — ignore tiny wobble
DESKEW_MAX_ANGLE  = 45.0   # degrees — ignore content-rotation (not tilt)
DENOISE_H         = 10     # fastNlMeansDenoising strength (higher = more smoothing)
CLAHE_CLIP        = 2.0    # CLAHE clip limit
CLAHE_GRID        = (8, 8) # CLAHE tile grid size
SHARPEN_ALPHA     = 1.8    # unsharp-mask foreground weight
SHARPEN_BETA      = -0.8   # unsharp-mask blur weight (must be -(alpha - 1))


def preprocess(image_path: str) -> Image.Image:
    """
    Load, clean, and return an RGB PIL image ready for OCR models.

    Args:
        image_path: Absolute path to the uploaded prescription image.

    Returns:
        Preprocessed RGB PIL Image.

    Raises:
        FileNotFoundError: If OpenCV cannot read the file.
    """
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Cannot load image: {image_path}")

    # ── 1. Upscale ────────────────────────────────────────────────────────────
    h, w = img.shape[:2]
    if max(w, h) < MIN_DIMENSION:
        scale = MIN_DIMENSION / max(w, h)
        img   = cv2.resize(
            img,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_CUBIC,
        )
        logger.debug("Upscaled → %dx%d", img.shape[1], img.shape[0])

    # ── 2. Deskew ─────────────────────────────────────────────────────────────
    # cv2.minAreaRect returns angles in [-90, 0).
    # Normalise to [-45, 45] so the guard works symmetrically.
    gray_full = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    thresh    = cv2.threshold(
        gray_full, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )[1]
    coords = cv2.findNonZero(thresh)
    if coords is not None:
        angle = cv2.minAreaRect(coords)[-1]   # always in [-90, 0)
        if angle < -45:
            angle += 90                        # now in (-45, 45]
        if DESKEW_MIN_ANGLE < abs(angle) <= DESKEW_MAX_ANGLE:
            cx = img.shape[1] // 2
            cy = img.shape[0] // 2
            M  = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
            img = cv2.warpAffine(
                img, M, (img.shape[1], img.shape[0]),
                flags=cv2.INTER_CUBIC,
                borderMode=cv2.BORDER_REPLICATE,
            )
            logger.debug("Deskewed %.1f°", angle)

    # ── 3. Denoise ────────────────────────────────────────────────────────────
    gray     = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    denoised = cv2.fastNlMeansDenoising(gray, h=DENOISE_H)

    # ── 4. CLAHE (local contrast enhancement) ────────────────────────────────
    clahe    = cv2.createCLAHE(clipLimit=CLAHE_CLIP, tileGridSize=CLAHE_GRID)
    enhanced = clahe.apply(denoised)

    # ── 5. Unsharp mask (sharpen) ─────────────────────────────────────────────
    blurred = cv2.GaussianBlur(enhanced, (5, 5), sigmaX=2)
    sharp   = cv2.addWeighted(enhanced, SHARPEN_ALPHA, blurred, SHARPEN_BETA, 0)

    # Both Paddle and Qwen require RGB input
    rgb = cv2.cvtColor(sharp, cv2.COLOR_GRAY2RGB)
    logger.info("Preprocessed → %dx%d RGB", rgb.shape[1], rgb.shape[0])
    return Image.fromarray(rgb)