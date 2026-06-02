import 'package:fftea/fftea.dart';

void main() {
  final fft = FFT(256);
  final input = List.generate(256, (i) => 0.0);
  final output = fft.realFft(input);
  print(output.discardConjugates().magnitudes().length);
}
