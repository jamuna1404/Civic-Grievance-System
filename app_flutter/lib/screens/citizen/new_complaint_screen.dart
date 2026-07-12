import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;

import '../../services/api_client.dart';

class NewComplaintScreen extends StatefulWidget {
  const NewComplaintScreen({super.key});

  @override
  State<NewComplaintScreen> createState() => _NewComplaintScreenState();
}

class _NewComplaintScreenState extends State<NewComplaintScreen> {
  final ApiClient _apiClient = ApiClient();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  
  // Image picker properties
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _pickedImage;

  // Audio recording properties
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedAudioPath;

  // GPS properties
  bool _isFetchingLocation = false;
  double? _latitude;
  double? _longitude;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // 1. Fetch current GPS Coordinates (FR-1.3)
  Future<void> _fetchGPSCoordinates() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar("Location services are disabled.", Colors.amber);
        setState(() => _isFetchingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar("Location permission denied.", Colors.amber);
          setState(() => _isFetchingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar("Location permissions are permanently denied.", Colors.amber);
        setState(() => _isFetchingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      _showSnackBar("GPS Coordinates Resolved successfully!", Colors.green);
    } catch (e) {
      _showSnackBar("Failed to fetch GPS coordinates: $e", Colors.redAccent);
    } finally {
      setState(() => _isFetchingLocation = false);
    }
  }

  // 2. Image Picker Preview (FR-1.1)
  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _pickedImage = image;
        });
      }
    } catch (e) {
      _showSnackBar("Error picking image: $e", Colors.redAccent);
    }
  }

  // 3. Audio Recording or Upload (FR-1.1)
  Future<void> _toggleAudioRecording() async {
    if (_isRecording) {
      // Stop recording
      try {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _recordedAudioPath = path;
        });
        _showSnackBar("Voice complaint recorded!", Colors.green);
      } catch (e) {
        _showSnackBar("Error stopping recording: $e", Colors.red);
      }
    } else {
      // Start recording
      try {
        if (await _audioRecorder.hasPermission()) {
          setState(() {
            _isRecording = true;
          });
          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aac),
            path: 'complaint_record.m4a',
          );
        } else {
          _showSnackBar("Audio recording permission denied.", Colors.amber);
        }
      } catch (e) {
        _showSnackBar("Error starting recording: $e", Colors.red);
      }
    }
  }

  // 4. Form Submit Multipart (FR-1.2, FR-1.3)
  Future<void> _submitComplaint() async {
    final text = _descriptionController.text.trim();
    final address = _addressController.text.trim();

    // FR-1.2: Check at least one modality
    if (text.isEmpty && _pickedImage == null && _recordedAudioPath == null) {
      _showSnackBar("Please provide at least one input modality (description, photo, or audio).", Colors.redAccent);
      return;
    }

    // FR-1.3: Check at least coordinates or address text
    final hasCoords = _latitude != null && _longitude != null;
    final hasAddress = address.isNotEmpty;
    if (!hasCoords && !hasAddress) {
      _showSnackBar("Please provide a location (coordinates resolved or manual address text).", Colors.redAccent);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final fields = <String, String>{};
      if (text.isNotEmpty) fields['text'] = text;
      if (hasCoords) {
        fields['location_lat'] = _latitude.toString();
        fields['location_lng'] = _longitude.toString();
      }
      if (hasAddress) fields['address_text'] = address;

      // Build Multipart Files
      final files = <http.MultipartFile>[];

      // Add image file
      if (_pickedImage != null) {
        if (kIsWeb) {
          final bytes = await _pickedImage!.readAsBytes();
          files.add(http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: 'complaint_photo.jpg',
          ));
        } else {
          files.add(await http.MultipartFile.fromPath(
            'image',
            _pickedImage!.path,
            filename: 'complaint_photo.jpg',
          ));
        }
      }

      // Add audio file
      if (_recordedAudioPath != null) {
        if (kIsWeb) {
          // Web recording is not fully supported locally without blob reader; handled gracefully
        } else {
          files.add(await http.MultipartFile.fromPath(
            'audio',
            _recordedAudioPath!,
            filename: 'complaint_audio.m4a',
          ));
        }
      }

      final responseStream = await _apiClient.postMultipart(
        path: '/api/complaints',
        fields: fields,
        files: files,
      );

      final response = await http.Response.fromStream(responseStream);

      if (response.statusCode == 201) {
        _showSnackBar("Complaint submitted successfully!", Colors.green);
        if (mounted) {
          Navigator.of(context).pop(true); # Go back to dashboard with refresh flag
        }
      } else {
        _showSnackBar("Submission failed: ${response.body}", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Error submitting complaint: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String msg, Color bg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1E293B);
    const primaryColor = Color(0xFF0EA5E9);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text("File a Grievance", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Text description field
            const Text("Grievance Description", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Describe the issue (e.g. broken streetlight in Perambur)...",
                hintStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Photo Attachment (FR-1.1)
            const Text("Attach Photograph", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  style: ElevatedButton.styleFrom(backgroundColor: cardColor),
                  icon: const Icon(Icons.photo_library, color: primaryColor),
                  label: const Text("Gallery", style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  style: ElevatedButton.styleFrom(backgroundColor: cardColor),
                  icon: const Icon(Icons.camera_alt, color: primaryColor),
                  label: const Text("Camera", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            if (_pickedImage != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: kIsWeb
                    ? Image.network(_pickedImage!.path, height: 180, fit: BoxFit.cover)
                    : Image.file(File(_pickedImage!.path), height: 180, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 20),

            // 3. Audio Recording (FR-1.1)
            const Text("Voice Memo / Audio Complaint", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleAudioRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.redAccent : cardColor,
                  ),
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: _isRecording ? Colors.white : primaryColor,
                  ),
                  label: Text(
                    _isRecording ? "Stop Recording" : "Record Voice",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                if (_recordedAudioPath != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 4),
                  const Text("Recorded", style: TextStyle(color: Colors.green)),
                ]
              ],
            ),
            const SizedBox(height: 20),

            // 4. GPS and Address Fallback (FR-1.3)
            const Text("Location Details", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isFetchingLocation ? null : _fetchGPSCoordinates,
              style: ElevatedButton.styleFrom(backgroundColor: cardColor),
              icon: _isFetchingLocation
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2))
                  : const Icon(Icons.my_location, color: primaryColor),
              label: Text(
                _latitude != null ? "GPS Resolved (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})" : "Resolve Device GPS",
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            const Text("Manual Address Fallback", style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            TextField(
              controller: _addressController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter address text (e.g. Ward 2, Perambur, Chennai)...",
                hintStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 32),

            // 5. Submit Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitComplaint,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("SUBMIT GRIEVANCE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
