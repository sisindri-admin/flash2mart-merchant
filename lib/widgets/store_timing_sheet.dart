import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Store Operating Hours & Temporary Auto-Pause Sheet (Option 4)
/// Features:
/// 1. Set Store Opening & Closing Time (e.g. 07:00 AM - 10:30 PM)
/// 2. Weekly Operating Days (Mon-Sun)
/// 3. Quick Temporary Pause (15m, 30m, 1h, 2h) with reasons (Lunch, Rush, Restock)
/// 4. 1-Tap Resume Store
class StoreTimingSheet extends StatefulWidget {
  final Map<String, dynamic> storeData;
  final VoidCallback? onUpdated;

  const StoreTimingSheet({
    super.key,
    required this.storeData,
    this.onUpdated,
  });

  @override
  State<StoreTimingSheet> createState() => _StoreTimingSheetState();
}

class _StoreTimingSheetState extends State<StoreTimingSheet> {
  late TimeOfDay _openTime;
  late TimeOfDay _closeTime;
  bool _isSaving = false;

  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  late Set<String> _selectedDays;

  // Pause Duration options in minutes
  final List<int> _pauseOptions = [15, 30, 60, 120];
  int? _selectedPauseMinutes;
  String _selectedPauseReason = 'Lunch / Tea Break';

  final List<String> _pauseReasons = [
    'Lunch / Tea Break',
    'Heavy Rush / Kitchen Overloaded',
    'Stock Unloading / Refill',
    'Power / Network Interruption',
    'Staff Shortage / Temporary Closed',
  ];

  @override
  void initState() {
    super.initState();
    _openTime = _parseTime(widget.storeData['openingTime']?.toString()) ?? const TimeOfDay(hour: 7, minute: 0);
    _closeTime = _parseTime(widget.storeData['closingTime']?.toString()) ?? const TimeOfDay(hour: 22, minute: 30);

    final dynamic daysList = widget.storeData['operatingDays'];
    if (daysList is List) {
      _selectedDays = Set<String>.from(daysList.map((e) => e.toString()));
    } else {
      _selectedDays = Set<String>.from(_days);
    }
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.trim().split(' ');
      final hm = parts[0].split(':');
      int hour = int.parse(hm[0]);
      final minute = int.parse(hm[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && hour < 12) {
        hour += 12;
      } else if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && hour == 12) {
        hour = 0;
      }
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _pickTime({required bool isOpenTime}) async {
    final initial = isOpenTime ? _openTime : _closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        if (isOpenTime) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
    }
  }

  Future<void> _saveTimings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      final openStr = _formatTime(_openTime);
      final closeStr = _formatTime(_closeTime);

      await FirebaseFirestore.instance.collection('merchants').doc(user.uid).set({
        'openingTime': openStr,
        'closingTime': closeStr,
        'operatingDays': _selectedDays.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (widget.onUpdated != null) widget.onUpdated!();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Operating hours saved: $openStr to $closeStr'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pauseStore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedPauseMinutes == null) return;

    setState(() => _isSaving = true);
    try {
      final pauseDuration = Duration(minutes: _selectedPauseMinutes!);
      final resumeAt = DateTime.now().add(pauseDuration);
      final resumeAtStr = '${resumeAt.hour > 12 ? resumeAt.hour - 12 : resumeAt.hour}:${resumeAt.minute.toString().padLeft(2, '0')} ${resumeAt.hour >= 12 ? 'PM' : 'AM'}';

      await FirebaseFirestore.instance.collection('merchants').doc(user.uid).set({
        'isOpen': false,
        'isPaused': true,
        'pauseUntil': Timestamp.fromDate(resumeAt),
        'pauseUntilFormatted': resumeAtStr,
        'pauseReason': _selectedPauseReason,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (widget.onUpdated != null) widget.onUpdated!();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏸️ Store paused for $_selectedPauseMinutes mins until $resumeAtStr ($_selectedPauseReason)'),
            backgroundColor: const Color(0xFFD97706),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _resumeStore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('merchants').doc(user.uid).set({
        'isOpen': true,
        'isPaused': false,
        'pauseUntil': FieldValue.delete(),
        'pauseUntilFormatted': FieldValue.delete(),
        'pauseReason': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (widget.onUpdated != null) widget.onUpdated!();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🟢 Store resumed and now ONLINE for customer orders!'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCurrentlyPaused = widget.storeData['isPaused'] == true;
    final String pauseUntilFormatted = (widget.storeData['pauseUntilFormatted'] ?? '').toString();
    final String pauseReason = (widget.storeData['pauseReason'] ?? 'Temporary Pause').toString();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: AppColors.accentBlue, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Store Timings & Auto-Pause',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: AppColors.textDark),
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),

            // ACTIVE PAUSE BANNER (IF CURRENTLY PAUSED)
            if (isCurrentlyPaused) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFFD97706), size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'STORE CURRENTLY PAUSED',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Paused for: $pauseReason',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF78350F)),
                    ),
                    if (pauseUntilFormatted.isNotEmpty)
                      Text(
                        'Scheduled to automatically resume at $pauseUntilFormatted',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isSaving ? null : _resumeStore,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('RESUME STORE NOW (GO ONLINE)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // SECTION 1: DAILY OPERATING HOURS
            const Text(
              '1. Daily Operating Hours',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            const Text('Customers can place orders during these hours:', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const SizedBox(height: 10),

            Row(
              children: [
                // Opening Time Picker
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(isOpenTime: true),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.wb_sunny_outlined, size: 14, color: Color(0xFFEA580C)),
                              SizedBox(width: 4),
                              Text('Opens At', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(_openTime),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Closing Time Picker
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(isOpenTime: false),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.nightlight_outlined, size: 14, color: Color(0xFF4F46E5)),
                              SizedBox(width: 4),
                              Text('Closes At', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(_closeTime),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Operating Days Multi-chips
            Wrap(
              spacing: 6,
              children: _days.map((day) {
                final isSelected = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(day),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedDays.add(day);
                      } else {
                        if (_selectedDays.length > 1) _selectedDays.remove(day);
                      }
                    });
                  },
                  selectedColor: AppColors.primaryGreenLight,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? AppColors.primaryGreen : AppColors.textDark,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: isSelected ? AppColors.primaryGreen : const Color(0xFFCBD5E1)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _saveTimings,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('SAVE OPERATING HOURS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            ),
            const Divider(height: 28),

            // SECTION 2: TEMPORARY AUTO-PAUSE STORE
            const Text(
              '2. Temporary Store Pause (Heavy Rush / Lunch)',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            const Text('Orders will be paused in Customer App for the chosen duration:', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const SizedBox(height: 10),

            // Duration Selection Chips
            Row(
              children: _pauseOptions.map((mins) {
                final isSelected = _selectedPauseMinutes == mins;
                final label = mins < 60 ? '${mins}m' : '${mins ~/ 60}h';
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.white : AppColors.textDark))),
                      selected: isSelected,
                      onSelected: (val) => setState(() => _selectedPauseMinutes = val ? mins : null),
                      selectedColor: const Color(0xFFD97706),
                      backgroundColor: const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Pause Reason Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedPauseReason,
              decoration: InputDecoration(
                labelText: 'Reason for Pause',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _pauseReasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12.5))))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedPauseReason = val);
              },
            ),
            const SizedBox(height: 14),

            // Confirm Pause Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _selectedPauseMinutes == null || _isSaving ? null : _pauseStore,
                icon: const Icon(Icons.pause_circle_outline, size: 20),
                label: Text(
                  _selectedPauseMinutes != null
                      ? 'PAUSE STORE FOR ${_selectedPauseMinutes! < 60 ? "${_selectedPauseMinutes}m" : "${_selectedPauseMinutes! ~/ 60}h"}'
                      : 'SELECT DURATION TO PAUSE',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
