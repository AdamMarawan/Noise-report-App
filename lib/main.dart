import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const NoiseTrackerApp());
}

// Data models
class Airport {
  final String code;
  final String name;
  final double latitude;
  final double longitude;
  final double distanceFromUser;

  Airport({
    required this.code,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceFromUser,
  });

  factory Airport.fromJson(Map<String, dynamic> json, double userLat, double userLng) {
    final lat = double.parse(json['latitude'].toString());
    final lng = double.parse(json['longitude'].toString());
    final distance = Geolocator.distanceBetween(userLat, userLng, lat, lng) / 1000;
    
    return Airport(
      code: json['iata'] ?? json['icao'] ?? 'Unknown',
      name: json['name'] ?? 'Unknown Airport',
      latitude: lat,
      longitude: lng,
      distanceFromUser: distance,
    );
  }
}

class Flight {
  final String callsign;
  final String? airline;
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final double speed;
  final String? origin;
  final String? destination;

  Flight({
    required this.callsign,
    this.airline,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.speed,
    this.origin,
    this.destination,
  });
}

class NoiseGroup {
  final String id;
  final String name;
  final String description;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusKm;
  final DateTime createdAt;
  final String createdBy;
  final List<String> memberIds;
  final int complaintCount;
  final bool isPublic;

  NoiseGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusKm,
    required this.createdAt,
    required this.createdBy,
    required this.memberIds,
    required this.complaintCount,
    required this.isPublic,
  });

  factory NoiseGroup.create({
    required String name,
    required String description,
    required double latitude,
    required double longitude,
    required double radiusKm,
    required String creatorId,
    bool isPublic = true,
  }) {
    return NoiseGroup(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      centerLatitude: latitude,
      centerLongitude: longitude,
      radiusKm: radiusKm,
      createdAt: DateTime.now(),
      createdBy: creatorId,
      memberIds: [creatorId],
      complaintCount: 0,
      isPublic: isPublic,
    );
  }
}

class NoiseComplaint {
  final String id;
  final String location;
  final String description;
  final DateTime timestamp;
  final double noiseLevel;
  final double latitude;
  final double longitude;
  final Airport? nearestAirport;
  final List<Flight> nearbyFlights;
  final String? suspectedFlight;
  final String reporterId;
  final List<String> verifiedBy;
  final List<String> groupIds;
  final bool isPublic;

  NoiseComplaint({
    String? id,
    required this.location,
    required this.description,
    required this.timestamp,
    required this.noiseLevel,
    required this.latitude,
    required this.longitude,
    this.nearestAirport,
    this.nearbyFlights = const [],
    this.suspectedFlight,
    required this.reporterId,
    this.verifiedBy = const [],
    this.groupIds = const [],
    this.isPublic = true,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  int get verificationCount => verifiedBy.length;
  bool isVerifiedBy(String userId) => verifiedBy.contains(userId);
  
  NoiseComplaint copyWithVerification(String userId) {
    final newVerifiedBy = List<String>.from(verifiedBy);
    if (!newVerifiedBy.contains(userId)) {
      newVerifiedBy.add(userId);
    }
    return NoiseComplaint(
      id: id,
      location: location,
      description: description,
      timestamp: timestamp,
      noiseLevel: noiseLevel,
      latitude: latitude,
      longitude: longitude,
      nearestAirport: nearestAirport,
      nearbyFlights: nearbyFlights,
      suspectedFlight: suspectedFlight,
      reporterId: reporterId,
      verifiedBy: newVerifiedBy,
      groupIds: groupIds,
      isPublic: isPublic,
    );
  }
}

class UserProfile {
  String name;
  String email;
  bool notificationsEnabled;
  bool darkMode;
  double? latitude;
  double? longitude;
  Airport? nearestAirport;
  String id;
  DateTime joinedAt;
  List<String> groupIds;

  UserProfile({
    required this.name,
    required this.email,
    this.notificationsEnabled = true,
    this.darkMode = false,
    this.latitude,
    this.longitude,
    this.nearestAirport,
    String? id,
    DateTime? joinedAt,
    this.groupIds = const [],
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       joinedAt = joinedAt ?? DateTime.now();
}

// Services
class FlightTrackingService {
  static const String _baseUrl = 'https://opensky-network.org/api';
  
  static Future<List<Flight>> getFlights({
    double? lat,
    double? lng,
    double? radiusKm,
    bool global = false,
  }) async {
    try {
      Uri uri;
      
      if (global) {
        uri = Uri.parse('$_baseUrl/states/all');
      } else if (lat != null && lng != null && radiusKm != null) {
        final double latDelta = radiusKm / 111.32;
        final double lngDelta = radiusKm / (111.32 * cos(lat * pi / 180));
        
        uri = Uri.parse('$_baseUrl/states/all').replace(queryParameters: {
          'lamin': (lat - latDelta).toStringAsFixed(6),
          'lomin': (lng - lngDelta).toStringAsFixed(6),
          'lamax': (lat + latDelta).toStringAsFixed(6),
          'lomax': (lng + lngDelta).toStringAsFixed(6),
        });
      } else {
        return [];
      }

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'AirportNoiseTracker/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final states = data['states'] as List?;
        
        if (states != null && states.isNotEmpty) {
          final flights = <Flight>[];
          
          for (final state in states) {
            try {
              if (state != null && state.length > 16) {
                final callsign = (state[1]?.toString() ?? '').trim();
                final latitude = state[6]?.toDouble() ?? 0.0;
                final longitude = state[5]?.toDouble() ?? 0.0;
                final altitude = state[7]?.toDouble() ?? 0.0;
                final velocity = state[9]?.toDouble() ?? 0.0;
                final heading = state[10]?.toDouble() ?? 0.0;
                final originCountry = state[2]?.toString() ?? '';
                
                if (latitude != 0.0 && longitude != 0.0 && callsign.isNotEmpty && altitude > 0) {
                  final flight = Flight(
                    callsign: callsign,
                    latitude: latitude,
                    longitude: longitude,
                    altitude: altitude,
                    heading: heading,
                    speed: velocity * 3.6,
                    airline: _extractAirline(callsign),
                    origin: originCountry,
                  );
                  
                  if (global) {
                    if (altitude > 1000 && velocity > 50) {
                      flights.add(flight);
                    }
                  } else {
                    flights.add(flight);
                  }
                }
              }
            } catch (e) {
              // Skip invalid flight data
            }
          }
          
          return flights;
        }
      }
    } catch (e) {
      debugPrint('Exception fetching flights: $e');
    }
    
    return [];
  }
  
  static String _extractAirline(String callsign) {
    if (callsign.length < 3) return 'Unknown';
    
    final Map<String, String> airlines = {
      'UAL': 'United Airlines',
      'AAL': 'American Airlines',
      'DAL': 'Delta Air Lines',
      'SWA': 'Southwest Airlines',
      'JBU': 'JetBlue Airways',
      'AFR': 'Air France',
      'BAW': 'British Airways',
      'DLH': 'Lufthansa',
      'KLM': 'KLM Royal Dutch Airlines',
      'SAS': 'Scandinavian Airlines',
      'AIC': 'Air India',
      'JAL': 'Japan Airlines',
      'ANA': 'All Nippon Airways',
      'CPA': 'Cathay Pacific',
      'SIA': 'Singapore Airlines',
      'QFA': 'Qantas',
      'EZY': 'easyJet',
      'RYR': 'Ryanair',
      'UAE': 'Emirates',
      'QTR': 'Qatar Airways',
      'ETH': 'Ethiopian Airlines',
      'THY': 'Turkish Airlines',
    };
    
    final prefix = callsign.substring(0, 3);
    return airlines[prefix] ?? callsign.substring(0, 3);
  }
  
  static Future<List<Flight>> getNearbyFlights(double lat, double lng, double radiusKm) async {
    return getFlights(lat: lat, lng: lng, radiusKm: radiusKm);
  }
  
  static Future<List<Flight>> getGlobalFlights() async {
    return getFlights(global: true);
  }
}

class AirportService {
  static Future<List<Airport>> getNearbyAirports(double lat, double lng) async {
    final List<Map<String, dynamic>> mockAirports = [
      {'iata': 'LAX', 'name': 'Los Angeles International Airport', 'latitude': '33.9425', 'longitude': '-118.4081'},
      {'iata': 'JFK', 'name': 'John F. Kennedy International Airport', 'latitude': '40.6413', 'longitude': '-73.7781'},
      {'iata': 'ORD', 'name': 'Chicago O\'Hare International Airport', 'latitude': '41.9742', 'longitude': '-87.9073'},
      {'iata': 'DFW', 'name': 'Dallas/Fort Worth International Airport', 'latitude': '32.8968', 'longitude': '-97.0380'},
      {'iata': 'SFO', 'name': 'San Francisco International Airport', 'latitude': '37.6213', 'longitude': '-122.3790'},
    ];

    return mockAirports
        .map((airport) => Airport.fromJson(airport, lat, lng))
        .toList()
      ..sort((a, b) => a.distanceFromUser.compareTo(b.distanceFromUser));
  }
}

// Main App
class NoiseTrackerApp extends StatefulWidget {
  const NoiseTrackerApp({super.key});

  @override
  State<NoiseTrackerApp> createState() => _NoiseTrackerAppState();
}

class _NoiseTrackerAppState extends State<NoiseTrackerApp> {
  UserProfile userProfile = UserProfile(
    name: "John Doe",
    email: "johndoe@example.com",
  );

  List<NoiseComplaint> complaints = [];
  List<NoiseComplaint> communityComplaints = [];
  List<NoiseGroup> userGroups = [];
  List<NoiseGroup> availableGroups = [];
  Position? currentPosition;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _loadCommunityData();
  }

  Future<void> _initializeLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        currentPosition = position;
        userProfile.latitude = position.latitude;
        userProfile.longitude = position.longitude;
      });

      final airports = await AirportService.getNearbyAirports(
        position.latitude,
        position.longitude,
      );
      
      if (airports.isNotEmpty) {
        setState(() {
          userProfile.nearestAirport = airports.first;
        });
      }

      _loadNearbyGroups();
    } catch (e) {
      debugPrint('Error getting location: $e');
      setState(() {
        currentPosition = Position(
          latitude: 37.7749,
          longitude: -122.4194,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
        userProfile.latitude = 37.7749;
        userProfile.longitude = -122.4194;
      });
    }
  }

  void _loadCommunityData() {
    _loadDemoGroups();
    _loadDemoCommunityComplaints();
  }

  void _loadDemoGroups() {
    final demoGroups = [
      NoiseGroup.create(
        name: "LAX Neighbors United",
        description: "Residents near LAX airport tracking aircraft noise",
        latitude: 33.9425,
        longitude: -118.4081,
        radiusKm: 15.0,
        creatorId: "demo_user_1",
      ),
      NoiseGroup.create(
        name: "SFO Community Watch",
        description: "San Francisco airport noise monitoring group",
        latitude: 37.6213,
        longitude: -122.3790,
        radiusKm: 20.0,
        creatorId: "demo_user_2",
      ),
      NoiseGroup.create(
        name: "Local Flight Trackers",
        description: "General aviation noise monitoring in your area",
        latitude: userProfile.latitude ?? 37.7749,
        longitude: userProfile.longitude ?? -122.4194,
        radiusKm: 10.0,
        creatorId: "demo_user_3",
      ),
    ];

    setState(() {
      availableGroups = demoGroups;
    });
  }

  void _loadDemoCommunityComplaints() {
    final now = DateTime.now();
    final demoComplaints = [
      NoiseComplaint(
        location: "123 Main St",
        description: "Loud aircraft takeoff, very disruptive",
        timestamp: now.subtract(const Duration(hours: 2)),
        noiseLevel: 85.5,
        latitude: (userProfile.latitude ?? 37.7749) + 0.001,
        longitude: (userProfile.longitude ?? -122.4194) + 0.001,
        reporterId: "neighbor_1",
        suspectedFlight: "UAL123",
        verifiedBy: const ["neighbor_2", "neighbor_3"],
        isPublic: true,
      ),
      NoiseComplaint(
        location: "456 Oak Ave",
        description: "Multiple aircraft in short succession",
        timestamp: now.subtract(const Duration(minutes: 30)),
        noiseLevel: 78.2,
        latitude: (userProfile.latitude ?? 37.7749) - 0.002,
        longitude: (userProfile.longitude ?? -122.4194) + 0.003,
        reporterId: "neighbor_2",
        suspectedFlight: "DAL456",
        verifiedBy: const ["neighbor_1"],
        isPublic: true,
      ),
    ];

    setState(() {
      communityComplaints = demoComplaints;
    });
  }

  void _loadNearbyGroups() {
    if (userProfile.latitude == null || userProfile.longitude == null) return;

    final nearbyGroups = availableGroups.where((group) {
      final distance = Geolocator.distanceBetween(
        userProfile.latitude!,
        userProfile.longitude!,
        group.centerLatitude,
        group.centerLongitude,
      ) / 1000;
      return distance <= 50;
    }).toList();

    setState(() {
      availableGroups = nearbyGroups;
    });
  }

  void updateProfile(UserProfile newProfile) {
    setState(() {
      userProfile = newProfile;
    });
  }

  void addComplaint(NoiseComplaint complaint) {
    setState(() {
      complaints.add(complaint);
    });

    if (userProfile.groupIds.isNotEmpty) {
      final communityComplaint = NoiseComplaint(
        id: complaint.id,
        location: complaint.location,
        description: complaint.description,
        timestamp: complaint.timestamp,
        noiseLevel: complaint.noiseLevel,
        latitude: complaint.latitude,
        longitude: complaint.longitude,
        nearestAirport: complaint.nearestAirport,
        nearbyFlights: complaint.nearbyFlights,
        suspectedFlight: complaint.suspectedFlight,
        reporterId: userProfile.id,
        groupIds: userProfile.groupIds,
        isPublic: complaint.isPublic,
      );

      setState(() {
        communityComplaints.insert(0, communityComplaint);
      });
    }
  }

  void verifyComplaint(NoiseComplaint complaint) {
    final updatedComplaints = communityComplaints.map((c) {
      if (c.id == complaint.id) {
        return c.copyWithVerification(userProfile.id);
      }
      return c;
    }).toList();

    setState(() {
      communityComplaints = updatedComplaints;
    });
  }

  void joinGroup(NoiseGroup group) {
    final updatedGroupIds = List<String>.from(userProfile.groupIds);
    if (!updatedGroupIds.contains(group.id)) {
      updatedGroupIds.add(group.id);
      
      final updatedProfile = UserProfile(
        name: userProfile.name,
        email: userProfile.email,
        notificationsEnabled: userProfile.notificationsEnabled,
        darkMode: userProfile.darkMode,
        latitude: userProfile.latitude,
        longitude: userProfile.longitude,
        nearestAirport: userProfile.nearestAirport,
        id: userProfile.id,
        joinedAt: userProfile.joinedAt,
        groupIds: updatedGroupIds,
      );
      
      setState(() {
        userProfile = updatedProfile;
        if (!userGroups.contains(group)) {
          userGroups.add(group);
        }
      });
    }
  }

  void createGroup(NoiseGroup group) {
    setState(() {
      availableGroups.add(group);
      userGroups.add(group);
    });
    joinGroup(group);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Airport Noise Tracker',
      theme: userProfile.darkMode ? ThemeData.dark() : ThemeData.light(),
      home: MainTabController(
        userProfile: userProfile,
        complaints: complaints,
        communityComplaints: communityComplaints,
        userGroups: userGroups,
        availableGroups: availableGroups,
        currentPosition: currentPosition,
        onProfileUpdate: updateProfile,
        onComplaintAdd: addComplaint,
        onComplaintVerify: verifyComplaint,
        onGroupJoin: joinGroup,
        onGroupCreate: createGroup,
      ),
    );
  }
}

// Main Tab Controller
class MainTabController extends StatefulWidget {
  final UserProfile userProfile;
  final List<NoiseComplaint> complaints;
  final List<NoiseComplaint> communityComplaints;
  final List<NoiseGroup> userGroups;
  final List<NoiseGroup> availableGroups;
  final Position? currentPosition;
  final Function(UserProfile) onProfileUpdate;
  final Function(NoiseComplaint) onComplaintAdd;
  final Function(NoiseComplaint) onComplaintVerify;
  final Function(NoiseGroup) onGroupJoin;
  final Function(NoiseGroup) onGroupCreate;

  const MainTabController({
    super.key,
    required this.userProfile,
    required this.complaints,
    required this.communityComplaints,
    required this.userGroups,
    required this.availableGroups,
    required this.currentPosition,
    required this.onProfileUpdate,
    required this.onComplaintAdd,
    required this.onComplaintVerify,
    required this.onGroupJoin,
    required this.onGroupCreate,
  });

  @override
  State<MainTabController> createState() => _MainTabControllerState();
}

class _MainTabControllerState extends State<MainTabController> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(
        complaints: widget.complaints,
        userProfile: widget.userProfile,
        currentPosition: widget.currentPosition,
        onComplaintAdd: widget.onComplaintAdd,
      ),
      FlightTrackingScreen(
        currentPosition: widget.currentPosition,
        userProfile: widget.userProfile,
      ),
      CommunityScreen(
        userProfile: widget.userProfile,
        communityComplaints: widget.communityComplaints,
        userGroups: widget.userGroups,
        availableGroups: widget.availableGroups,
        onComplaintVerify: widget.onComplaintVerify,
        onGroupJoin: widget.onGroupJoin,
        onGroupCreate: widget.onGroupCreate,
      ),
      AnalyticsScreen(
        complaints: widget.complaints,
        userProfile: widget.userProfile,
      ),
      SettingsScreen(
        userProfile: widget.userProfile,
        onProfileUpdate: widget.onProfileUpdate,
      ),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.flight), label: 'Flights'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Community'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Analytics'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// Dashboard Screen
class DashboardScreen extends StatefulWidget {
  final List<NoiseComplaint> complaints;
  final UserProfile userProfile;
  final Position? currentPosition;
  final Function(NoiseComplaint) onComplaintAdd;

  const DashboardScreen({
    super.key,
    required this.complaints,
    required this.userProfile,
    required this.currentPosition,
    required this.onComplaintAdd,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _noiseLevel = 0.0;
  bool _isListening = false;
  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final micPermission = await Permission.microphone.request();
    if (micPermission.isGranted) {
      _startListening();
    } else {
      _startFallbackSimulation();
    }
  }

  void _startListening() {
    try {
      _noiseMeter = NoiseMeter();

      _noiseSubscription = _noiseMeter!.noise.listen(
        (NoiseReading reading) {
          if (mounted) {
            setState(() {
              _noiseLevel = reading.meanDecibel.clamp(30.0, 120.0);
              _isListening = true;
            });
          }
        },
        onError: (Object error) {
          if (mounted) {
            debugPrint('Noise meter error: $error');
            _startFallbackSimulation();
          }
        },
      );
    } catch (e) {
      if (mounted) {
        debugPrint('Failed to start noise meter: $e');
        _startFallbackSimulation();
      }
    }
  }

  void _startFallbackSimulation() {
    final random = Random();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _noiseLevel = 35.0 + random.nextDouble() * 50.0;
          _isListening = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _noiseSubscription?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  String getNoiseLabel(double level) {
    if (level < 50) return 'Quiet';
    if (level < 60) return 'Low';
    if (level < 80) return 'Moderate';
    if (level < 100) return 'High';
    return 'Very High';
  }

  Color getNoiseColor(double level) {
    if (level < 50) return Colors.blue[100]!;
    if (level < 60) return Colors.green[100]!;
    if (level < 80) return Colors.orange[100]!;
    if (level < 100) return Colors.red[100]!;
    return Colors.purple[100]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Airport Noise Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.userProfile.nearestAirport != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_airport, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Nearest Airport',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.userProfile.nearestAirport!.name} (${widget.userProfile.nearestAirport!.code})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Distance: ${widget.userProfile.nearestAirport!.distanceFromUser.toStringAsFixed(1)} km',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  const Text(
                    'Live Noise Level:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(
                    _isListening ? Icons.mic : Icons.mic_off,
                    color: _isListening ? Colors.green : Colors.grey,
                  ),
                  Text(
                    _isListening ? 'Live' : 'Simulated',
                    style: TextStyle(
                      color: _isListening ? Colors.green : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: getNoiseColor(_noiseLevel),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Text(
                      '${_noiseLevel.toStringAsFixed(1)} dB',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      getNoiseLabel(_noiseLevel),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              Container(
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.grey[200],
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (_noiseLevel / 120.0).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: getNoiseColor(_noiseLevel).withOpacity(0.8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ComplaintFormScreen(
                          currentNoiseLevel: _noiseLevel,
                          currentPosition: widget.currentPosition,
                          nearestAirport: widget.userProfile.nearestAirport,
                          onComplaintAdd: widget.onComplaintAdd,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.report),
                  label: const Text('Report Airport Noise'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Complaints: ${widget.complaints.length}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      if (widget.userProfile.nearestAirport != null)
                        Text(
                          'Reports to ${widget.userProfile.nearestAirport!.code}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                    ],
                  ),
                  if (widget.complaints.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Avg: ${(widget.complaints.map((c) => c.noiseLevel).reduce((a, b) => a + b) / widget.complaints.length).toStringAsFixed(1)} dB',
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          'Last: ${widget.complaints.last.timestamp.toString().substring(11, 16)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Complaint Form Screen
class ComplaintFormScreen extends StatefulWidget {
  final double currentNoiseLevel;
  final Position? currentPosition;
  final Airport? nearestAirport;
  final Function(NoiseComplaint) onComplaintAdd;

  const ComplaintFormScreen({
    super.key,
    required this.currentNoiseLevel,
    required this.currentPosition,
    required this.nearestAirport,
    required this.onComplaintAdd,
  });

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _useCurrentLocation = false;
  List<Flight> _nearbyFlights = [];
  bool _loadingFlights = false;
  String? _selectedFlight;

  @override
  void initState() {
    super.initState();
    _loadNearbyFlights();
  }

  Future<void> _loadNearbyFlights() async {
    if (widget.currentPosition != null) {
      setState(() => _loadingFlights = true);
      
      final flights = await FlightTrackingService.getNearbyFlights(
        widget.currentPosition!.latitude,
        widget.currentPosition!.longitude,
        20.0,
      );
      
      setState(() {
        _nearbyFlights = flights;
        _loadingFlights = false;
      });
    }
  }

  void _useCurrentLocationToggle(bool value) {
    setState(() {
      _useCurrentLocation = value;
      if (value && widget.currentPosition != null) {
        _locationController.text = 'Current Location (${widget.currentPosition!.latitude.toStringAsFixed(4)}, ${widget.currentPosition!.longitude.toStringAsFixed(4)})';
      } else {
        _locationController.clear();
      }
    });
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final complaint = NoiseComplaint(
        location: _locationController.text,
        description: _descriptionController.text,
        timestamp: DateTime.now(),
        noiseLevel: widget.currentNoiseLevel,
        latitude: widget.currentPosition?.latitude ?? 0.0,
        longitude: widget.currentPosition?.longitude ?? 0.0,
        nearestAirport: widget.nearestAirport,
        nearbyFlights: _nearbyFlights,
        suspectedFlight: _selectedFlight,
        reporterId: "current_user",
      );

      widget.onComplaintAdd(complaint);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Complaint Submitted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location: ${_locationController.text}'),
                Text('Noise Level: ${widget.currentNoiseLevel.toStringAsFixed(1)} dB'),
                Text('Time: ${DateTime.now().toString().split('.')[0]}'),
                if (widget.nearestAirport != null)
                  Text('Nearest Airport: ${widget.nearestAirport!.name}'),
                if (_selectedFlight != null)
                  Text('Suspected Flight: $_selectedFlight'),
                const SizedBox(height: 8),
                Text('Description: ${_descriptionController.text}'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Your complaint has been logged and shared with your community groups.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Airport Noise'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Conditions',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Noise Level: ${widget.currentNoiseLevel.toStringAsFixed(1)} dB'),
                                Text('Time: ${DateTime.now().toString().substring(11, 16)}'),
                              ],
                            ),
                            if (widget.nearestAirport != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Airport: ${widget.nearestAirport!.code}'),
                                  Text('Distance: ${widget.nearestAirport!.distanceFromUser.toStringAsFixed(1)} km'),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Enter a location' : null,
                ),
                const SizedBox(height: 8),
                
                Row(
                  children: [
                    Checkbox(
                      value: _useCurrentLocation,
                      onChanged: (value) => _useCurrentLocationToggle(value ?? false),
                    ),
                    const Text('Use current location'),
                    const Spacer(),
                    if (widget.currentPosition != null)
                      Text(
                        'GPS: ${widget.currentPosition!.accuracy.toStringAsFixed(0)}m accuracy',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_nearbyFlights.isNotEmpty) ...[
                  const Text(
                    'Nearby Flights (optional)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          if (_loadingFlights)
                            const CircularProgressIndicator()
                          else
                            Column(
                              children: _nearbyFlights.take(5).map((flight) {
                                return RadioListTile<String>(
                                  title: Text(flight.callsign),
                                  subtitle: Text(
                                    'Alt: ${flight.altitude.toInt()}m, Speed: ${flight.speed.toInt()}km/h',
                                  ),
                                  value: flight.callsign,
                                  groupValue: _selectedFlight,
                                  onChanged: (value) {
                                    setState(() => _selectedFlight = value);
                                  },
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _descriptionController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                    alignLabelWithHint: true,
                    hintText: 'Describe the noise (e.g., aircraft takeoff, landing, engine noise)',
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Enter a description' : null,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitForm,
                    icon: const Icon(Icons.send),
                    label: const Text('Submit Complaint'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

// Flight Tracking Screen
class FlightTrackingScreen extends StatefulWidget {
  final Position? currentPosition;
  final UserProfile userProfile;

  const FlightTrackingScreen({
    super.key,
    required this.currentPosition,
    required this.userProfile,
  });

  @override
  State<FlightTrackingScreen> createState() => _FlightTrackingScreenState();
}

class _FlightTrackingScreenState extends State<FlightTrackingScreen> {
  GoogleMapController? mapController;
  List<Flight> flights = [];
  bool _loading = true;
  Timer? _refreshTimer;
  Position? currentPosition;
  bool _isTrackingLocation = false;
  bool _globalView = false;
  MapType _mapType = MapType.normal;
  double _currentZoom = 12.0;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() => _isTrackingLocation = true);
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        currentPosition = position;
      });

      if (mapController != null && !_globalView) {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            12.0,
          ),
        );
      }

      _loadFlights();
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (widget.currentPosition != null) {
        setState(() {
          currentPosition = widget.currentPosition;
        });
        _loadFlights();
      }
    } finally {
      setState(() => _isTrackingLocation = false);
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _loadFlights();
    });
  }

  Future<void> _loadFlights() async {
    if (currentPosition == null && !_globalView) return;

    setState(() => _loading = true);

    try {
      List<Flight> newFlights;
      
      if (_globalView) {
        newFlights = await FlightTrackingService.getGlobalFlights();
        if (newFlights.length > 1000) {
          newFlights = newFlights.take(1000).toList();
        }
      } else {
        newFlights = await FlightTrackingService.getNearbyFlights(
          currentPosition!.latitude,
          currentPosition!.longitude,
          50.0,
        );
      }
      
      if (mounted) {
        setState(() {
          flights = newFlights;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading flights: $e');
      setState(() => _loading = false);
    }
  }

  void _toggleGlobalView() {
    setState(() {
      _globalView = !_globalView;
      flights.clear();
    });

    if (mapController != null) {
      if (_globalView) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            const LatLng(20.0, 0.0),
            2.0,
          ),
        );
      } else if (currentPosition != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(currentPosition!.latitude, currentPosition!.longitude),
            10.0,
          ),
        );
      }
    }

    _loadFlights();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    
    if (_globalView) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(const LatLng(20.0, 0.0), 2.0),
      );
    } else if (currentPosition != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
          12.0,
        ),
      );
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentZoom = position.zoom;
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    
    final visibleFlights = _globalView 
        ? (_currentZoom > 5 ? flights.take(200) : flights.take(100))
        : flights;
    
    for (final flight in visibleFlights) {
      markers.add(
        Marker(
          markerId: MarkerId(flight.callsign),
          position: LatLng(flight.latitude, flight.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            flight.altitude > 10000 ? BitmapDescriptor.hueBlue : BitmapDescriptor.hueOrange
          ),
          infoWindow: InfoWindow(
            title: '✈️ ${flight.callsign}',
            snippet: '${flight.airline ?? 'Unknown Airline'}\n'
                    'Alt: ${flight.altitude.toInt()}m | Speed: ${flight.speed.toInt()}km/h\n'
                    'From: ${flight.origin ?? 'Unknown'}',
          ),
        ),
      );
    }

    if (!_globalView && currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(currentPosition!.latitude, currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '📍 Your Location',
            snippet: 'Accuracy: ${currentPosition!.accuracy.toInt()}m',
          ),
        ),
      );
    }

    if (!_globalView && widget.userProfile.nearestAirport != null) {
      markers.add(
        Marker(
          markerId: MarkerId('airport_${widget.userProfile.nearestAirport!.code}'),
          position: LatLng(
            widget.userProfile.nearestAirport!.latitude,
            widget.userProfile.nearestAirport!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '🛫 ${widget.userProfile.nearestAirport!.code}',
            snippet: widget.userProfile.nearestAirport!.name,
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_globalView ? 'Global Flight Tracking' : 'Local Flight Tracking'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_globalView ? Icons.location_on : Icons.public),
            onPressed: _toggleGlobalView,
            tooltip: _globalView ? 'Local View' : 'Global View',
          ),
          PopupMenuButton<MapType>(
            icon: const Icon(Icons.layers),
            onSelected: (MapType type) {
              setState(() => _mapType = type);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: MapType.normal, child: Text('Normal')),
              PopupMenuItem(value: MapType.satellite, child: Text('Satellite')),
              PopupMenuItem(value: MapType.terrain, child: Text('Terrain')),
              PopupMenuItem(value: MapType.hybrid, child: Text('Hybrid')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadFlights,
          ),
        ],
      ),
      body: (currentPosition == null && !_globalView)
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Getting your location...'),
                ],
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  onCameraMove: _onCameraMove,
                  initialCameraPosition: CameraPosition(
                    target: _globalView 
                        ? const LatLng(20.0, 0.0)
                        : LatLng(currentPosition?.latitude ?? 0, currentPosition?.longitude ?? 0),
                    zoom: _globalView ? 2.0 : 12.0,
                  ),
                  markers: _buildMarkers(),
                  mapType: _mapType,
                  myLocationEnabled: !_globalView,
                  myLocationButtonEnabled: !_globalView,
                  zoomControlsEnabled: true,
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  mapToolbarEnabled: false,
                  compassEnabled: true,
                  minMaxZoomPreference: _globalView 
                      ? const MinMaxZoomPreference(1.0, 15.0)
                      : const MinMaxZoomPreference(8.0, 20.0),
                ),
                if (_loading)
                  Positioned(
                    top: 20,
                    left: 20,
                    right: 20,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 16),
                            Text(_globalView ? 'Loading global flights...' : 'Updating flights...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '✈️ ${flights.length} flights ${_globalView ? 'worldwide' : 'nearby'}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Updated: ${DateTime.now().toString().substring(11, 16)}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (!_globalView) _buildLegendItem(Colors.red, 'You'),
                              _buildLegendItem(Colors.blue, 'High Alt'),
                              _buildLegendItem(Colors.orange, 'Low Alt'),
                              if (!_globalView) _buildLegendItem(Colors.green, 'Airport'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _globalView ? null : FloatingActionButton(
        onPressed: () {
          if (currentPosition != null && mapController != null) {
            mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(currentPosition!.latitude, currentPosition!.longitude),
                12.0,
              ),
            );
          }
        },
        child: const Icon(Icons.center_focus_strong),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// Community Screen
class CommunityScreen extends StatefulWidget {
  final UserProfile userProfile;
  final List<NoiseComplaint> communityComplaints;
  final List<NoiseGroup> userGroups;
  final List<NoiseGroup> availableGroups;
  final Function(NoiseComplaint) onComplaintVerify;
  final Function(NoiseGroup) onGroupJoin;
  final Function(NoiseGroup) onGroupCreate;

  const CommunityScreen({
    super.key,
    required this.userProfile,
    required this.communityComplaints,
    required this.userGroups,
    required this.availableGroups,
    required this.onComplaintVerify,
    required this.onGroupJoin,
    required this.onGroupCreate,
  });

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Network'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Groups'),
            Tab(icon: Icon(Icons.report), text: 'Live Feed'),
            Tab(icon: Icon(Icons.verified), text: 'Verify'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGroupsTab(),
          _buildLiveFeedTab(),
          _buildVerificationTab(),
        ],
      ),
    );
  }

  Widget _buildGroupsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (widget.userGroups.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  'My Groups',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showCreateGroupDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.userGroups.length,
                itemBuilder: (context, index) {
                  final group = widget.userGroups[index];
                  return _buildGroupCard(group, true);
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          Row(
            children: [
              Text(
                widget.userGroups.isEmpty ? 'Join a Group' : 'Discover More Groups',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (widget.userGroups.isEmpty)
                TextButton.icon(
                  onPressed: _showCreateGroupDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create New'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          Expanded(
            child: widget.availableGroups.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No groups found in your area'),
                        Text('Create one to get started!'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.availableGroups.length,
                    itemBuilder: (context, index) {
                      final group = widget.availableGroups[index];
                      final isJoined = widget.userGroups.any((g) => g.id == group.id);
                      return _buildGroupListTile(group, isJoined);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveFeedTab() {
    final recentComplaints = widget.communityComplaints
        .where((c) => c.reporterId != widget.userProfile.id)
        .take(20)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.live_tv, color: Colors.red),
              const SizedBox(width: 8),
              const Text(
                'Live Neighbor Reports',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${recentComplaints.length} recent',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: recentComplaints.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.volume_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No recent complaints from neighbors'),
                        Text('Join a group to see community reports'),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await Future.delayed(const Duration(seconds: 1));
                    },
                    child: ListView.builder(
                      itemCount: recentComplaints.length,
                      itemBuilder: (context, index) {
                        final complaint = recentComplaints[index];
                        return _buildComplaintCard(complaint);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationTab() {
    final unverifiedComplaints = widget.communityComplaints
        .where((c) => !c.isVerifiedBy(widget.userProfile.id) && 
                     c.reporterId != widget.userProfile.id)
        .take(10)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Verify Neighbor Reports',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Help strengthen community reports by verifying noise complaints from your neighbors.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: unverifiedComplaints.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No complaints pending verification'),
                        Text('Check back later for new reports'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: unverifiedComplaints.length,
                    itemBuilder: (context, index) {
                      final complaint = unverifiedComplaints[index];
                      return _buildVerificationCard(complaint);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(NoiseGroup group, bool isJoined) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isJoined)
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${group.memberIds.length} members',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              Text(
                '${group.complaintCount} complaints',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupListTile(NoiseGroup group, bool isJoined) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isJoined ? Colors.green : Colors.blue,
          child: Text(
            group.name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(group.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.description),
            const SizedBox(height: 4),
            Text(
              '${group.memberIds.length} members • ${group.radiusKm.toInt()}km radius',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        trailing: isJoined
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
                onPressed: () => widget.onGroupJoin(group),
                child: const Text('Join'),
              ),
      ),
    );
  }

  Widget _buildComplaintCard(NoiseComplaint complaint) {
    final timeAgo = _getTimeAgo(complaint.timestamp);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue[100],
                  child: Text(
                    'N',
                    style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Neighbor Report',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getNoiseColor(complaint.noiseLevel),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${complaint.noiseLevel.toInt()} dB',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(complaint.description),
            if (complaint.suspectedFlight != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.flight, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Flight: ${complaint.suspectedFlight}',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(complaint.location, style: TextStyle(color: Colors.grey[600]))),
                if (complaint.verificationCount > 0) ...[
                  const Icon(Icons.verified, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    '${complaint.verificationCount} verified',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationCard(NoiseComplaint complaint) {
    final timeAgo = _getTimeAgo(complaint.timestamp);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.orange[100],
                  child: Text(
                    'N',
                    style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Unverified Report',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getNoiseColor(complaint.noiseLevel),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${complaint.noiseLevel.toInt()} dB',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(complaint.description),
            if (complaint.suspectedFlight != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.flight, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Flight: ${complaint.suspectedFlight}',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(complaint.location, style: TextStyle(color: Colors.grey[600]))),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _verifyComplaint(complaint),
                  icon: const Icon(Icons.verified, size: 16),
                  label: const Text('Verify'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _verifyComplaint(NoiseComplaint complaint) {
    widget.onComplaintVerify(complaint);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Complaint verified! This strengthens community advocacy.'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () {
            // Undo functionality could be implemented here
          },
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    double radiusKm = 10.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Noise Group'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Coverage Radius: ${radiusKm.toInt()} km'),
                  Slider(
                    value: radiusKm,
                    min: 5.0,
                    max: 50.0,
                    divisions: 9,
                    onChanged: (value) => setState(() => radiusKm = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && 
                  widget.userProfile.latitude != null &&
                  widget.userProfile.longitude != null) {
                final group = NoiseGroup.create(
                  name: nameController.text,
                  description: descriptionController.text,
                  latitude: widget.userProfile.latitude!,
                  longitude: widget.userProfile.longitude!,
                  radiusKm: radiusKm,
                  creatorId: widget.userProfile.id,
                );
                widget.onGroupCreate(group);
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Group created successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Color _getNoiseColor(double level) {
    if (level < 60) return Colors.green[100]!;
    if (level < 80) return Colors.orange[100]!;
    return Colors.red[100]!;
  }
}

// Analytics Screen
class AnalyticsScreen extends StatelessWidget {
  final List<NoiseComplaint> complaints;
  final UserProfile userProfile;

  const AnalyticsScreen({
    super.key,
    required this.complaints,
    required this.userProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Airport Noise Analytics'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: complaints.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No complaints yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text('Submit airport noise complaints to see analytics'),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    _buildAirportSummary(context),
                    const SizedBox(height: 16),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildChart(),
                    const SizedBox(height: 24),
                    _buildFlightAnalysis(),
                    const SizedBox(height: 24),
                    _buildRecentComplaints(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAirportSummary(BuildContext context) {
    if (userProfile.nearestAirport == null) return const SizedBox();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_airport, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Impact Report',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Airport: ${userProfile.nearestAirport!.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Code: ${userProfile.nearestAirport!.code}'),
            Text('Distance: ${userProfile.nearestAirport!.distanceFromUser.toStringAsFixed(1)} km'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Your ${complaints.length} complaints will be compiled into a monthly report sent to ${userProfile.nearestAirport!.code} airport authority.',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final avgNoiseLevel = complaints.isEmpty
        ? 0.0
        : complaints.map((c) => c.noiseLevel).reduce((a, b) => a + b) / complaints.length;
    
    final maxNoiseLevel = complaints.isEmpty
        ? 0.0
        : complaints.map((c) => c.noiseLevel).reduce((a, b) => a > b ? a : b);

    final complaintsWithFlights = complaints.where((c) => c.suspectedFlight != null).length;

    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Total Reports'),
                  Text(
                    '${complaints.length}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Avg Noise'),
                  Text(
                    '${avgNoiseLevel.toStringAsFixed(1)} dB',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Flight ID\'d'),
                  Text(
                    '$complaintsWithFlights',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Noise Levels Over Time',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: complaints.isEmpty
                  ? const Center(child: Text('No data to display'))
                  : CustomPaint(
                      painter: NoiseChartPainter(complaints),
                      size: const Size(double.infinity, 200),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlightAnalysis() {
    final identifiedFlights = complaints
        .where((c) => c.suspectedFlight != null)
        .map((c) => c.suspectedFlight!)
        .toList();

    final flightCounts = <String, int>{};
    for (final flight in identifiedFlights) {
      flightCounts[flight] = (flightCounts[flight] ?? 0) + 1;
    }

    final sortedFlights = flightCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Most Reported Flights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (sortedFlights.isEmpty)
              const Text('No flights identified yet')
            else
              ...sortedFlights.take(5).map((entry) => ListTile(
                leading: const Icon(Icons.flight, color: Colors.blue),
                title: Text(entry.key),
                trailing: Text('${entry.value} reports'),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentComplaints() {
    final recentComplaints = complaints.take(5).toList();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Complaints',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (recentComplaints.isEmpty)
              const Text('No complaints yet')
            else
              ...recentComplaints.map((complaint) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red[100],
                  child: Text('${complaint.noiseLevel.toInt()}'),
                ),
                title: Text(complaint.location),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(complaint.description),
                    if (complaint.suspectedFlight != null)
                      Text('Flight: ${complaint.suspectedFlight}',
                          style: const TextStyle(color: Colors.blue)),
                  ],
                ),
                trailing: Text(
                  '${complaint.timestamp.hour}:${complaint.timestamp.minute.toString().padLeft(2, '0')}',
                ),
              )),
          ],
        ),
      ),
    );
  }
}

class NoiseChartPainter extends CustomPainter {
  final List<NoiseComplaint> complaints;

  NoiseChartPainter(this.complaints);

  @override
  void paint(Canvas canvas, Size size) {
    if (complaints.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final maxNoise = complaints.map((c) => c.noiseLevel).reduce((a, b) => a > b ? a : b);
    final minNoise = complaints.map((c) => c.noiseLevel).reduce((a, b) => a < b ? a : b);
    final range = maxNoise - minNoise;

    if (range == 0) return;

    for (int i = 0; i < complaints.length; i++) {
      final x = (i / (complaints.length - 1)) * size.width;
      final y = size.height - ((complaints[i].noiseLevel - minNoise) / range) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      final color = complaints[i].suspectedFlight != null ? Colors.red : Colors.blue;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Settings Screen
class SettingsScreen extends StatefulWidget {
  final UserProfile userProfile;
  final Function(UserProfile) onProfileUpdate;

  const SettingsScreen({
    super.key,
    required this.userProfile,
    required this.onProfileUpdate,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userProfile.name);
    _emailController = TextEditingController(text: widget.userProfile.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final updatedProfile = UserProfile(
      name: _nameController.text,
      email: _emailController.text,
      notificationsEnabled: widget.userProfile.notificationsEnabled,
      darkMode: widget.userProfile.darkMode,
      latitude: widget.userProfile.latitude,
      longitude: widget.userProfile.longitude,
      nearestAirport: widget.userProfile.nearestAirport,
      id: widget.userProfile.id,
      joinedAt: widget.userProfile.joinedAt,
      groupIds: widget.userProfile.groupIds,
    );
    widget.onProfileUpdate(updatedProfile);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              const Text(
                'Profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          child: const Text('Save Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              if (widget.userProfile.nearestAirport != null) ...[
                const Text(
                  'Airport Information',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.local_airport),
                          title: Text(widget.userProfile.nearestAirport!.name),
                          subtitle: Text('Code: ${widget.userProfile.nearestAirport!.code}'),
                        ),
                        Text('Distance: ${widget.userProfile.nearestAirport!.distanceFromUser.toStringAsFixed(1)} km'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Complaints are automatically attributed to this airport based on your location.',
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              
              const Text(
                'App Preferences',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Push Notifications'),
                      subtitle: const Text('Noise level alerts and flight updates'),
                      value: widget.userProfile.notificationsEnabled,
                      onChanged: (value) {
                        final updatedProfile = UserProfile(
                          name: widget.userProfile.name,
                          email: widget.userProfile.email,
                          notificationsEnabled: value,
                          darkMode: widget.userProfile.darkMode,
                          latitude: widget.userProfile.latitude,
                          longitude: widget.userProfile.longitude,
                          nearestAirport: widget.userProfile.nearestAirport,
                          id: widget.userProfile.id,
                          joinedAt: widget.userProfile.joinedAt,
                          groupIds: widget.userProfile.groupIds,
                        );
                        widget.onProfileUpdate(updatedProfile);
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Dark Mode'),
                      subtitle: const Text('Use dark theme'),
                      value: widget.userProfile.darkMode,
                      onChanged: (value) {
                        final updatedProfile = UserProfile(
                          name: widget.userProfile.name,
                          email: widget.userProfile.email,
                          notificationsEnabled: widget.userProfile.notificationsEnabled,
                          darkMode: value,
                          latitude: widget.userProfile.latitude,
                          longitude: widget.userProfile.longitude,
                          nearestAirport: widget.userProfile.nearestAirport,
                          id: widget.userProfile.id,
                          joinedAt: widget.userProfile.joinedAt,
                          groupIds: widget.userProfile.groupIds,
                        );
                        widget.onProfileUpdate(updatedProfile);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              const Text(
                'About',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Airport Noise Tracker',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('Version 1.0.0'),
                      const SizedBox(height: 16),
                      const Text(
                        'This app helps communities near airports track and report noise pollution. Your complaints contribute to advocacy efforts for quieter flight operations.',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Features:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('• Real-time noise level monitoring'),
                      const Text('• Live flight tracking'),
                      const Text('• Community networking'),
                      const Text('• Automatic airport detection'),
                      const Text('• Complaint attribution to flights'),
                      const Text('• Analytics and reporting'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}