import UIKit
import Flutter
import GoogleMaps
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Add your Google Maps API key here
    GMSServices.provideAPIKey("AIzaSyClBzrEB3mj17f5qUFP1-goERTf4dp6j4k")
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Request notification permissions
    if #available(iOS 14.0, *) {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        if granted {
          print("Notification permission granted")
        } else {
          print("Notification permission denied")
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}