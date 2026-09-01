import json
import sys
import os

def test_sft_json():
    example_path = "spec/example_movie.sft"
    spec_path = "spec/sft_spec.json"

    print("=========================================")
    print("Running SFT JSON Spec Validation (Python)")
    print("=========================================")

    if not os.path.exists(example_path):
        print(f"❌ Missing file {example_path}")
        sys.exit(1)

    with open(example_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert data.get("sft_version") == "1.0", "Invalid sft_version"
    assert "metadata" in data, "Missing metadata"
    assert "filters" in data, "Missing filters"
    assert len(data["filters"]) == 2, f"Expected 2 filters, got {len(data['filters'])}"

    for f in data["filters"]:
        assert "id" in f, "Filter missing id"
        assert "start_time" in f and "end_time" in f, "Filter missing start_time or end_time"
        assert f["start_time"] < f["end_time"], f"Invalid timestamps in filter {f['id']}"
        assert f["action"] in ["skip", "mute"], f"Unsupported action {f['action']}"
        assert f["category"] in ["gore", "violence", "nudity", "profanity", "other"], f"Invalid category {f['category']}"

    print("✅ All SFT schema assertions passed successfully!")
    print("=========================================")

if __name__ == "__main__":
    test_sft_json()
