import 'package:flutter_test/flutter_test.dart';
import 'package:hacki/cubits/cubits.dart';
import 'package:hacki/models/preference.dart';

void main() {
  test('dynamic color toggle is available in preference settings', () {
    expect(
      Preference.allPreferences.any(
        (Preference<dynamic> preference) =>
            preference is DynamicColorPreference,
      ),
      isTrue,
    );

    final PreferenceState state = PreferenceState.init();
    expect(state.isDynamicColorEnabled, isFalse);
  });
}
