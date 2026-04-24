from transformers import pipeline

def run_test():
    print("Initiating pure-python TinyLlama via HuggingFace Transformers...")
    pipe = pipeline("text-generation", model="TinyLlama/TinyLlama-1.1B-Chat-v1.0", max_new_tokens=40)
    messages = [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is 2+2?"},
    ]
    prompt = pipe.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    outputs = pipe(prompt, max_new_tokens=40, do_sample=True, temperature=0.7, top_k=50, top_p=0.95)
    print("Output:", outputs[0]["generated_text"])

if __name__ == '__main__':
    run_test()
