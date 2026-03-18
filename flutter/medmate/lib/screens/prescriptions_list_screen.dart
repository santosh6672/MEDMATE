import 'dart:convert';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'medicines_screen.dart';

// URL: GET /api/prescriptions/
// Reply: [ { "id", "medicines": [...], ... }, ... ]

class PrescriptionsListScreen extends StatefulWidget {
  const PrescriptionsListScreen({super.key});

  @override
  State<PrescriptionsListScreen> createState() => _PrescriptionsListScreenState();
}

class _PrescriptionsListScreenState extends State<PrescriptionsListScreen> {
  List prescriptions = [];
  bool isLoading = true;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    loadPrescriptions();
  }

  Future<void> loadPrescriptions() async {
    setState(() { isLoading = true; errorMessage = ""; });
    try {
      final response = await ApiService.getWithAuth("$kBaseUrl/api/prescriptions/");
      if (response.statusCode == 200) {
        setState(() { prescriptions = jsonDecode(response.body); isLoading = false; });
      } else {
        setState(() { errorMessage = "Failed to load prescriptions."; isLoading = false; });
      }
    } catch (_) {
      setState(() { errorMessage = "Cannot connect to server."; isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Prescriptions"),
          backgroundColor: kPrimary, foregroundColor: kWhite),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : errorMessage.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(20),
                  child: ErrorBanner(message: errorMessage)))
              : prescriptions.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 60, color: kTextGrey),
                          SizedBox(height: 12),
                          Text("No prescriptions yet.", style: TextStyle(color: kTextGrey, fontSize: 15)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: prescriptions.length,
                      itemBuilder: (context, index) {
                        final p = prescriptions[index];
                        final int id = p["id"];
                        final List meds = p["medicines"] ?? [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(14),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.description, color: kPrimary, size: 24),
                            ),
                            title: Text("Prescription #$id",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: kTextDark)),
                            subtitle: Text(
                              meds.isEmpty ? "Processing..." : "${meds.length} medicine(s) found",
                              style: const TextStyle(color: kTextGrey, fontSize: 13),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: kTextGrey),
                            onTap: () {
                              if (meds.isNotEmpty) {
                                Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => MedicinesScreen(medicines: meds)));
                              }
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}