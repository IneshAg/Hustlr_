"""
ring_detector.py ??? Statistical ring-fraud detection for Hustlr.

Two independent tests are run on every zone claim event batch:

1. Poisson Distribution Test (timestamp analysis)
   Genuine disruption claims arrive stochastically throughout the first
   20???40 minutes following an event, forming a Poisson inter-arrival
   distribution.  Coordinated rings fire uniformly within seconds of
   each other.  We use the dispersion index D = Var(??t)/Mean(??t) and
   a chi-squared goodness-of-fit test to classify the pattern.

2. DBSCAN Geographic Clustering (GPS analysis)
   Legitimate workers are spatially spread across a delivery zone
   (hundreds to thousands of meters apart).  Ring participants claiming
   from the same physical location produce implausibly tight clusters.
   We flag any cluster with ??? 5 workers within a 50m radius.
"""

from __future__ import annotations

import math
from typing import List, Tuple

import numpy as np
from scipy import stats
from sklearn.cluster import DBSCAN


# ?????? Haversine distance (meters) ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Return the great-circle distance in metres between two WGS-84 coordinates.

    Uses the haversine formula ??? accurate to < 0.5% for distances < 1 km,
    which is the relevant scale for dark-store delivery zones.
    """
    R = 6_371_000.0  # Earth radius in metres
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lam = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lam / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


# ?????? Poisson inter-arrival test ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

RING_P_VALUE_THRESHOLD = 0.05   # p < 0.05 ??? reject Poisson ??? coordinated ring
BURST_WINDOW_SECONDS   = 30     # ??? 30s spread across all claims = "burst"


def test_poisson_arrivals(timestamps: List[int]) -> dict:
    """
    Test whether claim timestamps within a 30-minute zone window follow the
    Poisson inter-arrival distribution expected from genuine disruptions.

    Algorithm:
      1. Sort timestamps and compute inter-arrival gaps (??t).
      2. Compute the dispersion index D = Var(??t) / Mean(??t).
         D ??? Mean(??t) for a Poisson process (memoryless).
         D ??? Mean(??t) indicates uniform/burst arrivals (ring).
      3. Run a one-sample KS test of ??t against an Exponential distribution
         with ?? = 1/Mean(??t) ??? the null hypothesis is Poisson arrivals.
         A low p-value rejects the null (ring confirmed).

    Args:
        timestamps: List of epoch-seconds claim submission times from the
                    same zone within a 30-minute window.  Minimum 3 required.

    Returns:
        {
          "is_coordinated_ring": bool,
          "p_value": float,
          "dispersion_index": float,
          "filing_pattern": "poisson" | "uniform" | "burst",
          "sample_size": int,
          "mean_inter_arrival_s": float,
        }
    """
    if len(timestamps) < 3:
        return {
            "is_coordinated_ring": False,
            "p_value": 1.0,
            "dispersion_index": 0.0,
            "filing_pattern": "poisson",
            "sample_size": len(timestamps),
            "mean_inter_arrival_s": 0.0,
            "note": "Insufficient data (< 3 claims) ??? cannot evaluate ring pattern",
        }

    ts = np.sort(np.array(timestamps, dtype=float))
    deltas = np.diff(ts)

    mean_delta = float(np.mean(deltas))
    var_delta  = float(np.var(deltas))
    dispersion = var_delta / mean_delta if mean_delta > 0 else 0.0

    # KS test against Exponential distribution (Poisson inter-arrivals)
    if mean_delta > 0:
        ks_stat, p_value = stats.kstest(
            deltas,
            "expon",
            args=(0.0, mean_delta),    # loc=0, scale=mean (= 1/??)
            N=len(deltas),
        )
    else:
        p_value = 0.0  # zero inter-arrivals = perfect burst

    # Classify pattern
    total_spread = float(ts[-1] - ts[0])
    if total_spread <= BURST_WINDOW_SECONDS:
        filing_pattern = "burst"
    elif p_value < RING_P_VALUE_THRESHOLD:
        filing_pattern = "uniform"   # non-Poisson, uniform spacing = coordinated
    else:
        filing_pattern = "poisson"

    is_ring = p_value < RING_P_VALUE_THRESHOLD or filing_pattern == "burst"

    return {
        "is_coordinated_ring":   is_ring,
        "p_value":               round(float(p_value), 6),
        "dispersion_index":      round(dispersion, 4),
        "filing_pattern":        filing_pattern,
        "sample_size":           len(timestamps),
        "mean_inter_arrival_s":  round(mean_delta, 2),
        "total_spread_s":        round(total_spread, 2),
    }


# ?????? DBSCAN GPS clustering ?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

RING_MIN_CLUSTER_SIZE    = 5      # ??? 5 workers in a tight cluster = ring
RING_CLUSTER_RADIUS_M    = 50.0   # 50m radius threshold (per spec)
EARTH_RADIUS_M           = 6_371_000.0


def _haversine_matrix(coords: np.ndarray) -> np.ndarray:
    """
    Build a pairwise haversine distance matrix (metres) for an array of
    shape (N, 2) where columns are [latitude, longitude] in degrees.
    """
    n = len(coords)
    D = np.zeros((n, n), dtype=float)
    for i in range(n):
        for j in range(i + 1, n):
            d = _haversine_m(coords[i, 0], coords[i, 1], coords[j, 0], coords[j, 1])
            D[i, j] = d
            D[j, i] = d
    return D


def detect_gps_clusters(gps_coords: List[Tuple[float, float]]) -> dict:
    """
    Run DBSCAN on GPS claim coordinates to detect implausibly tight
    geographic clusters indicative of ring fraud (workers claiming from
    the same physical location).

    Algorithm:
      1. Compute pairwise haversine distance matrix (metres).
      2. Run DBSCAN with eps=RING_CLUSTER_RADIUS_M (50m) and
         min_samples=RING_MIN_CLUSTER_SIZE (5 workers).
         Points within 50m of at least 4 neighbours form a core cluster.
      3. For each identified cluster compute its radius (half the max
         pairwise distance within the cluster).
      4. Flag if any cluster has ??? 5 workers within 50m.

    Args:
        gps_coords: List of (latitude, longitude) tuples for each claim in
                    the same zone event window.

    Returns:
        {
          "ring_detected": bool,
          "cluster_count": int,
          "tightest_cluster_radius_m": float,
          "largest_cluster_size": int,
          "noise_points": int,
        }
    """
    if len(gps_coords) < RING_MIN_CLUSTER_SIZE:
        return {
            "ring_detected":              False,
            "cluster_count":              0,
            "tightest_cluster_radius_m":  0.0,
            "largest_cluster_size":       len(gps_coords),
            "noise_points":               len(gps_coords),
            "note": f"Insufficient data (< {RING_MIN_CLUSTER_SIZE} claims)",
        }

    coords = np.array(gps_coords, dtype=float)

    # Haversine distance matrix so DBSCAN works in metres
    dist_matrix = _haversine_matrix(coords)

    db = DBSCAN(
        eps            = RING_CLUSTER_RADIUS_M,
        min_samples    = RING_MIN_CLUSTER_SIZE,
        metric         = "precomputed",
        algorithm      = "brute",
    )
    labels = db.fit_predict(dist_matrix)

    unique_clusters = set(labels) - {-1}
    noise_count     = int(np.sum(labels == -1))
    cluster_count   = len(unique_clusters)

    if cluster_count == 0:
        return {
            "ring_detected":              False,
            "cluster_count":              0,
            "tightest_cluster_radius_m":  0.0,
            "largest_cluster_size":       0,
            "noise_points":               noise_count,
        }

    # Analyse each cluster
    radii           = []
    cluster_sizes   = []
    for lbl in unique_clusters:
        members = np.where(labels == lbl)[0]
        cluster_sizes.append(len(members))

        if len(members) < 2:
            radii.append(0.0)
        else:
            sub_dists = dist_matrix[np.ix_(members, members)]
            radii.append(float(np.max(sub_dists)) / 2.0)   # radius = half diameter

    tightest_radius = float(min(radii))
    largest_size    = int(max(cluster_sizes))

    ring_detected = (
        cluster_count > 0
        and tightest_radius <= RING_CLUSTER_RADIUS_M
        and largest_size >= RING_MIN_CLUSTER_SIZE
    )

    return {
        "ring_detected":              ring_detected,
        "cluster_count":              cluster_count,
        "tightest_cluster_radius_m":  round(tightest_radius, 2),
        "largest_cluster_size":       largest_size,
        "noise_points":               noise_count,
        "cluster_radii_m":            [round(r, 2) for r in radii],
    }


# ?????? Combined ring verdict ?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

def combined_ring_verdict(poisson_result: dict, dbscan_result: dict) -> str:
    """
    Produce a recommended_action by combining both ring-detection signals.

    Decision matrix:
      Both positive  ??? human_review   (high confidence ring)
      Poisson only   ??? soft_hold      (temporal anomaly, await GPS confirm)
      DBSCAN only    ??? soft_hold      (spatial anomaly, may be dark-store queue)
      Neither        ??? auto_approve   (no ring signal)
    """
    p_ring = poisson_result.get("is_coordinated_ring", False)
    g_ring = dbscan_result.get("ring_detected", False)

    if p_ring and g_ring:
        return "human_review"
    if p_ring or g_ring:
        return "soft_hold"
    return "auto_approve"

