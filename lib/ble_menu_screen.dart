import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleMenuScreen extends StatefulWidget {
  const BleMenuScreen({super.key});

  @override
  State<BleMenuScreen> createState() => _BleMenuScreenState();
}

class _BleMenuScreenState extends State<BleMenuScreen> {
  Map<String, String> najdeneZariadenia = {}; // ID : Meno uzla
  bool prebiehaSkenovanie = false;

  @override
  void initState() {
    super.initState();
    inicializujBluetooth();
  }

  void inicializujBluetooth() async {
    try {
      if (!await FlutterBluePlus.isSupported) return;

      // Sledujeme nájdené zariadenia počas skenovania
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (result.device.platformName.isNotEmpty) {
            setState(() {
              // Uložíme ID (remoteId) a Meno zariadenia do tvojej mapy
              najdeneZariadenia[result.device.remoteId.toString()] =
                  result.device.platformName;
            });
          }
        }
      });
    } catch (e) {
      debugPrint("Bluetooth error: $e");
    }
  }

  void prepniSkenovanie() async {
    try {
      if (prebiehaSkenovanie) {
        await FlutterBluePlus.stopScan();
        if (mounted) {
          setState(() => prebiehaSkenovanie = false);
        }
      } else {
        if (mounted) {
          setState(() {
            najdeneZariadenia.clear();
            prebiehaSkenovanie = true;
          });
        }
        // Spustí skenovanie na 15 sekúnd
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

        // Keď skenovanie samo skončí, prepneme status
        FlutterBluePlus.isScanning.listen((scanning) {
          if (!scanning && mounted) {
            setState(() => prebiehaSkenovanie = false);
          }
        });
      }
    } catch (e) {
      debugPrint("Chyba prepínania skenu: $e");
      if (mounted) {
        setState(() => prebiehaSkenovanie = false);
      }
    }
  }

  void pripojKDoske(String deviceId) async {
    try {
      // Vytvoríme objekt zariadenia pomocou ID
      BluetoothDevice device = BluetoothDevice.fromId(deviceId);

      print("Pripájam sa k zariadeniu s ID: $deviceId");
      await device.connect();

      // Sledujeme stav pripojenia tohto konkrétneho zariadenia
      device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.connected) {
          print("Úspešne pripojené na všetkých platformách!");
          if (mounted) {
            Navigator.pop(context, 'Bluetooth: Pripojené');
          }
        }
      });
    } catch (e) {
      print("Chyba pripájania k zariadeniu: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE Párovanie")),
      body: Column(
        children: [
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: prepniSkenovanie,
            icon: Icon(
                prebiehaSkenovanie ? Icons.stop : Icons.bluetooth_searching),
            label: Text(
                prebiehaSkenovanie ? "Zastaviť hľadanie" : "Hľadať BLE Uzol"),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: najdeneZariadenia.entries.map((zariadenie) {
                return ListTile(
                  leading: const Icon(Icons.developer_board),
                  title: Text(zariadenie.value), // Názov uzla
                  subtitle: Text(zariadenie.key), // MAC adresa / ID
                  trailing: ElevatedButton(
                    onPressed: () => pripojKDoske(zariadenie.key),
                    child: const Text("Spárovať"),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
