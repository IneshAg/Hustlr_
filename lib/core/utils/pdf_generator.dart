import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfGenerator {
  /// Generate and preview the insurance certificate PDF.
  static Future<void> generateAndPreviewCertificate({
    String name       = 'Hustlr Worker',
    String zone       = 'Your Zone',
    String planName   = 'Standard Shield',
    String policyNumber = 'HS-PENDING',
    DateTime? coverageStart,
    DateTime? coverageEnd,
    int weeklyPremium = 49,
  }) async {
    final pdf  = pw.Document();
    final start  = coverageStart ?? DateTime.now();
    final end    = coverageEnd   ?? start.add(const Duration(days: 91));
    final dateStr   = '${start.day} ${_monthName(start.month)} ${start.year}';
    final expiryStr = '${end.day} ${_monthName(end.month)} ${end.year}';

    final allRows = <(String, String)>[
      ('Rain Disruption',   'Auto-triggers when rainfall > 64.5 mm/hr'),
      ('Extreme Heat',      'Triggers when temperature exceeds 42 °C'),
      ('Platform Outage',   'Outages lasting > 90 minutes'),
      ('Air Quality (AQI)', 'AQI > 200 — hazardous conditions'),
      ('Platform Outage',   'Dark-store closure or platform API failure'),
    ];
    final basicRows = allRows.take(2).toList();
    final standardRows = allRows.take(3).toList();
    final fullRows = allRows;

    final tierLower = planName.toLowerCase();
    final coverageRows = tierLower.contains('full')
        ? fullRows
        : tierLower.contains('basic')
            ? basicRows
            : standardRows;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('HUSTLR',
                          style: pw.TextStyle(
                            color: PdfColors.green800,
                            fontSize: 32,
                            fontWeight: pw.FontWeight.bold,
                          )),
                      pw.Text('CERTIFICATE OF INSURANCE',
                          style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 32),
                pw.Text('Policy Number: $policyNumber',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text('Coverage: $dateStr - $expiryStr',
                    style: const pw.TextStyle(fontSize: 14)),
                pw.Text('Weekly Premium: Rs $weeklyPremium',
                    style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 24),
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('COVERED PARTY',
                          style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey600,
                            fontWeight: pw.FontWeight.bold,
                          )),
                      pw.SizedBox(height: 8),
                      pw.Text('Name: $name'),
                      pw.Text('Zone: $zone'),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Text('ACTIVE COVERAGE: ${planName.toUpperCase()}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green800,
                    )),
                pw.SizedBox(height: 12),
                ...coverageRows.map((row) => _buildCoverageRow(row.$1, row.$2)),
                pw.Spacer(),
                pw.Divider(),
                pw.SizedBox(height: 12),
                pw.Text(
                    'This is a parametric insurance contract. Payouts are transferred '
                    'automatically based on zone-wide triggers. Do not share this document.',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                pw.SizedBox(height: 4),
                pw.Text('Digitally Signed by Hustlr Underwriting API',
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.grey800)),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final safePolicyNo = policyNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final fileName = 'Hustlr_Certificate_$safePolicyNo.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) => bytes, name: fileName);
    }
  }

  /// Generate and preview a claim payout receipt PDF.
  static Future<void> generateAndPreviewClaimReceipt({
    required String claimId,
    required String trigger,
    required String status,
    required DateTime createdAt,
    required int grossPayout,
    required int tranche1,
    required int tranche2,
    String? zone,
    int? fpsScore,
  }) async {
    final pdf = pw.Document();
    final createdStr = '${createdAt.day} ${_monthName(createdAt.month)} ${createdAt.year}';
    final safeClaimId = claimId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'HUSTLR',
                      style: pw.TextStyle(
                        color: PdfColors.green800,
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'CLAIM RECEIPT',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text('Claim ID: $claimId', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Trigger: $trigger', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Status: $status', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Claim Date: $createdStr', style: pw.TextStyle(fontSize: 12)),
                if (zone != null && zone.trim().isNotEmpty)
                  pw.Text('Zone: $zone', style: pw.TextStyle(fontSize: 12)),
                if (fpsScore != null)
                  pw.Text('Fraud Shield Score: $fpsScore', style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 20),
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    children: [
                      _receiptRow('Gross payout', 'Rs $grossPayout'),
                      pw.SizedBox(height: 8),
                      _receiptRow('Provisional (70%)', 'Rs $tranche1'),
                      pw.SizedBox(height: 8),
                      _receiptRow('Settlement (30%)', 'Rs $tranche2'),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text(
                  'This is a system-generated claim payout receipt for audit and reconciliation.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Digitally generated by Hustlr Claims Engine',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey800,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'Hustlr_Claim_Receipt_$safeClaimId.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) => bytes, name: fileName);
    }
  }

  static String _monthName(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  static pw.Widget _buildCoverageRow(String title, String desc) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 6,
            height: 6,
            margin: const pw.EdgeInsets.only(top: 4, right: 8),
            decoration: const pw.BoxDecoration(
                color: PdfColors.green, shape: pw.BoxShape.circle),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text(desc,
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _receiptRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }
}
