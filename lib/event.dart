import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

enum EventType { party, escapeRooms, bowling, bar, billiard }

class Event {
  final String eventId;
  final String name;
  final Position position;
  final DateTime date;
  final String address;
  final EventType type;
  final String link;
  int clickCount;
  final TimeOfDay openingTime;
  final TimeOfDay closingTime;
  final double rating;
  int reviewCount;
  final String description;

  Event({
    required this.eventId,
    required this.name,
    required this.position,
    required this.date,
    required this.address,
    required this.type,
    required this.link,
    this.clickCount = 0,
    required this.openingTime,
    required this.closingTime,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.description = '', // Initialize description field
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': position.latitude,
    'longitude': position.longitude,
    'date': date.toIso8601String(),
    'address': address,
    'type': type.toString().split('.').last,
    'link': link,
    'clickCount': clickCount,
    'openingTime': '${openingTime.hour}:${openingTime.minute}',
    'closingTime': '${closingTime.hour}:${closingTime.minute}',
    'rating': rating,
    'reviewCount': reviewCount,
    'description': description, // Add description field to JSON
  };

  factory Event.fromJson(Map<String, dynamic> json, String eventId) {
    return Event(
      eventId: eventId,
      name: json['name'],
      position: Position(
        latitude: json['latitude'],
        longitude: json['longitude'],
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        timestamp: DateTime.now(),
      ),
      date: DateTime.parse(json['date']),
      address: json['address'],
      type: EventType.values.firstWhere(
            (e) => e.toString().split('.').last == json['type'],
        orElse: () => EventType.party,
      ),
      link: json['link'],
      clickCount: json['clickCount'] ?? 0,
      openingTime: _parseTimeOfDay(json['openingTime']),
      closingTime: _parseTimeOfDay(json['closingTime']),
      rating: json['rating']?.toDouble() ?? 0.0,
      reviewCount: json['reviewCount'] ?? 0,
      description: json['description'] ?? '', // Add description field
    );
  }

  static TimeOfDay _parseTimeOfDay(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  bool isOpenNow() {
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final openingMinutes = openingTime.hour * 60 + openingTime.minute;
    final closingMinutes = closingTime.hour * 60 + closingTime.minute;

    if (closingMinutes < openingMinutes) {
      return currentMinutes >= openingMinutes ||
          currentMinutes < closingMinutes;
    } else {
      return currentMinutes >= openingMinutes &&
          currentMinutes < closingMinutes;
    }
  }
}

String getStatusBool(Event event) {
  if (isOpenNow(event)) {
    return 'open';
  } else {
    return 'closed';
  }
}

bool isOpenNow(Event event) {
  final now = TimeOfDay.now();
  final currentMinutes = now.hour * 60 + now.minute;
  final openingMinutes = event.openingTime.hour * 60 + event.openingTime.minute;
  final closingMinutes = event.closingTime.hour * 60 + event.closingTime.minute;

  if (closingMinutes < openingMinutes) {
    // Handle events that close after midnight
    return currentMinutes >= openingMinutes || currentMinutes < closingMinutes;
  } else {
    return currentMinutes >= openingMinutes && currentMinutes < closingMinutes;
  }
}
