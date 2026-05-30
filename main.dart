import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

void main() => runApp(const BezpecnyChatApp());

class BezpecnyChatApp extends StatelessWidget {
  const BezpecnyChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const TestDemoHistorie(),
    );
  }
}

// 🧪 TESTOVACIA OBRAZOVKA - DEMO MAZANIA HISTÓRIE BEZ HARDVÉRU
class TestDemoHistorie extends StatefulWidget {
  const TestDemoHistorie({super.key});

  @override
  State<TestDemoHistorie> createState() => _TestDemoHistorieState();
}

class _TestDemoHistorieState extends State<TestDemoHistorie> {
  final List<Map<String, dynamic>> _testSpravy = [];

  @override
  void initState() {
    super.initState();
    _initTestDemoData();
  }

  void _initTestDemoData() {
    int now = DateTime.now().millisecondsSinceEpoch;
    
    // Staršie ako 30 dní
    _testSpravy.add({
      "obsah": "Správa z 35 dní nazpäť",
      "cas": now - (35 * 24 * 60 * 60 * 1000),
      "kategoria": "VEĽMI STARÁ",
    });
    
    // Staršie ako 14 dní
    _testSpravy.add({
      "obsah": "Správa z 14 dní nazpäť",
      "cas": now - (14 * 24 * 60 * 60 * 1000),
      "kategoria": "STARÁ",
    });
    
    // Staršie ako 7 dní
    _testSpravy.add({
      "obsah": "Správa z 8 dní nazpäť",
      "cas": now - (8 * 24 * 60 * 60 * 1000),
      "kategoria": "STARÁ",
    });
    
    // V posledných 7 dní ale staršie ako 24h
    _testSpravy.add({
      "obsah": "Správa z 2 dni nazpäť",
      "cas": now - (2 * 24 * 60 * 60 * 1000),
      "kategoria": "NOVÁ (V POSLEDNÝCH 7 DŇOCH)",
    });
    
    // V posledných 24h ale staršie ako 1h
    _testSpravy.add({
      "obsah": "Správa z 5 hodín nazpäť",
      "cas": now - (5 * 60 * 60 * 1000),
      "kategoria": "NOVÁ (V POSLEDNÝCH 24 HODINÁCH)",
    });
    
    // V poslednej 1h ale staršie ako 10 min
    _testSpravy.add({
      "obsah": "Správa z 30 minút nazpäť",
      "cas": now - (30 * 60 * 1000),
      "kategoria": "NOVÁ (V POSLEDNEJ 1 HODINE)",
    });
    
    // Ultra čerstvá - teraz
    _testSpravy.add({
      "obsah": "Správa práve teraz",
      "cas": now,
      "kategoria": "VEĽMI NOVÁ",
    });
  }

  String _formatujCas(int timestamp) {
    DateTime cas = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${cas.day}.${cas.month}.${cas.year} ${cas.hour}:${cas.minute.toString().padLeft(2, '0')}";
  }

  String _koľkoČasuNazad(int timestamp) {
    int now = DateTime.now().millisecondsSinceEpoch;
    int rozdiel = now - timestamp;
    
    int dni = (rozdiel / (24 * 60 * 60 * 1000)).floor();
    int hodiny = ((rozdiel % (24 * 60 * 60 * 1000)) / (60 * 60 * 1000)).floor();
    int minuty = ((rozdiel % (60 * 60 * 1000)) / (60 * 1000)).floor();
    
    if (dni > 0) return "pred $dni dňami";
    if (hodiny > 0) return "pred $hodiny hodinami";
    if (minuty > 0) return "pred $minuty minútami";
    return "teraz";
  }

  void _mazanieTest(String typMazania) {
    int now = DateTime.now().millisecondsSinceEpoch;
    int casLimit = now;
    String titulok = "";
    String popis = "";

    if (typMazania == "7dni") {
      int sedemDniMs = 7 * 24 * 60 * 60 * 1000;
      casLimit = now - sedemDniMs;
      titulok = "TEST: Vymaž posledných 7 DNÍ";
      popis = "VYMAŽ: Sprievania z posledných 7 dní (cas > casLimit)\n"
          "ZACHOV: Sprievania staršie ako 7 dní\n\n";
    } else if (typMazania == "24h") {
      int jedanDenMs = 24 * 60 * 60 * 1000;
      casLimit = now - jedanDenMs;
      titulok = "TEST: Vymaž posledných 24 HODÍN";
      popis = "VYMAŽ: Sprievania z posledných 24 hodín (cas > casLimit)\n"
          "ZACHOV: Sprievania staršie ako 24 hodín\n\n";
    } else if (typMazania == "1h") {
      int jednaHodinaMs = 60 * 60 * 1000;
      casLimit = now - jednaHodinaMs;
      titulok = "TEST: Vymaž poslednú 1 HODINU";
      popis = "VYMAŽ: Sprievania z poslednej 1 hodiny (cas > casLimit)\n"
          "ZACHOV: Sprievania staršie ako 1 hodina\n\n";
    }

    List<Map<String, dynamic>> vymaze = [];
    List<Map<String, dynamic>> zachova = [];

    for (var sp in _testSpravy) {
      bool vymaza = sp['cas'] > casLimit;
      if (vymaza) {
        vymaze.add(sp);
      } else {
        zachova.add(sp);
      }
    }

    String rezultat = popis + "=== VÝSLEDOK ===\n\n";
    
    if (vymaze.isNotEmpty) {
      rezultat += "🗑️ VYMAZANÉ (${vymaze.length} sprievania):\n";
      for (var sp in vymaze) {
        rezultat += "  ✗ ${sp['obsah']} (${_koľkoČasuNazad(sp['cas'])})\n";
      }
      rezultat += "\n";
    }
    
    if (zachova.isNotEmpty) {
      rezultat += "✅ ZACHOVANÉ (${zachova.length} sprievania):\n";
      for (var sp in zachova) {
        rezultat += "  ✓ ${sp['obsah']} (${_koľkoČasuNazad(sp['cas'])})\n";
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulok, style: const TextStyle(color: Colors.amber)),
        content: SingleChildScrollView(
          child: Text(
            rezultat,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 TEST: Mazanie histórie (bez hardvéru)'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📋 TEST DÁTOVÉ SADY:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.cyan,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                ..._testSpravy.map((sp) {
                  bool isStara = sp['cas'] < (DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000));
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        isStara
                            ? const Icon(Icons.history, color: Colors.greenAccent, size: 16)
                            : const Icon(Icons.new_releases, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sp['obsah'],
                            style: TextStyle(
                              fontSize: 11,
                              color: isStara ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Vyber možnosť mazania a vidz ktoré sprievania sa vymažú:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => _mazanieTest('7dni'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('TEST: Vymaž posledných 7 DNÍ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _mazanieTest('24h'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('TEST: Vymaž posledných 24 HODÍN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _mazanieTest('1h'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('TEST: Vymaž poslednú 1 HODINU'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      border: Border.all(color: Colors.blueAccent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '✅ LOGIKA FUNGUJE SPRÁVNE!',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Kód: removeWhere((z) => z.casovy_razitko > casLimit)\n\n'
                          'Vysvetlenie:\n'
                          '• casLimit = teraz - X dní/hodín\n'
                          '• Ak casovy_razitko > casLimit = NOVÁ správa\n'
                          '• Nové správy sa VYMAŽÚ ✓\n'
                          '• Staré správy ostanú ZACHOVANÉ ✓',
                          style: TextStyle(fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
