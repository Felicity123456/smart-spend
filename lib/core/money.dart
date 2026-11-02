import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();
String newId() => uuid.v4();
String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';
String formatVndInput(String digits) => digits.replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]}.',
);
String money(int value) =>
    '${value < 0 ? '-' : ''}${formatVndInput(value.abs().toString())} ₫';

int parseMoney(String value, {bool allowZero = false}) {
  final text = value.trim();
  if (!RegExp(r'^(\d+|\d{1,3}(\.\d{3})+)$').hasMatch(text)) {
    throw Exception('Nhập số tiền VND hợp lệ, ví dụ 30.000 hoặc 3.000.000.');
  }
  final amount = int.tryParse(text.replaceAll('.', ''));
  if (amount == null ||
      amount < (allowZero ? 0 : 1) ||
      amount > 9000000000000000) {
    throw Exception(
      allowZero
          ? 'Số tiền phải không âm và trong giới hạn cho phép.'
          : 'Số tiền phải lớn hơn 0 và trong giới hạn cho phép.',
    );
  }
  return amount;
}

class VndInputFormatter extends TextInputFormatter {
  const VndInputFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!RegExp(r'^[\d.]*$').hasMatch(newValue.text)) return oldValue;
    final digits = newValue.text.replaceAll('.', '');
    final formatted = formatVndInput(digits);
    final cursor = newValue.selection.extentOffset.clamp(
      0,
      newValue.text.length,
    );
    final digitsBefore = newValue.text
        .substring(0, cursor)
        .replaceAll('.', '')
        .length;
    var seen = 0;
    var position = 0;
    while (position < formatted.length && seen < digitsBefore) {
      if (formatted[position] != '.') seen++;
      position++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: position),
    );
  }
}
