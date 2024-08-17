import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool firebaseInitialized = true;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    firebaseInitialized = false;
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  Future<void> loadAndSaveEvents(BuildContext context) async {
    try {
      // Reference to the text file in Firebase Storage
      Reference storageRef = FirebaseStorage.instance.ref().child('events/events.json.txt');

      // Download the text file content
      String downloadURL = await storageRef.getDownloadURL();
      final response = await http.get(Uri.parse(downloadURL));
      String fileContent = response.body;

      // Parse the file content to extract events
      List<Map<String, dynamic>> events = parseEvents(fileContent);

      // Save the events to Firestore
      await saveEventsToFirestore(events, context);

      // Show a message when events are loaded and saved
      print('Events loaded and saved to Firestore');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Events loaded and saved to Firestore')));
    } catch (e) {
      print('Error loading events: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading events: $e')));
    }
  }

  List<Map<String, dynamic>> parseEvents(String fileContent) {
    try {
      // Parse the entire file content as a JSON array
      List<dynamic> jsonArray = json.decode(fileContent);

      // Convert the list of dynamic to a list of maps
      List<Map<String, dynamic>> events = jsonArray.map((item) => item as Map<String, dynamic>).toList();

      return events;
    } catch (e) {
      print('Error parsing JSON: $e');
      return [];
    }
  }

  Future<void> saveEventsToFirestore(List<Map<String, dynamic>> events, BuildContext context) async {
    CollectionReference eventsRef = FirebaseFirestore.instance.collection('event information');

    // Fetch the highest existing ID from document IDs
    QuerySnapshot querySnapshot = await eventsRef.orderBy(FieldPath.documentId, descending: true).limit(1).get();
    int highestId = 0;
    if (querySnapshot.docs.isNotEmpty) {
      DocumentSnapshot doc = querySnapshot.docs.first;
      String idString = doc.id; // Get the document ID
      highestId = int.tryParse(idString) ?? 0; // Convert to integer
    }

    // Add new events with incremented IDs and set document ID
    for (Map<String, dynamic> event in events) {
      String name = event['name'] ?? '';
      String address = event['address'] ?? '';

      // Check for existing event with the same name and address
      QuerySnapshot existingEventsQuery = await eventsRef
          .where('name', isEqualTo: name)
          .where('address', isEqualTo: address)
          .get();

      if (existingEventsQuery.docs.isEmpty) {
        // No duplicate found, proceed to add the event
        highestId++;
        String newId = highestId.toString().padLeft(5, '0'); // New document ID with leading zeros
        event['eventId'] = newId; // Set the new ID as a field

        // Add the event with the new ID as the document ID
        try {
          await eventsRef.doc(newId).set(event);
        } catch (e) {
          print('Error saving event $newId: $e');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving event $newId: $e')));
        }
      } else {
        print('Duplicate event found and skipped: $name, $address');
      }
    }
  }

  Future<void> reviewCheck(BuildContext context) async {
    CollectionReference eventsRef = FirebaseFirestore.instance.collection('information');

    try {
      // Fetch all event documents
      QuerySnapshot eventsSnapshot = await eventsRef.get();

      // Check reviews for each event
      for (DocumentSnapshot eventDoc in eventsSnapshot.docs) {
        String eventId = eventDoc.id;
        await reviewCheckForEvent(eventId, context);
      }
    } catch (e) {
      print('Error fetching events for review check: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching events for review check: $e')));
    }
  }

  Future<void> reviewCheckForEvent(String eventId, BuildContext context) async {
    CollectionReference eventsRef = FirebaseFirestore.instance.collection('information');
    CollectionReference reviewsRef = eventsRef.doc(eventId).collection('reviews');

    try {
      // Fetch the event document to see if it exists
      DocumentSnapshot eventDoc = await eventsRef.doc(eventId).get();

      if (!eventDoc.exists) {
        // The event document does not exist, log and exit the function
        print('Event document with ID $eventId does not exist. No updates will be made.');
        return;
      }

      // If the event document exists, fetch reviews for the given event ID
      QuerySnapshot reviewsSnapshot = await reviewsRef.get();

      // Calculate the total number of reviews and total rating
      int reviewCount = reviewsSnapshot.size;
      double totalRating = reviewsSnapshot.docs.fold(0.0, (sum, doc) {
        return sum + (doc['rating'] ?? 0.0);
      });

      // Calculate the average rating
      double calculatedAverageRating = reviewCount > 0 ? totalRating / reviewCount : 0.0;

      // Print review information
      print('Event $eventId: Review count = $reviewCount, Total rating = $totalRating, Calculated average rating = $calculatedAverageRating');

      // Retrieve the event data
      Map<String, dynamic> eventData = eventDoc.data() as Map<String, dynamic>;

      // Update the event if the stored values are incorrect
      if (eventData['reviewCount'] != reviewCount || eventData['totalRating'] != totalRating || eventData['rating'] != calculatedAverageRating) {
        await eventsRef.doc(eventId).update({
          'reviewCount': reviewCount,
          'totalRating': totalRating,
          'rating': calculatedAverageRating,
        });
        print('Updated event $eventId with correct review count, total rating, and average rating.');
      } else {
        print('Event $eventId already has the correct review count, total rating, and average rating.');
      }

    } catch (e) {
      print('Error fetching reviews for event $eventId: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching reviews for event $eventId: $e')));
    }
  }

  Future<void> loadApprovedSuggestions(BuildContext context) async {
    try {
      CollectionReference suggestionsRef = FirebaseFirestore.instance.collection('user suggestions');
      CollectionReference eventsRef = FirebaseFirestore.instance.collection('event information');

      // Fetch suggestions where approved is 1
      QuerySnapshot approvedSuggestionsSnapshot = await suggestionsRef.where('approved', isEqualTo: 1).get();
      // Fetch suggestions where approved is 2 to delete them
      QuerySnapshot deleteSuggestionsSnapshot = await suggestionsRef.where('approved', isEqualTo: 2).get();

      // Delete documents with approved field 2
      for (DocumentSnapshot deleteDoc in deleteSuggestionsSnapshot.docs) {
        await suggestionsRef.doc(deleteDoc.id).delete();
        print('Deleted user suggestion document with ID ${deleteDoc.id} due to approved field being 2.');
      }

      if (approvedSuggestionsSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No approved suggestions found.')));
        return;
      }

      // Fetch the highest existing event ID from the event information collection
      QuerySnapshot querySnapshot = await eventsRef.orderBy(FieldPath.documentId, descending: true).limit(1).get();
      int highestId = 0;
      if (querySnapshot.docs.isNotEmpty) {
        DocumentSnapshot doc = querySnapshot.docs.first;
        String idString = doc.id;
        highestId = int.tryParse(idString) ?? 0;
      }

      // Process each approved suggestion
      for (DocumentSnapshot suggestionDoc in approvedSuggestionsSnapshot.docs) {
        Map<String, dynamic> suggestionData = suggestionDoc.data() as Map<String, dynamic>;

        // Increment the event ID
        highestId++;
        String newEventId = highestId.toString().padLeft(5, '0');

        // Calculate coordinates based on the address
        List<Location> locations = await locationFromAddress(suggestionData['address']);
        double latitude = locations.first.latitude;
        double longitude = locations.first.longitude;

        // Prepare the event data to save
        Map<String, dynamic> eventData = {
          'name': suggestionData['name'],
          'address': suggestionData['address'],
          'type': suggestionData['type'],
          'openingTime': suggestionData['openingTime'],
          'closingTime': suggestionData['closingTime'],
          'latitude': latitude,
          'longitude': longitude,
          'rating': 0,
          'reviewCount': 0,
          'totalRating': 0,
          'eventId': newEventId,
          'clickCount': 0,
          'link': '',
          'description': '',
        };

        // Save the event data to Firestore
        await eventsRef.doc(newEventId).set(eventData);

        // Optionally, remove the approved suggestion after processing
        await suggestionsRef.doc(suggestionDoc.id).delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approved suggestions loaded successfully.')));
    } catch (e) {
      print('Error loading approved suggestions: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading approved suggestions: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Event Manager'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () => loadAndSaveEvents(context),
              child: Text('Load Events from File'),
            ),
            ElevatedButton(
              onPressed: () => reviewCheck(context),
              child: Text('Review Check'),
            ),
            ElevatedButton(
              onPressed: () => loadApprovedSuggestions(context),
              child: Text('Load Approved Suggestions'),
            ),
          ],
        ),
      ),
    );
  }
}
