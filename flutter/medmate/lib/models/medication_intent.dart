enum MedicationIntent {
  uponWakeUp,
  beforeBreakfast,
  afterBreakfast,
  beforeLunch,
  afterLunch,
  beforeDinner,
  afterDinner,
  beforeSleep,
}

extension MedicationIntentEx on MedicationIntent {
  String get displayName {
    switch (this) {
      case MedicationIntent.uponWakeUp:
        return 'Upon Wake Up';
      case MedicationIntent.beforeBreakfast:
        return 'Before Breakfast';
      case MedicationIntent.afterBreakfast:
        return 'After Breakfast';
      case MedicationIntent.beforeLunch:
        return 'Before Lunch';
      case MedicationIntent.afterLunch:
        return 'After Lunch';
      case MedicationIntent.beforeDinner:
        return 'Before Dinner';
      case MedicationIntent.afterDinner:
        return 'After Dinner';
      case MedicationIntent.beforeSleep:
        return 'Before Sleep';
    }
  }
}
