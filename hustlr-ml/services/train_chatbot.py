import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
import joblib
import json
import os

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
    
    vectorizer = TfidfVectorizer(ngram_range=(1, 2))
    X = vectorizer.fit_transform(df['text'])
    y = df['intent']
    
    model = LogisticRegression(random_state=42, class_weight='balanced')
    model.fit(X, y)
    
    acc = model.score(X, y)
    print(f"Training Accuracy: {acc * 100:.2f}%")
    
    os.makedirs('models', exist_ok=True)
    joblib.dump(vectorizer, 'models/chatbot_vectorizer.pkl')
    joblib.dump(model, 'models/chatbot_model.pkl')
    
    with open('models/chatbot_responses.json', 'w') as f:
        json.dump(RESPONSES, f)
        
    print("Chatbot ML artifacts successfully saved to /models")

if __name__ == '__main__':
    train_model()
