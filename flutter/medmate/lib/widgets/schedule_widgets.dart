import 'package:flutter/material.dart';

import '../constants.dart';

const _purple = Color(0xFF7C4DFF);

class StatBox extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kWhite, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color:      kWhite,
                fontWeight: FontWeight.bold,
                fontSize:   18,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String label;
  final Color  color;
  final int    count;

  const SectionLabel({
    super.key,
    required this.label,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize:   15,
            fontWeight: FontWeight.w700,
            color:      color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize:   12,
              fontWeight: FontWeight.bold,
              color:      color,
            ),
          ),
        ),
      ],
    );
  }
}

Color _foodColor(String? tag) {
  switch (tag) {
    case 'With food':     return kAccent;
    case 'Empty stomach': return kRed;
    default:              return kTextGrey;
  }
}

IconData _foodIcon(String? tag) {
  switch (tag) {
    case 'With food':     return Icons.restaurant;
    case 'Empty stomach': return Icons.no_meals;
    default:              return Icons.remove_circle_outline;
  }
}

class GroupedScheduleCard extends StatelessWidget {
  final Map<String, dynamic>        group;
  final String Function(int, int)   formatTime;
  final void Function(int)?         onMarkTaken;

  const GroupedScheduleCard({
    super.key,
    required this.group,
    required this.formatTime,
    required this.onMarkTaken,
  });

  @override
  Widget build(BuildContext context) {
    final bool   allTaken  = group['allTaken'] == true;
    final Color  cardColor = allTaken ? kAccent : kPrimary;
    final String name      = group['name']    as String? ?? 'Unknown';
    final String dosage    = group['dosage']  as String? ?? '—';
    final String foodTag   = group['foodTag'] as String? ?? 'No preference';
    final List   doses     = group['doses']   as List? ?? [];
    final bool   showFood  = foodTag != 'No preference';
    final bool   multiDose = doses.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        kWhite,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: cardColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                Container(
                  width:  44,
                  height: 44,
                  decoration: BoxDecoration(
                    color:        cardColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    allTaken ? Icons.check_circle : Icons.medication,
                    color: cardColor,
                    size:  22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w700,
                          color:      kTextDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dosage,
                        style: const TextStyle(
                          fontSize: 13,
                          color:    kTextGrey,
                        ),
                      ),
                      if (showFood) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              _foodIcon(foodTag),
                              color: _foodColor(foodTag),
                              size:  12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              foodTag,
                              style: TextStyle(
                                fontSize:   12,
                                color:      _foodColor(foodTag),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (allTaken)
                  _Badge(label: 'All done', color: kAccent)
                else if (multiDose)
                  _Badge(label: '${doses.length}\u00d7/day', color: kPrimary),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.grey.shade100),

          ...List.generate(doses.length, (idx) {
            final Map    dose    = doses[idx] as Map;
            final bool   taken   = dose['taken']     == true;
            final bool   isBed   = dose['beforeBed'] == true;
            final int    origIdx = dose['originalIndex'] as int;
            final String time    = formatTime(
              dose['hour']   as int,
              dose['minute'] as int,
            );
            final bool  isLast    = idx == doses.length - 1;
            final Color doseColor = taken
                ? kAccent
                : isBed
                    ? _purple
                    : kPrimary;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      if (multiDose) ...[
                        Container(
                          width:  26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: doseColor.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${dose["doseNumber"]}',
                              style: TextStyle(
                                fontSize:   12,
                                fontWeight: FontWeight.bold,
                                color:      doseColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isBed
                                  ? Icons.bedtime_outlined
                                  : Icons.access_time,
                              color: doseColor,
                              size:  14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isBed ? '\u{1F319}  $time' : time,
                              style: TextStyle(
                                fontSize:   14,
                                fontWeight: FontWeight.w600,
                                color:      doseColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (taken)
                        _Badge(label: 'Taken', color: kAccent)
                      else if (onMarkTaken != null)
                        GestureDetector(
                          onTap:    () => onMarkTaken!(origIdx),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical:   4,
                            ),
                            decoration: BoxDecoration(
                              color:        doseColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: doseColor.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              'Mark Taken',
                              style: TextStyle(
                                color:      doseColor,
                                fontSize:   12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                    height:    1,
                    indent:    14,
                    endIndent: 14,
                    color:     Colors.grey.shade100,
                  ),
              ],
            );
          }),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:      color,
          fontSize:   12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}