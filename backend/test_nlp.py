import asyncio
from app.services.nlp_classifier import classify_complaint_text, normalize_text

# Mock departments dictionary matching seed data IDs
DEPARTMENTS_DICT = {
    1: "Water Supply & Sewerage",
    2: "Solid Waste Management",
    3: "Roads & Public Works",
    4: "Electricity Grid & Power",
    5: "Streetlight Maintenance"
}

TEST_CASES = [
    # 1. English standard complaints
    {
        "text": "Huge pothole on the main road causing traffic accidents and damage.",
        "expected_dept": "Roads & Public Works",
        "expected_status": "registered"
    },
    {
        "text": "The drinking water from our kitchen tap is muddy and smells like sewage.",
        "expected_dept": "Water Supply & Sewerage",
        "expected_status": "registered"
    },
    {
        "text": "Overflowing garbage pile at the corner of the street. It stinks.",
        "expected_dept": "Solid Waste Management",
        "expected_status": "registered"
    },
    {
        "text": "Fallen power cable is sparking on the road. Extremely dangerous.",
        "expected_dept": "Electricity Grid & Power",
        "expected_status": "registered"
    },
    {
        "text": "Streetlight is not working since last week. The entire street is dark.",
        "expected_dept": "Streetlight Maintenance",
        "expected_status": "registered"
    },
    
    # 2. Tamil-English code-switched complaints (testing lookup mapping)
    {
        "text": "road la periya pothole irukku, romba dangerous",
        "expected_dept": "Roads & Public Works",
        "expected_status": "registered"
    },
    {
        "text": "kuppai bin overflowing, toxic smell is coming",
        "expected_dept": "Solid Waste Management",
        "expected_status": "registered"
    },
    {
        "text": "vilakku not working in Egmore, complete dark road",
        "expected_dept": "Streetlight Maintenance",
        "expected_status": "registered"
    },
    {
        "text": "water pipe leak in our street, thanni waste-a pogudhu",
        "expected_dept": "Water Supply & Sewerage",
        "expected_status": "registered"
    },
    {
        "text": "current outage since morning, no electricity",
        "expected_dept": "Electricity Grid & Power",
        "expected_status": "registered"
    },

    # 3. Low confidence / ambiguous case (should route to needs_review)
    {
        "text": "I want to register a birth certificate or check application status.",
        "expected_dept": None,
        "expected_status": "needs_review"
    }
]

async def run_tests():
    print("Normalizing Tamil-English sample terms...")
    sample_phrase = "thanni pipe and kuppai bins"
    normalized = normalize_text(sample_phrase)
    print(f"Original   : '{sample_phrase}'")
    print(f"Normalized : '{normalized}'\n")

    print("--- Executing NLP Classification Unit Tests ---")
    
    passed_count = 0
    for idx, case in enumerate(TEST_CASES, 1):
        print(f"\nTest #{idx}: Input Text: '{case['text']}'")
        
        # Execute classification
        result = await classify_complaint_text(case["text"], DEPARTMENTS_DICT)
        
        dept_name = DEPARTMENTS_DICT.get(result["department_id"]) if result["department_id"] else None
        status = result["status"]
        confidence = result["confidence"]
        
        print(f"Prediction  : Department: '{dept_name}', Subcategory: '{result['subcategory']}', Status: '{status}' (Confidence: {confidence:.2f})")
        print(f"Expected    : Department: '{case['expected_dept']}', Status: '{case['expected_status']}'")
        
        # Assertions
        dept_ok = dept_name == case["expected_dept"]
        status_ok = status == case["expected_status"]
        
        if dept_ok and status_ok:
            print("RESULT      : PASS [OK]")
            passed_count += 1
        else:
            print("RESULT      : FAIL [ERROR]")

            
    print(f"\nNLP Tests Finished. Summary: {passed_count}/{len(TEST_CASES)} passed.")
    assert passed_count == len(TEST_CASES), "Some NLP test cases failed!"

if __name__ == "__main__":
    asyncio.run(run_tests())
