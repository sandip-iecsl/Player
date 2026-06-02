import 'dart:math';

class AudioDNA {
  final double tempo;
  final double energy;
  final double valence;
  final double danceability;
  final double loudness;
  final double acousticness;
  final double instrumentalness;
  final double liveness;
  final double speechiness;
  final int key;
  final int mode;
  final int timeSignature;

  AudioDNA({
    required this.tempo,
    required this.energy,
    required this.valence,
    required this.danceability,
    required this.loudness,
    required this.acousticness,
    required this.instrumentalness,
    required this.liveness,
    required this.speechiness,
    required this.key,
    required this.mode,
    required this.timeSignature,
  });

  List<double> toVector() => [
        tempo,
        energy,
        valence,
        danceability,
        loudness,
        acousticness,
        instrumentalness,
        liveness,
        speechiness,
        key.toDouble(),
        mode.toDouble(),
        timeSignature.toDouble(),
      ];

  static double euclideanDistance(AudioDNA v1, AudioDNA v2) {
    final list1 = v1.toVector();
    final list2 = v2.toVector();
    double sum = 0;
    for (int i = 0; i < list1.length; i++) {
      sum += pow(list1[i] - list2[i], 2);
    }
    return sqrt(sum);
  }
}

class UserContext {
  final String timeOfDay; // Morning, Night
  final String currentActivity; // Static, Moving
  final List<String> recentSeedArtists;

  UserContext({
    required this.timeOfDay,
    required this.currentActivity,
    required this.recentSeedArtists,
  });

  Map<String, dynamic> toJson() => {
        'time_of_day': timeOfDay,
        'current_activity': currentActivity,
        'recent_seed_artists': recentSeedArtists,
      };
}
