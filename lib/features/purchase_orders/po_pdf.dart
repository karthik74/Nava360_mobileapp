import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/download_saver.dart';
import 'po_models.dart';

const _companyName = 'Navachetana Livelihoods Private Limited';
final _red = PdfColor.fromInt(0xFFC62828);
final _grey = PdfColor.fromInt(0xFF555555);
final _line = PdfColor.fromInt(0xFFBBBBBB);

String _money(double v) => NumberFormat('#,##0.00', 'en_IN').format(v);
String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Builds an A4 PDF mirroring the web `PurchaseOrderDocument`. Uses a MultiPage
/// so long item lists paginate with the table header repeated.
Future<Uint8List> buildPoPdf(PurchaseOrder po) async {
  final df = DateFormat('dd MMM yyyy');
  final doc = pw.Document(title: po.poNumber, author: _companyName);

  pw.Widget block(String title, List<String?> lines) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red)),
            pw.SizedBox(height: 4),
            for (final l in lines)
              if (l != null && l.trim().isNotEmpty) pw.Text(l, style: const pw.TextStyle(fontSize: 9.5)),
          ]),
        ),
      );

  pw.Widget cell(String t, {bool head = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(t,
            textAlign: align,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: head ? PdfColors.white : PdfColors.black)),
      );

  final c = po.company;
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: _red),
      children: [
        cell('Description', head: true),
        cell('QTY', head: true, align: pw.TextAlign.right),
        cell('Unit price', head: true, align: pw.TextAlign.right),
        cell('GST %', head: true, align: pw.TextAlign.right),
        cell('GST amt', head: true, align: pw.TextAlign.right),
        cell('Total', head: true, align: pw.TextAlign.right),
      ],
    ),
    for (final i in po.items)
      pw.TableRow(children: [
        cell(i.description),
        cell(_qty(i.quantity), align: pw.TextAlign.right),
        cell(_money(i.unitPrice), align: pw.TextAlign.right),
        cell(_qty(i.gstPercent), align: pw.TextAlign.right),
        cell(_money(i.gstAmount), align: pw.TextAlign.right),
        cell(_money(i.total), align: pw.TextAlign.right),
      ]),
  ];

  pw.Widget totalRow(String l, double v, {bool bold = false}) => pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(l, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text('Rs. ${_money(v)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]),
      );

  pw.Widget sig(String label) => pw.Column(children: [
        pw.Container(width: 140, height: 0.7, color: PdfColors.black),
        pw.SizedBox(height: 3),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ]);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: _grey)),
    ),
    build: (ctx) => [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        color: _red,
        child: pw.Center(
            child: pw.Text('PURCHASE ORDER',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
      ),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_companyName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if ((c['address'] ?? '').isNotEmpty) pw.Text(c['address']!, style: const pw.TextStyle(fontSize: 9.5)),
            if ((c['gstin'] ?? '').isNotEmpty) pw.Text('GSTIN: ${c['gstin']}', style: const pw.TextStyle(fontSize: 9.5)),
            if ((c['cin'] ?? '').isNotEmpty) pw.Text('CIN: ${c['cin']}', style: const pw.TextStyle(fontSize: 9.5)),
            if ((c['mobile'] ?? '').isNotEmpty) pw.Text('Mobile: ${c['mobile']}', style: const pw.TextStyle(fontSize: 9.5)),
            if ((c['email'] ?? '').isNotEmpty) pw.Text('Email: ${c['email']}', style: const pw.TextStyle(fontSize: 9.5)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Date: ${po.poDate == null ? '-' : df.format(po.poDate!)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('PO No: ${po.poNumber}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      ]),
      pw.SizedBox(height: 8),
      pw.Text(
        'Please do delivery before this date: ${po.deliveryByDate == null ? '-' : df.format(po.deliveryByDate!)}',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red),
      ),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        block('SUPPLIER', [
          po.supplierName,
          po.supplierAddress,
          (po.supplierGstin ?? '').isEmpty ? null : 'GSTIN: ${po.supplierGstin}',
        ]),
        pw.SizedBox(width: 10),
        block('SHIP TO', [po.shippingName, po.shippingAddress]),
      ]),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(4),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1),
          4: pw.FlexColumnWidth(1.6),
          5: pw.FlexColumnWidth(1.8),
        },
        children: rows,
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(children: [
          totalRow('Subtotal', po.subtotal),
          totalRow('GST', po.gstTotal),
          pw.Divider(color: _line, height: 6),
          totalRow('Grand total', po.grandTotal, bold: true),
        ]),
      ),
      if ((po.remarks ?? '').trim().isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('Remarks', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red)),
        pw.Text(po.remarks!, style: const pw.TextStyle(fontSize: 9.5)),
      ],
      pw.SizedBox(height: 40),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        sig('Prepared by'),
        sig('Authorised signature'),
      ]),
    ],
  ));
  return doc.save();
}

/// Loads the PO, builds the PDF, saves it to Downloads and offers to open it.
Future<void> downloadPoPdf(BuildContext context, Future<PurchaseOrder> Function() load) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparing PDF…')));
  try {
    final po = await load();
    final bytes = await buildPoPdf(po);
    final name = 'PO-${po.poNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
    final saved = await DownloadSaver.savePdf(name, bytes);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Saved to ${saved.locationLabel}: $name'),
      action: saved.canOpen ? SnackBarAction(label: 'Open', onPressed: () => saved.open()) : null,
    ));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not create the PDF: $e')));
  }
}
