import os
import unittest
from PIL import Image, ImageDraw
from app.ml.image_analysis import analyze_image

class TestComputerVision(unittest.TestCase):
    
    @classmethod
    def setUpClass(cls):
        # Create temporary images
        cls.pothole_path = "temp_pothole.jpg"
        cls.garbage_path = "temp_garbage.jpg"
        cls.irrelevant_path = "temp_irrelevant.jpg"
        
        # 1. Draw Pothole: Gray road background with a dark road cavity ellipse
        img_pothole = Image.new("RGB", (256, 256), color="#7f8c8d")
        draw = ImageDraw.Draw(img_pothole)
        draw.ellipse([50, 70, 206, 186], fill="#2c3e50", outline="#1a252f", width=5)
        # Add some cracks
        draw.line([50, 70, 20, 40], fill="#1a252f", width=2)
        draw.line([206, 186, 230, 210], fill="#1a252f", width=2)
        img_pothole.save(cls.pothole_path)
        
        # 2. Draw Garbage Pile: Messy organic pile on dirt ground
        import random
        img_garbage = Image.new("RGB", (256, 256), color="#8b5a2b") # Soil background
        draw = ImageDraw.Draw(img_garbage)
        # Draw 150 random scraps of waste with messy overlapping shapes to represent a pile of trash/litter
        random.seed(42)
        for _ in range(150):
            x1 = random.randint(20, 210)
            y1 = random.randint(80, 220)
            w = random.randint(8, 40)
            h = random.randint(8, 40)
            col = random.choice([
                "#2ecc71", "#27ae60", # green plastics
                "#e74c3c", "#c0392b", # red plastic
                "#3498db", "#2980b9", # blue plastic
                "#f1c40f", "#f39c12", # yellow wrapper
                "#95a5a6", "#7f8c8d", # tin cans
                "#2c3e50", "#34495e"  # black trash bags
            ])
            shape = random.choice(["rect", "ellipse", "polygon"])
            if shape == "rect":
                draw.rectangle([x1, y1, x1+w, y1+h], fill=col)
            elif shape == "ellipse":
                draw.ellipse([x1, y1, x1+w, y1+h], fill=col)
            else:
                draw.polygon([
                    (x1, y1),
                    (x1+w, y1+random.randint(-5, 5)),
                    (x1+random.randint(-5, 5), y1+h)
                ], fill=col)
        img_garbage.save(cls.garbage_path)

        
        # 3. Draw Irrelevant: Abstract clean pink/magenta layout with clean geometric stripes
        img_irrelevant = Image.new("RGB", (256, 256), color="#e91e63")
        draw = ImageDraw.Draw(img_irrelevant)
        draw.line([0, 0, 256, 256], fill="#ffeb3b", width=12)
        draw.line([256, 0, 0, 256], fill="#ffeb3b", width=12)
        img_irrelevant.save(cls.irrelevant_path)

    @classmethod
    def tearDownClass(cls):
        # Clean up images
        for path in [cls.pothole_path, cls.garbage_path, cls.irrelevant_path]:
            if os.path.exists(path):
                os.remove(path)

    def test_pothole_classification(self):
        print("\nTesting pothole image classification...")
        result = analyze_image(self.pothole_path)
        print(f"Pothole image resolved to: {result['label']} (Confidence: {result['confidence']:.2f})")
        self.assertEqual(result["label"], "pothole")
        self.assertIn(result["severity_hint"], ["minor", "moderate", "severe"])

    def test_garbage_classification(self):
        print("\nTesting garbage image classification...")
        result = analyze_image(self.garbage_path)
        print(f"Garbage image resolved to: {result['label']} (Confidence: {result['confidence']:.2f})")
        self.assertEqual(result["label"], "garbage pile")
        self.assertIn(result["severity_hint"], ["minor", "moderate", "severe"])

    def test_irrelevant_classification(self):
        print("\nTesting irrelevant image classification...")
        result = analyze_image(self.irrelevant_path)
        print(f"Irrelevant image resolved to: {result['label']} (Confidence: {result['confidence']:.2f})")
        self.assertEqual(result["label"], "irrelevant/unclear image")
        self.assertEqual(result["severity_hint"], "minor")

if __name__ == "__main__":
    unittest.main()
