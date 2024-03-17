import 'package:flutter/material.dart';
import 'package:tier_monitor/pages/history_individual.dart';
import 'package:tier_monitor/pages/change_amount.dart';
import 'package:tier_monitor/pages/documentation.dart';

class SelectionPage extends StatelessWidget {
  final String stallName;

  const SelectionPage({super.key, required this.stallName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(stallName.split("#")[1]),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Tierbewegung(
                      stallname: stallName.toString(),
                    ),
                  ),
                );
              },
              child: const Text('Tierbewegung'),
            ),
            const SizedBox(height: 32.0),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Tiermassnahme(
                      stallname: stallName.toString(),
                    ),
                  ),
                );
              },
              child: const Text('Behandlung/Syntome dokumentieren'),
            ),
            const SizedBox(height: 32.0),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryPageSecondMedikation(
                      stallname: stallName.toString(),
                    ),
                  ),
                );
              },
              child: const Text('Krankheitsverlauf dokumentieren'),
            ),
          ],
        ),
      ),
    );
  }
}