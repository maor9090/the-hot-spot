import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math' as math;
import 'auth_service.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'personalPage.dart';
import 'utils.dart';
import 'event.dart';
import 'themes.dart';
import 'event_suggestion.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool firebaseInitialized = true;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseInitialized = false;
  }
  runApp(MyApp(firebaseInitialized: firebaseInitialized));
}

class MyApp extends StatefulWidget {
  final bool firebaseInitialized;

  const MyApp({super.key, required this.firebaseInitialized});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false;

  void toggleDarkMode(bool value) {
    setState(() {
      isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: isDarkMode ? darkTheme : lightTheme,
      home: widget.firebaseInitialized ? MyHomePage(onThemeChanged: toggleDarkMode) : const FirebaseErrorPage(),
    );
  }
}

class FirebaseErrorPage extends StatelessWidget {
  const FirebaseErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error'),
      ),
      body: const Center(
        child: Text('Failed to initialize Firebase.'),
      ),
    );
  }
}



TextSpan getStatus(Event event,bool isDarkMode) {
  String statusText = event.isOpenNow() ? 'open' : 'closed';
  String openingTime = formatTimeOfDay(event.openingTime);
  String closingTime = formatTimeOfDay(event.closingTime);

  TextSpan statusSpan = TextSpan(
    text: statusText,
    style: TextStyle(
      color: event.isOpenNow() ? Colors.green : Colors.red,
    ),
  );
  Color timeSpanColor = isDarkMode ? Colors.white : Colors.black;
  TextSpan timeSpan = TextSpan(
    text: event.isOpenNow()
        ? ' - closes at $closingTime'
        : ' - open at $openingTime',
    style: TextStyle(color: timeSpanColor),
  );

  return TextSpan(
    children: [statusSpan, timeSpan],
  );
}

String formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
Future<void> getTimeMessage(DateTime dateTime) async {
  final year = dateTime.year;
  final dayOfWeek = DateFormat('EEEE').format(dateTime).toLowerCase();

  final holidays = await fetchHolidays(year);
  final holidayDates = holidays.map((date) {
    final dateObj = DateTime.parse(date);
    return DateFormat('EEEE').format(dateObj).toLowerCase();
  }).toSet();

  String message;
  if (dayOfWeek == 'friday' || dayOfWeek == 'saturday' || holidayDates.contains(dayOfWeek)) {
    message = 'Time may differ on weekends and holidays';
  } else {
    message = '';
  }


  // Write to Firestore with the document ID "TimeMessage", overwrite the old document
  await FirebaseFirestore.instance.collection('events').doc('TimeMessage').set({
    'message': message,
    'timestamp': FieldValue.serverTimestamp(),
  });
}
Future<String> checkAndRetrieveTimeMessage() async {
  final today = DateTime.now();
  final todayDate = DateFormat('yyyy-MM-dd').format(today);

  final doc = await FirebaseFirestore.instance.collection('events').doc('TimeMessage').get();

  if (doc.exists) {
    final timestamp = (doc.data()?['timestamp'] as Timestamp?)?.toDate();
    final docDate = timestamp != null ? DateFormat('yyyy-MM-dd').format(timestamp) : null;

    if (docDate == todayDate) {
      // Document is up-to-date, return the existing message
      return doc.data()?['message'] ?? '';
    } else {
      // Document is outdated, update it by calling getTimeMessage
      await getTimeMessage(today);
      return await checkAndRetrieveTimeMessage(); // Recursive call to retrieve the updated message
    }
  } else {
    // Document doesn't exist, create it by calling getTimeMessage
    await getTimeMessage(today);
    return await checkAndRetrieveTimeMessage(); // Recursive call to retrieve the newly created message
  }
}
class MyHomePage extends StatefulWidget {
  final void Function(bool) onThemeChanged;
  const MyHomePage({super.key, required this.onThemeChanged});

  static Position? currentPosition;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  void toggleDarkMode(bool value) {
    setState(() {
      isDarkMode = value;
    });
    if (value) {
      ThemeData currentTheme = darkTheme;
    } else {
      ThemeData currentTheme = lightTheme;
    }
  }
  final timeMessage=checkAndRetrieveTimeMessage();
  bool isDarkMode = DateTime.now().hour >= 19||DateTime.now().hour<6;
  final AuthService _authService = AuthService();
  final TextEditingController _complaintController = TextEditingController();
  String _selectedOption = 'Featured';
  Timer? timer;
  late DateTime currentDate;
  bool showWelcomeMessage = true;
  bool showPartyInfo = false;
  bool showBarInfo = false;
  bool showBilliardInfo = false;
  bool showEscapeRoomsInfo = false;
  bool showBowlingInfo = false;
  bool showSettings = false;
  double distanceValue = 100;
  bool showError = false;
  String errorMessage = '';
  List<Event> randomEvents = [];
  User? _currentUser;

  List<EventType> showTime=[EventType.escapeRooms,EventType.bowling,EventType.bar,EventType.billiard];

  List<Event> partyEvents = [];
  List<Event> barEvents = [];
  List<Event> billiardEvents = [];
  List<Event> escpaeRoomsEvents = [];
  List<Event> bowlingEvents = [];

  @override
  void initState() {
    super.initState();
    currentDate = DateTime.now();
    timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        currentDate = DateTime.now();
      });
    });

    Timer(const Duration(seconds: 4), () {
      widget.onThemeChanged(isDarkMode);
      setState(() {
        showWelcomeMessage = false;
        _selectRandomInfo();
        _sortEventsByDistance(randomEvents); //incase of await remove
      });
    });
    _initializeApp();

    // Automatically sign in the user with Google
    _authService.signInWithGoogle().then((user) {
      setState(() {
        _currentUser = user;
        if (user == null) {}
      });
    }).catchError((error) {
      print('Error signing in: $error');
      setState(() {
        showError = true;
        errorMessage = 'Error signing in: $error';
      });
    });
  }

  Future<void> _initializeApp() async {
    _getCurrentLocation();
    //_sortEventsByDistance(randomEvents); incase of await remove the //

    _fetchEventsFromFirestore();

    // Automatically sign in the user with Google
    _authService.signInWithGoogle().then((user) {
      setState(() {
        _currentUser = user;
        if (user == null) {}
      });
    }).catchError((error) {
      print('Error signing in: $error');
      setState(() {
        showError = true;
        errorMessage = 'Error signing in: $error';
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _complaintController.dispose();
    super.dispose();
  }

  void _submitComplaint() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to submit a complaint')),
      );
      return;
    }

    String complaint = _complaintController.text;
    if (complaint.isNotEmpty) {
      try {
        final userId = _currentUser!.uid;
        final now = DateTime.now().toLocal();
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay =
        DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

        final querySnapshot = await FirebaseFirestore.instance
            .collection('events')
            .doc('complaints')
            .collection('complains')
            .where('userId', isEqualTo: userId)
            .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

        if (querySnapshot.docs.isEmpty) {
          // Get the highest existing document ID
          final docsSnapshot = await FirebaseFirestore.instance
              .collection('events')
              .doc('complaints')
              .collection('complains')
              .orderBy(FieldPath.documentId, descending: true)
              .limit(1)
              .get();

          int highestId = 0;
          if (docsSnapshot.docs.isNotEmpty) {
            String lastDocId = docsSnapshot.docs.first.id;
            highestId = int.tryParse(lastDocId) ?? 0;
          }

          // Increment to get the new document ID
          highestId++;
          String newDocId = highestId.toString().padLeft(5, '0'); // Format as 00001, 00002, etc.

          // Add the complaint with the new document ID
          await FirebaseFirestore.instance
              .collection('events')
              .doc('complaints')
              .collection('complains')
              .doc(newDocId)
              .set({
            'complaint': complaint,
            'userId': userId,
            'timestamp': Timestamp.fromDate(now),
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complaint submitted successfully')),
          );
          _complaintController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('You have already submitted a complaint today.')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit complaint: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a complaint')),
      );
    }
  }


  List<Event> _sortEventsByDistance(List<Event> events) {
    events.sort((a, b) {
      double distanceA = _calculateDistance(a.position);
      double distanceB = _calculateDistance(b.position);
      return distanceA.compareTo(distanceB);
    });
    return events;
  }

  Future<void> _fetchEventsFromFirestore() async {
    try {
      // Reference to the Firestore collection
      final eventsCollection =
      FirebaseFirestore.instance.collection('event information');
      final snapshot = await eventsCollection.get();

      if (snapshot.docs.isNotEmpty) {
        // Convert the documents to a list of Event objects
        List<Event> fetchedEvents = snapshot.docs.map((doc) {
          // Use the document data to create an Event instance
          return Event.fromJson(doc.data(), doc.id);
        }).toList();

        // Filter out events with dates that have already passed
        List<Event> upcomingEvents = fetchedEvents
            .toList();
        List<Event> upcomingEventsPartys = fetchedEvents
            .where((event) => event.date.isAfter(DateTime.now()))
            .toList();

        setState(() {
          // Separate the events based on their type
          partyEvents = upcomingEventsPartys
              .where((event) => event.type == EventType.party)
              .toList();
          barEvents = upcomingEvents
              .where((event) => event.type == EventType.bar)
              .toList();
          billiardEvents = upcomingEvents
              .where((event) => event.type == EventType.billiard)
              .toList();
          escpaeRoomsEvents = upcomingEvents
              .where((event) => event.type == EventType.escapeRooms)
              .toList();
          bowlingEvents = upcomingEvents
              .where((event) => event.type == EventType.bowling)
              .toList();
        });
      } else {
        setState(() {
          showError = true;
          errorMessage = 'No events found.';
        });
      }
    } catch (e) {
      setState(() {
        showError = true;
        errorMessage = 'Failed to load events: $e';
      });
    }
  }


  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        showError = true;
        errorMessage = 'Location services are disabled.';
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          showError = true;
          errorMessage = 'Location permissions are denied.';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        showError = true;
        errorMessage = 'Location permissions are permanently denied.';
      });
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        MyHomePage.currentPosition = position;
      });
    } catch (e) {
      setState(() {
        showError = true;
        errorMessage = 'Failed to get current location: $e';
      });
    }
  }

  void _selectOption(String option) {
    setState(() {
      _selectedOption = option;
      showWelcomeMessage = false;
      showPartyInfo = _selectedOption == 'Parties';
      showEscapeRoomsInfo = _selectedOption == 'Escape rooms';
      showBarInfo =_selectedOption=='Bars';
      showBilliardInfo= _selectedOption=='Billiards';
      showBowlingInfo = _selectedOption == 'Bowling';
      showSettings = _selectedOption == 'Settings';
    });

    if (option == 'Featured') {
      _resetToHomePage();
    }
  }

  void _resetToHomePage() {
    setState(() {
      _selectedOption = 'Featured';
      showWelcomeMessage = false;
      showPartyInfo = false;
      showBarInfo=false;
      showBilliardInfo=false;
      showEscapeRoomsInfo = false;
      showBowlingInfo = false;
      showSettings = false;
      _selectRandomInfo();
      _sortEventsByDistance(randomEvents);
    });
  }

  void _selectRandomInfo() {
    final random = math.Random();
    randomEvents = [];

    if (partyEvents.isNotEmpty) {
      Event randomPartyEvent = partyEvents[random.nextInt(partyEvents.length)];
      randomEvents.add(randomPartyEvent);
    }

    if (escpaeRoomsEvents.isNotEmpty) {
      Event randomFunAndGamesEvent =
          escpaeRoomsEvents[random.nextInt(escpaeRoomsEvents.length)];
      randomEvents.add(randomFunAndGamesEvent);
    }

    if (bowlingEvents.isNotEmpty) {
      Event randomBowlingEvent =
          bowlingEvents[random.nextInt(bowlingEvents.length)];
      randomEvents.add(randomBowlingEvent);
    }
    if (barEvents.isNotEmpty) {
      Event randomBarEvent =
      barEvents[random.nextInt(barEvents.length)];
      randomEvents.add(randomBarEvent);
    }
    if (billiardEvents.isNotEmpty) {
      Event randomBilliardEvent =
      billiardEvents[random.nextInt(billiardEvents.length)];
      randomEvents.add(randomBilliardEvent);
    }
    setState(() {
      showPartyInfo = false;
      showBarInfo = false;
      showBilliardInfo=false;
      showEscapeRoomsInfo = false;
      showBowlingInfo = false;
      showSettings = false;
    });
  }

  double _calculateDistance(Position eventPosition) {
    if (MyHomePage.currentPosition == null) {
      return 0.0;
    }
    return Geolocator.distanceBetween(
      MyHomePage.currentPosition!.latitude,
      MyHomePage.currentPosition!.longitude,
      eventPosition.latitude,
      eventPosition.longitude,
    );
  }

  List<Event> _filterEventsByDistance(List<Event> events) {
    if (distanceValue == 0 || MyHomePage.currentPosition == null) {
      return events;
    }
    return events.where((event) {
      double distance = _calculateDistance(event.position) / 1000;
      return distance <= distanceValue;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate =
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

    return Scaffold(
      appBar: AppBar(
        title:Text('${_selectedOption}'),
        actions: <Widget>[
          if (!showWelcomeMessage)
            PopupMenuButton<String>(
              onSelected: _selectOption,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'Featured',
                  child: Text('Return to Featured'),
                ),
                const PopupMenuItem<String>(
                  value: 'Parties',
                  child: Text('Parties'),
                ),
                const PopupMenuItem<String>(
                  value: 'Bars',
                  child: Text('Bars'),
                ),
                const PopupMenuItem<String>(
                  value: 'Billiards',
                  child: Text('Billiards'),
                ),
                const PopupMenuItem<String>(
                  value: 'Escape rooms',
                  child: Text('Escape rooms'),
                ),
                const PopupMenuItem<String>(
                  value: 'Bowling',
                  child: Text('Bowling'),
                ),
                const PopupMenuItem<String>(
                  value: 'Settings',
                  child: Text('Settings'),
                ),
              ],
            ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (showSettings) _buildSettings(),
          if (!showSettings &&
              !showPartyInfo &&
              !showEscapeRoomsInfo &&
              !showBarInfo &&
              !showBilliardInfo &&
              !showBowlingInfo)
            Column(
              children: [
                if (showWelcomeMessage)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Welcome! Current Date: $formattedDate',
                      style: const TextStyle(
                        fontSize: 18,
                      ),
                    ),
                  ),
                if (showError)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                      ),
                    ),
                  ),
                if (!showWelcomeMessage && !showError)
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Current Date: $formattedDate',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: randomEvents.length,
                            itemBuilder: (context, index) {
                              Event event = randomEvents[index];
                              double distance = _calculateDistance(event.position) / 1000;

                              return ListTile(
                                title: Text(
                                  event.name,
                                  style: const TextStyle(),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rating: ${event.rating}/5, ${event.reviewCount} reviews',
                                      style: const TextStyle(),
                                    ),
                                    if (!showTime.contains(event.type))
                                      Text(
                                        'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(event.date)}',
                                        style: const TextStyle(),
                                      ),
                                    if (showTime.contains(event.type) && getStatusBool(event) == 'open')
                                      FutureBuilder<String>(
                                        future: timeMessage, // Fetch time message
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return const Text('Loading...'); // Placeholder while loading
                                          } else if (snapshot.hasError) {
                                            return Text('Error: ${snapshot.error}'); // Error handling
                                          } else if (snapshot.hasData) {
                                            return Row(
                                              children: [
                                                RichText(
                                                  text: getStatus(event, isDarkMode),
                                                ),
                                                const SizedBox(width: 8.0), // Adjust spacing between RichText and Text
                                                Text(
                                                  snapshot.data!,
                                                  style: TextStyle(color: Colors.yellow[700], fontSize: 10.0), // Adjust style as needed
                                                ),
                                              ],
                                            );
                                          } else {
                                            return const SizedBox.shrink(); // Empty widget if no data
                                          }
                                        },
                                      ),
                                    if (showTime.contains(event.type) && getStatusBool(event) == 'closed')
                                      FutureBuilder<String>(
                                        future: timeMessage, // Fetch time message
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return const Text('Loading...'); // Placeholder while loading
                                          } else if (snapshot.hasError) {
                                            return Text('Error: ${snapshot.error}'); // Error handling
                                          } else if (snapshot.hasData) {
                                            return Row(
                                              children: [
                                                RichText(
                                                  text: getStatus(event, isDarkMode),
                                                ),
                                                const SizedBox(width: 8.0), // Adjust spacing between RichText and Text
                                                Text(
                                                  snapshot.data!,
                                                  style: TextStyle(color: Colors.yellow[700], fontSize: 10.0), // Adjust style as needed
                                                ),
                                              ],
                                            );
                                          } else {
                                            return const SizedBox.shrink(); // Empty widget if no data
                                          }
                                        },
                                      ),
                                    Text(
                                      'Distance: ${distance.toStringAsFixed(2)} km',
                                      style: const TextStyle(),
                                    ),
                                    Text(
                                      'Address: ${event.address}',
                                      style: const TextStyle(),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        final url = Uri.parse(event.link);
                                        if (await canLaunchUrl(url)) {
                                          await launchURL(context, url, event);
                                        } else {
                                          throw 'Could not launch $url';
                                        }
                                      },
                                      child: const Text(
                                        'Web: Click here',
                                        style: TextStyle(color: Colors.blue),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EventDetailPage(
                                        event: event,
                                        isDarkMode: isDarkMode,
                                        showTime: showTime,
                                        timeMessage: timeMessage,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (showPartyInfo || showEscapeRoomsInfo || showBowlingInfo || showBarInfo || showBilliardInfo)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Current Date: $formattedDate',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _getCurrentEventList().length,
                    itemBuilder: (context, index) {
                      Event event = _getCurrentEventList()[index];
                      double distance = _calculateDistance(event.position) / 1000;

                      return ListTile(
                        title: Text(
                          event.name,
                          style: const TextStyle(),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rating: ${event.rating}/5, ${event.reviewCount} reviews',
                              style: const TextStyle(),
                            ),
                            if (!showTime.contains(event.type))
                              Text(
                                'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(event.date)}',
                                style: const TextStyle(),
                              ),
                            if (showTime.contains(event.type) && getStatusBool(event) == 'open')
                              FutureBuilder<String>(
                                future: timeMessage, // Fetch time message
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Text('Loading...'); // Placeholder while loading
                                  } else if (snapshot.hasError) {
                                    return Text('Error: ${snapshot.error}'); // Error handling
                                  } else if (snapshot.hasData) {
                                    return Row(
                                      children: [
                                        RichText(
                                          text: getStatus(event, isDarkMode),
                                        ),
                                        const SizedBox(width: 8.0), // Adjust spacing between RichText and Text
                                        Text(
                                          snapshot.data!,
                                          style: TextStyle(color: Colors.yellow[700], fontSize: 10.0), // Adjust style as needed
                                        ),
                                      ],
                                    );
                                  } else {
                                    return const SizedBox.shrink(); // Empty widget if no data
                                  }
                                },
                              ),
                            if (showTime.contains(event.type) && getStatusBool(event) == 'closed')
                              FutureBuilder<String>(
                                future: timeMessage, // Fetch time message
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Text('Loading...'); // Placeholder while loading
                                  } else if (snapshot.hasError) {
                                    return Text('Error: ${snapshot.error}'); // Error handling
                                  } else if (snapshot.hasData) {
                                    return Row(
                                      children: [
                                        RichText(
                                          text: getStatus(event, isDarkMode),
                                        ),
                                        const SizedBox(width: 8.0), // Adjust spacing between RichText and Text
                                        Text(
                                          snapshot.data!,
                                          style: TextStyle(color: Colors.yellow[700], fontSize: 10.0), // Adjust style as needed
                                        ),
                                      ],
                                    );
                                  } else {
                                    return const SizedBox.shrink(); // Empty widget if no data
                                  }
                                },
                              ),
                            Text(
                              'Distance: ${distance.toStringAsFixed(2)} km',
                              style: const TextStyle(),
                            ),
                            Text(
                              'Address: ${event.address}',
                              style: const TextStyle(),
                            ),
                            InkWell(
                              onTap: () async {
                                final url = Uri.parse(event.link);
                                if (await canLaunchUrl(url)) {
                                  await launchURL(context, url, event);
                                } else {
                                  throw 'Could not launch $url';
                                }
                              },
                              child: const Text(
                                'Web: Click here',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EventDetailPage(
                                event: event,
                                isDarkMode: isDarkMode,
                                showTime: showTime,
                                timeMessage: timeMessage,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),

    );
  }

  Widget _buildSettings() {

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text('Adjust your preferences below:'),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Distance Filter (km):'),
            Expanded(
              child: Slider(
                value: distanceValue,
                min: 0,
                max: 100,
                onChanged: (value) {
                  setState(() {
                    distanceValue = value;
                  });
                },
              ),
            ),
            Text(distanceValue.toStringAsFixed(0)),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Dark Mode:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Enable Dark Mode'),
          value: isDarkMode,
          onChanged: (bool value) {
            setState(() {
              isDarkMode = value;
              widget.onThemeChanged(isDarkMode);
              // You can use a callback or a state management solution here to apply the dark mode to the entire app
            });
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Submit a Complaint:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _complaintController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter your complaint here...',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _submitComplaint,
          child: const Text('Submit Complaint'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SuggestLocationPage()),
            );
          },
          child: const Text('Suggest a Location'),
        ),
      ],
    );
  }


  List<Event> _getCurrentEventList() {
    if (showPartyInfo) {
      partyEvents = _sortEventsByDistance(partyEvents);
      return _filterEventsByDistance(partyEvents);
    } else if(showBarInfo){
      barEvents = _sortEventsByDistance(barEvents);
      return _filterEventsByDistance(barEvents);
    } else if(showBilliardInfo) {
      billiardEvents = _sortEventsByDistance(billiardEvents);
      return _filterEventsByDistance(billiardEvents);
    }else if (showEscapeRoomsInfo) {
      escpaeRoomsEvents = _sortEventsByDistance(escpaeRoomsEvents);
      return _filterEventsByDistance(escpaeRoomsEvents);
    } else if (showBowlingInfo) {
      bowlingEvents = _sortEventsByDistance(bowlingEvents);
      return _filterEventsByDistance(bowlingEvents);
    }
    return [];
  }
}


