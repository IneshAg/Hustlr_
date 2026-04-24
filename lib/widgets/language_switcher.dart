import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';

class LanguageSwitcher extends StatelessWidget {
  final bool showLabel;
  const LanguageSwitcher({this.showLabel = true, super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocaleProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const Text(
            'Language',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A6741),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LocaleProvider.supportedLanguages
            .entries
            .map((entry) => GestureDetector(
                onTap: () => provider.setLocale(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: provider.locale.languageCode == entry.key
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFF4F6F4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: provider.locale.languageCode == entry.key
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: provider.locale.languageCode == entry.key
                        ? Colors.white
                        : const Color(0xFF4A6741),
                    ),
                  ),
                ),
              ))
            .toList(),
        ),
      ],
    );
  }
}
