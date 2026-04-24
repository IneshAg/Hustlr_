from __future__ import annotations

from pathlib import Path
import random

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATASETS_DIR = PROJECT_ROOT / "hustlr-ml" / "outputs" / "datasets"
NLP_CSV = DATASETS_DIR / "nlp_disruption_events.csv"
RANDOM_STATE = 42

CITY_ZONES = {
    "Chennai": [
        "Adyar",
        "Anna Nagar",
        "Chromepet",
        "Guduvanchery",
        "Guindy",
        "Kathankulathur",
        "Kelambakkam",
        "Perambur",
        "Potheri",
        "Porur",
        "Sholinganallur",
        "Siruseri",
        "T Nagar",
        "Tambaram",
        "Urapakkam",
        "Velachery",
    ],
    "Mumbai": [
        "Andheri",
        "Bandra",
        "Borivali",
        "Chembur",
        "Dadar",
        "Ghatkopar",
        "Lower Parel",
        "Powai",
        "Thane",
        "Vashi",
    ],
    "Bengaluru": [
        "BTM Layout",
        "Electronic City",
        "HSR Layout",
        "Indiranagar",
        "Jayanagar",
        "Koramangala",
        "Marathahalli",
        "Rajajinagar",
        "Whitefield",
        "Yelahanka",
    ],
    "Kolkata": [
        "Behala",
        "Dum Dum",
        "Esplanade",
        "Garia",
        "Howrah",
        "New Town",
        "Park Street",
        "Salt Lake",
        "Sealdah",
        "Tollygunge",
    ],
}

LABEL_COUNTS = {
    "normal": 13121,
    "heavy_rain": 1375,
    "extreme_rain": 566,
    "bandh": 256,
    "heat_wave": 197,
}

DATES = pd.date_range("2025-07-01", "2025-12-31", freq="6h")


def typo(word: str, rng: random.Random) -> str:
    if len(word) < 5 or rng.random() > 0.08:
        return word
    i = rng.randrange(len(word) - 1)
    chars = list(word)
    chars[i], chars[i + 1] = chars[i + 1], chars[i]
    return "".join(chars)


def noisy_join(parts: list[str], rng: random.Random) -> str:
    text = " ".join(p for p in parts if p)
    if rng.random() < 0.18:
        words = text.split()
        idx = rng.randrange(len(words))
        words[idx] = typo(words[idx], rng)
        text = " ".join(words)
    if rng.random() < 0.15:
        text += rng.choice([" #chennai", " #delivery", " #riderlife", ""])
    if rng.random() < 0.10:
        text = text.replace(" is ", " is honestly ", 1)
    return text.strip()


def normal_text(city: str, zone: str, dt: pd.Timestamp, rng: random.Random) -> tuple[str, float]:
    lead = rng.choice([
        f"{zone} side",
        f"{city.lower()} ops update",
        "imd note",
        "delivery status",
        "morning run",
        "evening shift",
        "",
    ])
    body = rng.choice([
        "roads are moving fine and orders are normal",
        "only a light drizzle, nothing serious for deliveries",
        "humid weather but service is running smoothly",
        "cloudy sky, no flooding reported in the area",
        "traffic is moderate, weather is okay",
        "some dark clouds but no disruption so far",
        "heat is there but still manageable on bike",
        "bandh rumours are false, shops are open",
        "alert looked scary earlier but this stretch is clear now",
        "people keep saying rain issue but this pocket is functioning",
    ])
    tail = rng.choice([
        "",
        "right now",
        "for this slot",
        "at the moment",
        f"around {dt.hour}:00",
    ])
    return noisy_join([lead, body, tail], rng), 0.92


def heavy_rain_text(city: str, zone: str, dt: pd.Timestamp, rng: random.Random) -> tuple[str, float]:
    lead = rng.choice([
        f"{zone} getting hit badly",
        f"waterlogging in {zone}",
        "rider update",
        f"{city.lower()} weather alert",
        "customers are calling nonstop",
        "",
    ])
    body = rng.choice([
        "visibility is poor and bikes are slowing down",
        "roads are filling up and riders are taking detours",
        "steady downpour, hard to complete orders",
        "underpass is messy and delivery timing has slipped",
        "streets are shiny with water and the next run feels risky",
        "not full disaster, but this has gone beyond a normal shower",
        "surface water is building and even short routes are stretching",
    ])
    tail = rng.choice([
        f"around {zone} main road",
        "please avoid low-lying lanes",
        f"since {max(dt.hour - 1, 0)} pm",
        "orders are moving slower than usual",
        "",
    ])
    return noisy_join([lead, body, tail], rng), round(rng.uniform(0.78, 0.96), 2)


def extreme_rain_text(city: str, zone: str, dt: pd.Timestamp, rng: random.Random) -> tuple[str, float]:
    lead = rng.choice([
        "ndma emergency advisory",
        "red alert update",
        f"{zone} is getting slammed",
        "field escalation",
        "",
    ])
    body = rng.choice([
        "roads are submerged and power cuts are being reported",
        "cyclonic rain, trees are down and delivery is near impossible",
        "water entering shops, this has turned severe very quickly",
        "absolute cloudburst conditions with multiple streets blocked",
        "rescue vehicles visible and the rain has crossed normal heavy levels",
        "the whole stretch looks washed out and two-wheelers are backing off",
        "what started as a bad spell is now a full emergency situation",
    ])
    tail = rng.choice([
        f"in {zone}",
        "stay indoors if possible",
        "service outage risk is high",
        f"since {dt.strftime('%I %p').lstrip('0')}",
        "",
    ])
    return noisy_join([lead, body, tail], rng), round(rng.uniform(0.88, 0.99), 2)


def bandh_text(city: str, zone: str, dt: pd.Timestamp, rng: random.Random) -> tuple[str, float]:
    lead = rng.choice([
        f"{city.lower()} shutdown update",
        "police diversion note",
        f"{zone} market side",
        "field ops alert",
        "",
    ])
    body = rng.choice([
        "shops are half shut and protest groups are blocking the junction",
        "bandh impact visible, traffic diverted and very few orders coming in",
        "autos, bikes and dark-store movement slowed because of protest action",
        "roadblock near the signal, delivery fleet is waiting",
        "some stores stayed open but transport is choked by shutdown activity",
        "feels like a shutdown even though weather itself is manageable",
    ])
    tail = rng.choice([
        "heard drums and slogans nearby",
        "this is more than normal traffic",
        f"around {dt.strftime('%I %p').lstrip('0')}",
        "",
    ])
    return noisy_join([lead, body, tail], rng), round(rng.uniform(0.76, 0.95), 2)


def heat_wave_text(city: str, zone: str, dt: pd.Timestamp, rng: random.Random) -> tuple[str, float]:
    lead = rng.choice([
        "rider health note",
        f"{zone} in {city} feels like an oven",
        "imd summer alert",
        "",
    ])
    body = rng.choice([
        "phone is overheating and the sun is brutal",
        "helmet heat is unbearable, had to stop for water",
        "air feels dry and harsh, riders are slowing down",
        "not rain, just dangerous heat building up on the road",
        "feels above forty and body is draining fast",
        "the road surface itself feels hot enough to throw heat back at you",
    ])
    tail = rng.choice([
        f"by {dt.strftime('%I %p').lstrip('0')}",
        "need shade every few minutes",
        "deliveries are possible but exhausting",
        "",
    ])
    return noisy_join([lead, body, tail], rng), round(rng.uniform(0.74, 0.94), 2)


TEXT_BUILDERS = {
    "normal": normal_text,
    "heavy_rain": heavy_rain_text,
    "extreme_rain": extreme_rain_text,
    "bandh": bandh_text,
    "heat_wave": heat_wave_text,
}


def rainfall_for_label(label: str, rng: random.Random) -> float:
    if label == "normal":
        return round(rng.uniform(0.0, 2.4), 2)
    if label == "heavy_rain":
        return round(rng.uniform(18.0, 62.0), 2)
    if label == "extreme_rain":
        return round(rng.uniform(65.0, 155.0), 2)
    return 0.0


def build_dataset() -> pd.DataFrame:
    rng = random.Random(RANDOM_STATE)
    rows = []
    event_num = 1

    for label, count in LABEL_COUNTS.items():
        builder = TEXT_BUILDERS[label]
        for _ in range(count):
            city = rng.choice(list(CITY_ZONES))
            zone = rng.choice(CITY_ZONES[city])
            dt = pd.Timestamp(rng.choice(DATES))
            text, confidence = builder(city, zone, dt, rng)

            if label == "normal" and rng.random() < 0.22:
                text = noisy_join(
                    [
                        text,
                        rng.choice([
                            f"heard rain in another {city.lower()} area but not here",
                            f"{city} warning looked scary but this pocket is fine",
                            "temperature is high though still workable",
                            "minor slowdown only",
                        ]),
                    ],
                    rng,
                )
            if label == "normal" and rng.random() < 0.18:
                text = noisy_join(
                    [
                        text,
                        rng.choice([
                            f"saw water in another {city.lower()} lane but here it is still rideable",
                            f"protest talk is floating around in {city} but no hard road closure yet",
                            "very hot, still not enough to disrupt the shift",
                            "warning exists, ground reality here is mostly okay",
                        ]),
                    ],
                    rng,
                )
            if label == "heavy_rain" and rng.random() < 0.28:
                text = noisy_join(
                    [
                        rng.choice([
                            "maybe not cyclone grade yet,",
                            "customers think the app is down but the main issue is outside,",
                            "hard to tell if this becomes severe,",
                        ]),
                        text,
                    ],
                    rng,
                )
            if label == "extreme_rain" and rng.random() < 0.35:
                text = noisy_join(
                    [
                        text,
                        rng.choice([
                            "some riders first thought it was only heavy rain",
                            "looks worse on ground than the alert text suggests",
                            "this started like normal monsoon but escalated fast",
                        ]),
                    ],
                    rng,
                )
            if label == "bandh" and rng.random() < 0.25:
                text = noisy_join(
                    [
                        text,
                        rng.choice([
                            "weather is not the main problem here",
                            "roads themselves are open in parts but movement is still choked",
                            "from far away it just looks like traffic until you get closer",
                        ]),
                    ],
                    rng,
                )
            if label == "heat_wave" and rng.random() < 0.25:
                text = noisy_join(
                    [
                        text,
                        rng.choice([
                            "dark clouds are around but there is no useful cooling",
                            "service has not stopped, just slowed by rider fatigue",
                            "people keep expecting rain but the heat is the real issue",
                        ]),
                    ],
                    rng,
                )

            rows.append(
                {
                    "event_id": f"EVT{event_num:06d}",
                    "date": dt.strftime("%Y-%m-%d"),
                    "city": city,
                    "zone": zone,
                    "raw_text": text,
                    "trigger_label": label,
                    "confidence": confidence,
                    "is_disruption": int(label != "normal"),
                    "mm_rainfall": rainfall_for_label(label, rng),
                    "window_start": dt.strftime("%H:%M"),
                    "window_end": (dt + pd.Timedelta(hours=1)).strftime("%H:%M"),
                }
            )
            event_num += 1

    df = pd.DataFrame(rows)
    df = inject_annotation_ambiguity(df, rng)
    return df.sample(frac=1.0, random_state=RANDOM_STATE).reset_index(drop=True)


def inject_annotation_ambiguity(df: pd.DataFrame, rng: random.Random) -> pd.DataFrame:
    out = df.copy()
    plans = [
        ("normal", 0.025, ["heavy_rain", "bandh", "heat_wave"]),
        ("heavy_rain", 0.08, ["normal", "extreme_rain"]),
        ("extreme_rain", 0.12, ["heavy_rain"]),
        ("bandh", 0.10, ["normal"]),
        ("heat_wave", 0.10, ["normal"]),
    ]
    for source_label, frac, target_labels in plans:
        idx = out.index[out["trigger_label"] == source_label].tolist()
        if not idx:
            continue
        n = max(1, int(len(idx) * frac))
        chosen = rng.sample(idx, n)
        for row_idx in chosen:
            out.at[row_idx, "trigger_label"] = rng.choice(target_labels)
            out.at[row_idx, "is_disruption"] = int(out.at[row_idx, "trigger_label"] != "normal")
            out.at[row_idx, "confidence"] = round(min(float(out.at[row_idx, "confidence"]), rng.uniform(0.45, 0.72)), 2)
    return out


def main() -> None:
    df = build_dataset()
    df.to_csv(NLP_CSV, index=False)
    print(f"Rebuilt {NLP_CSV} with {len(df)} rows")
    print(df["trigger_label"].value_counts().to_dict())
    print(f"Unique texts: {df['raw_text'].nunique()}")


if __name__ == "__main__":
    main()
