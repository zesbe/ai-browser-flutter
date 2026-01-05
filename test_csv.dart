import 'dart:io';
import 'package:csv/csv.dart';

void main() async {
  final file = File('/storage/emulated/0/Download/Google Passwords.csv');

  print('File exists: ${await file.exists()}');

  final content = await file.readAsString();
  print('Content length: ${content.length} bytes');
  print('First 500 chars:\n${content.substring(0, 500)}');

  print('\n--- Parsing CSV ---');

  final csvTable = const CsvToListConverter(
    shouldParseNumbers: false,
    allowInvalid: true,
  ).convert(content);

  print('Total rows: ${csvTable.length}');
  print('Header: ${csvTable.first}');
  print('First data row: ${csvTable[1]}');
  print('Row 1 length: ${csvTable[1].length}');

  // Count valid rows
  int validRows = 0;
  int emptyUrl = 0;
  int emptyPassword = 0;
  int shortRows = 0;

  for (int i = 1; i < csvTable.length; i++) {
    final row = csvTable[i];
    if (row.length < 4) {
      shortRows++;
      print('Short row $i: $row');
      continue;
    }

    final url = row[1].toString().trim();
    final password = row[3].toString().trim();

    if (url.isEmpty) {
      emptyUrl++;
      continue;
    }
    if (password.isEmpty) {
      emptyPassword++;
      continue;
    }

    validRows++;
  }

  print('\n--- Summary ---');
  print('Valid rows: $validRows');
  print('Empty URL: $emptyUrl');
  print('Empty password: $emptyPassword');
  print('Short rows (<4 cols): $shortRows');
}
