import subprocess
import time
import os
import csv
import argparse
import signal
from pathlib import Path
from datetime import datetime

class BenchmarkHarness:
    def __init__(self, method: str, workload: str, output_file: str):
        self.method = method
        self.workload = workload
        self.output_file = output_file
        self.checkpoint_dir = Path("./checkpoints")
        self.checkpoint_dir.mkdir(exist_ok=True)
        
    def get_dir_size(self, path: Path) -> float:
        """Returns size in GB."""
        root_directory = Path(path)
        return sum(f.stat().st_size for f in root_directory.glob('**/*') if f.is_file()) / (1024**3)

    def run_benchmark(self):
        print(f"--- Starting {self.method} benchmark on {self.workload} ---")
        
        # 1. Start the Workload
        start_time = datetime.now()
        process = subprocess.Popen(self.workload.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pid = process.pid
        print(f"Workload started with PID: {pid}")

        # Allow workload to initialize (e.g., load weights into VRAM)
        time.sleep(5) 

        # 2. Trigger Checkpoint
        print(f"Triggering {self.method} checkpoint...")
        cp_start = time.perf_counter()
        
        if self.method == "mock":
            # Simulate a 5-second checkpoint and a 2GB file
            time.sleep(5)
            mock_file = self.checkpoint_dir / "mock_state.img"
            with open(mock_file, "wb") as f:
                f.write(os.urandom(1024 * 1024 * 10)) # 10MB mock file
        
        elif self.method == "criu":
            # Example: criu dump -t PID --images-dir ./checkpoints --cuda-checkpoint-bin ./cuda-checkpoint
            subprocess.run([
                "sudo", "criu", "dump", "-t", str(pid), 
                "--images-dir", str(self.checkpoint_dir),
                "--cuda-checkpoint-bin", "./cuda-checkpoint",
                "--shell-job"
            ], check=True)
            
        elif self.method == "cedana":
            # Example: cedana checkpoint PID
            subprocess.run(["cedana", "checkpoint", str(pid), "--output", str(self.checkpoint_dir)], check=True)

        cp_end = time.perf_counter()
        checkpoint_duration = cp_end - cp_start
        checkpoint_size = self.get_dir_size(self.checkpoint_dir)

        print(f"Checkpoint completed in {checkpoint_duration:.2f}s. Size: {checkpoint_size:.4f} GB")

        # 3. Simulate Restore
        print(f"Restoring process...")
        res_start = time.perf_counter()
        
        if self.method == "mock":
            time.sleep(2)
        elif self.method == "criu":
            subprocess.run(["sudo", "criu", "restore", "--images-dir", str(self.checkpoint_dir), "--shell-job"], check=True)
        elif self.method == "cedana":
            subprocess.run(["cedana", "restore", str(self.checkpoint_dir)], check=True)

        res_end = time.perf_counter()
        restore_duration = res_end - res_start
        print(f"Restore completed in {restore_duration:.2f}s")

        # 4. Log Results
        self.log_results({
            "timestamp": start_time.isoformat(),
            "method": self.method,
            "workload": self.workload,
            "checkpoint_time_sec": round(checkpoint_duration, 4),
            "restore_time_sec": round(restore_duration, 4),
            "checkpoint_size_gb": round(checkpoint_size, 6)
        })

    def log_results(self, data: dict):
        file_exists = os.path.isfile(self.output_file)
        with open(self.output_file, 'a', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=data.keys())
            if not file_exists:
                writer.writeheader()
            writer.writerow(data)
        print(f"Results saved to {self.output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--method", choices=["mock", "criu", "cedana"], default="mock")
    parser.add_argument("--workload", type=str, default="python3 -c 'import time; [print(i) or time.sleep(1) for i in range(100)]'")
    parser.add_argument("--output", type=str, default="results.csv")
    args = parser.parse_args()

    harness = BenchmarkHarness(args.method, args.workload, args.output)
    harness.run_benchmark()