import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = user.photoURL;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warmad'),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: AuthService.instance.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              user.displayName ?? 'Pengguna',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(user.email ?? '', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
