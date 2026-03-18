import os
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

from detect_boxes import CraftDetector
from ocr import recognize_from_boxes
from ayareason import AyaMedicalReasoner


def main(image_path):

    print("Initializing models...")

    craft = CraftDetector()
    aya = AyaMedicalReasoner()

    print("\nStep 1: Detecting text regions...")
    boxes = craft.detect(image_path)

    print(f"Detected {len(boxes)} text boxes.")

    print("\nStep 2: Running Paddle OCR...")
    paddle_text, details = recognize_from_boxes(image_path, boxes)

    print("\n--- Paddle OCR Output ---\n")
    print(paddle_text)

    print("\nStep 3: Running Aya reasoning...")
    structured_output = aya.reason(image_path, paddle_text)

    print("\n--- Final Structured Output ---\n")
    print(structured_output)


if __name__ == "__main__":
    image_path = "C:\\Users\\kuruv\\Desktop\\projects\\MEDMATE\\data\\30.jpg"
    main(image_path)