"""
GNN Fraud Detection Training Script
===================================
Trains GraphSAGE model for fraud ring detection.

Usage:
    python scripts/train_model8_gnn_fraud.py

Output:
    - models/gnn_fraud_detector.pt (trained model)
    - outputs/gnn_training_metrics.json (training metrics)
"""

import sys
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ML_ROOT = os.path.dirname(SCRIPT_DIR)
SERVICES_DIR = os.path.join(ML_ROOT, 'services')

# Support both direct script runs and train_all_local runs.
if ML_ROOT not in sys.path:
    sys.path.append(ML_ROOT)
if SERVICES_DIR not in sys.path:
    sys.path.append(SERVICES_DIR)

import torch
import torch.nn.functional as F
from torch_geometric.loader import DataLoader
import numpy as np
import pandas as pd
import json
from datetime import datetime
import random

from gnn_fraud_detection import GraphSAGEFraudDetector, FraudGraphBuilder, save_model


CHENNAI_ZONE_IDS = [
    'adyar',
    'velachery',
    'anna_nagar',
    't_nagar',
    'guduvanchery',
    'kathankulathur',
    'kelambakkam',
    'potheri',
    'siruseri',
    'urapakkam',
]


# Configuration
NUM_WORKERS = 500
NUM_FRAUD_WORKERS = 50  # 10% contamination rate
NUM_EPOCHS = 100
LEARNING_RATE = 0.001
HIDDEN_DIM = 64
BATCH_SIZE = 32
FRAUD_THRESHOLD = 0.7

# Synthetic data generation
FRAUD_PATTERNS = {
    'device_ring': {
        'description': 'Multiple workers sharing the same device',
        'count': 15,
        'features': {
            'device_shared_count': lambda: random.randint(5, 15),
            'account_age_days': lambda: random.randint(1, 30),
            'avg_daily_orders': lambda: random.randint(5, 15),
            'claim_frequency': lambda: random.randint(5, 10),
            'zone_depth_avg': lambda: random.uniform(0.1, 0.4),
            'historical_clean_ratio': lambda: random.uniform(0.0, 0.3)
        }
    },
    'upi_ring': {
        'description': 'Multiple workers sharing the same UPI ID',
        'count': 15,
        'features': {
            'device_shared_count': lambda: random.randint(1, 3),
            'account_age_days': lambda: random.randint(1, 45),
            'avg_daily_orders': lambda: random.randint(10, 20),
            'claim_frequency': lambda: random.randint(8, 12),
            'zone_depth_avg': lambda: random.uniform(0.2, 0.5),
            'historical_clean_ratio': lambda: random.uniform(0.1, 0.4)
        }
    },
    'zone_cluster': {
        'description': 'Workers in same zone with similar claim timing',
        'count': 20,
        'features': {
            'device_shared_count': lambda: random.randint(1, 2),
            'account_age_days': lambda: random.randint(10, 60),
            'avg_daily_orders': lambda: random.randint(15, 25),
            'claim_frequency': lambda: random.randint(3, 7),
            'zone_depth_avg': lambda: random.uniform(0.4, 0.7),
            'historical_clean_ratio': lambda: random.uniform(0.3, 0.6)
        }
    }
}


def generate_synthetic_worker_data(num_workers: int, num_fraud: int) -> list:
    """
    Generate synthetic worker data for training.
    
    Args:
        num_workers: Total number of workers
        num_fraud: Number of fraud workers
    
    Returns:
        List of worker dictionaries
    """
    workers = []
    
    # Generate clean workers
    for i in range(num_workers - num_fraud):
        workers.append({
            'id': f'clean_worker_{i}',
            'account_age_days': random.randint(30, 365),
            'avg_daily_orders': random.randint(15, 30),
            'claim_frequency': random.randint(1, 5),
            'device_shared_count': 1,
            'zone_depth_avg': random.uniform(0.5, 1.0),
            'historical_clean_ratio': random.uniform(0.6, 1.0),
            'device_fingerprint': f'device_{random.randint(0, num_workers - num_fraud)}',
            'upi_id': f'upi_{random.randint(0, num_workers - num_fraud)}',
            'zone_id': random.choice(CHENNAI_ZONE_IDS),
            'claim_latency': random.randint(45, 300),
            'registered_at': datetime.now()
        })
    
    # Generate fraud workers with patterns
    fraud_worker_id = num_workers - num_fraud
    device_ring_id = f'device_ring_{random.randint(0, 1000)}'
    upi_ring_id = f'upi_ring_{random.randint(0, 1000)}'
    zone_cluster_id = random.choice(CHENNAI_ZONE_IDS)
    
    # Device ring fraud
    for i in range(FRAUD_PATTERNS['device_ring']['count']):
        workers.append({
            'id': f'fraud_device_{i}',
            'account_age_days': FRAUD_PATTERNS['device_ring']['features']['account_age_days'](),
            'avg_daily_orders': FRAUD_PATTERNS['device_ring']['features']['avg_daily_orders'](),
            'claim_frequency': FRAUD_PATTERNS['device_ring']['features']['claim_frequency'](),
            'device_shared_count': FRAUD_PATTERNS['device_ring']['features']['device_shared_count'](),
            'zone_depth_avg': FRAUD_PATTERNS['device_ring']['features']['zone_depth_avg'](),
            'historical_clean_ratio': FRAUD_PATTERNS['device_ring']['features']['historical_clean_ratio'](),
            'device_fingerprint': device_ring_id,  # Same device
            'upi_id': f'upi_{fraud_worker_id + i}',
            'zone_id': random.choice(['adyar', 'velachery', 'siruseri', 'kelambakkam']),
            'claim_latency': random.randint(5, 30),  # Very fast claims
            'registered_at': datetime.now()
        })
    
    # UPI ring fraud
    for i in range(FRAUD_PATTERNS['upi_ring']['count']):
        workers.append({
            'id': f'fraud_upi_{i}',
            'account_age_days': FRAUD_PATTERNS['upi_ring']['features']['account_age_days'](),
            'avg_daily_orders': FRAUD_PATTERNS['upi_ring']['features']['avg_daily_orders'](),
            'claim_frequency': FRAUD_PATTERNS['upi_ring']['features']['claim_frequency'](),
            'device_shared_count': FRAUD_PATTERNS['upi_ring']['features']['device_shared_count'](),
            'zone_depth_avg': FRAUD_PATTERNS['upi_ring']['features']['zone_depth_avg'](),
            'historical_clean_ratio': FRAUD_PATTERNS['upi_ring']['features']['historical_clean_ratio'](),
            'device_fingerprint': f'device_{fraud_worker_id + i}',
            'upi_id': upi_ring_id,  # Same UPI
            'zone_id': random.choice(['anna_nagar', 't_nagar', 'guduvanchery', 'urapakkam', 'kathankulathur', 'potheri']),
            'claim_latency': random.randint(10, 45),
            'registered_at': datetime.now()
        })
    
    # Zone cluster fraud
    for i in range(FRAUD_PATTERNS['zone_cluster']['count']):
        workers.append({
            'id': f'fraud_zone_{i}',
            'account_age_days': FRAUD_PATTERNS['zone_cluster']['features']['account_age_days'](),
            'avg_daily_orders': FRAUD_PATTERNS['zone_cluster']['features']['avg_daily_orders'](),
            'claim_frequency': FRAUD_PATTERNS['zone_cluster']['features']['claim_frequency'](),
            'device_shared_count': FRAUD_PATTERNS['zone_cluster']['features']['device_shared_count'](),
            'zone_depth_avg': FRAUD_PATTERNS['zone_cluster']['features']['zone_depth_avg'](),
            'historical_clean_ratio': FRAUD_PATTERNS['zone_cluster']['features']['historical_clean_ratio'](),
            'device_fingerprint': f'device_{fraud_worker_id + i}',
            'upi_id': f'upi_{fraud_worker_id + i}',
            'zone_id': zone_cluster_id,  # Same zone
            'claim_latency': random.randint(15, 25),  # Similar timing
            'registered_at': datetime.now()
        })
    
    # Shuffle workers
    random.shuffle(workers)
    
    # Create labels
    for worker in workers:
        if worker['id'].startswith('fraud_'):
            worker['label'] = 1  # Fraud
        else:
            worker['label'] = 0  # Clean
    
    return workers


def train_model(model, train_loader, optimizer, device):
    """
    Train the GNN model for one epoch.
    
    Args:
        model: GraphSAGE model
        train_loader: DataLoader with training data
        optimizer: Optimizer
        device: Device to train on
    
    Returns:
        Average loss for the epoch
    """
    model.train()
    total_loss = 0
    
    for data in train_loader:
        data = data.to(device)
        
        optimizer.zero_grad()
        
        # Forward pass
        out = model(data.x, data.edge_index)
        
        # Calculate loss (cross-entropy)
        loss = F.cross_entropy(out, data.y)
        
        # Backward pass
        loss.backward()
        optimizer.step()
        
        total_loss += loss.item()
    
    return total_loss / len(train_loader)


def evaluate_model(model, test_loader, device):
    """
    Evaluate the GNN model.
    
    Args:
        model: GraphSAGE model
        test_loader: DataLoader with test data
        device: Device to evaluate on
    
    Returns:
        Dictionary with evaluation metrics
    """
    model.eval()
    
    total_correct = 0
    total_samples = 0
    total_loss = 0
    
    all_preds = []
    all_labels = []
    
    with torch.no_grad():
        for data in test_loader:
            data = data.to(device)
            
            # Forward pass
            out = model(data.x, data.edge_index)
            
            # Calculate loss
            loss = F.cross_entropy(out, data.y)
            total_loss += loss.item()
            
            # Get predictions
            pred = out.argmax(dim=1)
            
            # Calculate accuracy
            total_correct += (pred == data.y).sum().item()
            total_samples += data.y.size(0)
            
            # Store predictions and labels for metrics
            all_preds.extend(pred.cpu().numpy())
            all_labels.extend(data.y.cpu().numpy())
    
    # Calculate metrics
    accuracy = total_correct / total_samples
    
    # Calculate precision, recall, F1
    from sklearn.metrics import precision_score, recall_score, f1_score
    
    precision = precision_score(all_labels, all_preds, average='binary')
    recall = recall_score(all_labels, all_preds, average='binary')
    f1 = f1_score(all_labels, all_preds, average='binary')
    
    return {
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1': f1,
        'loss': total_loss / len(test_loader)
    }


def main():
    """Main training function."""
    print("=" * 60)
    print("  Hustlr M8 — GNN Fraud Detection Training")
    print("  ML-BLUEPRINT-v1.0")
    print("=" * 60)
    
    # Set random seed for reproducibility
    torch.manual_seed(42)
    np.random.seed(42)
    random.seed(42)
    
    # Check device
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"\n[CONFIG] Device: {device}")
    print(f"[CONFIG] Num workers: {NUM_WORKERS}")
    print(f"[CONFIG] Num fraud workers: {NUM_FRAUD_WORKERS}")
    print(f"[CONFIG] Num epochs: {NUM_EPOCHS}")
    print(f"[CONFIG] Learning rate: {LEARNING_RATE}")
    print(f"[CONFIG] Hidden dim: {HIDDEN_DIM}")
    
    # Generate synthetic data
    print("\n[STAGE 1] Generating synthetic worker data...")
    workers = generate_synthetic_worker_data(NUM_WORKERS, NUM_FRAUD_WORKERS)
    print(f"          Generated {len(workers)} workers")
    print(f"          Fraud workers: {sum(1 for w in workers if w['label'] == 1)}")
    print(f"          Clean workers: {sum(1 for w in workers if w['label'] == 0)}")
    
    # Build graph
    print("\n[STAGE 2] Building fraud graph...")
    graph_builder = FraudGraphBuilder()
    graph = graph_builder.build_graph_from_workers(workers)
    
    # Add labels to graph
    labels = torch.tensor([w['label'] for w in workers], dtype=torch.long)
    graph.y = labels
    
    print(f"          Nodes: {graph.x.shape[0]}")
    print(f"          Edges: {graph.edge_index.shape[1]}")
    
    # Split data into train/test (80/20)
    num_train = int(0.8 * len(workers))
    train_mask = torch.zeros(len(workers), dtype=torch.bool)
    train_mask[:num_train] = True
    test_mask = ~train_mask
    
    graph.train_mask = train_mask
    graph.test_mask = test_mask
    
    print(f"          Train samples: {train_mask.sum().item()}")
    print(f"          Test samples: {test_mask.sum().item()}")
    
    # Create model
    print("\n[STAGE 3] Creating GraphSAGE model...")
    model = GraphSAGEFraudDetector(
        node_features=6,
        hidden_dim=HIDDEN_DIM,
        num_classes=2
    ).to(device)
    
    graph = graph.to(device)
    
    # Optimizer
    optimizer = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE)
    
    # Training loop
    print("\n[STAGE 4] Training model...")
    best_f1 = 0
    training_metrics = []
    
    for epoch in range(NUM_EPOCHS):
        # Train
        model.train()
        optimizer.zero_grad()
        
        out = model(graph.x, graph.edge_index)
        loss = F.cross_entropy(out[graph.train_mask], graph.y[graph.train_mask])
        loss.backward()
        optimizer.step()
        
        # Evaluate
        model.eval()
        with torch.no_grad():
            out = model(graph.x, graph.edge_index)
            pred = out.argmax(dim=1)
            
            # Train metrics
            train_correct = (pred[graph.train_mask] == graph.y[graph.train_mask]).sum().item()
            train_accuracy = train_correct / graph.train_mask.sum().item()
            
            # Test metrics
            test_correct = (pred[graph.test_mask] == graph.y[graph.test_mask]).sum().item()
            test_accuracy = test_correct / graph.test_mask.sum().item()
            
            # Calculate F1 score
            from sklearn.metrics import f1_score
            test_f1 = f1_score(
                graph.y[graph.test_mask].cpu().numpy(),
                pred[graph.test_mask].cpu().numpy(),
                average='binary'
            )
        
        # Save best model
        if test_f1 > best_f1:
            best_f1 = test_f1
            save_model(model, 'models/gnn_fraud_detector.pt')
        
        # Print progress
        if epoch % 10 == 0 or epoch == NUM_EPOCHS - 1:
            print(f"  Epoch {epoch:3d}/{NUM_EPOCHS} | "
                  f"Loss: {loss.item():.4f} | "
                  f"Train Acc: {train_accuracy:.4f} | "
                  f"Test Acc: {test_accuracy:.4f} | "
                  f"Test F1: {test_f1:.4f}")
        
        # Store metrics
        training_metrics.append({
            'epoch': epoch,
            'loss': loss.item(),
            'train_accuracy': train_accuracy,
            'test_accuracy': test_accuracy,
            'test_f1': test_f1
        })
    
    # Final evaluation
    print("\n[STAGE 5] Final evaluation...")
    model.eval()
    with torch.no_grad():
        out = model(graph.x, graph.edge_index)
        pred = out.argmax(dim=1)
        
        # Calculate final metrics
        from sklearn.metrics import classification_report, confusion_matrix
        
        test_pred = pred[graph.test_mask].cpu().numpy()
        test_true = graph.y[graph.test_mask].cpu().numpy()
        
        print("\nClassification Report:")
        print(classification_report(test_true, test_pred, target_names=['Clean', 'Fraud']))
        
        print("\nConfusion Matrix:")
        print(confusion_matrix(test_true, test_pred))
    
    # Save training metrics
    print("\n[STAGE 6] Saving training metrics...")
    os.makedirs('outputs', exist_ok=True)
    
    metrics_file = 'outputs/gnn_training_metrics.json'
    with open(metrics_file, 'w') as f:
        json.dump({
            'best_f1': best_f1,
            'final_metrics': {
                'accuracy': test_accuracy,
                'f1': test_f1
            },
            'training_history': training_metrics
        }, f, indent=2)
    
    print(f"          Metrics saved to {metrics_file}")
    
    # Test fraud ring detection
    print("\n[STAGE 7] Testing fraud ring detection...")
    fraud_rings = graph_builder.detect_fraud_rings(model, graph, fraud_threshold=FRAUD_THRESHOLD)
    print(f"          Detected {len(fraud_rings)} fraud rings")
    
    for i, ring in enumerate(fraud_rings[:5]):  # Show first 5
        print(f"          Ring {i+1}: Worker {ring['worker_id']}, "
              f"Prob: {ring['fraud_probability']:.3f}, "
              f"Size: {ring['ring_size']}")
    
    print("\n[DONE] GNN Fraud Detection training completed!")
    print(f"[DONE] Best F1 Score: {best_f1:.4f}")
    print(f"[DONE] Model saved to: models/gnn_fraud_detector.pt")


if __name__ == "__main__":
    main()
