import 'package:flutter/material.dart';

class MemoDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<DateTime> markedDates;
  final String? title;

  const MemoDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.markedDates,
    this.title,
  });

  @override
  State<MemoDatePickerDialog> createState() => _MemoDatePickerDialogState();
}

class _MemoDatePickerDialogState extends State<MemoDatePickerDialog> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month);
    _selected = widget.initialDate;
  }

  bool _isMarked(DateTime date) =>
      widget.markedDates.contains(DateTime(date.year, date.month, date.day));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leadingBlanks = DateTime(_month.year, _month.month, 1).weekday - 1;
    final today = DateTime.now();
    final prevMonth = DateTime(_month.year, _month.month - 1);
    final nextMonth = DateTime(_month.year, _month.month + 1);
    final canBack = !prevMonth
        .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month));
    final canForward = !nextMonth
        .isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 선택적 제목
            if (widget.title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      widget.title!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
            ],
            // 월 이동 헤더
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: canBack
                      ? () => setState(
                          () => _month = DateTime(_month.year, _month.month - 1))
                      : null,
                ),
                Expanded(
                  child: Text(
                    '${_month.year}년 ${_month.month}월',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: canForward
                      ? () => setState(
                          () => _month = DateTime(_month.year, _month.month + 1))
                      : null,
                ),
              ],
            ),
            // 요일 헤더
            Row(
              children: ['월', '화', '수', '목', '금', '토', '일']
                  .asMap()
                  .entries
                  .map((e) => Expanded(
                        child: Center(
                          child: Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: e.key == 5
                                  ? Colors.blue.shade400
                                  : e.key == 6
                                      ? Colors.red.shade400
                                      : Colors.grey,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            // 날짜 그리드
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.85,
              children: [
                ...List.generate(leadingBlanks, (_) => const SizedBox()),
                ...List.generate(daysInMonth, (i) {
                  final day = DateTime(_month.year, _month.month, i + 1);
                  final isToday = DateUtils.isSameDay(day, today);
                  final isSelected = DateUtils.isSameDay(day, _selected);
                  final isMarked = _isMarked(day);
                  final isFuture = day.isAfter(widget.lastDate);

                  return GestureDetector(
                    onTap: isFuture
                        ? null
                        : () => setState(() => _selected = day),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? colorScheme.primary
                                : isToday
                                    ? colorScheme.primary.withAlpha(30)
                                    : null,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isFuture
                                    ? Colors.grey.shade300
                                    : isSelected
                                        ? Colors.white
                                        : isToday
                                            ? colorScheme.primary
                                            : null,
                                fontWeight: isToday || isSelected
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isMarked
                                ? (isSelected
                                    ? Colors.white
                                    : colorScheme.primary)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 4),
            // 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
