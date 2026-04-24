import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('ta')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Hustlr'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Income Protection'**
  String get tagline;

  /// No description provided for @login_title.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Hustlr'**
  String get login_title;

  /// No description provided for @login_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Income protection for Zepto delivery partners'**
  String get login_subtitle;

  /// No description provided for @login_phone_label.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get login_phone_label;

  /// No description provided for @login_phone_hint.
  ///
  /// In en, this message translates to:
  /// **'Enter your 10-digit number'**
  String get login_phone_hint;

  /// No description provided for @login_send_otp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get login_send_otp;

  /// No description provided for @login_change_language.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get login_change_language;

  /// No description provided for @otp_title.
  ///
  /// In en, this message translates to:
  /// **'Verify your number'**
  String get otp_title;

  /// No description provided for @otp_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to'**
  String get otp_subtitle;

  /// No description provided for @otp_verify.
  ///
  /// In en, this message translates to:
  /// **'Verify & Continue'**
  String get otp_verify;

  /// No description provided for @otp_resend.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get otp_resend;

  /// No description provided for @otp_demo_hint.
  ///
  /// In en, this message translates to:
  /// **'Demo: enter any 6 digits'**
  String get otp_demo_hint;

  /// No description provided for @onboarding_step1.
  ///
  /// In en, this message translates to:
  /// **'What is your name?'**
  String get onboarding_step1;

  /// No description provided for @onboarding_step2.
  ///
  /// In en, this message translates to:
  /// **'Which city do you work in?'**
  String get onboarding_step2;

  /// No description provided for @onboarding_step3.
  ///
  /// In en, this message translates to:
  /// **'Which zone do you work in?'**
  String get onboarding_step3;

  /// No description provided for @onboarding_step4.
  ///
  /// In en, this message translates to:
  /// **'Which platform do you deliver for?'**
  String get onboarding_step4;

  /// No description provided for @onboarding_name_hint.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get onboarding_name_hint;

  /// No description provided for @onboarding_zone_hint.
  ///
  /// In en, this message translates to:
  /// **'Search your Zepto dark store zone...'**
  String get onboarding_zone_hint;

  /// No description provided for @onboarding_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboarding_continue;

  /// No description provided for @onboarding_submit.
  ///
  /// In en, this message translates to:
  /// **'Start Protection'**
  String get onboarding_submit;

  /// No description provided for @onboarding_kyc_helper.
  ///
  /// In en, this message translates to:
  /// **'Your platform worker ID (or linked ID) is used for KYC and to match your gig account. You already agreed to identity and ML checks on the consent screen.'**
  String get onboarding_kyc_helper;

  /// No description provided for @onboarding_complete_title.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get onboarding_complete_title;

  /// No description provided for @onboarding_complete_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your personalized protection plan is ready.'**
  String get onboarding_complete_subtitle;

  /// No description provided for @onboarding_complete_zone.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get onboarding_complete_zone;

  /// No description provided for @onboarding_complete_platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get onboarding_complete_platform;

  /// No description provided for @onboarding_complete_cta.
  ///
  /// In en, this message translates to:
  /// **'Go to Dashboard'**
  String get onboarding_complete_cta;

  /// No description provided for @nav_home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get nav_home;

  /// No description provided for @nav_policy.
  ///
  /// In en, this message translates to:
  /// **'Policy'**
  String get nav_policy;

  /// No description provided for @nav_claims.
  ///
  /// In en, this message translates to:
  /// **'Claims'**
  String get nav_claims;

  /// No description provided for @nav_wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get nav_wallet;

  /// No description provided for @nav_profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get nav_profile;

  /// No description provided for @dashboard_greeting_morning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get dashboard_greeting_morning;

  /// No description provided for @dashboard_greeting_afternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get dashboard_greeting_afternoon;

  /// No description provided for @dashboard_greeting_evening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get dashboard_greeting_evening;

  /// No description provided for @dashboard_protection_active.
  ///
  /// In en, this message translates to:
  /// **'Your gig-economy protection is active.'**
  String get dashboard_protection_active;

  /// No description provided for @dashboard_rain_alert.
  ///
  /// In en, this message translates to:
  /// **'Rain Alert'**
  String get dashboard_rain_alert;

  /// No description provided for @dashboard_high_risk.
  ///
  /// In en, this message translates to:
  /// **'High Risk Zone'**
  String get dashboard_high_risk;

  /// No description provided for @dashboard_payout_active.
  ///
  /// In en, this message translates to:
  /// **'Payout protection active.'**
  String get dashboard_payout_active;

  /// No description provided for @dashboard_live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get dashboard_live;

  /// No description provided for @dashboard_active_policy.
  ///
  /// In en, this message translates to:
  /// **'Active Policy'**
  String get dashboard_active_policy;

  /// No description provided for @dashboard_shielded.
  ///
  /// In en, this message translates to:
  /// **'SHIELDED'**
  String get dashboard_shielded;

  /// No description provided for @dashboard_expand_coverage.
  ///
  /// In en, this message translates to:
  /// **'Coverage'**
  String get dashboard_expand_coverage;

  /// No description provided for @dashboard_expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get dashboard_expand;

  /// No description provided for @dashboard_docs.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get dashboard_docs;

  /// No description provided for @dashboard_certificate.
  ///
  /// In en, this message translates to:
  /// **'Certificate'**
  String get dashboard_certificate;

  /// No description provided for @dashboard_opportunity_lost.
  ///
  /// In en, this message translates to:
  /// **'Opportunity Lost'**
  String get dashboard_opportunity_lost;

  /// No description provided for @dashboard_missed.
  ///
  /// In en, this message translates to:
  /// **'missed'**
  String get dashboard_missed;

  /// No description provided for @dashboard_unshielded_loss.
  ///
  /// In en, this message translates to:
  /// **'Unshielded activity loss'**
  String get dashboard_unshielded_loss;

  /// No description provided for @dashboard_activate_shield.
  ///
  /// In en, this message translates to:
  /// **'Activate Full Shield →'**
  String get dashboard_activate_shield;

  /// No description provided for @dashboard_current_active.
  ///
  /// In en, this message translates to:
  /// **'CURRENT ACTIVE POLICY'**
  String get dashboard_current_active;

  /// No description provided for @dashboard_high_risk_prefix.
  ///
  /// In en, this message translates to:
  /// **'High risk in'**
  String get dashboard_high_risk_prefix;

  /// No description provided for @dashboard_secure_coverage.
  ///
  /// In en, this message translates to:
  /// **'Secure coverage now.'**
  String get dashboard_secure_coverage;

  /// No description provided for @dashboard_activate.
  ///
  /// In en, this message translates to:
  /// **'ACTIVATE'**
  String get dashboard_activate;

  /// No description provided for @dashboard_modular.
  ///
  /// In en, this message translates to:
  /// **'MODULAR'**
  String get dashboard_modular;

  /// No description provided for @dashboard_add_coverage.
  ///
  /// In en, this message translates to:
  /// **'Add New\nCoverage'**
  String get dashboard_add_coverage;

  /// No description provided for @dashboard_legal.
  ///
  /// In en, this message translates to:
  /// **'LEGAL'**
  String get dashboard_legal;

  /// No description provided for @dashboard_view_cert.
  ///
  /// In en, this message translates to:
  /// **'View\nCertificate'**
  String get dashboard_view_cert;

  /// No description provided for @dashboard_generating_cert.
  ///
  /// In en, this message translates to:
  /// **'Generating your certificate...'**
  String get dashboard_generating_cert;

  /// No description provided for @dashboard_see_why.
  ///
  /// In en, this message translates to:
  /// **'SEE WHY'**
  String get dashboard_see_why;

  /// No description provided for @dashboard_missed_payouts.
  ///
  /// In en, this message translates to:
  /// **'missed\npayouts'**
  String get dashboard_missed_payouts;

  /// No description provided for @dashboard_potential_loss.
  ///
  /// In en, this message translates to:
  /// **'Potential earnings lost this month'**
  String get dashboard_potential_loss;

  /// No description provided for @policy_title.
  ///
  /// In en, this message translates to:
  /// **'My Policy'**
  String get policy_title;

  /// No description provided for @policy_active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get policy_active;

  /// No description provided for @policy_per_week.
  ///
  /// In en, this message translates to:
  /// **'/wk'**
  String get policy_per_week;

  /// No description provided for @policy_basic.
  ///
  /// In en, this message translates to:
  /// **'Basic Shield'**
  String get policy_basic;

  /// No description provided for @policy_standard.
  ///
  /// In en, this message translates to:
  /// **'Standard Shield'**
  String get policy_standard;

  /// No description provided for @policy_full.
  ///
  /// In en, this message translates to:
  /// **'Full Shield'**
  String get policy_full;

  /// No description provided for @policy_covers.
  ///
  /// In en, this message translates to:
  /// **'Covers'**
  String get policy_covers;

  /// No description provided for @policy_upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade Plan'**
  String get policy_upgrade;

  /// No description provided for @policy_fixed_price.
  ///
  /// In en, this message translates to:
  /// **'Fixed price · Same for all workers'**
  String get policy_fixed_price;

  /// No description provided for @claims_title.
  ///
  /// In en, this message translates to:
  /// **'Claims'**
  String get claims_title;

  /// No description provided for @claims_simulate.
  ///
  /// In en, this message translates to:
  /// **'Simulate Rain Disruption'**
  String get claims_simulate;

  /// No description provided for @claims_total.
  ///
  /// In en, this message translates to:
  /// **'Total Claimed'**
  String get claims_total;

  /// No description provided for @claims_received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get claims_received;

  /// No description provided for @claims_pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get claims_pending;

  /// No description provided for @claims_approved.
  ///
  /// In en, this message translates to:
  /// **'APPROVED'**
  String get claims_approved;

  /// No description provided for @claims_status_pending.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get claims_status_pending;

  /// No description provided for @claims_report.
  ///
  /// In en, this message translates to:
  /// **'Report a Disruption'**
  String get claims_report;

  /// No description provided for @claims_report_disruption.
  ///
  /// In en, this message translates to:
  /// **'Report Disruption'**
  String get claims_report_disruption;

  /// No description provided for @claims_heavy_rain.
  ///
  /// In en, this message translates to:
  /// **'Heavy Rain'**
  String get claims_heavy_rain;

  /// No description provided for @claims_extreme_heat.
  ///
  /// In en, this message translates to:
  /// **'Extreme Heat'**
  String get claims_extreme_heat;

  /// No description provided for @claims_platform_downtime.
  ///
  /// In en, this message translates to:
  /// **'Platform Downtime'**
  String get claims_platform_downtime;

  /// No description provided for @claims_bandh.
  ///
  /// In en, this message translates to:
  /// **'Bandh / Curfew'**
  String get claims_bandh;

  /// No description provided for @claims_pollution.
  ///
  /// In en, this message translates to:
  /// **'Severe Pollution'**
  String get claims_pollution;

  /// No description provided for @claims_internet.
  ///
  /// In en, this message translates to:
  /// **'Internet Blackout'**
  String get claims_internet;

  /// No description provided for @claims_auto_triggered.
  ///
  /// In en, this message translates to:
  /// **'Auto-triggered'**
  String get claims_auto_triggered;

  /// No description provided for @claims_recent_history.
  ///
  /// In en, this message translates to:
  /// **'Recent History'**
  String get claims_recent_history;

  /// No description provided for @claims_claimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get claims_claimed;

  /// No description provided for @claims_no_claims.
  ///
  /// In en, this message translates to:
  /// **'No claims yet'**
  String get claims_no_claims;

  /// No description provided for @claims_no_claims_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Disruptions in your zone will appear here automatically.'**
  String get claims_no_claims_subtitle;

  /// No description provided for @claim_detail_title.
  ///
  /// In en, this message translates to:
  /// **'Claim Details'**
  String get claim_detail_title;

  /// No description provided for @claim_detail_detected.
  ///
  /// In en, this message translates to:
  /// **'Disruption detected in zone'**
  String get claim_detail_detected;

  /// No description provided for @claim_detail_shift.
  ///
  /// In en, this message translates to:
  /// **'Shift window verified'**
  String get claim_detail_shift;

  /// No description provided for @claim_detail_fraud.
  ///
  /// In en, this message translates to:
  /// **'Fraud check passed'**
  String get claim_detail_fraud;

  /// No description provided for @claim_detail_logged.
  ///
  /// In en, this message translates to:
  /// **'Claim logged'**
  String get claim_detail_logged;

  /// No description provided for @claim_detail_provisional.
  ///
  /// In en, this message translates to:
  /// **'Provisional credit'**
  String get claim_detail_provisional;

  /// No description provided for @claim_detail_settlement.
  ///
  /// In en, this message translates to:
  /// **'Settlement releasing'**
  String get claim_detail_settlement;

  /// No description provided for @claim_detail_payout.
  ///
  /// In en, this message translates to:
  /// **'Payout Breakdown'**
  String get claim_detail_payout;

  /// No description provided for @claim_detail_gross.
  ///
  /// In en, this message translates to:
  /// **'Gross Payout'**
  String get claim_detail_gross;

  /// No description provided for @claim_detail_tranche1.
  ///
  /// In en, this message translates to:
  /// **'Provisional 70%'**
  String get claim_detail_tranche1;

  /// No description provided for @claim_detail_tranche2.
  ///
  /// In en, this message translates to:
  /// **'Settlement 30%'**
  String get claim_detail_tranche2;

  /// No description provided for @claim_detail_fraud_shield.
  ///
  /// In en, this message translates to:
  /// **'Hustlr Fraud Shield'**
  String get claim_detail_fraud_shield;

  /// No description provided for @claim_detail_verified.
  ///
  /// In en, this message translates to:
  /// **'Your claim passed all 7 verification layers'**
  String get claim_detail_verified;

  /// No description provided for @claim_detail_fps.
  ///
  /// In en, this message translates to:
  /// **'FPS Score'**
  String get claim_detail_fps;

  /// No description provided for @claim_detail_clean.
  ///
  /// In en, this message translates to:
  /// **'GREEN — Clean'**
  String get claim_detail_clean;

  /// No description provided for @claim_detail_download.
  ///
  /// In en, this message translates to:
  /// **'Download Receipt'**
  String get claim_detail_download;

  /// No description provided for @wallet_title.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet_title;

  /// No description provided for @wallet_balance.
  ///
  /// In en, this message translates to:
  /// **'Available Balance'**
  String get wallet_balance;

  /// No description provided for @wallet_withdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw to UPI'**
  String get wallet_withdraw;

  /// No description provided for @wallet_smart_savings.
  ///
  /// In en, this message translates to:
  /// **'Smart Savings'**
  String get wallet_smart_savings;

  /// No description provided for @wallet_you_saved.
  ///
  /// In en, this message translates to:
  /// **'You saved'**
  String get wallet_you_saved;

  /// No description provided for @wallet_insurance_payout.
  ///
  /// In en, this message translates to:
  /// **'Insurance Payout'**
  String get wallet_insurance_payout;

  /// No description provided for @wallet_policy_premium.
  ///
  /// In en, this message translates to:
  /// **'Policy Premium'**
  String get wallet_policy_premium;

  /// No description provided for @wallet_see_analytics.
  ///
  /// In en, this message translates to:
  /// **'See Analytics'**
  String get wallet_see_analytics;

  /// No description provided for @wallet_recent_activity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get wallet_recent_activity;

  /// No description provided for @wallet_recent_transactions.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get wallet_recent_transactions;

  /// No description provided for @wallet_filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get wallet_filter;

  /// No description provided for @wallet_see_all.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get wallet_see_all;

  /// No description provided for @wallet_help_title.
  ///
  /// In en, this message translates to:
  /// **'Need help with claims?'**
  String get wallet_help_title;

  /// No description provided for @wallet_help_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Our specialized gig-economy support team is available 24/7.'**
  String get wallet_help_subtitle;

  /// No description provided for @wallet_chat.
  ///
  /// In en, this message translates to:
  /// **'Chat with us'**
  String get wallet_chat;

  /// No description provided for @wallet_tranche.
  ///
  /// In en, this message translates to:
  /// **'Tranche credit'**
  String get wallet_tranche;

  /// No description provided for @wallet_premium_deducted.
  ///
  /// In en, this message translates to:
  /// **'Premium deducted'**
  String get wallet_premium_deducted;

  /// No description provided for @profile_title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile_title;

  /// No description provided for @profile_personal_info.
  ///
  /// In en, this message translates to:
  /// **'PERSONAL INFO'**
  String get profile_personal_info;

  /// No description provided for @profile_name.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get profile_name;

  /// No description provided for @profile_zone.
  ///
  /// In en, this message translates to:
  /// **'ZONE'**
  String get profile_zone;

  /// No description provided for @profile_mobile.
  ///
  /// In en, this message translates to:
  /// **'MOBILE'**
  String get profile_mobile;

  /// No description provided for @profile_upi_id.
  ///
  /// In en, this message translates to:
  /// **'UPI ID'**
  String get profile_upi_id;

  /// No description provided for @profile_account_info.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT INFO'**
  String get profile_account_info;

  /// No description provided for @profile_hustlr_id.
  ///
  /// In en, this message translates to:
  /// **'HUSTLR ID'**
  String get profile_hustlr_id;

  /// No description provided for @profile_active_plan.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE PLAN'**
  String get profile_active_plan;

  /// No description provided for @profile_validity.
  ///
  /// In en, this message translates to:
  /// **'VALIDITY'**
  String get profile_validity;

  /// No description provided for @profile_partner.
  ///
  /// In en, this message translates to:
  /// **'PARTNER'**
  String get profile_partner;

  /// No description provided for @profile_delivery_partner.
  ///
  /// In en, this message translates to:
  /// **'Delivery Partner'**
  String get profile_delivery_partner;

  /// No description provided for @profile_language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profile_language;

  /// No description provided for @profile_language_english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get profile_language_english;

  /// No description provided for @profile_language_tamil.
  ///
  /// In en, this message translates to:
  /// **'தமிழ்'**
  String get profile_language_tamil;

  /// No description provided for @profile_language_hindi.
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get profile_language_hindi;

  /// No description provided for @profile_documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get profile_documents;

  /// No description provided for @profile_policy_doc.
  ///
  /// In en, this message translates to:
  /// **'Policy Certificate'**
  String get profile_policy_doc;

  /// No description provided for @profile_coverage_doc.
  ///
  /// In en, this message translates to:
  /// **'Coverage Details'**
  String get profile_coverage_doc;

  /// No description provided for @profile_receipts.
  ///
  /// In en, this message translates to:
  /// **'Payment Receipts'**
  String get profile_receipts;

  /// No description provided for @profile_support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get profile_support;

  /// No description provided for @profile_logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get profile_logout;

  /// No description provided for @profile_logout_confirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get profile_logout_confirm;

  /// No description provided for @profile_logout_yes.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get profile_logout_yes;

  /// No description provided for @profile_logout_no.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profile_logout_no;

  /// No description provided for @support_title.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get support_title;

  /// No description provided for @support_search.
  ///
  /// In en, this message translates to:
  /// **'Search for help...'**
  String get support_search;

  /// No description provided for @support_live_chat.
  ///
  /// In en, this message translates to:
  /// **'Live Chat'**
  String get support_live_chat;

  /// No description provided for @support_live_chat_sub.
  ///
  /// In en, this message translates to:
  /// **'Avg reply: 2 min'**
  String get support_live_chat_sub;

  /// No description provided for @support_call.
  ///
  /// In en, this message translates to:
  /// **'Call Us'**
  String get support_call;

  /// No description provided for @support_call_sub.
  ///
  /// In en, this message translates to:
  /// **'Available 24/7'**
  String get support_call_sub;

  /// No description provided for @support_whatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get support_whatsapp;

  /// No description provided for @support_whatsapp_sub.
  ///
  /// In en, this message translates to:
  /// **'Instant support'**
  String get support_whatsapp_sub;

  /// No description provided for @support_email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get support_email;

  /// No description provided for @support_email_sub.
  ///
  /// In en, this message translates to:
  /// **'Send a message'**
  String get support_email_sub;

  /// No description provided for @support_faq.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get support_faq;

  /// No description provided for @support_faq_1_q.
  ///
  /// In en, this message translates to:
  /// **'How are claims triggered?'**
  String get support_faq_1_q;

  /// No description provided for @support_faq_1_a.
  ///
  /// In en, this message translates to:
  /// **'Our app monitors official data feeds 24/7. When a disruption (heavy rain, extreme heat, air pollution, or platform downtime) is confirmed in your zone, a claim is created automatically. You don\'t need to do anything—no documents, no waiting.'**
  String get support_faq_1_a;

  /// No description provided for @support_faq_2_q.
  ///
  /// In en, this message translates to:
  /// **'When will I receive my payout?'**
  String get support_faq_2_q;

  /// No description provided for @support_faq_2_a.
  ///
  /// In en, this message translates to:
  /// **'Fast & automatic: 70% is credited to your UPI within minutes after the claim is approved. The remaining 30% follows within 48 hours. Our system cross-checks your GPS location with platform login data to ensure you were actively working.'**
  String get support_faq_2_a;

  /// No description provided for @support_faq_3_q.
  ///
  /// In en, this message translates to:
  /// **'What if I miss a disruption alert?'**
  String get support_faq_3_q;

  /// No description provided for @support_faq_3_a.
  ///
  /// In en, this message translates to:
  /// **'You can file a manual claim directly from the app. Go to Claims → Report Disruption, describe the issue, and submit live evidence from your phone\'s camera. Our AI verifies it within 24 hours.'**
  String get support_faq_3_a;

  /// No description provided for @support_faq_4_q.
  ///
  /// In en, this message translates to:
  /// **'Can I upgrade or downgrade my coverage?'**
  String get support_faq_4_q;

  /// No description provided for @support_faq_4_a.
  ///
  /// In en, this message translates to:
  /// **'Yes, anytime. Go to Policy → Upgrade Plan to switch between Standard Shield (₹49/week) and Full Shield (₹79/week). Changes take effect on the next Monday.'**
  String get support_faq_4_a;

  /// No description provided for @support_faq_5_q.
  ///
  /// In en, this message translates to:
  /// **'How are weekly premiums calculated?'**
  String get support_faq_5_q;

  /// No description provided for @support_faq_5_a.
  ///
  /// In en, this message translates to:
  /// **'Your premium is based on: (1) historical disruption probability in your zone, (2) your platform\'s uptime rate, and (3) your personal claim history. Cleaner records → lower premiums. That\'s why Hustlr rewards trust.'**
  String get support_faq_5_a;

  /// No description provided for @support_faq_6_q.
  ///
  /// In en, this message translates to:
  /// **'What if no disruptions happen in my zone?'**
  String get support_faq_6_q;

  /// No description provided for @support_faq_6_a.
  ///
  /// In en, this message translates to:
  /// **'Great! You\'re protected either way. If your zone stays clear for 4 consecutive weeks, you unlock a 10% cashback on your premiums (Full Shield only). The app tracks this automatically.'**
  String get support_faq_6_a;

  /// No description provided for @support_faq_7_q.
  ///
  /// In en, this message translates to:
  /// **'How do I withdraw my payout balance?'**
  String get support_faq_7_q;

  /// No description provided for @support_faq_7_a.
  ///
  /// In en, this message translates to:
  /// **'Open Wallet → tap Withdraw. Enter your UPI ID (same as your registered Razorpay). Transfers are instant and free—no hidden charges. Money lands in your bank within 2 hours.'**
  String get support_faq_7_a;

  /// No description provided for @support_raise_ticket.
  ///
  /// In en, this message translates to:
  /// **'Raise a Ticket'**
  String get support_raise_ticket;

  /// No description provided for @support_ticket_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Describe your issue...'**
  String get support_ticket_placeholder;

  /// No description provided for @support_submit.
  ///
  /// In en, this message translates to:
  /// **'Submit Ticket'**
  String get support_submit;

  /// No description provided for @tip_peak_hours_title.
  ///
  /// In en, this message translates to:
  /// **'Earn more during peak hours'**
  String get tip_peak_hours_title;

  /// No description provided for @tip_peak_hours_body.
  ///
  /// In en, this message translates to:
  /// **'Morning 8–11 AM and evening 5–9 PM have the highest order density in your zone. Consistent peak-hour deliveries build a stronger income history.'**
  String get tip_peak_hours_body;

  /// No description provided for @tip_monsoon_title.
  ///
  /// In en, this message translates to:
  /// **'Stay covered through monsoon season'**
  String get tip_monsoon_title;

  /// No description provided for @tip_monsoon_body.
  ///
  /// In en, this message translates to:
  /// **'Chennai\'s northeast monsoon runs October to December. Workers with active coverage receive payouts automatically when rain thresholds are crossed.'**
  String get tip_monsoon_body;

  /// No description provided for @tip_zone_title.
  ///
  /// In en, this message translates to:
  /// **'Stay close to your dark store'**
  String get tip_zone_title;

  /// No description provided for @tip_zone_body.
  ///
  /// In en, this message translates to:
  /// **'Orders are assigned based on proximity to the Zepto dark store. Staying within your delivery radius means faster assignment and more deliveries per shift.'**
  String get tip_zone_body;

  /// No description provided for @tip_activate_title.
  ///
  /// In en, this message translates to:
  /// **'Activate coverage before the week starts'**
  String get tip_activate_title;

  /// No description provided for @tip_activate_body.
  ///
  /// In en, this message translates to:
  /// **'Coverage activates on Monday and covers disruptions through Sunday. Activate Monday morning for full weekly protection.'**
  String get tip_activate_body;

  /// No description provided for @tip_cashback_title.
  ///
  /// In en, this message translates to:
  /// **'Earn cashback with Full Shield'**
  String get tip_cashback_title;

  /// No description provided for @tip_cashback_body.
  ///
  /// In en, this message translates to:
  /// **'Complete 4 consecutive claim-free weeks on Full Shield and receive 10% of your premiums back as wallet credit.'**
  String get tip_cashback_body;

  /// No description provided for @error_network.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please check your internet.'**
  String get error_network;

  /// No description provided for @error_generic.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get error_generic;

  /// No description provided for @error_insufficient_balance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance for withdrawal.'**
  String get error_insufficient_balance;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @manual_claim_title.
  ///
  /// In en, this message translates to:
  /// **'Report a Disruption'**
  String get manual_claim_title;

  /// No description provided for @manual_claim_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the issue affecting your zone'**
  String get manual_claim_subtitle;

  /// No description provided for @manual_claim_road_blocked.
  ///
  /// In en, this message translates to:
  /// **'Road Blocked / Accident'**
  String get manual_claim_road_blocked;

  /// No description provided for @manual_claim_road_desc.
  ///
  /// In en, this message translates to:
  /// **'Unable to pass through main active route'**
  String get manual_claim_road_desc;

  /// No description provided for @manual_claim_dark_store.
  ///
  /// In en, this message translates to:
  /// **'Dark Store / Hub Closed'**
  String get manual_claim_dark_store;

  /// No description provided for @manual_claim_dark_desc.
  ///
  /// In en, this message translates to:
  /// **'Zepto pickup location is inaccessible'**
  String get manual_claim_dark_desc;

  /// No description provided for @manual_claim_internet_outage.
  ///
  /// In en, this message translates to:
  /// **'Internet Outage'**
  String get manual_claim_internet_outage;

  /// No description provided for @manual_claim_internet_desc.
  ///
  /// In en, this message translates to:
  /// **'No signal / Complete provider blackout'**
  String get manual_claim_internet_desc;

  /// No description provided for @manual_claim_other.
  ///
  /// In en, this message translates to:
  /// **'Other Delivery Blockage'**
  String get manual_claim_other;

  /// No description provided for @manual_claim_other_desc.
  ///
  /// In en, this message translates to:
  /// **'Specify unexpected physical issue'**
  String get manual_claim_other_desc;

  /// No description provided for @manual_claim_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get manual_claim_continue;

  /// No description provided for @manual_claim_need_help.
  ///
  /// In en, this message translates to:
  /// **'Need help?'**
  String get manual_claim_need_help;

  /// No description provided for @camera_title.
  ///
  /// In en, this message translates to:
  /// **'Capture Evidence\nFor AI Assessment'**
  String get camera_title;

  /// No description provided for @camera_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Use live camera only — gallery uploads not accepted'**
  String get camera_subtitle;

  /// No description provided for @camera_scanning.
  ///
  /// In en, this message translates to:
  /// **'AI scanning...'**
  String get camera_scanning;

  /// No description provided for @camera_internet_auto.
  ///
  /// In en, this message translates to:
  /// **'Signal strength: 1 bar detected automatically'**
  String get camera_internet_auto;

  /// No description provided for @camera_no_photo.
  ///
  /// In en, this message translates to:
  /// **'No photo needed'**
  String get camera_no_photo;

  /// No description provided for @kyc_consent_title.
  ///
  /// In en, this message translates to:
  /// **'Data consent & KYC'**
  String get kyc_consent_title;

  /// No description provided for @kyc_consent_intro.
  ///
  /// In en, this message translates to:
  /// **'Before you create your profile, confirm how we use your data. This supports fair payouts and fraud prevention under Indian insurance and data protection norms.'**
  String get kyc_consent_intro;

  /// No description provided for @kyc_consent_location_title.
  ///
  /// In en, this message translates to:
  /// **'Location (GPS)'**
  String get kyc_consent_location_title;

  /// No description provided for @kyc_consent_location_body.
  ///
  /// In en, this message translates to:
  /// **'We use your device location to verify you are in a covered trigger zone when you are on shift and to reduce false claims. You can manage location in system settings.'**
  String get kyc_consent_location_body;

  /// No description provided for @kyc_consent_identity_title.
  ///
  /// In en, this message translates to:
  /// **'Selfie photos & identity checks'**
  String get kyc_consent_identity_title;

  /// No description provided for @kyc_consent_identity_body.
  ///
  /// In en, this message translates to:
  /// **'We capture photos only with your front (selfie) camera for face verification and liveness checks. Images may be processed by automated fraud and ML systems to protect the insurance pool.'**
  String get kyc_consent_identity_body;

  /// No description provided for @kyc_consent_payout_title.
  ///
  /// In en, this message translates to:
  /// **'Payouts & bank / UPI'**
  String get kyc_consent_payout_title;

  /// No description provided for @kyc_consent_payout_body.
  ///
  /// In en, this message translates to:
  /// **'We collect payment details (UPI or bank) to send payouts. Accurate KYC-linked information is required for disbursement.'**
  String get kyc_consent_payout_body;

  /// No description provided for @kyc_consent_view_compliance.
  ///
  /// In en, this message translates to:
  /// **'Full regulatory summary'**
  String get kyc_consent_view_compliance;

  /// No description provided for @kyc_consent_continue.
  ///
  /// In en, this message translates to:
  /// **'I agree — continue'**
  String get kyc_consent_continue;

  /// No description provided for @claim_camera_selfie_title.
  ///
  /// In en, this message translates to:
  /// **'Selfie camera only'**
  String get claim_camera_selfie_title;

  /// No description provided for @claim_camera_selfie_body.
  ///
  /// In en, this message translates to:
  /// **'Evidence photos must be taken with your front camera so we can verify you fairly and reduce fraud. This step does not use the rear camera.'**
  String get claim_camera_selfie_body;

  /// No description provided for @claim_camera_selfie_cta.
  ///
  /// In en, this message translates to:
  /// **'Open selfie camera'**
  String get claim_camera_selfie_cta;

  /// No description provided for @claim_camera_selfie_hint.
  ///
  /// In en, this message translates to:
  /// **'If prompted, allow camera access. Good lighting helps verification.'**
  String get claim_camera_selfie_hint;

  /// No description provided for @step_up_face_selfie_notice.
  ///
  /// In en, this message translates to:
  /// **'Front (selfie) camera only. Your photo is sent securely for liveness and gesture checks.'**
  String get step_up_face_selfie_notice;

  /// No description provided for @step_up_face_ml_notice.
  ///
  /// In en, this message translates to:
  /// **'Automated checks (including ML) help prevent fraud and protect payouts.'**
  String get step_up_face_ml_notice;

  /// No description provided for @step_up_face_capturing.
  ///
  /// In en, this message translates to:
  /// **'Opening selfie camera…'**
  String get step_up_face_capturing;

  /// No description provided for @step_up_face_hold.
  ///
  /// In en, this message translates to:
  /// **'Hold still; face the camera.'**
  String get step_up_face_hold;

  /// No description provided for @review_title.
  ///
  /// In en, this message translates to:
  /// **'Evidence Captured'**
  String get review_title;

  /// No description provided for @review_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Review your photos before submitting'**
  String get review_subtitle;

  /// No description provided for @review_network_failure.
  ///
  /// In en, this message translates to:
  /// **'Network Failure Verified'**
  String get review_network_failure;

  /// No description provided for @review_network_desc.
  ///
  /// In en, this message translates to:
  /// **'Your device signal strength was strictly verified by OS sensors. No physical photos required.'**
  String get review_network_desc;

  /// No description provided for @review_recapture.
  ///
  /// In en, this message translates to:
  /// **'Re-capture'**
  String get review_recapture;

  /// No description provided for @review_submit.
  ///
  /// In en, this message translates to:
  /// **'Submit Evidence →'**
  String get review_submit;

  /// No description provided for @review_add_more.
  ///
  /// In en, this message translates to:
  /// **'Add More Photos'**
  String get review_add_more;

  /// No description provided for @review_label.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get review_label;

  /// No description provided for @submitted_title.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get submitted_title;

  /// No description provided for @submitted_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your evidence is under review'**
  String get submitted_subtitle;

  /// No description provided for @submitted_next.
  ///
  /// In en, this message translates to:
  /// **'What happens next?'**
  String get submitted_next;

  /// No description provided for @submitted_next_1.
  ///
  /// In en, this message translates to:
  /// **'Review within 4 hours'**
  String get submitted_next_1;

  /// No description provided for @submitted_next_2.
  ///
  /// In en, this message translates to:
  /// **'You will be notified when resolved'**
  String get submitted_next_2;

  /// No description provided for @submitted_next_3.
  ///
  /// In en, this message translates to:
  /// **'Provisional credit may be issued immediately'**
  String get submitted_next_3;

  /// No description provided for @submitted_demo.
  ///
  /// In en, this message translates to:
  /// **'Demo mode — Offline fallback shown'**
  String get submitted_demo;

  /// No description provided for @submitted_back.
  ///
  /// In en, this message translates to:
  /// **'Back to Claims'**
  String get submitted_back;

  /// No description provided for @chat_live_support.
  ///
  /// In en, this message translates to:
  /// **'Live Support'**
  String get chat_live_support;

  /// No description provided for @chat_agent.
  ///
  /// In en, this message translates to:
  /// **'Support Agent'**
  String get chat_agent;

  /// No description provided for @chat_typing.
  ///
  /// In en, this message translates to:
  /// **'Typing...'**
  String get chat_typing;

  /// No description provided for @chat_hint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get chat_hint;

  /// No description provided for @chat_bot_greeting.
  ///
  /// In en, this message translates to:
  /// **'Hi, I am a Hustlr claims agent. How can I help you regarding your manual claim?'**
  String get chat_bot_greeting;

  /// No description provided for @chat_attach_id.
  ///
  /// In en, this message translates to:
  /// **'ID Card'**
  String get chat_attach_id;

  /// No description provided for @chat_attach_weather.
  ///
  /// In en, this message translates to:
  /// **'Weather Proof'**
  String get chat_attach_weather;

  /// No description provided for @chat_attach_receipt.
  ///
  /// In en, this message translates to:
  /// **'Medical Receipt'**
  String get chat_attach_receipt;

  /// No description provided for @offline_banner_text.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Claims will be saved.'**
  String get offline_banner_text;

  /// No description provided for @review_save_offline.
  ///
  /// In en, this message translates to:
  /// **'Save Offline'**
  String get review_save_offline;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
