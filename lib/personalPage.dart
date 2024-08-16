import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'event.dart';
import 'utils.dart';
import 'main.dart';

class EventDetailPage extends StatefulWidget {
  final Event event;
  final bool isDarkMode;
  final List<EventType> showTime;
  final timeMessage;
  const EventDetailPage({super.key, required this.event,required this.isDarkMode,required this.showTime,required this.timeMessage});


  @override
  _EventDetailPageState createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final TextEditingController _reviewController = TextEditingController();
  double _rating = 1.0;
  final AuthService _authService = AuthService();
  User? _currentUser;

  final List<QueryDocumentSnapshot> _reviews = [];
  bool _hasMoreReviews = true;
  bool _isLoading = false;
  DocumentSnapshot? _lastDocument;
  static const int _reviewsPerPage = 10;

  double? _selectedRating;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _fetchReviews();
  }

  Future<void> _getCurrentUser() async {
    _currentUser = FirebaseAuth.instance.currentUser;
    setState(() {});
  }

  Future<void> _fetchReviews() async {
    if (_isLoading || !_hasMoreReviews) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query query = FirebaseFirestore.instance
          .collection('information')
          .doc(widget.event.eventId)
          .collection('reviews')
          .orderBy('timestamp', descending: true)
          .limit(_reviewsPerPage);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      QuerySnapshot querySnapshot = await query.get();
      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        _reviews.addAll(querySnapshot.docs);
        if (querySnapshot.docs.length < _reviewsPerPage) {
          _hasMoreReviews = false;
        }
      } else {
        _hasMoreReviews = false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch reviews: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }



  Future<void> _submitReview() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to submit a review')),
      );
      return;
    }

    String review = _reviewController.text;
    if (review.isNotEmpty && _rating > 0) { // Check if rating is greater than 0
      try {
        final userId = _currentUser!.uid;
        final userName = _currentUser!.displayName ?? 'Anonymous'; // Get user display name
        final now = DateTime.now().toLocal();

        // Check if the user has already submitted a review
        final reviewQuerySnapshot = await FirebaseFirestore.instance
            .collection('information')
            .doc(widget.event.eventId)
            .collection('reviews')
            .where('userId', isEqualTo: userId)
            .get();

        if (reviewQuerySnapshot.docs.isEmpty) {
          // No existing review, proceed with submission
          await FirebaseFirestore.instance
              .collection('information')
              .doc(widget.event.eventId)
              .collection('reviews')
              .add({
            'review': review,
            'rating': _rating,
            'userId': userId,
            'userName': userName, 
            'timestamp': Timestamp.fromDate(now),
          });

          // Update review count and average rating
          final eventDoc = FirebaseFirestore.instance.collection('information').doc(widget.event.eventId);
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            final snapshot = await transaction.get(eventDoc);
            if (!snapshot.exists) {
              throw Exception('Event document does not exist');
            }

            final data = snapshot.data()!;
            final currentCount = data['reviewCount'] ?? 0;
            final currentTotalRating = data['totalRating'] ?? 0.0;

            final newCount = currentCount + 1;
            final newTotalRating = currentTotalRating + _rating;
            final newAverageRating = newTotalRating / newCount;

            // Round the average rating to one decimal place
            final roundedAverageRating = double.parse(newAverageRating.toStringAsFixed(1));

            transaction.update(eventDoc, {
              'reviewCount': newCount,
              'totalRating': newTotalRating,
              'rating': roundedAverageRating, // Update the existing rating field with the rounded average rating
            });
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review submitted successfully')),
          );
          _reviewController.clear();
          setState(() {
            _rating = 1.0; 
            _reviews.clear(); 
            _lastDocument = null;
            _hasMoreReviews = true;
            _fetchReviews(); 
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have already submitted a review for this event.'),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a review and provide a rating greater than 0')),
      );
    }
  }


  List<Map<String, dynamic>> get _filteredReviews {
    if (_selectedRating == null) {
      return _reviews.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } else {
      return _reviews
          .where((doc) => (doc.data() as Map<String, dynamic>)['rating'] == _selectedRating)
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    }
  }

  Widget _buildRatingFilterButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(5, (index) {
        final rating = index + 1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedRating = (_selectedRating == rating) ? null : rating.toDouble();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedRating == rating ? Colors.blue : Colors.grey,
            ),
            child: Text(
              '$rating ${_selectedRating == rating ? '⭐' : ''}',  
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event.name),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.event.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rating: ${widget.event.rating}/5, ${widget.event.reviewCount} reviews',
                  ),
                  const SizedBox(height: 16),
                  if (!widget.showTime.contains(widget.event.type))
                    Text(
                      'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.event.date)}',
                    ),
                  if (widget.showTime.contains(widget.event.type) &&
                      getStatusBool(widget.event) == 'open')
                    FutureBuilder<String>(
                      future: widget.timeMessage,   
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Text('Loading...');
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');     
                        } else if (snapshot.hasData) {
                          return Row(
                            children: [
                              RichText(
                                text: getStatus(widget.event, widget.isDarkMode),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                snapshot.data!,
                                style: TextStyle(color: Colors.yellow[700], fontSize: 10.0),  
                              ),
                            ],
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  if (widget.showTime.contains(widget.event.type) &&
                      getStatusBool(widget.event) == 'closed')
                    FutureBuilder<String>(
                      future: widget.timeMessage,   
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Text('Loading...');
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');     
                        } else if (snapshot.hasData) {
                          return Row(
                            children: [
                              RichText(
                                text: getStatus(widget.event, widget.isDarkMode),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                snapshot.data!,
                                style: TextStyle(color: Colors.yellow[700], fontSize: 10.0),  
                              ),
                            ],
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  Text(
                    'Distance: ${(_calculateDistance(widget.event.position) / 1000).toStringAsFixed(2)} km',
                  ),
                  Text(
                    'Address: ${widget.event.address}',
                  ),
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse(widget.event.link);
                      if (await canLaunchUrl(url)) {
                        await launchURL(context,url, widget.event);
                      } else {
                        throw 'Could not launch $url';
                      }
                    },
                    child: const Text(
                      'Web: Click here',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                  Text(
                    'description: ${widget.event.description}',
                  ),
                  const SizedBox(height: 16),
                  _buildRatingFilterButtons(),
                  const SizedBox(height: 16),
                  const Text('Past Reviews:'),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                if (_filteredReviews.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No reviews available'),
                    ),
                  );
                }

                if (index < _filteredReviews.length) {
                  final review = _filteredReviews[index];
                  return ListTile(
                    title: Text(review['review'] ?? 'No review'),
                    subtitle: Text(
                      '${review['rating']} ⭐ - ${DateFormat('dd/MM/yyyy').format(
                        (review['timestamp'] as Timestamp).toDate(),
                      )}',
                    ),
                    leading: CircleAvatar(
                      child: Text(review['userName']?.substring(0, 1) ?? '?'),
                    ),
                  );
                } else if (index == _filteredReviews.length) {
                  return _hasMoreReviews
                      ? Center(
                    child: ElevatedButton(
                      onPressed: _fetchReviews,
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const Text('Show More'),
                    ),
                  )
                      : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No more reviews available'),
                    ),
                  );
                }
                return null;
              },
              childCount: _filteredReviews.isEmpty
                  ? 1
                  : _filteredReviews.length + 1,
            ),
          ),


          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rate this event:'),
                  Slider(
                    value: _rating,
                    onChanged: (value) {
                      setState(() {
                        _rating = value;
                      });
                    },
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$_rating',
                  ),
                  TextField(
                    controller: _reviewController,
                    decoration: const InputDecoration(
                      labelText: 'Write your review',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _submitReview,
                    child: const Text('Submit Review'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
}

