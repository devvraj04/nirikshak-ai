import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;

  static String get getBaseUrl {
    if (kIsWeb) {
      return 'http://192.168.0.147:8080';
    }
    if (Platform.isAndroid) {
      return 'http://192.168.0.147:8080';
    }
    return 'http://192.168.0.147:8080';
  }

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: getBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 300), // Increased to 5 mins for slow CPU OCR
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await dio.get('/health');
      return response.data;
    } catch (e) {
      return {'status': 'offline', 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> uploadScanImage(String filePath, {String? backFilePath, String? leftFilePath, String? rightFilePath, String? topFilePath, String? bottomFilePath, String? userId}) async {
    final map = <String, dynamic>{
      'file': await MultipartFile.fromFile(filePath, filename: 'package_scan.jpg'),
    };
    if (userId != null) {
      map['user_id'] = userId;
    }
    if (backFilePath != null) {
      map['back_file'] = await MultipartFile.fromFile(backFilePath, filename: 'package_scan_back.jpg');
    }
    if (leftFilePath != null) {
      map['left_file'] = await MultipartFile.fromFile(leftFilePath, filename: 'package_scan_left.jpg');
    }
    if (rightFilePath != null) {
      map['right_file'] = await MultipartFile.fromFile(rightFilePath, filename: 'package_scan_right.jpg');
    }
    if (topFilePath != null) {
      map['top_file'] = await MultipartFile.fromFile(topFilePath, filename: 'package_scan_top.jpg');
    }
    if (bottomFilePath != null) {
      map['bottom_file'] = await MultipartFile.fromFile(bottomFilePath, filename: 'package_scan_bottom.jpg');
    }
    final formData = FormData.fromMap(map);
    final response = await dio.post('/scans', data: formData);
    return response.data;
  }

  Future<Map<String, dynamic>> processScan(String scanId) async {
    final response = await dio.post('/scans/$scanId/process');
    return response.data;
  }

  Future<Map<String, dynamic>> getScanOcr(String scanId) async {
    final response = await dio.get('/scans/$scanId/ocr');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getViolationAnalysis(String scanId, {String? ruleId}) async {
    final path = ruleId != null && ruleId.isNotEmpty
        ? '/scans/$scanId/violations/$ruleId/analysis'
        : '/scans/$scanId/violations/analysis';
    final response = await dio.get(path);
    return response.data;
  }

  Future<List<dynamic>> fetchReviewQueue() async {
    final response = await dio.get('/reviews/queue');
    return response.data;
  }

  Future<Map<String, dynamic>> submitReview(String scanId, String reviewerId, String decision, String? notes) async {
    final response = await dio.post('/reviews', data: {
      'scan_id': scanId,
      'reviewer_id': reviewerId,
      'decision': decision,
      'notes': notes,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> fileComplaint(
      String citizenId, double paidPrice, double printedMrp, String shopkeeperName, String shopAddress, String description,
      {String? receiptPath, String? productPath}) async {
    final validCitizenId = citizenId.trim().isNotEmpty
        ? citizenId.trim()
        : '00000000-0000-0000-0000-000000000001';

    final map = <String, dynamic>{
      'citizen_id': validCitizenId,
      'paid_price': paidPrice,
      'printed_mrp': printedMrp,
      'shopkeeper_name': shopkeeperName,
      'shop_address': shopAddress,
      'description': description,
    };

    if (receiptPath != null && receiptPath.isNotEmpty) {
      if (receiptPath.startsWith('http://') || receiptPath.startsWith('https://')) {
        map['receipt_image_url'] = receiptPath;
      } else {
        final f = File(receiptPath);
        if (f.existsSync()) {
          map['receipt_image'] = await MultipartFile.fromFile(receiptPath, filename: 'receipt.jpg');
        }
      }
    }

    if (productPath != null && productPath.isNotEmpty) {
      if (productPath.startsWith('http://') || productPath.startsWith('https://')) {
        map['product_image_url'] = productPath;
      } else {
        final f = File(productPath);
        if (f.existsSync()) {
          map['product_image'] = await MultipartFile.fromFile(productPath, filename: 'product.jpg');
        }
      }
    }
    
    final formData = FormData.fromMap(map);
    final response = await dio.post('/complaints', data: formData);
    return response.data;
  }
  Future<Map<String, dynamic>> fetchCitizenHistory(String userId) async {
    final response = await dio.get('/users/$userId/history');
    return response.data;
  }

  Future<List<dynamic>> fetchComplaints() async {
    final response = await dio.get('/complaints');
    return response.data;
  }

  Future<Map<String, dynamic>> reviewComplaint(String complaintId, String officerId, String status, String? notes) async {
    final response = await dio.patch('/complaints/$complaintId/review', data: {
      'officer_id': officerId,
      'status': status,
      'resolution_notes': notes,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> fetchManufacturerHistory(String name) async {
    final response = await dio.get('/manufacturers/$name/history');
    return response.data;
  }

  Future<List<dynamic>> fetchManufacturerRatings() async {
    final response = await dio.get('/manufacturers/ratings');
    return response.data;
  }

  Future<Map<String, dynamic>> rateManufacturer(String name, String officerId, String rating, String? notes) async {
    final response = await dio.post('/manufacturers/$name/rate', data: {
      'officer_id': officerId,
      'rating': rating,
      'notes': notes,
    });
    return response.data;
  }

  /// Retrieve twice-daily price surveillance history and violation history for a product.
  Future<Map<String, dynamic>> getProductEcommerceTwin(String scanId, {String? productId}) async {
    final path = (productId != null && productId.isNotEmpty)
        ? '/products/$productId/ecommerce-twin'
        : '/products/by-scan/$scanId/ecommerce-twin';
    final response = await dio.get(path);
    return Map<String, dynamic>.from(response.data);
  }

  /// Retrieve all registered Legal Metrology rules with statutory references.
  Future<List<dynamic>> fetchRules() async {
    final response = await dio.get('/rules');
    return response.data;
  }

  /// Query the RAG-powered Legal Metrology AI Chatbot.
  Future<Map<String, dynamic>> sendChatMessage(String message, {String? ruleId, String? context}) async {
    final response = await dio.post('/chat', data: {
      'message': message,
      if (ruleId != null && ruleId.isNotEmpty) 'rule_id': ruleId,
      if (context != null && context.isNotEmpty) 'context': context,
    });
    return Map<String, dynamic>.from(response.data);
  }
}
