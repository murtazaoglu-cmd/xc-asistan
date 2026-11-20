import 'package:material_ui/material_ui.dart';

import '../util/money.dart';

/// Tutar gösterimi: "₺12.450,00" (negatif: "−₺1.250,00"). Rakamlar tabular (hizalı).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.hideZeroKurus = false,
    this.colorizeNegative = false,
    this.textAlign,
  });

  /// TL (ondalık) değerden: sunucu JSON'u için `MoneyText.json(row['total'])`.
  MoneyText.json(
    Object? jsonValue, {
    super.key,
    this.style,
    this.hideZeroKurus = false,
    this.colorizeNegative = false,
    this.textAlign,
  }) : amount = Money.fromJson(jsonValue);

  final Money amount;
  final TextStyle? style;
  final bool hideZeroKurus;

  /// Negatif tutarı hata renginde göster (renk + "−" işareti birlikte).
  final bool colorizeNegative;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    var s = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (colorizeNegative && amount.isNegative) {
      s = s.copyWith(color: Theme.of(context).colorScheme.error);
    }
    return Text(
      amount.format(hideZeroKurus: hideZeroKurus),
      style: s,
      textAlign: textAlign,
    );
  }
}
