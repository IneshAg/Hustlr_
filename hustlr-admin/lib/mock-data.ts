/// Mock data service for admin dashboard demonstration
/// Generates realistic insurance data for development/testing

// Data Models
export interface AdminAnalytics {
  summary: AnalyticsSummary;
  claimsTimeline: ClaimsTimelineData[];
  premiumsTimeline: PremiumsTimelineData[];
  lossRatioTimeline: LossRatioTimelineData[];
  eventsTimeline: EventsTimelineData[];
  triggerBreakdown: TriggerBreakdownData[];
  severityBuckets: SeverityBuckets;
  prediction?: Prediction;
}

export interface AnalyticsSummary {
  totalClaims: number;
  totalPayout: number;
  totalPremium: number;
  lossRatio: number;
  flaggedClaims: number;
  totalEvents: number;
}

export interface ClaimsTimelineData {
  date: string;
  claims: number;
  payout: number;
  flagged: number;
}

export interface PremiumsTimelineData {
  week: string;
  amount: number;
}

export interface LossRatioTimelineData {
  week: string;
  premium: number;
  payout: number;
  lossRatio: number;
}

export interface EventsTimelineData {
  date: string;
  count: number;
}

export interface TriggerBreakdownData {
  type: string;
  count: number;
}

export interface SeverityBuckets {
  low: number;
  medium: number;
  high: number;
}

export interface Prediction {
  riskLevel: string;
  expectedClaimsRange: string;
  details?: string;
  aqiRisk?: string;
  source?: string;
  zonesChecked?: number;
}

export interface FraudCase {
  id: string;
  userId: string;
  userName: string;
  userPhone: string;
  trustScore: number;
  trustTier: string;
  policyId: string;
  planTier: string;
  weeklyPremium: number;
  fraudStatus: string;
  fraudScore: number;
  triggerType: string;
  zone: string;
  city: string;
  severity: number;
  grossPayout: number;
  createdAt: Date;
  fraudSignals: FraudSignal[];
  reason: string;
}

export interface FraudSignal {
  name: string;
  value: number;
  weight: number;
  contribution: number;
}

export interface AdminUser {
  id: string;
  name: string;
  phone: string;
  zone: string;
  city: string;
  trustScore: number;
  trustTier: string;
  cleanWeeks: number;
  cashbackEarned: number;
  cashbackPending: number;
  activePolicy: boolean;
  policyTier: string;
  weeklyPremium: number;
  claimsCount: number;
  lastClaimDate?: Date;
  kycStatus: string;
  createdAt: Date;
}

export interface SystemHealth {
  apis: ApiHealth[];
  status: string;
  lastAdjudicatorRun?: AdjudicatorRun;
  errors24h: number;
}

export interface ApiHealth {
  name: string;
  ok: boolean;
  status: number;
}

export interface AdjudicatorRun {
  at: Date;
  claimsCreated: number;
  durationMs: number;
}

export interface PayoutRequest {
  id: string;
  claimId: string;
  userId: string;
  userName: string;
  userPhone: string;
  amount: number;
  status: string;
  paymentMethod: string;
  upiRef?: string;
  createdAt: Date;
  processedAt?: Date;
}

export interface AdminPolicy {
  id: string;
  userId: string;
  userName: string;
  planTier: string;
  basePremium: number;
  zoneAdjustment: number;
  issAdjustment: number;
  weeklyPremium: number;
  maxWeeklyPayout: number;
  maxDailyPayout: number;
  status: string;
  autoRenew: boolean;
  coverageStart: Date;
  paidUntil: Date;
  commitmentEnd: Date;
  poolId: string;
  createdAt: Date;
}

// Mock Data Service
class MockAdminDataService {
  private static random = Math.random;

  static getAnalytics(): AdminAnalytics {
    return {
      summary: {
        totalClaims: 847,
        totalPayout: 4567890,
        totalPremium: 8923456,
        lossRatio: 51.2,
        flaggedClaims: 34,
        totalEvents: 1234,
      },
      claimsTimeline: this.generateClaimsTimeline(30),
      premiumsTimeline: this.generatePremiumsTimeline(4),
      lossRatioTimeline: this.generateLossRatioTimeline(4),
      eventsTimeline: this.generateEventsTimeline(30),
      triggerBreakdown: this.generateTriggerBreakdown(),
      severityBuckets: {
        low: 456,
        medium: 234,
        high: 157,
      },
      prediction: {
        riskLevel: this.random() > 0.5 ? 'medium' : 'high',
        expectedClaimsRange: '45-62',
        details: 'Moderate rainfall expected in Chennai zone. AQI levels within normal range.',
        aqiRisk: 'Low air quality risk',
        source: 'Prophet Model v2.1',
        zonesChecked: 12,
      },
    };
  }

  static getFraudQueue(limit: number = 20): FraudCase[] {
    return Array.from({ length: limit }, (_, index) => this.generateFraudCase(index));
  }

  static getUsers(limit: number = 50): AdminUser[] {
    return Array.from({ length: limit }, (_, index) => this.generateUser(index));
  }

  static getSystemHealth(): SystemHealth {
    return {
      apis: [
        { name: 'Auth Service', ok: this.random() > 0.3, status: this.random() > 0.3 ? 200 : 500 },
        { name: 'Claims API', ok: true, status: 200 },
        { name: 'ML Fraud Service', ok: true, status: 200 },
        { name: 'Payment Gateway', ok: this.random() > 0.3, status: this.random() > 0.3 ? 200 : 503 },
        { name: 'Notification Service', ok: true, status: 200 },
        { name: 'Weather API', ok: this.random() > 0.3, status: this.random() > 0.3 ? 200 : 404 },
        { name: 'AQI Monitor', ok: true, status: 200 },
        { name: 'Risk Pool Service', ok: true, status: 200 },
        { name: 'Policy Engine', ok: true, status: 200 },
        { name: 'Wallet Service', ok: true, status: 200 },
        { name: 'Rider Tracking', ok: this.random() > 0.3, status: this.random() > 0.3 ? 200 : 502 },
      ],
      status: 'operational',
      lastAdjudicatorRun: {
        at: new Date(Date.now() - Math.floor(this.random() * 30 * 60 * 1000)),
        claimsCreated: Math.floor(this.random() * 50) + 10,
        durationMs: Math.floor(this.random() * 5000) + 1000,
      },
      errors24h: Math.floor(this.random() * 15),
    };
  }

  static getPayoutQueue(limit: number = 20): PayoutRequest[] {
    return Array.from({ length: limit }, (_, index) => this.generatePayoutRequest(index));
  }

  static getPolicies(limit: number = 30): AdminPolicy[] {
    return Array.from({ length: limit }, (_, index) => this.generatePolicy(index));
  }

  // Private helper methods

  private static generateClaimsTimeline(days: number): ClaimsTimelineData[] {
    return Array.from({ length: days }, (_, index) => {
      const date = new Date();
      date.setDate(date.getDate() - (days - index));
      return {
        date: this.formatDate(date),
        claims: Math.floor(this.random() * 50) + 10,
        payout: (this.random() * 50000 + 10000),
        flagged: Math.floor(this.random() * 10),
      };
    });
  }

  private static generatePremiumsTimeline(weeks: number): PremiumsTimelineData[] {
    return Array.from({ length: weeks }, (_, index) => {
      const date = new Date();
      date.setDate(date.getDate() - (weeks - index) * 7);
      return {
        week: this.formatDate(date),
        amount: (this.random() * 200000 + 50000),
      };
    });
  }

  private static generateLossRatioTimeline(weeks: number): LossRatioTimelineData[] {
    return Array.from({ length: weeks }, (_, index) => {
      const date = new Date();
      date.setDate(date.getDate() - (weeks - index) * 7);
      const premium = this.random() * 200000 + 50000;
      const payout = this.random() * 150000 + 20000;
      const lossRatio = (payout / premium) * 100;
      return {
        week: this.formatDate(date),
        premium,
        payout,
        lossRatio,
      };
    });
  }

  private static generateEventsTimeline(days: number): EventsTimelineData[] {
    return Array.from({ length: days }, (_, index) => {
      const date = new Date();
      date.setDate(date.getDate() - (days - index));
      return {
        date: this.formatDate(date),
        count: Math.floor(this.random() * 30) + 5,
      };
    });
  }

  private static generateTriggerBreakdown(): TriggerBreakdownData[] {
    return [
      { type: 'weather', count: Math.floor(this.random() * 200) + 100 },
      { type: 'traffic', count: Math.floor(this.random() * 100) + 50 },
      { type: 'social', count: Math.floor(this.random() * 50) + 20 },
    ];
  }

  private static generateFraudCase(index: number): FraudCase {
    const statuses = ['FLAGGED', 'REVIEW', 'CLEAN', 'REJECTED'];
    const reasons = [
      'GPS location mismatch',
      'Unusual claim frequency',
      'Device fingerprint mismatch',
      'Shift pattern anomaly',
      'Network inconsistency',
      'Timing irregularity',
    ];

    return {
      id: `claim_${Math.floor(this.random() * 10000)}`,
      userId: `user_${Math.floor(this.random() * 1000)}`,
      userName: this.generateName(),
      userPhone: `+91${Math.floor(this.random() * 10000000000)}`,
      trustScore: Math.floor(this.random() * 1000),
      trustTier: this.getTrustTier(Math.floor(this.random() * 1000)),
      policyId: `policy_${Math.floor(this.random() * 500)}`,
      planTier: this.getPlanTier(),
      weeklyPremium: Math.floor(this.random() * 200) + 50,
      fraudStatus: statuses[Math.floor(this.random() * statuses.length)],
      fraudScore: Math.floor(this.random() * 100),
      triggerType: this.getTriggerType(),
      zone: this.getZone(),
      city: 'Chennai',
      severity: Math.round(this.random() * 10),
      grossPayout: this.random() * 5000 + 1000,
      createdAt: new Date(Date.now() - Math.floor(this.random() * 168 * 60 * 60 * 1000)),
      fraudSignals: this.generateFraudSignals(),
      reason: reasons[Math.floor(this.random() * reasons.length)],
    };
  }

  private static generateUser(index: number): AdminUser {
    return {
      id: `user_${Math.floor(this.random() * 10000)}`,
      name: this.generateName(),
      phone: `+91${Math.floor(this.random() * 10000000000)}`,
      zone: this.getZone(),
      city: 'Chennai',
      trustScore: Math.floor(this.random() * 1000),
      trustTier: this.getTrustTier(Math.floor(this.random() * 1000)),
      cleanWeeks: Math.floor(this.random() * 52),
      cashbackEarned: Math.floor(this.random() * 5000),
      cashbackPending: Math.floor(this.random() * 500),
      activePolicy: this.random() > 0.5,
      policyTier: this.getPlanTier(),
      weeklyPremium: Math.floor(this.random() * 200) + 50,
      claimsCount: Math.floor(this.random() * 20),
      lastClaimDate: this.random() > 0.5 ? new Date(Date.now() - Math.floor(this.random() * 30 * 24 * 60 * 60 * 1000)) : undefined,
      kycStatus: this.getKycStatus(),
      createdAt: new Date(Date.now() - Math.floor(this.random() * 365 * 24 * 60 * 60 * 1000)),
    };
  }

  private static generatePayoutRequest(index: number): PayoutRequest {
    const statuses = ['APPROVED', 'PENDING', 'PROCESSING', 'FAILED'];
    return {
      id: `payout_${Math.floor(this.random() * 10000)}`,
      claimId: `claim_${Math.floor(this.random() * 5000)}`,
      userId: `user_${Math.floor(this.random() * 1000)}`,
      userName: this.generateName(),
      userPhone: `+91${Math.floor(this.random() * 10000000000)}`,
      amount: this.random() * 5000 + 1000,
      status: statuses[Math.floor(this.random() * statuses.length)],
      paymentMethod: this.random() > 0.5 ? 'UPI' : 'Wallet',
      upiRef: this.random() > 0.5 ? `UPI${Math.floor(this.random() * 1000000000)}` : undefined,
      createdAt: new Date(Date.now() - Math.floor(this.random() * 72 * 60 * 60 * 1000)),
      processedAt: this.random() > 0.5 ? new Date(Date.now() - Math.floor(this.random() * 24 * 60 * 60 * 1000)) : undefined,
    };
  }

  private static generatePolicy(index: number): AdminPolicy {
    const statuses = ['active', 'expired', 'cancelled', 'suspended'];
    return {
      id: `policy_${Math.floor(this.random() * 10000)}`,
      userId: `user_${Math.floor(this.random() * 1000)}`,
      userName: this.generateName(),
      planTier: this.getPlanTier(),
      basePremium: Math.floor(this.random() * 100) + 30,
      zoneAdjustment: Math.floor(this.random() * 50),
      issAdjustment: Math.floor(this.random() * 30),
      weeklyPremium: Math.floor(this.random() * 200) + 50,
      maxWeeklyPayout: Math.floor(this.random() * 1000) + 500,
      maxDailyPayout: Math.floor(this.random() * 300) + 100,
      status: statuses[Math.floor(this.random() * statuses.length)],
      autoRenew: this.random() > 0.5,
      coverageStart: new Date(Date.now() - Math.floor(this.random() * 90 * 24 * 60 * 60 * 1000)),
      paidUntil: new Date(Date.now() + Math.floor(this.random() * 30 * 24 * 60 * 60 * 1000)),
      commitmentEnd: new Date(Date.now() + Math.floor(this.random() * 90 * 24 * 60 * 60 * 1000)),
      poolId: `pool_${Math.floor(this.random() * 50)}`,
      createdAt: new Date(Date.now() - Math.floor(this.random() * 180 * 24 * 60 * 60 * 1000)),
    };
  }

  private static generateFraudSignals(): FraudSignal[] {
    const signals = [
      { name: 'GPS Jitter', value: this.random(), weight: 0.8, contribution: Math.floor(this.random() * 30) },
      { name: 'Zone Match', value: this.random(), weight: 0.6, contribution: Math.floor(this.random() * 20) },
      { name: 'Accelerometer', value: this.random(), weight: 0.7, contribution: Math.floor(this.random() * 25) },
      { name: 'WiFi SSID', value: this.random(), weight: 0.4, contribution: Math.floor(this.random() * 15) },
      { name: 'Claim Timing', value: this.random(), weight: 0.5, contribution: Math.floor(this.random() * 20) },
    ];
    return signals.sort(() => this.random() - 0.5);
  }

  private static generateName(): string {
    const firstNames = ['Raj', 'Priya', 'Amit', 'Sneha', 'Vikram', 'Anita', 'Rahul', 'Pooja', 'Arjun', 'Kavita'];
    const lastNames = ['Kumar', 'Sharma', 'Patel', 'Singh', 'Gupta', 'Verma', 'Reddy', 'Nair', 'Iyer', 'Menon'];
    return `${firstNames[Math.floor(this.random() * firstNames.length)]} ${lastNames[Math.floor(this.random() * lastNames.length)]}`;
  }

  private static formatDate(date: Date): string {
    return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`;
  }

  private static getTrustTier(score: number): string {
    if (score >= 900) return 'PLATINUM';
    if (score >= 750) return 'GOLD';
    if (score >= 600) return 'SILVER';
    if (score >= 500) return 'BRONZE';
    return 'AT_RISK';
  }

  private static getPlanTier(): string {
    const tiers = ['basic', 'standard', 'full'];
    return tiers[Math.floor(this.random() * tiers.length)];
  }

  private static getTriggerType(): string {
    const types = ['rain', 'traffic', 'social', 'curfew', 'cyclone'];
    return types[Math.floor(this.random() * types.length)];
  }

  private static getZone(): string {
    const zones = ['Zone A', 'Zone B', 'Zone C', 'Zone D', 'Zone E', 'Zone F'];
    return zones[Math.floor(this.random() * zones.length)];
  }

  private static getKycStatus(): string {
    const statuses = ['verified', 'pending', 'rejected'];
    return statuses[Math.floor(this.random() * statuses.length)];
  }
}

export default MockAdminDataService;
