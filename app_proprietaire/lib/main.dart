import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://kepelthzggcjxkserllz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtlcGVsdGh6Z2djanhrc2VybGx6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwMDI2NjMsImV4cCI6MjA4OTU3ODY2M30.HyrrtynTSF9TQHGNcHvJRG8pExFo-v1Xg-YAGp3gmhk',
  );
  runApp(const CakeAlertApp());
}

class AppColors {
  static const background = Color(0xFF0D0D0D);
  static const surface    = Color(0xFF1A1A1A);
  static const card       = Color(0xFF222222);
  static const beige      = Color(0xFFF5EFE6);
  static const grey       = Color(0xFF8A8A8A);
  static const white      = Color(0xFFFFFFFF);
  static const divider    = Color(0xFF2C2C2C);
  static const red        = Color(0xFFE05252);
  static const orange     = Color(0xFFFF9800);
}

class PhotoItem {
  final String url;
  final String name;
  final DateTime date;

  PhotoItem({required this.url, required this.name, required this.date});
}

class CakeAlertApp extends StatelessWidget {
  const CakeAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cake Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: const AlertPage(),
    );
  }
}

class AlertPage extends StatefulWidget {
  const AlertPage({super.key});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<PhotoItem> _photos = [];
  PhotoItem? _latestPhoto;
  bool _showAlert = false;
  bool _loading = true;
  Timer? _pollingTimer;

  late AnimationController _alertAnimController;
  late AnimationController _pulseController;
  late Animation<double> _alertAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _alertAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _alertAnim = CurvedAnimation(
      parent: _alertAnimController,
      curve: Curves.elasticOut,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadPhotos();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkNewPhotos();
    });
  }

  // ════════════════════════════════════════════════════════
  //  PARSE DATE depuis le nom du fichier
  //  format: photo_2026-03-20-13-07-10-870485.jpg
  // ════════════════════════════════════════════════════════
  DateTime _parseDateFromName(String name) {
    try {
      // Retire "photo_" et ".jpg"
      final clean = name
          .replaceAll('photo_', '')
          .replaceAll('.jpg', '');
      // clean = "2026-03-20-13-07-10-870485"
      final parts = clean.split('-');
      return DateTime(
        int.parse(parts[0]), // année
        int.parse(parts[1]), // mois
        int.parse(parts[2]), // jour
        int.parse(parts[3]), // heure
        int.parse(parts[4]), // minute
        int.parse(parts[5]), // seconde
      );
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      '', 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun',
      'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Il y a ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return 'Il y a ${diff.inDays}j';
  }

  // ════════════════════════════════════════════════════════
  //  CHARGE TOUTES LES PHOTOS
  // ════════════════════════════════════════════════════════
  Future<void> _loadPhotos() async {
    try {
      final List<FileObject> files = await supabase.storage
          .from('photos')
          .list(path: 'CakeSecurity');

      final photos = files.map((f) {
        final url = supabase.storage
            .from('photos')
            .getPublicUrl('CakeSecurity/${f.name}');
        return PhotoItem(
          url: url,
          name: f.name,
          date: _parseDateFromName(f.name),
        );
      }).toList();

      photos.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _photos = photos;
        _latestPhoto = photos.isNotEmpty ? photos.first : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erreur chargement: $e');
      setState(() => _loading = false);
    }
  }

  // ════════════════════════════════════════════════════════
  //  VÉRIFIE NOUVELLES PHOTOS
  // ════════════════════════════════════════════════════════
  Future<void> _checkNewPhotos() async {
    try {
      final List<FileObject> files = await supabase.storage
          .from('photos')
          .list(path: 'CakeSecurity');

      if (files.isEmpty) return;

      final photos = files.map((f) {
        final url = supabase.storage
            .from('photos')
            .getPublicUrl('CakeSecurity/${f.name}');
        return PhotoItem(
          url: url,
          name: f.name,
          date: _parseDateFromName(f.name),
        );
      }).toList();

      photos.sort((a, b) => b.date.compareTo(a.date));

      if (_latestPhoto == null || photos.first.url != _latestPhoto!.url) {
        setState(() {
          _photos = photos;
          _latestPhoto = photos.first;
          _showAlert = true;
        });

        _alertAnimController.forward(from: 0);

        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) setState(() => _showAlert = false);
        });
      }
    } catch (e) {
      debugPrint('Erreur polling: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _alertAnimController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  //  UI
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CAKE ALERT',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_photos.length} détection${_photos.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  // Indicateur live pulsant
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                              color: _showAlert
                                  ? AppColors.red
                                  : AppColors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showAlert ? 'ALERTE' : 'VEILLE',
                            style: TextStyle(
                              color: _showAlert
                                  ? AppColors.red
                                  : AppColors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Ligne séparatrice ──────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 0.5,
              color: AppColors.divider,
            ),

            const SizedBox(height: 12),

            // ── Alerte ────────────────────────────────
            if (_showAlert)
              ScaleTransition(
                scale: _alertAnim,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.red.withOpacity(0.5), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.red.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('🚨',
                              style: TextStyle(fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ALERTE INTRUSION !',
                              style: TextStyle(
                                color: AppColors.red,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '⚠️ Quelqu\'un essaye de voler ton gâteau !',
                              style: TextStyle(
                                color: AppColors.beige,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Dernière photo ─────────────────────────
            if (_latestPhoto != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Dernière détection',
                          style: TextStyle(
                            color: AppColors.grey,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          _timeAgo(_latestPhoto!.date),
                          style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () =>
                          _showFullPhoto(context, _latestPhoto!),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              _latestPhoto!.url,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.beige,
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Badge date/heure sur la photo
                          Positioned(
                            bottom: 10, left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 11, color: AppColors.beige),
                                  const SizedBox(width: 5),
                                  Text(
                                    _formatDate(_latestPhoto!.date),
                                    style: const TextStyle(
                                      color: AppColors.beige,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.access_time,
                                      size: 11, color: AppColors.beige),
                                  const SizedBox(width: 5),
                                  Text(
                                    _formatTime(_latestPhoto!.date),
                                    style: const TextStyle(
                                      color: AppColors.beige,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // ── Titre historique ───────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('Historique',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                        height: 0.5, color: AppColors.divider),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── Grille historique ──────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.beige,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _photos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🎂',
                                  style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              const Text(
                                'Aucune détection pour l\'instant',
                                style: TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.82,
                          ),
                          itemCount: _photos.length,
                          itemBuilder: (context, index) {
                            final photo = _photos[index];
                            return GestureDetector(
                              onTap: () =>
                                  _showFullPhoto(context, photo),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.divider,
                                      width: 0.5),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Image
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(14),
                                        ),
                                        child: Image.network(
                                          photo.url,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context,
                                              child, progress) {
                                            if (progress == null)
                                              return child;
                                            return Container(
                                              color: AppColors.surface,
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                  color: AppColors.beige,
                                                  strokeWidth: 1,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    // Date + heure
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 8, 10, 10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.calendar_today,
                                                size: 10,
                                                color: AppColors.beige,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatDate(photo.date),
                                                style: const TextStyle(
                                                  color: AppColors.beige,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment
                                                    .spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.access_time,
                                                    size: 10,
                                                    color: AppColors.grey,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _formatTime(
                                                        photo.date),
                                                    style: const TextStyle(
                                                      color: AppColors.grey,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                _timeAgo(photo.date),
                                                style: const TextStyle(
                                                  color: AppColors.orange,
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Photo plein écran avec date ──────────────────────
  void _showFullPhoto(BuildContext context, PhotoItem photo) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(photo.url, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 13, color: AppColors.beige),
                    const SizedBox(width: 6),
                    Text(_formatDate(photo.date),
                      style: const TextStyle(
                        color: AppColors.beige,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Icon(Icons.access_time,
                        size: 13, color: AppColors.grey),
                    const SizedBox(width: 6),
                    Text(_formatTime(photo.date),
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('Appuie pour fermer',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}