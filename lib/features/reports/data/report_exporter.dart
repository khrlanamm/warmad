import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/dates.dart';
import '../domain/report.dart';

/// Shares a cash flow report through the Android share sheet.
class ReportExporter {
  const ReportExporter();

  static String _fileName(CashFlowReport report, String extension) =>
      'warmad-arus-kas-${report.range.startKey}-${report.range.endKey}'
      '.$extension';

  Future<void> _share(String name, List<int> bytes, String subject) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }

  Future<void> shareCsv(CashFlowReport report, String warungName) {
    return _share(
      _fileName(report, 'csv'),
      report.toCsv().codeUnits,
      'Laporan arus kas $warungName',
    );
  }

  Future<void> sharePdf(CashFlowReport report, String warungName) async {
    // The built-in PDF font has no thousands dot problem, but it lacks the
    // typographic minus sign, so amounts are formatted with plain ASCII here.
    String rupiah(int amount) {
      final digits = amount.abs().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
      return '${amount < 0 ? '-' : ''}Rp$digits';
    }

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'Laporan arus kas',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(warungName, style: const pw.TextStyle(fontSize: 13)),
          pw.Text(
            '${report.range.startKey} sampai ${report.range.endKey}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: ['Ringkasan', 'Jumlah'],
            cellAlignments: {1: pw.Alignment.centerRight},
            data: [
              ['Kas masuk', rupiah(report.cashIn)],
              ['Kas keluar', rupiah(report.cashOut)],
              ['Arus kas bersih', rupiah(report.net)],
              ['Jumlah penjualan', '${report.salesCount}'],
              ['Penjualan kasbon (belum dibayar)', rupiah(report.salesCredit)],
            ],
          ),
          pw.SizedBox(height: 14),
          if (report.outflows.isNotEmpty) ...[
            pw.TableHelper.fromTextArray(
              headers: ['Kas keluar untuk', 'Jumlah'],
              cellAlignments: {1: pw.Alignment.centerRight},
              data: [
                for (final outflow in report.outflows)
                  [outflow.label, rupiah(outflow.amount)],
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          pw.TableHelper.fromTextArray(
            headers: ['Tanggal', 'Kas masuk', 'Kas keluar', 'Bersih'],
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            data: [
              for (final entry in report.days)
                [
                  dayKeyOf(entry.day),
                  rupiah(entry.summary.cashIn),
                  rupiah(entry.summary.cashOut),
                  rupiah(entry.summary.net),
                ],
            ],
          ),
        ],
      ),
    );
    await _share(
      _fileName(report, 'pdf'),
      await document.save(),
      'Laporan arus kas $warungName',
    );
  }
}
