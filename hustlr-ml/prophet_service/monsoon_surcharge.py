from datetime import date

def calculate_surcharge(base_premium: int, policy_creation_date: date):
    """
    Monsoon surcharge formula:
    If month in [10, 11, 12] -> apply 22% surcharge to base premium.
    """
    month = policy_creation_date.month
    
    if month in [10, 11, 12]:
        surcharge_pct = 0.22
        reason = "Monsoon season pricing (Oct?Dec). Rain trigger probability raised from 12% baseline to 32%."
    else:
        surcharge_pct = 0.0
        reason = "Standard pricing."
        
    adjusted_premium = int(base_premium * (1 + surcharge_pct))
    
    return {
        "base_premium": base_premium,
        "surcharge_pct": surcharge_pct,
        "adjusted_premium": adjusted_premium,
        "surcharge_reason": reason
    }
