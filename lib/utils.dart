import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'personalPage.dart';
import 'main.dart';
import 'event.dart';
import 'dart:convert';

class NetworkAsset {
  final String url;

  NetworkAsset(this.url);
}

Future<void> launchURL(BuildContext context, Uri url, Event event) async {
  try {
    if (await canLaunchUrl(url)) {
      await _updateEventClickCount(event);
      await launchUrl(url);
    } else {
      throw 'Could not launch $url';
    }
  } catch (e) {
    print('Error launching URL: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not launch URL: $e')),
    );
  }
}

Future<void> _updateEventClickCount(Event event) async {
  try {
    final eventRef = FirebaseFirestore.instance.collection('information').doc(event.eventId);
    await eventRef.update({
      'clickCount': FieldValue.increment(1),
    });
  } catch (e) {
    print('Error updating click count: $e');
    // Optionally, show an error message to the user
  }
}

Future<http.Response> load(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    return response;
  } catch (e) {
    print('Error loading URL: $e');
    rethrow;
  }
}
Future<List> fetchHolidays(int year) async {
  final apiKey = '2PWMekdMImNKUNfBfMJoLLByhdAXOHzb';
  final country = 'IL';
  final url = Uri.parse('https://calendarific.com/api/v2/holidays?api_key=$apiKey&country=$country&year=$year');

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final holidays = (data['response']['holidays'] as List)
        .map((holiday) => holiday['date']['iso'])
        .toList();
    return holidays;
  } else {
    throw Exception('Failed to load holidays');
  }
}



