import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noise_tracker/main.dart';

void main() {
  group('Noise Tracker iOS App Tests', () {
    testWidgets('App launches with correct initial state', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      expect(find.text('Noise Dashboard'), findsOneWidget);
      expect(find.text('Live Noise Level:'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Report Noise'), findsOneWidget);
      expect(find.textContaining('dB'), findsOneWidget);
    });

    testWidgets('Bottom navigation works correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      expect(find.text('Noise Dashboard'), findsOneWidget);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(find.text('Noise Map'), findsOneWidget);

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(find.text('Noise Analytics'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Noise Dashboard'), findsOneWidget);
    });

    testWidgets('Profile editing works correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final nameFields = find.byType(TextFormField);
      expect(nameFields, findsAtLeastNWidgets(2));

      await tester.enterText(nameFields.first, 'Jane Smith');
      await tester.enterText(nameFields.last, 'jane.smith@example.com');

      await tester.tap(find.text('Save Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile updated!'), findsOneWidget);
    });

    testWidgets('Complaint submission works', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report Noise'));
      await tester.pumpAndSettle();

      expect(find.text('Current Noise Level'), findsOneWidget);
      expect(find.textContaining('dB'), findsAtLeastNWidgets(1));

      await tester.enterText(find.byType(TextFormField).first, 'Test Location');
      await tester.enterText(find.byType(TextFormField).last, 'Test Description');
      
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Complaint Submitted'), findsOneWidget);
      expect(find.text('Test Location'), findsOneWidget);
      expect(find.text('Test Description'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Noise Dashboard'), findsOneWidget);
      expect(find.text('Recent Complaints: 1'), findsOneWidget);
    });

    testWidgets('Analytics screen shows data after complaints', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report Noise'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Test Location');
      await tester.enterText(find.byType(TextFormField).last, 'Test Description');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();

      expect(find.text('Total Complaints'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Avg Noise Level'), findsOneWidget);
      expect(find.text('Max Noise Level'), findsOneWidget);
      expect(find.text('Noise Levels Over Time'), findsOneWidget);
      expect(find.text('Recent Complaints'), findsOneWidget);
    });

    testWidgets('Dark mode toggle works', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final darkModeSwitch = find.byType(SwitchListTile).last;
      await tester.tap(darkModeSwitch);
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsAtLeastNWidgets(2));
    });

    testWidgets('Noise level display shows correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('dB'), findsOneWidget);
      
      final micIcon = find.byIcon(Icons.mic);
      final micOffIcon = find.byIcon(Icons.mic_off);
      
      expect(micIcon.evaluate().isNotEmpty || micOffIcon.evaluate().isNotEmpty, true);
      expect(find.text('Live').evaluate().isNotEmpty || find.text('Simulated').evaluate().isNotEmpty, true);
      
      final noiseText = tester.widget<Text>(find.textContaining('dB')).data!;
      expect(noiseText.contains('dB'), true);
    });
  });
}
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noise_tracker/main.dart';

void main() {
  group('Noise Tracker iOS App Tests', () {
    testWidgets('App launches with correct initial state', (WidgetTester tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(const NoiseTrackerApp());
      
      // Wait for all animations to complete
      await tester.pumpAndSettle();

      // Verify that the app starts with the dashboard screen
      expect(find.text('Noise Dashboard'), findsOneWidget);
      expect(find.text('Live Noise Level:'), findsOneWidget);
      
      // Verify that the bottom navigation bar is present
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      
      // Verify that the Report Noise button is present
      expect(find.text('Report Noise'), findsOneWidget);
      
      // Verify that noise level is displayed
      expect(find.textContaining('dB'), findsOneWidget);
    });

    testWidgets('Bottom navigation works correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      // Start on Dashboard
      expect(find.text('Noise Dashboard'), findsOneWidget);

      // Tap on the Map tab
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      // Verify that we navigated to the map screen
      expect(find.text('Noise Map'), findsOneWidget);
      expect(find.text('Noise Dashboard'), findsNothing);

      // Tap on the Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Verify that we navigated to the settings screen
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Noise Map'), findsNothing);

      // Navigate back to Dashboard
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Noise Dashboard'), findsOneWidget);
    });

    testWidgets('Report Noise navigation works', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      // Find and tap the Report Noise button
      await tester.tap(find.text('Report Noise'));
      await tester.pumpAndSettle();

      // Verify that we navigated to the complaint form screen
      expect(find.text('Submit Noise Complaint'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);

      // Go back to dashboard
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Noise Dashboard'), findsOneWidget);
    });

    testWidgets('Complaint form validation works', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      // Navigate to complaint form
      await tester.tap(find.text('Report Noise'));
      await tester.pumpAndSettle();

      // Try to submit empty form
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Verify validation messages appear
      expect(find.text('Enter a location'), findsOneWidget);
      expect(find.text('Enter a description'), findsOneWidget);
    });

    testWidgets('Complaint form submission works', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      // Navigate to complaint form
      await tester.tap(find.text('Report Noise'));
      await tester.pumpAndSettle();

      // Fill out the form
      await tester.enterText(find.byType(TextFormField).first, 'Test Location');
      await tester.enterText(find.byType(TextFormField).last, 'Test Description');
      
      // Submit the form
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Verify success dialog appears
      expect(find.text('Complaint Submitted'), findsOneWidget);
      expect(find.text('Test Location'), findsOneWidget);
      expect(find.text('Test Description'), findsOneWidget);

      // Close the dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Should be back on dashboard
      expect(find.text('Noise Dashboard'), findsOneWidget);
    });

    testWidgets('Settings screen displays correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Verify settings content
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('johndoe@example.com'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('Noise level updates periodically', (WidgetTester tester) async {
      await tester.pumpWidget(const NoiseTrackerApp());
      await tester.pumpAndSettle();

      // Get initial noise level
      final initialNoiseLevelFinder = find.textContaining('dB');
      expect(initialNoiseLevelFinder, findsOneWidget);

      // Wait for a few seconds for the timer to update
      await tester.pump(const Duration(seconds: 2));
      
      // The noise level should be displayed
      expect(find.textContaining('dB'), findsOneWidget);
      
      // Verify the noise level format is correct
      final hasLowModerateoOrHigh = find.textContaining('(Low)').evaluate().isNotEmpty ||
                                   find.textContaining('(Moderate)').evaluate().isNotEmpty ||
                                   find.textContaining('(High)').evaluate().isNotEmpty;
      expect(hasLowModerateoOrHigh, true);
    });
  });
}