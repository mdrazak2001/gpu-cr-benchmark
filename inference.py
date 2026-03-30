from transformers import pipeline
import time
import os
import sys

# Silence the noise
os.environ["TRANSFORMERS_VERBOSITY"] = "error"
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"

model_name = "gpt2"
print(f"Loading {model_name}...", flush=True)
pipe = pipeline("text-generation", model=model_name, device=0)
print("Model loaded - READY", flush=True)

i = 0
while True:
    try:
        out = pipe("The weather today is", max_new_tokens=20)
        i += 1
        # Clean output for the log
        text = out[0]['generated_text'].replace('\n', ' ')
        print(f"[{i}] {text[:80]}", flush=True)
        time.sleep(2)
    except Exception as e:
        print(f"Error during inference: {e}", flush=True)
        time.sleep(5)
