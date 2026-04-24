import os
from huggingface_hub import hf_hub_download

def download_tinyllama():
    os.makedirs('models', exist_ok=True)
    print("Downloading TinyLlama-1.1B (Q4_K_M) - ~680MB...")
    model_path = hf_hub_download(
        repo_id="TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
        filename="tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        local_dir="models",
        local_dir_use_symlinks=False
    )
    print(f"Model successfully saved to {model_path}")

if __name__ == '__main__':
    download_tinyllama()
