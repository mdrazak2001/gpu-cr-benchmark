from transformers import pipeline
import time

print("Loading model...")
pipe = pipeline("text-generation", model="gpt2", device=0)
print("Model loaded on GPU")

# Keep running to allow checkpointing
count = 0
while True:
    result = pipe("The weather today is", max_new_tokens=20)
    count += 1
    print(f"Inference {count}: {result[0]['generated_text'][:50]}")
    time.sleep(2)
