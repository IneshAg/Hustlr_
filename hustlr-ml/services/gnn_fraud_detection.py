"""
GNN Fraud Detection using GraphSAGE
====================================
Detects fraud rings and coordinated fraud patterns using Graph Neural Networks.

Architecture:
- GraphSAGE (Graph Sample and Aggregation) for graph-based learning
- Node features: worker behavior metrics
- Edge types: device sharing, UPI sharing, zone clustering
- Output: fraud probability per node (worker)
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch_geometric.nn import SAGEConv, global_mean_pool
from torch_geometric.data import Data, DataLoader
from typing import List, Dict, Tuple, Optional
import numpy as np
import joblib
import os


class GraphSAGEFraudDetector(nn.Module):
    """
    GraphSAGE model for fraud ring detection.
    
    Architecture:
    - 3 GraphSAGE convolutional layers
    - Dropout for regularization
    - Final classification layer
    """
    
    def __init__(
        self,
        node_features: int = 6,
        hidden_dim: int = 64,
        num_classes: int = 2,
        dropout: float = 0.5
    ):
        super(GraphSAGEFraudDetector, self).__init__()
        
        # GraphSAGE layers
        self.conv1 = SAGEConv(node_features, hidden_dim)
        self.conv2 = SAGEConv(hidden_dim, hidden_dim)
        self.conv3 = SAGEConv(hidden_dim, hidden_dim)
        
        # Classification head
        self.classifier = nn.Linear(hidden_dim, num_classes)
        
        # Dropout
        self.dropout = nn.Dropout(dropout)
        
    def forward(self, x, edge_index, batch=None):
        """
        Forward pass through the network.
        
        Args:
            x: Node features [num_nodes, num_features]
            edge_index: Edge indices [2, num_edges]
            batch: Batch vector (optional, for mini-batch training)
        
        Returns:
            Logits for each node [num_nodes, num_classes]
        """
        # Layer 1
        x = self.conv1(x, edge_index)
        x = F.relu(x)
        x = self.dropout(x)
        
        # Layer 2
        x = self.conv2(x, edge_index)
        x = F.relu(x)
        x = self.dropout(x)
        
        # Layer 3
        x = self.conv3(x, edge_index)
        x = F.relu(x)
        
        # Classification
        out = self.classifier(x)
        
        return out
    
    def predict(self, x, edge_index):
        """
        Predict fraud probability for each node.
        
        Returns:
            Fraud probability for each node [num_nodes]
        """
        self.eval()
        with torch.no_grad():
            logits = self.forward(x, edge_index)
            probs = F.softmax(logits, dim=1)
            return probs[:, 1].cpu().numpy()  # Return fraud probability


class FraudGraphBuilder:
    """
    Builds fraud detection graphs from worker data.
    
    Edge types:
    1. Device sharing: Same device fingerprint
    2. UPI sharing: Same UPI ID
    3. Zone clustering: Similar claim timing in same zone
    4. Registration burst: Workers registered together
    """
    
    def __init__(self):
        # Node features to extract
        self.node_features = [
            'account_age_days',
            'avg_daily_orders',
            'claim_frequency',
            'device_shared_count',
            'zone_depth_avg',
            'historical_clean_ratio'
        ]
    
    def build_graph_from_workers(self, workers: List[Dict]) -> Data:
        """
        Build a PyTorch Geometric Data object from worker data.
        
        Args:
            workers: List of worker dictionaries with features
        
        Returns:
            PyTorch Geometric Data object
        """
        if not workers:
            raise ValueError("No workers provided to build graph")
        
        # Extract node features
        node_features = []
        node_ids = []
        
        for worker in workers:
            features = [worker.get(f, 0) for f in self.node_features]
            node_features.append(features)
            node_ids.append(worker['id'])
        
        # Convert to tensor
        x = torch.tensor(node_features, dtype=torch.float)
        
        # Build edges based on fraud signals
        edge_index = self._build_edges(workers, node_ids)
        
        # Create Data object
        data = Data(x=x, edge_index=edge_index)
        
        # Store node IDs for reference
        data.node_ids = node_ids
        
        return data
    
    def _build_edges(self, workers: List[Dict], node_ids: List[str]) -> torch.Tensor:
        """
        Build edges between workers based on fraud signals.
        
        Returns:
            Edge index tensor [2, num_edges]
        """
        edges = []
        
        for i, worker_a in enumerate(workers):
            for j, worker_b in enumerate(workers):
                if i >= j:
                    continue
                
                # Edge 1: Device sharing
                if worker_a.get('device_fingerprint') and worker_a.get('device_fingerprint') == worker_b.get('device_fingerprint'):
                    edges.append([i, j])
                    edges.append([j, i])
                
                # Edge 2: UPI sharing
                if worker_a.get('upi_id') and worker_a.get('upi_id') == worker_b.get('upi_id'):
                    edges.append([i, j])
                    edges.append([j, i])
                
                # Edge 3: Zone clustering (similar claim timing in same zone)
                if (worker_a.get('zone_id') == worker_b.get('zone_id') and
                    abs(worker_a.get('claim_latency', 0) - worker_b.get('claim_latency', 0)) < 10):
                    edges.append([i, j])
                    edges.append([j, i])
                
                # Edge 4: Registration burst (registered within 1 hour)
                if worker_a.get('registered_at') and worker_b.get('registered_at'):
                    time_diff = abs(worker_a['registered_at'] - worker_b['registered_at'])
                    if time_diff.total_seconds() < 3600:  # 1 hour
                        edges.append([i, j])
                        edges.append([j, i])
        
        # Convert to tensor
        if not edges:
            # No edges found, return empty edge index
            return torch.empty((2, 0), dtype=torch.long)
        
        return torch.tensor(edges, dtype=torch.long).t().contiguous()
    
    def detect_fraud_rings(
        self,
        model: GraphSAGEFraudDetector,
        graph: Data,
        fraud_threshold: float = 0.7
    ) -> List[Dict]:
        """
        Detect fraud rings using the trained GNN model.
        
        Args:
            model: Trained GraphSAGE model
            graph: PyTorch Geometric Data object
            fraud_threshold: Probability threshold for fraud classification
        
        Returns:
            List of detected fraud rings
        """
        # Get fraud probabilities
        fraud_probs = model.predict(graph.x, graph.edge_index)
        
        # Find workers with high fraud probability
        fraud_indices = np.where(fraud_probs > fraud_threshold)[0]
        
        rings = []
        
        for idx in fraud_indices:
            # Get neighbors (connected nodes)
            neighbors = self._get_neighbors(graph.edge_index, idx)
            
            # Find neighbors with high fraud probability
            fraud_neighbors = [n for n in neighbors if fraud_probs[n] > 0.5]
            
            if fraud_neighbors:
                rings.append({
                    'worker_id': graph.node_ids[idx],
                    'fraud_probability': float(fraud_probs[idx]),
                    'ring_members': [graph.node_ids[n] for n in fraud_neighbors],
                    'ring_size': len(fraud_neighbors) + 1
                })
        
        return rings
    
    def _get_neighbors(self, edge_index: torch.Tensor, node_idx: int) -> List[int]:
        """
        Get neighbors of a node from edge index.
        
        Args:
            edge_index: Edge index tensor [2, num_edges]
            node_idx: Node index
        
        Returns:
            List of neighbor node indices
        """
        if edge_index.numel() == 0:
            return []
        
        # Find all edges connected to the node
        mask = (edge_index[0] == node_idx) | (edge_index[1] == node_idx)
        connected_edges = edge_index[:, mask]
        
        # Get unique neighbors
        neighbors = set()
        for edge in connected_edges.t():
            if edge[0].item() != node_idx:
                neighbors.add(edge[0].item())
            if edge[1].item() != node_idx:
                neighbors.add(edge[1].item())
        
        return list(neighbors)


def save_model(model: GraphSAGEFraudDetector, path: str) -> None:
    """
    Save trained GNN model to disk.
    
    Args:
        model: Trained model
        path: Path to save model
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    torch.save(model.state_dict(), path)
    print(f"Model saved to {path}")


def load_model(path: str, node_features: int = 6, hidden_dim: int = 64, num_classes: int = 2) -> GraphSAGEFraudDetector:
    """
    Load trained GNN model from disk.
    
    Args:
        path: Path to saved model
        node_features: Number of node features
        hidden_dim: Hidden dimension
        num_classes: Number of output classes
    
    Returns:
        Loaded model
    """
    model = GraphSAGEFraudDetector(
        node_features=node_features,
        hidden_dim=hidden_dim,
        num_classes=num_classes
    )
    model.load_state_dict(torch.load(path, map_location='cpu'))
    model.eval()
    print(f"Model loaded from {path}")
    return model


if __name__ == "__main__":
    # Test the model architecture
    print("Testing GNN Fraud Detection Model...")
    
    # Create dummy data
    num_nodes = 100
    num_features = 6
    num_edges = 200
    
    x = torch.randn(num_nodes, num_features)
    edge_index = torch.randint(0, num_nodes, (2, num_edges))
    
    # Create model
    model = GraphSAGEFraudDetector(
        node_features=num_features,
        hidden_dim=64,
        num_classes=2
    )
    
    # Forward pass
    output = model(x, edge_index)
    print(f"Model output shape: {output.shape}")
    
    # Test prediction
    fraud_probs = model.predict(x, edge_index)
    print(f"Fraud probabilities shape: {fraud_probs.shape}")
    print(f"Sample fraud probabilities: {fraud_probs[:5]}")
    
    print("\nGNN Fraud Detection Model test completed successfully!")
