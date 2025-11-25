class CallRecord {
  final String phoneNumber;
  final DateTime startTime;
  final Duration duration;
  final int deepfakeDetections;
  final double highestProbability;

  CallRecord({
    required this.phoneNumber,
    required this.startTime,
    required this.duration,
    this.deepfakeDetections = 0,
    this.highestProbability = 0.0,
  });
}

final List<CallRecord> callHistory = [];