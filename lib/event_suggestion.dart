import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';  // Import FirebaseAuth for user identification
import 'event.dart';

class SuggestLocationPage extends StatefulWidget {
  @override
  _SuggestLocationPageState createState() => _SuggestLocationPageState();
}

class _SuggestLocationPageState extends State<SuggestLocationPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _openingTimeController = TextEditingController();
  final TextEditingController _closingTimeController = TextEditingController();
  EventType? _selectedType;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (pickedTime != null) {
      final String formattedTime = pickedTime.format(context);
      controller.text = formattedTime;
    }
  }

  void _submitSuggestion() async {
    if (_nameController.text.isEmpty ||
        _addressController.text.isEmpty ||
        _selectedType == null ||
        _openingTimeController.text.isEmpty ||
        _closingTimeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields before submitting')),
      );
      return;
    }

    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to submit a suggestion')),
      );
      return;
    }

    try {
      final userId = _currentUser!.uid;
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

      CollectionReference suggestionsRef = FirebaseFirestore.instance.collection('user suggestions');

      // Check if the user has already submitted a suggestion this week
      QuerySnapshot querySnapshot = await suggestionsRef
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have already submitted a suggestion this week.')),
        );
        return;
      }

      // Fetch the highest existing document ID
      querySnapshot = await suggestionsRef.orderBy(FieldPath.documentId, descending: true).limit(1).get();
      int highestId = 0;
      if (querySnapshot.docs.isNotEmpty) {
        DocumentSnapshot doc = querySnapshot.docs.first;
        String idString = doc.id;
        highestId = int.tryParse(idString) ?? 0;
      }

      highestId++;
      String newId = highestId.toString().padLeft(5, '0');

      await suggestionsRef.doc(newId).set({
        'name': _nameController.text,
        'address': _addressController.text,
        'type': _selectedType.toString().split('.').last,
        'openingTime': _openingTimeController.text,
        'closingTime': _closingTimeController.text,
        'timestamp': Timestamp.now(),
        'userId': userId,
        'approved': 0,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location suggestion submitted successfully')),
      );

      // Clear the form after submission
      _nameController.clear();
      _addressController.clear();
      _openingTimeController.clear();
      _closingTimeController.clear();
      setState(() {
        _selectedType = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit suggestion: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Suggest a Location'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(labelText: 'Address'),
            ),
            DropdownButtonFormField<EventType>(
              value: _selectedType,
              onChanged: (EventType? newValue) {
                setState(() {
                  _selectedType = newValue;
                });
              },
              items: EventType.values.map((EventType type) {
                return DropdownMenuItem<EventType>(
                  value: type,
                  child: Text(type.toString().split('.').last),
                );
              }).toList(),
              decoration: InputDecoration(labelText: 'Event Type'),
            ),
            TextField(
              controller: _openingTimeController,
              decoration: InputDecoration(labelText: 'Opening Time'),
              readOnly: true,
              onTap: () => _selectTime(context, _openingTimeController),
            ),
            TextField(
              controller: _closingTimeController,
              decoration: InputDecoration(labelText: 'Closing Time'),
              readOnly: true,
              onTap: () => _selectTime(context, _closingTimeController),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitSuggestion,
              child: Text('Submit Suggestion'),
            ),
          ],
        ),
      ),
    );
  }
}
