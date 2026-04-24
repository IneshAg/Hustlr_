// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Hustlr';

  @override
  String get tagline => 'Income Protection';

  @override
  String get login_title => 'Welcome to Hustlr';

  @override
  String get login_subtitle => 'Income protection for Zepto delivery partners';

  @override
  String get login_phone_label => 'Mobile Number';

  @override
  String get login_phone_hint => 'Enter your 10-digit number';

  @override
  String get login_send_otp => 'Send OTP';

  @override
  String get login_change_language => 'Change Language';

  @override
  String get otp_title => 'Verify your number';

  @override
  String get otp_subtitle => 'Enter the 6-digit code sent to';

  @override
  String get otp_verify => 'Verify & Continue';

  @override
  String get otp_resend => 'Resend OTP';

  @override
  String get otp_demo_hint => 'Demo: enter any 6 digits';

  @override
  String get onboarding_step1 => 'What is your name?';

  @override
  String get onboarding_step2 => 'Which city do you work in?';

  @override
  String get onboarding_step3 => 'Which zone do you work in?';

  @override
  String get onboarding_step4 => 'Which platform do you deliver for?';

  @override
  String get onboarding_name_hint => 'Enter your full name';

  @override
  String get onboarding_zone_hint => 'Search your Zepto dark store zone...';

  @override
  String get onboarding_continue => 'Continue';

  @override
  String get onboarding_submit => 'Start Protection';

  @override
  String get onboarding_kyc_helper =>
      'Your platform worker ID (or linked ID) is used for KYC and to match your gig account. You already agreed to identity and ML checks on the consent screen.';

  @override
  String get onboarding_complete_title => 'You\'re all set';

  @override
  String get onboarding_complete_subtitle =>
      'Your personalized protection plan is ready.';

  @override
  String get onboarding_complete_zone => 'Zone';

  @override
  String get onboarding_complete_platform => 'Platform';

  @override
  String get onboarding_complete_cta => 'Go to Dashboard';

  @override
  String get nav_home => 'Home';

  @override
  String get nav_policy => 'Policy';

  @override
  String get nav_claims => 'Claims';

  @override
  String get nav_wallet => 'Wallet';

  @override
  String get nav_profile => 'Profile';

  @override
  String get dashboard_greeting_morning => 'Good morning';

  @override
  String get dashboard_greeting_afternoon => 'Good afternoon';

  @override
  String get dashboard_greeting_evening => 'Good evening';

  @override
  String get dashboard_protection_active =>
      'Your gig-economy protection is active.';

  @override
  String get dashboard_rain_alert => 'Rain Alert';

  @override
  String get dashboard_high_risk => 'High Risk Zone';

  @override
  String get dashboard_payout_active => 'Payout protection active.';

  @override
  String get dashboard_live => 'LIVE';

  @override
  String get dashboard_active_policy => 'Active Policy';

  @override
  String get dashboard_shielded => 'SHIELDED';

  @override
  String get dashboard_expand_coverage => 'Coverage';

  @override
  String get dashboard_expand => 'Expand';

  @override
  String get dashboard_docs => 'Docs';

  @override
  String get dashboard_certificate => 'Certificate';

  @override
  String get dashboard_opportunity_lost => 'Opportunity Lost';

  @override
  String get dashboard_missed => 'missed';

  @override
  String get dashboard_unshielded_loss => 'Unshielded activity loss';

  @override
  String get dashboard_activate_shield => 'Activate Full Shield →';

  @override
  String get dashboard_current_active => 'CURRENT ACTIVE POLICY';

  @override
  String get dashboard_high_risk_prefix => 'High risk in';

  @override
  String get dashboard_secure_coverage => 'Secure coverage now.';

  @override
  String get dashboard_activate => 'ACTIVATE';

  @override
  String get dashboard_modular => 'MODULAR';

  @override
  String get dashboard_add_coverage => 'Add New\nCoverage';

  @override
  String get dashboard_legal => 'LEGAL';

  @override
  String get dashboard_view_cert => 'View\nCertificate';

  @override
  String get dashboard_generating_cert => 'Generating your certificate...';

  @override
  String get dashboard_see_why => 'SEE WHY';

  @override
  String get dashboard_missed_payouts => 'missed\npayouts';

  @override
  String get dashboard_potential_loss => 'Potential earnings lost this month';

  @override
  String get policy_title => 'My Policy';

  @override
  String get policy_active => 'Active';

  @override
  String get policy_per_week => '/wk';

  @override
  String get policy_basic => 'Basic Shield';

  @override
  String get policy_standard => 'Standard Shield';

  @override
  String get policy_full => 'Full Shield';

  @override
  String get policy_covers => 'Covers';

  @override
  String get policy_upgrade => 'Upgrade Plan';

  @override
  String get policy_fixed_price => 'Fixed price · Same for all workers';

  @override
  String get claims_title => 'Claims';

  @override
  String get claims_simulate => 'Simulate Rain Disruption';

  @override
  String get claims_total => 'Total Claimed';

  @override
  String get claims_received => 'Received';

  @override
  String get claims_pending => 'Pending';

  @override
  String get claims_approved => 'APPROVED';

  @override
  String get claims_status_pending => 'PENDING';

  @override
  String get claims_report => 'Report a Disruption';

  @override
  String get claims_report_disruption => 'Report Disruption';

  @override
  String get claims_heavy_rain => 'Heavy Rain';

  @override
  String get claims_extreme_heat => 'Extreme Heat';

  @override
  String get claims_platform_downtime => 'Platform Downtime';

  @override
  String get claims_bandh => 'Bandh / Curfew';

  @override
  String get claims_pollution => 'Severe Pollution';

  @override
  String get claims_internet => 'Internet Blackout';

  @override
  String get claims_auto_triggered => 'Auto-triggered';

  @override
  String get claims_recent_history => 'Recent History';

  @override
  String get claims_claimed => 'Claimed';

  @override
  String get claims_no_claims => 'No claims yet';

  @override
  String get claims_no_claims_subtitle =>
      'Disruptions in your zone will appear here automatically.';

  @override
  String get claim_detail_title => 'Claim Details';

  @override
  String get claim_detail_detected => 'Disruption detected in zone';

  @override
  String get claim_detail_shift => 'Shift window verified';

  @override
  String get claim_detail_fraud => 'Fraud check passed';

  @override
  String get claim_detail_logged => 'Claim logged';

  @override
  String get claim_detail_provisional => 'Provisional credit';

  @override
  String get claim_detail_settlement => 'Settlement releasing';

  @override
  String get claim_detail_payout => 'Payout Breakdown';

  @override
  String get claim_detail_gross => 'Gross Payout';

  @override
  String get claim_detail_tranche1 => 'Provisional 70%';

  @override
  String get claim_detail_tranche2 => 'Settlement 30%';

  @override
  String get claim_detail_fraud_shield => 'Hustlr Fraud Shield';

  @override
  String get claim_detail_verified =>
      'Your claim passed all 7 verification layers';

  @override
  String get claim_detail_fps => 'FPS Score';

  @override
  String get claim_detail_clean => 'GREEN — Clean';

  @override
  String get claim_detail_download => 'Download Receipt';

  @override
  String get wallet_title => 'Wallet';

  @override
  String get wallet_balance => 'Available Balance';

  @override
  String get wallet_withdraw => 'Withdraw to UPI';

  @override
  String get wallet_smart_savings => 'Smart Savings';

  @override
  String get wallet_you_saved => 'You saved';

  @override
  String get wallet_insurance_payout => 'Insurance Payout';

  @override
  String get wallet_policy_premium => 'Policy Premium';

  @override
  String get wallet_see_analytics => 'See Analytics';

  @override
  String get wallet_recent_activity => 'Recent Activity';

  @override
  String get wallet_recent_transactions => 'Recent Transactions';

  @override
  String get wallet_filter => 'Filter';

  @override
  String get wallet_see_all => 'See All';

  @override
  String get wallet_help_title => 'Need help with claims?';

  @override
  String get wallet_help_subtitle =>
      'Our specialized gig-economy support team is available 24/7.';

  @override
  String get wallet_chat => 'Chat with us';

  @override
  String get wallet_tranche => 'Tranche credit';

  @override
  String get wallet_premium_deducted => 'Premium deducted';

  @override
  String get profile_title => 'Profile';

  @override
  String get profile_personal_info => 'PERSONAL INFO';

  @override
  String get profile_name => 'NAME';

  @override
  String get profile_zone => 'ZONE';

  @override
  String get profile_mobile => 'MOBILE';

  @override
  String get profile_upi_id => 'UPI ID';

  @override
  String get profile_account_info => 'ACCOUNT INFO';

  @override
  String get profile_hustlr_id => 'HUSTLR ID';

  @override
  String get profile_active_plan => 'ACTIVE PLAN';

  @override
  String get profile_validity => 'VALIDITY';

  @override
  String get profile_partner => 'PARTNER';

  @override
  String get profile_delivery_partner => 'Delivery Partner';

  @override
  String get profile_language => 'Language';

  @override
  String get profile_language_english => 'English';

  @override
  String get profile_language_tamil => 'தமிழ்';

  @override
  String get profile_language_hindi => 'हिन्दी';

  @override
  String get profile_documents => 'Documents';

  @override
  String get profile_policy_doc => 'Policy Certificate';

  @override
  String get profile_coverage_doc => 'Coverage Details';

  @override
  String get profile_receipts => 'Payment Receipts';

  @override
  String get profile_support => 'Support';

  @override
  String get profile_logout => 'Log Out';

  @override
  String get profile_logout_confirm => 'Are you sure you want to log out?';

  @override
  String get profile_logout_yes => 'Log Out';

  @override
  String get profile_logout_no => 'Cancel';

  @override
  String get support_title => 'Help & Support';

  @override
  String get support_search => 'Search for help...';

  @override
  String get support_live_chat => 'Live Chat';

  @override
  String get support_live_chat_sub => 'Avg reply: 2 min';

  @override
  String get support_call => 'Call Us';

  @override
  String get support_call_sub => 'Available 24/7';

  @override
  String get support_whatsapp => 'WhatsApp';

  @override
  String get support_whatsapp_sub => 'Instant support';

  @override
  String get support_email => 'Email';

  @override
  String get support_email_sub => 'Send a message';

  @override
  String get support_faq => 'Frequently Asked Questions';

  @override
  String get support_faq_1_q => 'How are claims triggered?';

  @override
  String get support_faq_1_a =>
      'Our app monitors official data feeds 24/7. When a disruption (heavy rain, extreme heat, air pollution, or platform downtime) is confirmed in your zone, a claim is created automatically. You don\'t need to do anything—no documents, no waiting.';

  @override
  String get support_faq_2_q => 'When will I receive my payout?';

  @override
  String get support_faq_2_a =>
      'Fast & automatic: 70% is credited to your UPI within minutes after the claim is approved. The remaining 30% follows within 48 hours. Our system cross-checks your GPS location with platform login data to ensure you were actively working.';

  @override
  String get support_faq_3_q => 'What if I miss a disruption alert?';

  @override
  String get support_faq_3_a =>
      'You can file a manual claim directly from the app. Go to Claims → Report Disruption, describe the issue, and submit live evidence from your phone\'s camera. Our AI verifies it within 24 hours.';

  @override
  String get support_faq_4_q => 'Can I upgrade or downgrade my coverage?';

  @override
  String get support_faq_4_a =>
      'Yes, anytime. Go to Policy → Upgrade Plan to switch between Standard Shield (₹49/week) and Full Shield (₹79/week). Changes take effect on the next Monday.';

  @override
  String get support_faq_5_q => 'How are weekly premiums calculated?';

  @override
  String get support_faq_5_a =>
      'Your premium is based on: (1) historical disruption probability in your zone, (2) your platform\'s uptime rate, and (3) your personal claim history. Cleaner records → lower premiums. That\'s why Hustlr rewards trust.';

  @override
  String get support_faq_6_q => 'What if no disruptions happen in my zone?';

  @override
  String get support_faq_6_a =>
      'Great! You\'re protected either way. If your zone stays clear for 4 consecutive weeks, you unlock a 10% cashback on your premiums (Full Shield only). The app tracks this automatically.';

  @override
  String get support_faq_7_q => 'How do I withdraw my payout balance?';

  @override
  String get support_faq_7_a =>
      'Open Wallet → tap Withdraw. Enter your UPI ID (same as your registered Razorpay). Transfers are instant and free—no hidden charges. Money lands in your bank within 2 hours.';

  @override
  String get support_raise_ticket => 'Raise a Ticket';

  @override
  String get support_ticket_placeholder => 'Describe your issue...';

  @override
  String get support_submit => 'Submit Ticket';

  @override
  String get tip_peak_hours_title => 'Earn more during peak hours';

  @override
  String get tip_peak_hours_body =>
      'Morning 8–11 AM and evening 5–9 PM have the highest order density in your zone. Consistent peak-hour deliveries build a stronger income history.';

  @override
  String get tip_monsoon_title => 'Stay covered through monsoon season';

  @override
  String get tip_monsoon_body =>
      'Chennai\'s northeast monsoon runs October to December. Workers with active coverage receive payouts automatically when rain thresholds are crossed.';

  @override
  String get tip_zone_title => 'Stay close to your dark store';

  @override
  String get tip_zone_body =>
      'Orders are assigned based on proximity to the Zepto dark store. Staying within your delivery radius means faster assignment and more deliveries per shift.';

  @override
  String get tip_activate_title => 'Activate coverage before the week starts';

  @override
  String get tip_activate_body =>
      'Coverage activates on Monday and covers disruptions through Sunday. Activate Monday morning for full weekly protection.';

  @override
  String get tip_cashback_title => 'Earn cashback with Full Shield';

  @override
  String get tip_cashback_body =>
      'Complete 4 consecutive claim-free weeks on Full Shield and receive 10% of your premiums back as wallet credit.';

  @override
  String get error_network => 'Connection error. Please check your internet.';

  @override
  String get error_generic => 'Something went wrong. Please try again.';

  @override
  String get error_insufficient_balance =>
      'Insufficient balance for withdrawal.';

  @override
  String get loading => 'Loading...';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get back => 'Back';

  @override
  String get manual_claim_title => 'Report a Disruption';

  @override
  String get manual_claim_subtitle => 'Select the issue affecting your zone';

  @override
  String get manual_claim_road_blocked => 'Road Blocked / Accident';

  @override
  String get manual_claim_road_desc =>
      'Unable to pass through main active route';

  @override
  String get manual_claim_dark_store => 'Dark Store / Hub Closed';

  @override
  String get manual_claim_dark_desc => 'Zepto pickup location is inaccessible';

  @override
  String get manual_claim_internet_outage => 'Internet Outage';

  @override
  String get manual_claim_internet_desc =>
      'No signal / Complete provider blackout';

  @override
  String get manual_claim_other => 'Other Delivery Blockage';

  @override
  String get manual_claim_other_desc => 'Specify unexpected physical issue';

  @override
  String get manual_claim_continue => 'Continue';

  @override
  String get manual_claim_need_help => 'Need help?';

  @override
  String get camera_title => 'Capture Evidence\nFor AI Assessment';

  @override
  String get camera_subtitle =>
      'Use live camera only — gallery uploads not accepted';

  @override
  String get camera_scanning => 'AI scanning...';

  @override
  String get camera_internet_auto =>
      'Signal strength: 1 bar detected automatically';

  @override
  String get camera_no_photo => 'No photo needed';

  @override
  String get kyc_consent_title => 'Data consent & KYC';

  @override
  String get kyc_consent_intro =>
      'Before you create your profile, confirm how we use your data. This supports fair payouts and fraud prevention under Indian insurance and data protection norms.';

  @override
  String get kyc_consent_location_title => 'Location (GPS)';

  @override
  String get kyc_consent_location_body =>
      'We use your device location to verify you are in a covered trigger zone when you are on shift and to reduce false claims. You can manage location in system settings.';

  @override
  String get kyc_consent_identity_title => 'Selfie photos & identity checks';

  @override
  String get kyc_consent_identity_body =>
      'We capture photos only with your front (selfie) camera for face verification and liveness checks. Images may be processed by automated fraud and ML systems to protect the insurance pool.';

  @override
  String get kyc_consent_payout_title => 'Payouts & bank / UPI';

  @override
  String get kyc_consent_payout_body =>
      'We collect payment details (UPI or bank) to send payouts. Accurate KYC-linked information is required for disbursement.';

  @override
  String get kyc_consent_view_compliance => 'Full regulatory summary';

  @override
  String get kyc_consent_continue => 'I agree — continue';

  @override
  String get claim_camera_selfie_title => 'Selfie camera only';

  @override
  String get claim_camera_selfie_body =>
      'Evidence photos must be taken with your front camera so we can verify you fairly and reduce fraud. This step does not use the rear camera.';

  @override
  String get claim_camera_selfie_cta => 'Open selfie camera';

  @override
  String get claim_camera_selfie_hint =>
      'If prompted, allow camera access. Good lighting helps verification.';

  @override
  String get step_up_face_selfie_notice =>
      'Front (selfie) camera only. Your photo is sent securely for liveness and gesture checks.';

  @override
  String get step_up_face_ml_notice =>
      'Automated checks (including ML) help prevent fraud and protect payouts.';

  @override
  String get step_up_face_capturing => 'Opening selfie camera…';

  @override
  String get step_up_face_hold => 'Hold still; face the camera.';

  @override
  String get review_title => 'Evidence Captured';

  @override
  String get review_subtitle => 'Review your photos before submitting';

  @override
  String get review_network_failure => 'Network Failure Verified';

  @override
  String get review_network_desc =>
      'Your device signal strength was strictly verified by OS sensors. No physical photos required.';

  @override
  String get review_recapture => 'Re-capture';

  @override
  String get review_submit => 'Submit Evidence →';

  @override
  String get review_add_more => 'Add More Photos';

  @override
  String get review_label => 'Evidence';

  @override
  String get submitted_title => 'Submitted';

  @override
  String get submitted_subtitle => 'Your evidence is under review';

  @override
  String get submitted_next => 'What happens next?';

  @override
  String get submitted_next_1 => 'Review within 4 hours';

  @override
  String get submitted_next_2 => 'You will be notified when resolved';

  @override
  String get submitted_next_3 => 'Provisional credit may be issued immediately';

  @override
  String get submitted_demo => 'Demo mode — Offline fallback shown';

  @override
  String get submitted_back => 'Back to Claims';

  @override
  String get chat_live_support => 'Live Support';

  @override
  String get chat_agent => 'Support Agent';

  @override
  String get chat_typing => 'Typing...';

  @override
  String get chat_hint => 'Type a message...';

  @override
  String get chat_bot_greeting =>
      'Hi, I am a Hustlr claims agent. How can I help you regarding your manual claim?';

  @override
  String get chat_attach_id => 'ID Card';

  @override
  String get chat_attach_weather => 'Weather Proof';

  @override
  String get chat_attach_receipt => 'Medical Receipt';

  @override
  String get offline_banner_text => 'You are offline. Claims will be saved.';

  @override
  String get review_save_offline => 'Save Offline';
}
