# workload.py
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

model_name = "gpt2"

tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForCausalLM.from_pretrained(model_name).cuda()

while True:
    inputs = tokenizer("Hello world", return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=20)