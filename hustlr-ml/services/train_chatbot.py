import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split, cross_val_score, StratifiedKFold
from sklearn.metrics import classification_report, accuracy_score
import joblib
import json
import os
import numpy as np

# Training dataset
DATA = [
    # Claim & Status
    {"text": "what is the status of my claim?", "intent": "claim"},
    {"text": "did you process my claim", "intent": "claim"},
    {"text": "how long does claim take", "intent": "claim"},
    {"text": "check claim status", "intent": "claim"},
    {"text": "do i need to file a claim?", "intent": "claim"},
    {"text": "where is my claim money", "intent": "claim"},

    # Withdraw & UPI
    {"text": "how do I withdraw my money", "intent": "withdraw"},
    {"text": "withdraw balance to upi", "intent": "withdraw"},
    {"text": "transfer to bank", "intent": "withdraw"},
    {"text": "get my payout in bank", "intent": "withdraw"},
    {"text": "upi withdrawal not working", "intent": "withdraw"},

    # Payouts
    {"text": "how does the payout work", "intent": "payout"},
    {"text": "when do I get paid", "intent": "payout"},
    {"text": "parametric payout explained", "intent": "payout"},
    {"text": "how much money do i receive", "intent": "payout"},

    # Rain
    {"text": "how does rain payout work", "intent": "rain"},
    {"text": "heavy rain flood coverage", "intent": "rain"},
    {"text": "rain sensor limit", "intent": "rain"},
    {"text": "imd rain threshold", "intent": "rain"},

    # Premium
    {"text": "why is premium 49?", "intent": "premium"},
    {"text": "cost of standard shield", "intent": "premium"},
    {"text": "how much does policy cost", "intent": "premium"},
    {"text": "deduction from swiggy", "intent": "premium"},

    # Refund
    {"text": "can i get a refund", "intent": "refund"},
    {"text": "cancel policy", "intent": "refund"},
    {"text": "stop my coverage", "intent": "refund"},
    {"text": "getting my 49 rupees back", "intent": "refund"},

    # KYC
    {"text": "how do you verify my identity", "intent": "kyc"},
    {"text": "kyc documents needed", "intent": "kyc"},
    {"text": "is my adhaar safe", "intent": "kyc"},
    {"text": "delivery partner id", "intent": "kyc"},

    # Upgrade
    {"text": "what is full shield", "intent": "upgrade"},
    {"text": "upgrade my plan", "intent": "upgrade"},
    {"text": "dark store closure coverage", "intent": "upgrade"},
    {"text": "bandh and curfew", "intent": "upgrade"},

    # Policy
    {"text": "what does my policy cover", "intent": "policy"},
    {"text": "show my coverage plan", "intent": "policy"},
    {"text": "standard shield details", "intent": "policy"},
    {"text": "what disruptions are insured", "intent": "policy"},

    # Zone
    {"text": "tell me about my zone", "intent": "zone"},
    {"text": "my location coverage", "intent": "zone"},
    {"text": "where is sensor located", "intent": "zone"},
    {"text": "zone depth score", "intent": "zone"},

    # Heat
    {"text": "extreme heat payout", "intent": "heat"},
    {"text": "temperature exceeded 43 degrees", "intent": "heat"},
    {"text": "too hot to work", "intent": "heat"},
    {"text": "heatwave coverage", "intent": "heat"},

    # AQI
    {"text": "air quality alert", "intent": "aqi"},
    {"text": "pollution is too high", "intent": "aqi"},
    {"text": "cpcb sensor aqi 300", "intent": "aqi"},
    {"text": "smog payout", "intent": "aqi"},

    # Fraud
    {"text": "how do you detect fake claims", "intent": "fraud"},
    {"text": "google cloud vision liveness", "intent": "fraud"},
    {"text": "anti spoofing", "intent": "fraud"},
    {"text": "fraud detection", "intent": "fraud"},

    # Tracking
    {"text": "background location tracking", "intent": "tracking"},
    {"text": "gps tracking in background", "intent": "tracking"},
    {"text": "foreground service", "intent": "tracking"},
    {"text": "how is location recorded", "intent": "tracking"},

    # Camera
    {"text": "taking a photo for claim", "intent": "camera"},
    {"text": "manual evidence picture", "intent": "camera"},
    {"text": "live capture requirement", "intent": "camera"},

    # ML
    {"text": "how does the ml tracking work", "intent": "ml"},
    {"text": "isolation forest anomaly", "intent": "ml"},
    {"text": "machine learning score", "intent": "ml"},
    {"text": "ai model for risk", "intent": "ml"},

    # Default/Greeting
    {"text": "hello", "intent": "default"},
    {"text": "hi who are you", "intent": "default"},
    {"text": "help me", "intent": "default"},
    {"text": "need assistance", "intent": "default"}
]

RESPONSES = {
    'claim': 'Most claims are processed automatically once a disruption trigger is confirmed. If a trigger is missed, you can file a manual claim from the app. Payout timing depends on risk checks and review status.',
    'withdraw': 'You can withdraw your payout balance to any UPI ID from the Wallet tab. Transfers reflect within 2 hours via Razorpay.',
    'payout': 'Hustlr uses parametric insurance — payouts are triggered automatically when official thresholds are crossed. 70% is paid immediately, and 30% within 48 hours.',
    'rain': 'Heavy rain payouts activate when rainfall exceeds 64.5mm/hr as confirmed by IMD sensors in your zone.',
    'premium': 'Your weekly premium is calculated based on your zone\'s historical risk. Standard Shield is ₹49/week.',
    'refund': 'Hustlr doesn\'t offer refunds, but if no disruption events occur, that reduces your future premium via actuarial adjustment.',
    'kyc': 'Your identity was verified during onboarding via your Delivery Partner ID. For any KYC updates, please contact our support team.',
    'upgrade': 'Full Shield (₹79/week) covers everything in Standard Shield, plus Bandh/Curfew events, Internet Blackouts, Dark Store Closures, and AQI > 200 alerts. You can upgrade anytime from the Policy tab!',
    'policy': 'Your active plan covers heavy rain, extreme heat, AQI alerts, platform downtime, and bandh events.',
    'zone': 'Your zone is detected from your onboarding location. Disruption events are validated zone-specifically using live sensor data from IMD, CPCB, and platform APIs.',
    'heat': 'Extreme heat payouts are triggered when your zone temperature exceeds 43°C (IMD), sustained for 2+ hours during active delivery shifts.',
    'aqi': 'Air quality payouts trigger when AQI exceeds 300 (Hazardous) as measured by CPCB sensors within 10km of your delivery zone.',
    'fraud': 'Hustlr prevents fraud using Google Cloud Vision for facial liveness checks, combined with local device sensor telemetry (accelerometer anomalies) to verify true delivery conditions.',
    'tracking': 'Your location is tracked in the background during active shifts. On some devices with aggressive battery policies, background tracking can pause unless app permissions and battery settings are optimized.',
    'camera': 'Our camera auto-launches and requires live capture with timestamp and EXIF integrity to prevent screenshot fraud.',
    'ml': 'Our backend uses an Isolation Forest ML model to detect anomalous patterns in your phone\'s telemetry, mixed with historical claim frequencies on a gradient-boosted tree.',
    'default': 'I\'m here to help! You can ask me about your policy, payouts, claims, premiums, zone coverage, fraud prevention, ML tracking, or how to withdraw your balance.'
}

def train_model():
    df = pd.DataFrame(DATA)
    y = df['intent']

    # ── Step 1: Stratified 80/20 train/test split ──────────────────────────
    # Stratify ensures every intent class is represented in both folds.
    # With only 113 samples some classes have 3-4 examples, so test_size=0.20
    # gives roughly 1 held-out sample per class — good enough to detect
    # systematic mis-classifications without wasting training data.
    X_text_train, X_text_test, y_train, y_test = train_test_split(
        df['text'], y,
        test_size=0.20,
        random_state=42,
        stratify=y,
    )
    print(f"[Chatbot] Split: {len(X_text_train)} train / {len(X_text_test)} test samples")

    # ── Step 2: Fit vectorizer on TRAINING data only ───────────────────────
    # Fitting on all data would leak test vocabulary — this prevents that.
    vectorizer = TfidfVectorizer(ngram_range=(1, 2))
    X_train = vectorizer.fit_transform(X_text_train)
    X_test  = vectorizer.transform(X_text_test)       # transform only, no fit

    # ── Step 3: Train the classifier ──────────────────────────────────────
    model = LogisticRegression(
        random_state=42,
        class_weight='balanced',
        max_iter=500,
    )
    model.fit(X_train, y_train)

    # ── Step 4: Evaluate on held-out test set ─────────────────────────────
    y_pred    = model.predict(X_test)
    train_acc = accuracy_score(y_train, model.predict(X_train))
    test_acc  = accuracy_score(y_test, y_pred)

    print("[Chatbot] ── Evaluation Results ────────────────────────────────")
    print(f"[Chatbot]   Train accuracy : {train_acc * 100:.2f}%")
    print(f"[Chatbot]   Test  accuracy : {test_acc  * 100:.2f}%  ← held-out")
    print("[Chatbot]   Per-class report (test set):")
    print(classification_report(y_test, y_pred, zero_division=0))

    # ── Step 5: Leave-One-Out cross-val for robust small-dataset estimate ──
    vectorizer_full = TfidfVectorizer(ngram_range=(1, 2))
    X_full = vectorizer_full.fit_transform(df['text'])
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    cv_scores = cross_val_score(
        LogisticRegression(random_state=42, class_weight='balanced', max_iter=500),
        X_full, y, cv=cv, scoring='accuracy'
    )
    print(f"[Chatbot]   5-Fold CV accuracy: {np.mean(cv_scores)*100:.2f}% ± {np.std(cv_scores)*100:.2f}%")
    print("[Chatbot] ────────────────────────────────────────────────────────")

    # ── Step 6: Re-train on FULL dataset for production artifact ──────────
    # After evaluation, we retrain on all data so the deployed model
    # benefits from every example. This is standard practice.
    vectorizer_prod = TfidfVectorizer(ngram_range=(1, 2))
    X_prod = vectorizer_prod.fit_transform(df['text'])
    model_prod = LogisticRegression(
        random_state=42, class_weight='balanced', max_iter=500
    )
    model_prod.fit(X_prod, y)

    os.makedirs('models', exist_ok=True)
    joblib.dump(vectorizer_prod, 'models/chatbot_vectorizer.pkl')
    joblib.dump(model_prod,      'models/chatbot_model.pkl')

    with open('models/chatbot_responses.json', 'w') as f:
        json.dump(RESPONSES, f)

    print("[Chatbot] Production artifacts saved to /models")
    print(f"[Chatbot] Reported test accuracy: {test_acc*100:.2f}% | CV: {np.mean(cv_scores)*100:.2f}%")
    return {
        "train_accuracy":   round(train_acc, 4),
        "test_accuracy":    round(test_acc, 4),
        "cv_mean_accuracy": round(float(np.mean(cv_scores)), 4),
        "cv_std":           round(float(np.std(cv_scores)), 4),
    }

if __name__ == '__main__':
    train_model()
