import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kepelthzggcjxkserllz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtlcGVsdGh6Z2djanhrc2VybGx6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwMDI2NjMsImV4cCI6MjA4OTU3ODY2M30.HyrrtynTSF9TQHGNcHvJRG8pExFo-v1Xg-YAGp3gmhk',
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  cameras = await availableCameras();
  runApp(const CakeSecurityApp());
}

class AppColors {
  static const background = Color(0xFF0D0D0D);
  static const surface    = Color(0xFF1A1A1A);
  static const beige      = Color(0xFFF5EFE6);
  static const grey       = Color(0xFF8A8A8A);
  static const white      = Color(0xFFFFFFFF);
  static const divider    = Color(0xFF2C2C2C);
  static const green      = Color(0xFF4CAF50);
  static const red        = Color(0xFFE05252);
  static const orange     = Color(0xFFFF9800);
}

class CakeSecurityApp extends StatelessWidget {
  const CakeSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cake Security',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: const CameraPage(),
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  // ── Caméra ─────────────────────────────────────────────
  CameraController? _controller;
  bool _isInitialized = false;
  int _currentCameraIndex = 0;

  // ── BLE ────────────────────────────────────────────────
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionStateSubscription;
  final List<StreamSubscription> _notifySubscriptions = [];
  String _bleStatus = 'Recherche BLE...';
  bool _bleConnected = false;
  bool _isConnecting = false;
  bool _disposed = false;

  // ── Photos ─────────────────────────────────────────────
  int _photoCount = 0;
  bool _takingPhoto = false;
  String? _flashMessage;

  // ── Debug ──────────────────────────────────────────────
  String _lastReceivedUuid = '';
  String _lastReceivedValue = '';

  @override
  void initState() {
    super.initState();
    _initCamera(cameras[0]);
    _startBLEScan();
  }

  // ════════════════════════════════════════════════════════
  //  CAMÉRA
  // ════════════════════════════════════════════════════════
  Future<void> _initCamera(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Erreur caméra: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (cameras.length < 2) return;
    await _controller?.dispose();
    setState(() => _isInitialized = false);
    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    await _initCamera(cameras[_currentCameraIndex]);
  }

  // ════════════════════════════════════════════════════════
  //  PHOTO + UPLOAD SUPABASE
  // ════════════════════════════════════════════════════════
  Future<void> _takeAndSavePhoto() async {
    if (_controller == null || !_isInitialized || _takingPhoto) return;
    setState(() => _takingPhoto = true);

    try {
      // 1. Prend la photo
      final XFile photo = await _controller!.takePicture();

      // 2. Sauvegarde locale temporaire
      final Directory appDir = await getTemporaryDirectory();
      final String timestamp =
          DateTime.now().toString().replaceAll(RegExp(r'[:\. ]'), '-');
      final String fileName = 'photo_$timestamp.jpg';
      final String localPath = p.join(appDir.path, fileName);
      await File(photo.path).copy(localPath);

      setState(() => _flashMessage = '⬆️ Upload en cours...');

      // 3. Upload vers Supabase Storage
      final supabase = Supabase.instance.client;
      final bytes = await File(localPath).readAsBytes();

      await supabase.storage
          .from('photos')
          .uploadBinary(
            'CakeSecurity/$fileName',
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      // 4. Récupère l'URL publique
      final String publicUrl = supabase.storage
          .from('photos')
          .getPublicUrl('CakeSecurity/$fileName');

      debugPrint('✅ Photo uploadée : $publicUrl');

      setState(() {
        _photoCount++;
        _flashMessage = '📸 Photo #$_photoCount envoyée !';
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _flashMessage = null);
      });

    } catch (e) {
      debugPrint('❌ Erreur: $e');
      setState(() => _flashMessage = '❌ Erreur upload: $e');
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  // ════════════════════════════════════════════════════════
  //  BLE — SCAN
  // ════════════════════════════════════════════════════════
  Future<void> _startBLEScan() async {
    if (_disposed) return;
    if (mounted) setState(() => _bleStatus = 'Scan BLE...');

    _scanSubscription?.cancel();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName.contains('WB55') && !_isConnecting) {
          _isConnecting = true;
          await FlutterBluePlus.stopScan();
          await _connectToDevice(r.device);
          break;
        }
      }
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && !_bleConnected && !_disposed && !_isConnecting) {
        Future.delayed(const Duration(seconds: 3), () {
          if (!_bleConnected && !_disposed) _startBLEScan();
        });
      }
    });
  }

  // ════════════════════════════════════════════════════════
  //  BLE — CONNEXION
  // ════════════════════════════════════════════════════════
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (mounted) {
      setState(() => _bleStatus = 'Connexion à ${device.platformName}...');
    }

    try {
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        debugPrint('🔗 État connexion: $state');

        if (state == BluetoothConnectionState.disconnected) {
          if (mounted) {
            setState(() {
              _bleConnected = false;
              _isConnecting = false;
              _bleStatus = 'Déconnecté — Reconnexion...';
            });
          }
          for (var sub in _notifySubscriptions) sub.cancel();
          _notifySubscriptions.clear();

          if (!_disposed) {
            Future.delayed(const Duration(seconds: 3), () {
              if (!_bleConnected && !_disposed) _startBLEScan();
            });
          }
        }
      });

      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _bleConnected = true;
          _bleStatus = 'Connecté : ${device.platformName}';
        });
      }

      await Future.delayed(const Duration(milliseconds: 500));
      await _setupNotifications(device);

    } catch (e) {
      debugPrint('❌ Erreur connexion: $e');
      if (mounted) {
        setState(() {
          _bleConnected = false;
          _isConnecting = false;
          _bleStatus = 'Erreur — Nouvel essai...';
        });
      }
      Future.delayed(const Duration(seconds: 3), () {
        if (!_bleConnected && !_disposed) _startBLEScan();
      });
    }
  }

  // ════════════════════════════════════════════════════════
  //  BLE — NOTIFICATIONS + DÉCODAGE FLOAT IEEE 754
  // ════════════════════════════════════════════════════════
  Future<void> _setupNotifications(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic char in service.characteristics) {
          if (char.properties.notify || char.properties.indicate) {
            try {
              await char.setNotifyValue(true);

              final sub = char.onValueReceived.listen((value) {
                debugPrint('📡 [${char.uuid}] → $value');

                if (mounted) {
                  setState(() {
                    _lastReceivedUuid = char.uuid.toString();
                    _lastReceivedValue = value.toString();
                  });
                }

                // Décodage float IEEE 754 little-endian
                // set_data_temperature(99) → [0, 0, 198, 66]
                if (value.length >= 4) {
                  final byteData = ByteData(4);
                  byteData.setUint8(0, value[0]);
                  byteData.setUint8(1, value[1]);
                  byteData.setUint8(2, value[2]);
                  byteData.setUint8(3, value[3]);
                  final float = byteData.getFloat32(0, Endian.little);
                  debugPrint('🌡️ Valeur décodée: $float');

                  if (float == 99.0) {
                    debugPrint('🎯 Signal 99.0 → PHOTO !');
                    _takeAndSavePhoto();
                  }
                }

                // Sécurité byte direct
                if (value.isNotEmpty && value[0] == 99) {
                  debugPrint('🎯 Signal direct 99 → PHOTO !');
                  _takeAndSavePhoto();
                }
              });

              _notifySubscriptions.add(sub);
            } catch (e) {
              debugPrint('⚠️ Notify impossible sur ${char.uuid}: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur setup notifications: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    for (var sub in _notifySubscriptions) sub.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  //  UI
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [

          // ── Preview caméra ───────────────────────────
          if (_isInitialized && _controller != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.beige,
                strokeWidth: 1.5,
              ),
            ),

          // ── Dégradé haut ────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 180,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xDD0D0D0D), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Dégradé bas ─────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0, height: 200,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xEE0D0D0D), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Flash blanc quand photo ──────────────────
          if (_takingPhoto)
            Container(color: Colors.white.withOpacity(0.25)),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CAKE SECURITY',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text('Surveillance active',
                            style: TextStyle(
                              color: AppColors.grey,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('LIVE',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Statut BLE ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _bleConnected
                            ? AppColors.green.withOpacity(0.5)
                            : _bleStatus.contains('Reconnexion') ||
                              _bleStatus.contains('essai')
                                ? AppColors.orange.withOpacity(0.5)
                                : AppColors.divider,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _bleConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_searching,
                          size: 14,
                          color: _bleConnected
                              ? AppColors.green
                              : _bleStatus.contains('Reconnexion') ||
                                _bleStatus.contains('essai')
                                  ? AppColors.orange
                                  : AppColors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _bleStatus,
                          style: TextStyle(
                            color: _bleConnected
                                ? AppColors.green
                                : _bleStatus.contains('Reconnexion') ||
                                  _bleStatus.contains('essai')
                                    ? AppColors.orange
                                    : AppColors.grey,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ── Debug panel ─────────────────────────
                if (_lastReceivedUuid.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.orange.withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🔬 DEBUG — Dernier BLE reçu',
                            style: TextStyle(
                              color: AppColors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('UUID: $_lastReceivedUuid',
                            style: const TextStyle(
                                color: AppColors.beige, fontSize: 9)),
                          Text('Valeur: $_lastReceivedValue',
                            style: const TextStyle(
                                color: AppColors.beige, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),

                // ── Message flash ───────────────────────
                if (_flashMessage != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: AppColors.beige.withOpacity(0.3)),
                      ),
                      child: Text(
                        _flashMessage!,
                        style: const TextStyle(
                          color: AppColors.beige,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                // ── Barre du bas ────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_photoCount photo${_photoCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: AppColors.beige,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentCameraIndex == 0
                                ? 'Caméra arrière'
                                : 'Caméra avant',
                            style: const TextStyle(
                              color: AppColors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _switchCamera,
                        child: Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: const Icon(
                            Icons.flip_camera_ios_outlined,
                            color: AppColors.beige,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}