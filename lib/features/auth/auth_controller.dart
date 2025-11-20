// lib/features/auth/auth_controller.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants.dart';
import '../../core/error_handler.dart';

/// Controlador para manejar toda la lógica de autenticación
class AuthController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Google Sign-In (v7+) usa singleton
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;

  /// Stream del usuario actual
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Usuario actual
  User? get currentUser => _auth.currentUser;

  /// Asegura que GoogleSignIn esté inicializado (v7+)
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  /// Verifica si un email es institucional
  bool isInstitutionalEmail(String email) {
    return InstitutionalDomains.isInstitutional(email);
  }

  /// Crea o actualiza el documento del usuario en Firestore
  Future<void> ensureUserDocument(User user) async {
    try {
      final uid = user.uid;
      final email = (user.email ?? '').toLowerCase();
      final isInstitutional = isInstitutionalEmail(email);
      final domain = email.contains('@') ? email.split('@')[1] : '';

      final ref = _firestore.collection(FirestoreCollections.users).doc(uid);

      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(ref);

        if (!snap.exists) {
          // Crear nuevo usuario
          txn.set(ref, {
            'email': email,
            'displayName': user.displayName ?? '',
            'photoURL': user.photoURL ?? '',
            'domain': domain,
            'mode': isInstitutional ? 'institucional' : 'externo',
            'role': UserRoles.student,
            'rol': UserRoles.student,
            'active': true,
            'estado': 'activo',
            'isInstitutional': isInstitutional,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          AppLogger.success('Usuario creado: $email');
        } else {
          // Actualizar usuario existente
          final data = snap.data() as Map<String, dynamic>? ?? {};
          final patch = <String, dynamic>{};

          // Sincronizar roles
          if (data['role'] == null && data['rol'] == null) {
            patch['role'] = UserRoles.student;
            patch['rol'] = UserRoles.student;
          } else {
            if (data['role'] == null && data['rol'] != null) {
              patch['role'] = data['rol'];
            }
            if (data['rol'] == null && data['role'] != null) {
              patch['rol'] = data['role'];
            }
          }

          // Activar usuario si estaba inactivo
          if ((data['active'] ?? false) != true) {
            patch['active'] = true;
          }
          if ((data['estado'] ?? '').toString().toLowerCase() != 'activo') {
            patch['estado'] = 'activo';
          }

          if (patch.isNotEmpty) {
            patch['updatedAt'] = FieldValue.serverTimestamp();
            txn.set(ref, patch, SetOptions(merge: true));
            AppLogger.info('Usuario actualizado: $email');
          } else {
            txn.update(ref, {'updatedAt': FieldValue.serverTimestamp()});
          }
        }
      });
    } catch (e, st) {
      AppLogger.error('Error al crear/actualizar documento de usuario', e, st);
      rethrow;
    }
  }

  /// Inicia sesión con email y contraseña
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.info('Intentando login con email: $email');

      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      AppLogger.success('Login exitoso: $email');
      return credential;
    } on FirebaseAuthException catch (e) {
      AppLogger.error('Error de autenticación', e);
      throw ErrorHandler.handleAuthError(e);
    } catch (e, st) {
      AppLogger.error('Error inesperado en login', e, st);
      rethrow;
    }
  }

  /// Registra un nuevo usuario con email y contraseña
  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
    required Map<String, dynamic> profileData,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      AppLogger.info('Registrando nuevo usuario: $normalizedEmail');

      // En este modo NO se permite registro con correo institucional
      if (isInstitutionalEmail(normalizedEmail)) {
        throw ErrorMessages.institutionalOnly;
      }

      final nombres = (profileData['nombres'] ?? '').toString().trim();
      final apellidos = (profileData['apellidos'] ?? '').toString().trim();
      final telefono = (profileData['telefono'] ?? '').toString().trim();
      final documento = (profileData['documento'] ?? '').toString().trim();

      // Validar documento duplicado
      if (documento.isNotEmpty) {
        final existingByDocument = await _firestore
            .collection(FirestoreCollections.users)
            .where('documento', isEqualTo: documento)
            .limit(1)
            .get();

        if (existingByDocument.docs.isNotEmpty) {
          AppLogger.warning('Documento duplicado para $normalizedEmail');
          throw ErrorMessages.documentAlreadyInUse;
        }
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final displayName = [nombres, apellidos]
          .where((part) => part.isNotEmpty)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (displayName.isNotEmpty) {
        await credential.user!.updateDisplayName(displayName);
      }

      // Crear documento base en Firestore
      await ensureUserDocument(credential.user!);

      final profileDoc = <String, dynamic>{
        if (displayName.isNotEmpty) 'displayName': displayName,
        'nombres': nombres,
        'apellidos': apellidos,
        if (telefono.isNotEmpty) 'telefono': telefono,
        if (documento.isNotEmpty) 'documento': documento,
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (profileDoc.isNotEmpty) {
        await _firestore
            .collection(FirestoreCollections.users)
            .doc(credential.user!.uid)
            .set(profileDoc, SetOptions(merge: true));
      }

      AppLogger.success('Registro exitoso: $email');
      return credential;
    } on FirebaseAuthException catch (e) {
      AppLogger.error('Error al registrar', e);
      throw ErrorHandler.handleAuthError(e);
    } catch (e, st) {
      AppLogger.error('Error inesperado en registro', e, st);
      rethrow;
    }
  }

  /// Inicia sesión con Google
  ///
  /// [institutionalMode] = true  → solo acepta correos institucionales
  Future<UserCredential> signInWithGoogle({
    required bool institutionalMode,
  }) async {
    try {
      AppLogger.info(
        'Intentando login con Google (institucional: $institutionalMode)',
      );

      final GoogleAuthProvider provider = GoogleAuthProvider();
      UserCredential credential;

      if (kIsWeb) {
        // Web: usar popup/redirect de Firebase directamente
        try {
          credential = await _auth.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'popup-blocked' ||
              e.code == 'popup-closed-by-user' ||
              e.code == 'unauthorized-domain') {
            AppLogger.warning(
                'Popup bloqueado o cerrado en web, intentando redirect');
            await _auth.signInWithRedirect(provider);
            // El flujo continuará en el callback de redirect
            throw 'redirect';
          }
          rethrow;
        }
      } else {
        // Mobile/Desktop: usar google_sign_in v7+
        await _ensureGoogleInitialized();

       if (!_googleSignIn.supportsAuthenticate()) {
  AppLogger.error(
      'GoogleSignIn.authenticate() no soportado en esta plataforma');
  throw 'Google Sign-In no está soportado en esta plataforma.';
}


        // Flujo interactivo de autenticación
        final googleUser =
            await _googleSignIn.authenticate(scopeHint: const ['email']);

        // Obtener token de ID (ya no existe accessToken en v7)
        final googleAuth = googleUser.authentication;

        final oauthCredential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        credential = await _auth.signInWithCredential(oauthCredential);
      }

      final email = credential.user?.email?.toLowerCase() ?? '';

      // Validar dominio institucional si es necesario
      if (institutionalMode && !isInstitutionalEmail(email)) {
        await _auth.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {
          // Ignorar errores de signOut de Google
        }
        throw ErrorMessages.institutionalOnly;
      }

      // Crear/actualizar documento en Firestore
      await ensureUserDocument(credential.user!);

      AppLogger.success('Login con Google exitoso: $email');
      return credential;
    } on FirebaseAuthException catch (e) {
      AppLogger.error('Error en login con Google (FirebaseAuth)', e);
      throw ErrorHandler.handleAuthError(e);
    } catch (e, st) {
      if (e == 'redirect') {
        // El flujo continúa en el callback del redirect en web
        rethrow;
      }
      AppLogger.error('Error inesperado en Google Sign In', e, st);
      rethrow;
    }
  }

  /// Envía email de recuperación de contraseña
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      AppLogger.info('Enviando email de recuperación a: $email');

      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());

      AppLogger.success('Email de recuperación enviado');
    } on FirebaseAuthException catch (e) {
      AppLogger.error('Error al enviar email de recuperación', e);
      throw ErrorHandler.handleAuthError(e);
    } catch (e, st) {
      AppLogger.error('Error inesperado al enviar email', e, st);
      rethrow;
    }
  }

  /// Cierra sesión
  Future<void> signOut() async {
    try {
      AppLogger.info('Cerrando sesión');
      await _auth.signOut();

      // Intentar también cerrar sesión de Google en plataformas nativas
      try {
        await _ensureGoogleInitialized();
        await _googleSignIn.signOut();
      } catch (_) {
        // Si falla, no rompemos el flujo de logout
      }

      AppLogger.success('Sesión cerrada');
    } catch (e, st) {
      AppLogger.error('Error al cerrar sesión', e, st);
      rethrow;
    }
  }
}
