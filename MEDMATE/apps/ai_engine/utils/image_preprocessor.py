"""
utils/image_preprocessor.py
"""

import logging

import cv2
from PIL import Image

logger = logging.getLogger(__name__)

MIN_DIMENSION  = 1000
DESKEW_MIN     = 0.5
DESKEW_MAX     = 45.0
DENOISE_H      = 10
CLAHE_CLIP     = 2.0
CLAHE_GRID     = (8, 8)
SHARPEN_ALPHA  = 1.8
SHARPEN_BETA   = -(SHARPEN_ALPHA - 1)   # derived — stays consistent if ALPHA changes


def preprocess(image_path: str) -> Image.Image:
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Cannot load image: {image_path}")

    # 1. Upscale
    h, w = img.shape[:2]
    if max(w, h) < MIN_DIMENSION:
        scale = MIN_DIMENSION / max(w, h)
        img   = cv2.resize(
            img,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_CUBIC,
        )
        logger.debug("Upscaled → %dx%d", img.shape[1], img.shape[0])

    # 2. Deskew
    h, w     = img.shape[:2]
    ar        = h / w
    gray_full = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    thresh    = cv2.threshold(
        gray_full, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )[1]
    coords = cv2.findNonZero(thresh)
    if coords is not None and not (0.9 <= ar <= 1.1):
        angle = cv2.minAreaRect(coords)[-1]
        if angle < -45:
            angle += 90
        if DESKEW_MIN < abs(angle) <= DESKEW_MAX:
            cx = w // 2
            cy = h // 2
            M  = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
            img = cv2.warpAffine(
                img, M, (w, h),
                flags=cv2.INTER_CUBIC,
                borderMode=cv2.BORDER_REPLICATE,
            )
            logger.debug("Deskewed %.1f°", angle)

    # 3. Denoise
    gray     = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    denoised = cv2.fastNlMeansDenoising(gray, h=DENOISE_H)

    # 4. CLAHE
    clahe    = cv2.createCLAHE(clipLimit=CLAHE_CLIP, tileGridSize=CLAHE_GRID)
    enhanced = clahe.apply(denoised)

    # 5. Sharpen
    blurred = cv2.GaussianBlur(enhanced, (5, 5), sigmaX=2)
    sharp   = cv2.addWeighted(enhanced, SHARPEN_ALPHA, blurred, SHARPEN_BETA, 0)

    rgb = cv2.cvtColor(sharp, cv2.COLOR_GRAY2RGB)
    logger.info("Preprocessed → %dx%d RGB", rgb.shape[1], rgb.shape[0])
    return Image.fromarray(rgb)