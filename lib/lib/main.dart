import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'services/monitoring_alarm_service.dart';
import 'screens/home/monitoring_emergency_overlay.dart';
import 'services/dose_service.dart';
import 'design/medic_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

// ─── Top-level background message handler ─────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📩 Background message: ${message.messageId}');
}

// ─── Entry point ──────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
  } catch (error) { debugPrint('App Check setup: $error'); }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final notificationService = NotificationService();
  await notificationService.initialize();

  // Transparent status bar — content draws edge-to-edge
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:            Colors.transparent,
    statusBarIconBrightness:   Brightness.light,
    statusBarBrightness:       Brightness.dark,
    systemNavigationBarColor:  Color(0xFFF6F5F0),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MedicTrackApp());
}

// ─── Root app ─────────────────────────────────────────────────────────────────
class MedicTrackApp extends StatefulWidget {
  const MedicTrackApp({Key? key}) : super(key: key);

  @override
  State<MedicTrackApp> createState() => _MedicTrackAppState();
}

class _MedicTrackAppState extends State<MedicTrackApp> {
  @override
  void initState() {
    super.initState();
    DoseService.instance.start();
    MonitoringAlarmService.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: monitoringNavigatorKey,
      builder: (context, child) => MonitoringEmergencyOverlay(child: child ?? const SizedBox.shrink()),
      title:                    'MedicTrack',
      debugShowCheckedModeBanner: false,
      theme:                    _buildTheme(),
      home:                     const SplashScreen(),
    );
  }

  // ── Theme ───────────────────────────────────────────────────────────────────
  ThemeData _buildTheme() {
    // Design tokens
    const navy = MedicColors.forest;
    const teal = MedicColors.green;
    const surface = MedicColors.canvas;
    const card = MedicColors.cFFFFFF;
    const border = MedicColors.line;

    final base = ThemeData(
      useMaterial3:  true,
      fontFamily: 'sans-serif',
      primaryColor:  teal,
      scaffoldBackgroundColor: surface,

      colorScheme: ColorScheme.light(
        primary:          teal,
        onPrimary:        Colors.white,
        secondary:        const Color(0xFF477C91),
        onSecondary:      Colors.white,
        surface:          card,
        onSurface:        navy,
        background:       surface,
        onBackground:     navy,
        error:            const Color(0xFFC05256),
        onError:          Colors.white,
        outline:          border,
        surfaceVariant:   surface,
        onSurfaceVariant: const Color(0xFF63756D),
      ),

      // ── Typography ──────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge:  TextStyle(fontFamily: 'serif', fontSize: 32, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -1.0, height: 1.15),
        displayMedium: TextStyle(fontFamily: 'serif', fontSize: 26, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.8, height: 1.2),
        displaySmall:  TextStyle(fontFamily: 'serif', fontSize: 22, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.5),
        headlineLarge: TextStyle(fontFamily: 'serif', fontSize: 20, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.4),
        headlineMedium: TextStyle(fontFamily: 'serif', fontSize: 18, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.3),
        headlineSmall: TextStyle(fontFamily: 'serif', fontSize: 16, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.2),
        titleLarge:    TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: navy),
        titleMedium:   TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: navy),
        titleSmall:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: Color(0xFF63756D)),
        bodyLarge:     TextStyle(fontSize: 15, fontWeight: FontWeight.w400,
            color: navy, height: 1.55),
        bodyMedium:    TextStyle(fontSize: 14, fontWeight: FontWeight.w400,
            color: navy, height: 1.5),
        bodySmall:     TextStyle(fontSize: 12, fontWeight: FontWeight.w400,
            color: Color(0xFF63756D), height: 1.4),
        labelLarge:    TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
            color: Colors.white, letterSpacing: 0.2),
        labelMedium:   TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: Color(0xFF63756D), letterSpacing: 0.3),
        labelSmall:    TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: Color(0xFF83938B), letterSpacing: 0.4),
      ),

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        elevation:       0,
        scrolledUnderElevation: 0,
        centerTitle:     false,
        backgroundColor: Colors.transparent,
        foregroundColor: navy,
        iconTheme:       IconThemeData(color: navy, size: 22),
        titleTextStyle:  TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.3),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      // ── Elevated button ─────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:  teal,
          foregroundColor:  Colors.white,
          elevation:        0,
          shadowColor:      Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              letterSpacing: 0.2),
        ),
      ),

      // ── Outlined button ─────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: teal,
          side:            const BorderSide(color: teal, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      // ── Text button ─────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: teal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      // ── Input decoration ────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: card,
        hintStyle: const TextStyle(color: Color(0xFF83938B), fontSize: 14,
            fontWeight: FontWeight.w400),
        labelStyle: const TextStyle(color: Color(0xFF63756D), fontSize: 13,
            fontWeight: FontWeight.w600),
        floatingLabelStyle: const TextStyle(color: teal, fontSize: 12,
            fontWeight: FontWeight.w700),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: teal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFC05256), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFC05256), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        prefixIconColor: const Color(0xFF63756D),
        suffixIconColor: const Color(0xFF83938B),
      ),

      // ── Card ────────────────────────────────────────────────────────────
      cardTheme: CardTheme(
        elevation: 0,
        color:     card,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Divider ─────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color:     border,
        thickness: 1,
        space:     1,
      ),

      // ── SnackBar ────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor:   navy,
        contentTextStyle:  const TextStyle(color: Colors.white,
            fontSize: 13, fontWeight: FontWeight.w600),
        behavior:          SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
      ),

      // ── Bottom sheet ────────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor:   card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: Color(0xFFE2E5DC),
        dragHandleSize:  Size(40, 4),
      ),

      // ── Chip ────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:  surface,
        selectedColor:    teal,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),

      // ── Dialog ──────────────────────────────────────────────────────────
      dialogTheme: DialogTheme(
        backgroundColor: card,
        elevation:       0,
        shadowColor:     Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle:  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: navy, letterSpacing: -0.3),
        contentTextStyle: const TextStyle(fontSize: 14, color: Color(0xFF63756D),
            height: 1.5),
      ),

      // ── FloatingActionButton ─────────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation:       0,
        shape: CircleBorder(),
      ),

      // ── ListTile ─────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        iconColor:      Color(0xFF63756D),
        titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: navy),
        subtitleTextStyle: TextStyle(fontSize: 12, color: Color(0xFF63756D)),
      ),

      // ── Switch ──────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor:  MaterialStateProperty.resolveWith((s) =>
        s.contains(MaterialState.selected) ? Colors.white : const Color(0xFF83938B)),
        trackColor:  MaterialStateProperty.resolveWith((s) =>
        s.contains(MaterialState.selected) ? teal : const Color(0xFFE2E5DC)),
        trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
      ),

      // ── Checkbox ────────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((s) =>
        s.contains(MaterialState.selected) ? teal : Colors.transparent),
        checkColor: MaterialStateProperty.all(Colors.white),
        side: const BorderSide(color: Color(0xFF83938B), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),

      // ── Radio ────────────────────────────────────────────────────────────
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((s) =>
        s.contains(MaterialState.selected) ? teal : const Color(0xFF83938B)),
      ),

      // ── Progress indicator ───────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color:            teal,
        linearMinHeight:  4,
        linearTrackColor: Color(0xFFE2E5DC),
        circularTrackColor: Color(0xFFE2E5DC),
      ),

      // ── Tab bar ──────────────────────────────────────────────────────────
      tabBarTheme: const TabBarTheme(
        labelColor:         teal,
        unselectedLabelColor: Color(0xFF83938B),
        indicatorColor:     teal,
        indicatorSize:      TabBarIndicatorSize.label,
        labelStyle:         TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor:       border,
      ),

      // ── Icon ─────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(color: Color(0xFF63756D), size: 22),
    );

    return base;
  }
}